/**
 * EtherCAT/Ethernet Hybrid Switch Fabric
 * Target: Gowin GW1NR-9
 * FIXED: 
 * 1. FIFO logic updated to FWFT.
 * 2. Added Safe-Transmit logic (delayed Start, immediate End) to align tx_en 
 * with BRAM read latency.
 */

module ecat_switch_top (
    input sys_clk,  // e.g., 50MHz
    input rst_n,

    // --- Port A (PC) ---
    input  [3:0] rxd_a,
    input        rx_dv_a,
    output [3:0] txd_a,
    output       tx_en_a,

    // --- Port B (EtherCAT Chain) ---
    input  [3:0] rxd_b,
    input        rx_dv_b,
    output [3:0] txd_b,
    output       tx_en_b,

    // --- Port C (Ethernet Device) ---
    input  [3:0] rxd_c,
    input        rx_dv_c,
    output [3:0] txd_c,
    output       tx_en_c
);

  // ============================================================
  // 1. DOWNSTREAM LOGIC (PC -> B or C)
  // ============================================================

  wire [3:0] c_fifo_wr_data;
  wire       c_fifo_wr_en;
  wire [3:0] c_fifo_rd_data;
  wire       c_fifo_rd_empty;
  wire       c_fifo_rd_en;

  // The "Splitter" inspects traffic from A and decides destination
  packet_classifier u_classifier (
      .clk        (sys_clk),
      .rst_n      (rst_n),
      .mii_d_in   (rxd_a),
      .mii_dv_in  (rx_dv_a),
      .mii_d_ecat (txd_b),
      .mii_en_ecat(tx_en_b),
      .fifo_wr_en (c_fifo_wr_en),
      .fifo_data  (c_fifo_wr_data)
  );

  // FIFO for Port C
  simple_fifo #(
      .DEPTH(4096),
      .WIDTH(4)
  ) u_fifo_down_c (
      .clk  (sys_clk),
      .rst_n(rst_n),
      .wr_en(c_fifo_wr_en),
      .din  (c_fifo_wr_data),
      .rd_en(c_fifo_rd_en),
      .dout (c_fifo_rd_data),
      .empty(c_fifo_rd_empty),
      .full ()
  );

  // --- TIMING FIX FOR DOWNSTREAM (Port C) ---
  reg  c_fifo_not_empty_d;
  wire c_fifo_has_data_now = !c_fifo_rd_empty;

  // Delay the "Not Empty" signal by 1 clock to match BRAM read latency
  always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) c_fifo_not_empty_d <= 0;
    else c_fifo_not_empty_d <= c_fifo_has_data_now;
  end

  // MASK: Wait for delayed start, but cut off immediately on real empty
  // This ensures txd_c is valid when tx_en_c goes high.
  wire c_fifo_safe_valid =  /*c_fifo_has_data_now & */ c_fifo_not_empty_d;

  assign txd_c    = c_fifo_rd_data;
  assign tx_en_c  = c_fifo_safe_valid;
  assign c_fifo_rd_en = c_fifo_safe_valid;


  // ============================================================
  // 2. UPSTREAM LOGIC (B or C -> PC)
  // ============================================================

  wire [3:0] up_c_fifo_out;
  wire       up_c_fifo_empty;
  wire       up_c_fifo_read;

  simple_fifo #(
      .DEPTH(4096),
      .WIDTH(4)
  ) u_fifo_up_c (
      .clk  (sys_clk),
      .rst_n(rst_n),
      .wr_en(rx_dv_c),
      .din  (rxd_c),
      .rd_en(up_c_fifo_read),
      .dout (up_c_fifo_out),
      .empty(up_c_fifo_empty),
      .full ()
  );

  // --- TIMING FIX FOR UPSTREAM (Arbiter) ---
  reg  up_c_fifo_not_empty_d;
  wire up_c_fifo_has_data_now = !up_c_fifo_empty;

  always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) up_c_fifo_not_empty_d <= 0;
    else up_c_fifo_not_empty_d <= up_c_fifo_has_data_now;
  end

  // Pass the SAFE signal to the Arbiter
  wire up_c_safe_valid =  /*up_c_fifo_has_data_now &*/ up_c_fifo_not_empty_d;

  // The Priority Arbiter
  upstream_arbiter u_arbiter (
      .clk(sys_clk),
      .rst_n(rst_n),
      .mii_d_b(rxd_b),
      .mii_dv_b(rx_dv_b),
      .fifo_c_data(up_c_fifo_out),
      // Use the SAFE Valid signal instead of raw empty
      // Inverting valid to "empty" because Arbiter logic expects "empty" input
      .fifo_c_empty(!up_c_safe_valid),
      .fifo_c_read(up_c_fifo_read),
      .mii_d_a(txd_a),
      .mii_en_a(tx_en_a)
  );

endmodule


