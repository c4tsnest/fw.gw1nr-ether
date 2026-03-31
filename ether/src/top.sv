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

    output wire [4:0] led,
    output wire [7:0] gpio_out
);

    esc_minimal_slave #(
            .GPIO_OUT_WIDTH(8),
            .GPIO_IN_WIDTH (0)
    ) u_esc (
            .clk     (clock),
            .rst_n   (rst_n),
            .link_up (link_a),
            .rxd     (rxd_a),
            .rx_dv   (rxdv_a),
            .txd     (txd_a),
            .tx_en   (txen_a),
            .gpio_in (),
            .gpio_out(gpio_out)
    );

    assign txd_b = 4'h0;
    assign txen_b = 1'b0;
    assign txd_c = 4'h0;
    assign txen_c = 1'b0;

    led #(
            .CLK_HZ         (25_000_000),
            .ACT_HOLD_MS    (120),
            .BLINK_TOGGLE_HZ(12)
    ) u_led (
            .clk    (clock),
            .rst_n  (rst_n),
            .link0  (link_a),
            .link1  (link_b),
            .rx_act0(rxdv_a),
            .rx_act1(rxdv_b),
            .led    (led)
    );

    wire _unused_ok = &{txclk_a, rxer_a, rxclk_a, txclk_b, rxer_b, rxclk_b, rxd_b,
                        link_c, txclk_c, rxdv_c, rxer_c, rxclk_c, rxd_c};

endmodule