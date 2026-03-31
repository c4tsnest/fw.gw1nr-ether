module led #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer ACT_HOLD_MS = 120,
    parameter integer BLINK_TOGGLE_HZ = 12
) (
    input wire clk,
    input wire rst_n,
    input wire link0,
    input wire link1,
    input wire rx_act0,
    input wire rx_act1,
    output reg [4:0] led
);

  localparam integer ACT_HOLD_TICKS = (CLK_HZ / 1000) * ACT_HOLD_MS;
  localparam integer BLINK_TOGGLE_TICKS = CLK_HZ / BLINK_TOGGLE_HZ;

  reg [31:0] blink_counter;
  reg blink_phase;

  reg rx0_ff0, rx0_ff1;
  reg rx1_ff0, rx1_ff1;

  reg [31:0] act_hold0;
  reg [31:0] act_hold1;

  wire act0_latched = (act_hold0 != 32'd0);
  wire act1_latched = (act_hold1 != 32'd0);

  always @(posedge clk or negedge rst_n) begin
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