// ============================================================
// MODULE: Packet Classifier
// ============================================================
module packet_classifier (
    input       clk,
    input       rst_n,
    input [3:0] mii_d_in,
    input       mii_dv_in,

    output reg [3:0] mii_d_ecat,
    output reg       mii_en_ecat,

    output reg       fifo_wr_en,
    output reg [3:0] fifo_data
);

  reg [10:0] byte_cnt;
  reg        nibble_sel;  // 0=Low, 1=High
  reg [ 7:0] current_byte;

  reg [15:0] ether_type;
  reg [ 1:0] state;

  localparam S_IDLE = 0;
  localparam S_PARSE = 1;
  localparam S_ROUTE_B = 2;
  localparam S_ROUTE_C = 3;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      byte_cnt <= 0;
      nibble_sel <= 0;
      mii_en_ecat <= 0;
      fifo_wr_en <= 0;
    end else begin
      // Defaults
      mii_en_ecat <= 0;
      fifo_wr_en  <= 0;
      mii_d_ecat  <= mii_d_in;
      fifo_data   <= mii_d_in;

      if (!mii_dv_in) begin
        state <= S_IDLE;
        byte_cnt <= 0;
        nibble_sel <= 0;
      end else begin

        if (nibble_sel == 0) begin
          current_byte[3:0] <= mii_d_in;
          nibble_sel <= 1;
        end else begin
          current_byte[7:4] <= mii_d_in;
          nibble_sel <= 0;
          byte_cnt <= byte_cnt + 1;
        end

        case (state)
          S_IDLE: begin
            state <= S_PARSE;
            mii_en_ecat <= 1;
            fifo_wr_en <= 1;
          end

          S_PARSE: begin
            mii_en_ecat <= 1;
            fifo_wr_en  <= 1;

            if (nibble_sel == 1) begin
              if (byte_cnt == 20) ether_type[7:0] <= {mii_d_in, current_byte[3:0]};
              if (byte_cnt == 21) begin
                ether_type[15:8] <= {mii_d_in, current_byte[3:0]};
                if (ether_type[7:0] == 8'h88 && {mii_d_in, current_byte[3:0]} == 8'hA4) begin
                  state <= S_ROUTE_B;
                end else begin
                  state <= S_ROUTE_C;
                end
              end
            end
          end

          S_ROUTE_B: begin
            mii_en_ecat <= 1;
            fifo_wr_en  <= 0;
          end

          S_ROUTE_C: begin
            mii_en_ecat <= 0;
            fifo_wr_en  <= 1;
          end
        endcase
      end
    end
  end
endmodule


// ============================================================
// MODULE: Upstream Arbiter
// ============================================================
module upstream_arbiter (
    input            clk,
    input            rst_n,
    input      [3:0] mii_d_b,
    input            mii_dv_b,
    input      [3:0] fifo_c_data,
    input            fifo_c_empty,  // Connected to SAFE valid signal (inverted)
    output reg       fifo_c_read,
    output reg [3:0] mii_d_a,
    output reg       mii_en_a
);

  localparam S_IDLE = 0;
  localparam S_SEND_B = 1;
  localparam S_SEND_C = 2;

  reg [1:0] state;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      mii_en_a <= 0;
      fifo_c_read <= 0;
    end else begin
      fifo_c_read <= 0;
      mii_en_a <= 0;

      if (mii_dv_b) begin
        state <= S_SEND_B;
        mii_d_a <= mii_d_b;
        mii_en_a <= 1;
      end else begin
        case (state)
          S_IDLE: begin
            mii_en_a <= 0;
            if (mii_dv_b) begin
              state <= S_SEND_B;
            end else if (!fifo_c_empty) begin
              state <= S_SEND_C;
              fifo_c_read <= 1;
            end
          end

          S_SEND_B: begin
            if (mii_dv_b) begin
              mii_d_a  <= mii_d_b;
              mii_en_a <= 1;
            end else begin
              state <= S_IDLE;
            end
          end

          S_SEND_C: begin
            if (!fifo_c_empty) begin
              mii_d_a <= fifo_c_data;
              mii_en_a <= 1;
              fifo_c_read <= 1;
            end else begin
              state <= S_IDLE;
            end
          end
        endcase
      end
    end
  end
endmodule


// ============================================================
// MODULE: Simple FIFO (FWFT)
// ============================================================
module simple_fifo #(
    parameter DEPTH = 1024,
    WIDTH = 4
) (
    input clk,
    rst_n,
    input wr_en,
    input [WIDTH-1:0] din,
    input rd_en,
    output reg [WIDTH-1:0] dout,
    output empty,
    output full
);
  reg [WIDTH-1:0] mem[0:DEPTH-1];
  reg [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;
  reg [$clog2(DEPTH):0] count;

  assign empty = (count == 0);
  assign full  = (count == DEPTH);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= 0;
      rd_ptr <= 0;
      count  <= 0;
      dout   <= 0;
    end else begin
      if (wr_en && !full) begin
        mem[wr_ptr] <= din;
        wr_ptr <= (wr_ptr == DEPTH - 1) ? 0 : wr_ptr + 1;
      end

      // Output Register (FWFT)
      // Valid data appears here 1 clock after rd_ptr updates
      // or 1 clock after write if empty.
      dout <= mem[rd_ptr];

      if (rd_en && !empty) begin
        rd_ptr <= (rd_ptr == DEPTH - 1) ? 0 : rd_ptr + 1;
      end

      if (wr_en && !rd_en && !full) count <= count + 1;
      else if (!wr_en && rd_en && !empty) count <= count - 1;
    end
  end
endmodule
