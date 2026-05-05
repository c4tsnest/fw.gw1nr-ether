module top (
    input logic rst_n,
    input logic clock,

    input  logic       link_a,
    input  logic       txclk_a,
    input  logic       rxdv_a,
    input  logic       rxer_a,
    input  logic       rxclk_a,
    input  logic [3:0] rxd_a,
    output logic       txen_a,
    output logic [3:0] txd_a,
    output logic       nrst_a,

    input  logic       link_b,
    input  logic       txclk_b,
    input  logic       rxdv_b,
    input  logic       rxer_b,
    input  logic       rxclk_b,
    input  logic [3:0] rxd_b,
    output logic       txen_b,
    output logic [3:0] txd_b,
    output logic       nrst_b,

    input  logic       link_c,
    input  logic       txclk_c,
    input  logic       rxdv_c,
    input  logic       rxer_c,
    input  logic       rxclk_c,
    input  logic [3:0] rxd_c,
    output logic       txen_c,
    output logic [3:0] txd_c,
    output logic       nrst_c,

    output logic [4:0] led
);

  localparam int unsigned RESET_HOLD_CYCLES = 125_000;
  logic [19:0] reset_hold_counter;
  logic        reset_hold_active;

  esc_minimal_slave #(
      .GPIO_OUT_WIDTH(8),
      .GPIO_IN_WIDTH (0)
  ) u_esc (
      .clk     (clock),
      .rst_n   (rst_n),
      .link_up (link_b),
      .rxd     (rxd_b),
      .rx_dv   (rxdv_b),
      .txd     (txd_b),
      .tx_en   (txen_b),
      .gpio_in (),
      .gpio_out()
  );

  always_comb begin
    txd_a  = 4'h0;
    txen_a = 1'b0;
    txd_c  = 4'h0;
    txen_c = 1'b0;
  end

  always_ff @(posedge clock or negedge rst_n) begin
    if (!rst_n) begin
      reset_hold_counter <= '0;
      reset_hold_active  <= 1'b1;
    end else begin
      if (reset_hold_active) begin
        if (reset_hold_counter >= (RESET_HOLD_CYCLES - 1)) begin
          reset_hold_counter <= '0;
          reset_hold_active  <= 1'b0;
        end else begin
          reset_hold_counter <= reset_hold_counter + 1'b1;
        end
      end
    end
  end

  always_comb begin
    nrst_a = ~reset_hold_active;
    nrst_b = ~reset_hold_active;
    nrst_c = ~reset_hold_active;
  end

  led #(
      .CLK_HZ         (25_000_000),
      .ACT_HOLD_MS    (120),
      .BLINK_TOGGLE_HZ(20)
  ) u_led (
      .clk   (clock),
      .rst_n (rst_n),
      .link_a(~link_a),
      .link_b(~link_b),
      .link_c(~link_c),
      .act_a (rxdv_a | txen_a),
      .act_b (rxdv_b | txen_b),
      .act_c (rxdv_c | txen_c),
      .led   (led)
  );

endmodule
