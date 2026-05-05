module esc_minimal_slave #(
    parameter int unsigned GPIO_OUT_WIDTH = 8,
    parameter int unsigned GPIO_IN_WIDTH  = 0
) (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       link_up,
    input  esc_pkg::nibble_t           rxd,
    input  logic                       rx_dv,
    output esc_pkg::nibble_t           txd,
    output logic                       tx_en,
    input  logic [GPIO_IN_WIDTH-1:0]   gpio_in,
    output logic [GPIO_OUT_WIDTH-1:0]  gpio_out
);

  import esc_pkg::*;

  esc_tx_byte_if tx_byte_if ();
  esc_reg_if     reg_if ();
  esc_fifo_if    fifo_if ();

  byte_t rx_data;
  logic  rx_valid;
  logic  rx_frame_start;
  logic  rx_frame_end;

  logic [15:0] byte_idx;
  logic        is_ethercat;
  logic        has_preamble;
  logic [15:0] frame_offset;
  logic        preamble_valid;

  logic        crc_exclude;

  logic [15:0] station_addr;
  logic [15:0] debug_wkc_value;

  logic unused_gpio_in;
  assign unused_gpio_in = |gpio_in;

  esc_mii_rx u_mii_rx (
      .clk            (clk),
      .rst_n          (rst_n),
      .rxd            (rxd),
      .rx_dv          (rx_dv),
      .rx_data        (rx_data),
      .rx_valid       (rx_valid),
      .rx_frame_start (rx_frame_start),
      .rx_frame_end   (rx_frame_end)
  );

  esc_frame_parser u_frame_parser (
      .clk            (clk),
      .rst_n          (rst_n),
      .rx_data        (rx_data),
      .rx_valid       (rx_valid),
      .rx_frame_start (rx_frame_start),
      .byte_idx       (byte_idx),
      .is_ethercat    (is_ethercat),
      .has_preamble   (has_preamble),
      .frame_offset   (frame_offset),
      .preamble_valid (preamble_valid)
  );

  esc_datagram_handler u_handler (
      .clk             (clk),
      .rst_n           (rst_n),
      .rx_data         (rx_data),
      .rx_valid        (rx_valid),
      .rx_frame_start  (rx_frame_start),
      .is_ethercat     (is_ethercat),
      .has_preamble    (has_preamble),
      .preamble_valid  (preamble_valid),
      .byte_idx        (byte_idx),
      .frame_offset    (frame_offset),
      .reg_if          (reg_if.master),
      .station_addr    (station_addr),
      .tx_out          (tx_byte_if.source),
      .crc_exclude     (crc_exclude),
      .debug_wkc_value (debug_wkc_value)
  );

  esc_regfile #(
      .GPIO_OUT_WIDTH (GPIO_OUT_WIDTH),
      .GPIO_IN_WIDTH  (GPIO_IN_WIDTH)
  ) u_regfile (
      .clk              (clk),
      .rst_n            (rst_n),
      .link_up          (link_up),
      .reg_if           (reg_if.slave),
      .station_addr     (station_addr),
      .gpio_out         (gpio_out),
      .debug_wkc_value  (debug_wkc_value)
  );

  esc_crc u_crc (
      .clk           (clk),
      .rst_n         (rst_n),
      .tx_byte       (tx_byte_if.data),
      .tx_byte_valid (tx_byte_if.valid),
      .crc_exclude   (crc_exclude),
      .frame_start   (rx_frame_start),
      .frame_end     (rx_frame_end),
      .fifo_out      (fifo_if.source)
  );

  esc_mii_tx u_mii_tx (
      .clk     (clk),
      .rst_n   (rst_n),
      .fifo_in (fifo_if.sink),
      .txd     (txd),
      .tx_en   (tx_en)
  );

endmodule
