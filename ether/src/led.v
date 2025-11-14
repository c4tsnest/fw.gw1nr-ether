module led (
    input clk,
    input rst_n,
    input linkb,
    input linkc,
    input actb,
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

      if (linkb) begin
        led[1] <= 1'b1;
      end else begin
        if (actb) begin
          if (counter_2p5M <= 25'd124_9999) begin
            led[1] <= 1'b0;
          end else begin
            led[1] <= 1'b1;
          end
        end else begin
          led[1] <= 1'b0;
        end
      end

      if (linkc) begin
        led[2] <= 1'b1;
      end else begin
        led[2] <= 1'b0;
      end

    end
  end

endmodule
