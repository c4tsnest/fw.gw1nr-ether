module led #(
    parameter int unsigned CLK_HZ = 25_000_000,
    parameter int unsigned ACT_HOLD_MS = 120,
    parameter int unsigned BLINK_TOGGLE_HZ = 12
) (
    input logic clk,
    input logic rst_n,
    input logic link0,
    input logic link1,
    input logic rx_act0,
    input logic rx_act1,
    output logic [4:0] led
);

  localparam int unsigned ACT_HOLD_TICKS = (CLK_HZ / 1000) * ACT_HOLD_MS;
  localparam int unsigned BLINK_TOGGLE_TICKS = CLK_HZ / BLINK_TOGGLE_HZ;

  logic [31:0] blink_counter;
  logic blink_phase;

  logic rx0_ff0, rx0_ff1;
  logic rx1_ff0, rx1_ff1;

  logic [31:0] act_hold0;
  logic [31:0] act_hold1;
  logic act0_latched;
  logic act1_latched;

  always_comb begin
    act0_latched = (act_hold0 != 32'd0);
    act1_latched = (act_hold1 != 32'd0);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      blink_counter <= 32'd0;
      blink_phase <= 1'b0;

      rx0_ff0 <= 1'b0;
      rx0_ff1 <= 1'b0;
      rx1_ff0 <= 1'b0;
      rx1_ff1 <= 1'b0;

      act_hold0 <= 32'd0;
      act_hold1 <= 32'd0;

      led <= 5'b00000;
    end else begin
      if (blink_counter >= (BLINK_TOGGLE_TICKS - 1)) begin
        blink_counter <= 32'd0;
        blink_phase <= ~blink_phase;
      end else begin
        blink_counter <= blink_counter + 32'd1;
      end

      rx0_ff0 <= rx_act0;
      rx0_ff1 <= rx0_ff0;
      rx1_ff0 <= rx_act1;
      rx1_ff1 <= rx1_ff0;

      if (rx0_ff1) begin
        act_hold0 <= ACT_HOLD_TICKS;
      end else if (act_hold0 != 32'd0) begin
        act_hold0 <= act_hold0 - 32'd1;
      end

      if (rx1_ff1) begin
        act_hold1 <= ACT_HOLD_TICKS;
      end else if (act_hold1 != 32'd0) begin
        act_hold1 <= act_hold1 - 32'd1;
      end

      led[0] <= link0 & (~act0_latched | blink_phase);
      led[1] <= link1 & (~act1_latched | blink_phase);
      led[4:2] <= 3'b000;
    end
  end

endmodule