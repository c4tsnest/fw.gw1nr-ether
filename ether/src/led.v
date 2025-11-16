module led (
    input clk,
    input rst_n,
    input link_a,
    input link_b,
    input link_c,
    input act_a,
    input act_b,
    input act_c,
    output reg [4:0] led
);

  reg [24:0] counter_25M;
  reg [24:0] counter_2p5M;

  always @(posedge clk) begin
    if (!rst_n) begin
      counter_25M <= 25'd0;
    end else if (counter_25M < 25'd2499_9999) begin
      counter_25M <= counter_25M + 1'b1;
    end else begin
      counter_25M <= 25'd0;
    end
    if (!rst_n) begin
      counter_2p5M <= 25'd0;
    end else if (counter_2p5M < 25'd249_9999) begin
      counter_2p5M <= counter_2p5M + 1'b1;
    end else begin
      counter_2p5M <= 25'd0;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      led <= 5'b11111;
    end else begin
      if (counter_25M <= 25'd249_9999) begin
        led[0] <= 1'b0;
      end else begin
        led[0] <= 1'b1;
      end

      if (link_a) begin
        led[1] <= 1'b1;
      end else begin
        if (act_a) begin
          if (counter_2p5M <= 25'd124_9999) begin
            led[1] <= 1'b0;
          end else begin
            led[1] <= 1'b1;
          end
        end else begin
          led[1] <= 1'b0;
        end
      end

      if (link_b) begin
        led[2] <= 1'b1;
      end else begin
        if (act_b) begin
          if (counter_2p5M <= 25'd124_9999) begin
            led[2] <= 1'b0;
          end else begin
            led[2] <= 1'b1;
          end
        end else begin
          led[2] <= 1'b0;
        end
      end

      if (link_c) begin
        led[3] <= 1'b1;
      end else begin
        if (act_c) begin
          if (counter_2p5M <= 25'd124_9999) begin
            led[3] <= 1'b0;
          end else begin
            led[3] <= 1'b1;
          end
        end else begin
          led[3] <= 1'b0;
        end
      end

    end
  end

endmodule
