module mii (
    // input       rx_clk,
    input clk,
    input rst_n,

    input  [3:0] rxd_a,
    input        rx_dv_a,
    input        rx_er_a,
    input        link_a,
    // input        tx_clk,
    output [3:0] txd_a,
    output       tx_en_a,
    output       act_a,

    input  [3:0] rxd_b,
    input        rx_dv_b,
    input        rx_er_b,
    input        link_b,
    output [3:0] txd_b,
    output       tx_en_b,
    output       act_b,

    input  [3:0] rxd_c,
    input        rx_dv_c,
    input        rx_er_c,
    input        link_c,
    output [3:0] txd_c,
    output       tx_en_c,
    output       act_c
);

  reg [ 3:0] txd_reg_a;
  reg        tx_en_reg_a;
  reg [ 3:0] rxd_buf_a;
  reg        dv_buf_a;
  reg [31:0] act_counter_a;
  reg        act_reg_a;
  assign txd_a   = txd_reg_a;
  assign tx_en_a = tx_en_reg_a;
  assign act_a   = act_reg_a;

  reg [ 3:0] txd_reg_b;
  reg        tx_en_reg_b;
  reg [ 3:0] rxd_buf_b;
  reg        dv_buf_b;
  reg [31:0] act_counter_b;
  reg        act_reg_b;
  assign txd_b   = txd_reg_b;
  assign tx_en_b = tx_en_reg_b;
  assign act_b   = act_reg_b;

  reg [ 3:0] txd_reg_c;
  reg        tx_en_reg_c;
  reg [ 3:0] rxd_buf_c;
  reg        dv_buf_c;
  reg [31:0] act_counter_c;
  reg        act_reg_c;
  assign txd_c   = txd_reg_c;
  assign tx_en_c = tx_en_reg_c;
  assign act_c   = act_reg_c;

  always @(posedge clk) begin
    if (!rst_n) begin
      rxd_buf_a   <= 4'b0000;
      dv_buf_a    <= 1'b0;
      txd_reg_a   <= 4'b0000;
      tx_en_reg_a <= 1'b0;
      act_counter_a <= 32'd0;
      act_reg_a <= 1'b0;

      rxd_buf_b   <= 4'b0000;
      dv_buf_b    <= 1'b0;
      txd_reg_b   <= 4'b0000;
      tx_en_reg_b <= 1'b0;
      act_counter_b <= 32'd0;
      act_reg_b <= 1'b0;

      rxd_buf_c   <= 4'b0000;
      dv_buf_c    <= 1'b0;
      txd_reg_c   <= 4'b0000;
      tx_en_reg_c <= 1'b0;
      act_counter_c <= 32'd0;
      act_reg_c <= 1'b0;
    end else begin
      rxd_buf_a <= rxd_a;
      dv_buf_a <= rx_dv_a;
      rxd_buf_b <= rxd_b;
      dv_buf_b <= rx_dv_b;
      rxd_buf_c <= rxd_c;
      dv_buf_c <= rx_dv_c;

      txd_reg_b <= rxd_buf_c;
      tx_en_reg_b <= dv_buf_c;
      txd_reg_c <= rxd_buf_b;
      tx_en_reg_c <= dv_buf_b;

      // act counter
      if (dv_buf_a) begin
        act_counter_a <= 32'd0;
      end else begin
        if (act_counter_a < 32'hFFFFFFFF) begin
          act_counter_a <= act_counter_a + 1'b1;
        end else begin
          act_counter_a <= 32'hFFFFFFFF;
        end
      end
      if (dv_buf_b) begin
        act_counter_b <= 32'd0;
      end else begin
        if (act_counter_b < 32'hFFFFFFFF) begin
          act_counter_b <= act_counter_b + 1'b1;
        end else begin
          act_counter_b <= 32'hFFFFFFFF;
        end
      end
      if (dv_buf_c) begin
        act_counter_c <= 32'd0;
      end else begin
        if (act_counter_c < 32'hFFFFFFFF) begin
          act_counter_c <= act_counter_c + 1'b1;
        end else begin
          act_counter_c <= 32'hFFFFFFFF;
        end
      end

      // act signal
      if (!link_a && (act_counter_a < 32'd2500000)) begin
        act_reg_a <= 1'b1;
      end else begin
        act_reg_a <= 1'b0;
      end
      if (!link_b && (act_counter_b < 32'd2500000)) begin
        act_reg_b <= 1'b1;
      end else begin
        act_reg_b <= 1'b0;
      end
      if (!link_c && (act_counter_c < 32'd2500000)) begin
        act_reg_c <= 1'b1;
      end else begin
        act_reg_c <= 1'b0;
      end

    end
  end

endmodule

/*
module mii_tx (
    input  wire       tx_clk,
    input  wire       rstn,
    input  wire [7:0] tx_byte,
    input  wire       tx_byte_valid,
    output reg        tx_byte_ready,
    output reg  [3:0] TXD,
    output reg        TX_EN
);
  // state: send preamble (7 bytes of 0x55), SFD 0xD5, then payload bytes L->M, then FCS later
  reg [ 3:0] nibble_sel;  // 0: upper nibble, 1: lower nibble etc. but we'll use toggling scheme
  reg [ 7:0] active_byte;
  reg        have_byte;
  reg [15:0] preamble_cnt;

  always @(posedge tx_clk) begin
    if (!rstn) begin
      TXD <= 4'b0000;
      TX_EN <= 1'b0;
      tx_byte_ready <= 1'b1;
      nibble_sel <= 0;
      have_byte <= 0;
      preamble_cnt <= 0;
    end else begin
      // load byte when available and not holding one
      if (!have_byte && tx_byte_valid) begin
        active_byte <= tx_byte;
        have_byte <= 1;
        tx_byte_ready <= 1'b0;  // consuming
      end else if (have_byte && !tx_byte_valid) begin
        tx_byte_ready <= 1'b1;
      end

      // For simplicity: transmit preamble first once, then stream bytes as they arrive
      if (preamble_cnt < 7 * 2) begin  // each byte takes two nibbles cycles
        TX_EN <= 1'b1;
        // send 0x55 pattern MSB-first as two nibbles (upper then lower)
        if (nibble_sel == 0) begin
          TXD <= 4'h5;  // upper nibble (0x5)
        end else begin
          TXD <= 4'h5;  // lower nibble also 0x5
        end
        nibble_sel <= ~nibble_sel;
        if (nibble_sel == 1) preamble_cnt <= preamble_cnt + 1;
      end else if (preamble_cnt == 7 * 2) begin
        // send SFD 0xD5
        TX_EN <= 1'b1;
        if (nibble_sel == 0) TXD <= 4'hD;
        else TXD <= 4'h5;
        nibble_sel <= ~nibble_sel;
        if (nibble_sel == 1) preamble_cnt <= preamble_cnt + 1;
      end else begin
        // payload transmission
        if (have_byte) begin
          TX_EN <= 1'b1;
          if (nibble_sel == 0) TXD <= active_byte[7:4];
          else TXD <= active_byte[3:0];
          nibble_sel <= ~nibble_sel;
          if (nibble_sel == 1) begin
            have_byte <= 0;  // byte transmitted
            tx_byte_ready <= 1'b1;
          end
        end else begin
          // idle
          TX_EN <= 1'b0;
          TXD   <= 4'b0000;
        end
      end
    end
  end
endmodule
*/
