module top (
    input rst_n,
    input clock,

    input link_a,
    input txclk_a,
    input rxdv_a,
    input rxer_a,
    input rxclk_a,
    input [3:0] rxd_a,
    output txen_a,
    output wire [3:0] txd_a,

    input link_b,
    input txclk_b,
    input rxdv_b,
    input rxer_b,
    input rxclk_b,
    input [3:0] rxd_b,
    output txen_b,
    output wire [3:0] txd_b,

    input link_c,
    input txclk_c,
    input rxdv_c,
    input rxer_c,
    input rxclk_c,
    input [3:0] rxd_c,
    output txen_c,
    output wire [3:0] txd_c,

    output wire [4:0] led
);

  wire act_a;
  wire act_b;
  wire act_c;

  led u1 (
      .clk(clock),
      .rst_n(rst_n),
      .link_a(link_a),
      .link_b(link_b),
      .link_c(link_c),
      .act_a(act_a),
      .act_b(act_b),
      .act_c(act_c),
      .led(led)
  );

  mii u2 (
      .clk(clock),
      .rst_n(rst_n),
      .rxd_a(rxd_a),
      .rx_dv_a(rxdv_a),
      .rx_er_a(rxer_a),
      .link_a(link_a),
      .txd_a(txd_a),
      .tx_en_a(txen_a),
      .act_a(act_a),
      .rxd_b(rxd_b),
      .rx_dv_b(rxdv_b),
      .rx_er_b(rxer_b),
      .link_b(link_b),
      .txd_b(txd_b),
      .tx_en_b(txen_b),
      .act_b(act_b),
      .rxd_c(rxd_c),
      .rx_dv_c(rxdv_c),
      .rx_er_c(rxer_c),
      .link_c(link_c),
      .txd_c(txd_c),
      .tx_en_c(txen_c),
      .act_c(act_c)
  );

endmodule
