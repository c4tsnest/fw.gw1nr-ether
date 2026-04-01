module led #(
    parameter int unsigned CLK_HZ = 25_000_000,
    parameter int unsigned ACT_HOLD_MS = 120,
    parameter int unsigned BLINK_TOGGLE_HZ = 20
) (
    input logic clk,
    input logic rst_n,
    input logic link_a,
    input logic link_b,
    input logic link_c,
    input logic act_a,
    input logic act_b,
    input logic act_c,
    output logic [4:0] led
);

  localparam int unsigned ACT_HOLD_TICKS = (CLK_HZ / 1000) * ACT_HOLD_MS;
  localparam int unsigned BLINK_TOGGLE_TICKS = CLK_HZ / BLINK_TOGGLE_HZ;
  localparam int unsigned HEARTBEAT_TOGGLE_TICKS = CLK_HZ / 2;

  logic [31:0] blink_counter;
  logic blink_phase;
  logic [31:0] heartbeat_counter;
  logic heartbeat_phase;

  logic act_a_ff0, act_a_ff1;
  logic act_b_ff0, act_b_ff1;
  logic act_c_ff0, act_c_ff1;

  logic [31:0] act_hold_a;
  logic [31:0] act_hold_b;
  logic [31:0] act_hold_c;
  logic act_a_latched;
  logic act_b_latched;
  logic act_c_latched;

  logic link_a_on;
  logic link_b_on;
  logic link_c_on;

  always_comb begin
    act_a_latched = (act_hold_a != 32'd0);
    act_b_latched = (act_hold_b != 32'd0);
    act_c_latched = (act_hold_c != 32'd0);

    link_a_on = link_a && (~act_a_latched || blink_phase);
    link_b_on = link_b && (~act_b_latched || blink_phase);
    link_c_on = link_c && (~act_c_latched || blink_phase);

    led[0] = ~heartbeat_phase;
    led[1] = ~link_a_on;
    led[2] = ~link_b_on;
    led[3] = ~link_c_on;
    led[4] = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      blink_counter <= 32'd0;
      blink_phase <= 1'b0;
      heartbeat_counter <= 32'd0;
      heartbeat_phase <= 1'b0;

      act_a_ff0 <= 1'b0;
      act_a_ff1 <= 1'b0;
      act_b_ff0 <= 1'b0;
      act_b_ff1 <= 1'b0;
      act_c_ff0 <= 1'b0;
      act_c_ff1 <= 1'b0;

      act_hold_a <= 32'd0;
      act_hold_b <= 32'd0;
      act_hold_c <= 32'd0;
    end else begin
      if (blink_counter >= (BLINK_TOGGLE_TICKS - 1)) begin
        blink_counter <= 32'd0;
        blink_phase <= ~blink_phase;
      end else begin
        blink_counter <= blink_counter + 32'd1;
      end

      if (heartbeat_counter >= (HEARTBEAT_TOGGLE_TICKS - 1)) begin
        heartbeat_counter <= 32'd0;
        heartbeat_phase <= ~heartbeat_phase;
      end else begin
        heartbeat_counter <= heartbeat_counter + 32'd1;
      end

      act_a_ff0 <= act_a;
      act_a_ff1 <= act_a_ff0;
      act_b_ff0 <= act_b;
      act_b_ff1 <= act_b_ff0;
      act_c_ff0 <= act_c;
      act_c_ff1 <= act_c_ff0;

      if (act_a_ff1) begin
        act_hold_a <= ACT_HOLD_TICKS;
      end else if (act_hold_a != 32'd0) begin
        act_hold_a <= act_hold_a - 32'd1;
      end

      if (act_b_ff1) begin
        act_hold_b <= ACT_HOLD_TICKS;
      end else if (act_hold_b != 32'd0) begin
        act_hold_b <= act_hold_b - 32'd1;
      end

      if (act_c_ff1) begin
        act_hold_c <= ACT_HOLD_TICKS;
      end else if (act_hold_c != 32'd0) begin
        act_hold_c <= act_hold_c - 32'd1;
      end
    end
  end

endmodule