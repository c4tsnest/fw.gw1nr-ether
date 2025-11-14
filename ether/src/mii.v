module mii (
    input clk,
    input rst_n,
    output reg link
);

  reg [24:0] counter;

  always @(posedge clk) begin
    if (!rst_n) begin
    end else begin

    end
  end

endmodule

module mii_loopback (
    // input       rx_clk,
    input clk,
    input rst_n,

    input [3:0] rxd,
    input       rx_dv,
    input       rx_er,
    input       link,

    // input        tx_clk,
    output [3:0] txd,
    output       tx_en,

    output act
);

  reg [3:0] txd_reg;
  reg       tx_en_reg;

  assign txd   = txd_reg;
  assign tx_en = tx_en_reg;

  reg [ 3:0] rxd_buf;
  reg        dv_buf;

  reg [31:0] act_counter;
  reg        act_reg;
  assign act = act_reg;

  always @(posedge clk) begin
    if (!rst_n) begin
      rxd_buf   <= 4'b0000;
      dv_buf    <= 1'b0;
      txd_reg   <= 4'b0000;
      tx_en_reg <= 1'b0;
      act_counter <= 32'd0;
      act_reg <= 1'b0;
    end else begin
      rxd_buf <= rxd;
      dv_buf <= rx_dv;

      txd_reg <= rxd_buf;
      tx_en_reg <= dv_buf;

      // act counter
      if (dv_buf) begin
        act_counter <= 32'd0;
      end else begin
        if (act_counter < 32'hFFFFFFFF) begin
          act_counter <= act_counter + 1'b1;
        end else begin
          act_counter <= 32'hFFFFFFFF;
        end
      end

      // act signal
      if (!link && (act_counter < 32'd2500000)) begin
        act_reg <= 1'b1;
      end else begin
        act_reg <= 1'b0;
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
