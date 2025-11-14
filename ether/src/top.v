
module top (
    input rst_n,
    input clock,
    input linkb,
    input linkc,
    input txclk,
    input rxdv,
    input rxer,
    input rxclk,
    input [3:0] rxd,
    output txen,
    output wire [3:0] txd,
    output wire [4:0] led
);

  wire actb;

  led u1 (
      .clk  (clock),
      .rst_n(rst_n),
      .linkb(linkb),
      .linkc(linkc),
      .actb (actb),
      .led  (led)
  );

  mii_loopback u2 (
      .clk  (clock),
      .rst_n(rst_n),
      .rxd  (rxd),
      .rx_dv(rxdv),
      .rx_er(rxer),
      .link (linkb),
      .txd  (txd),
      .tx_en(txen),
      .act  (actb)
  );

endmodule
