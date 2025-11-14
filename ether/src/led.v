module led (
    input clk,
    input rst_n,
    input linkb,
    input linkc,
    input actb,
    output reg [4:0] led
);

  reg [24:0] counter;

  always @(posedge clk) begin
    if (!rst_n) begin
      counter <= 25'd0;
    end else if (counter < 25'd2499_9999) begin
      counter <= counter + 1'b1;
    end else begin
      counter <= 25'd0;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      led <= 5'b11111;
    end else begin
      if (counter <= 25'd249_9999) begin
        led[0] <= 1'b0;
      end else begin
        led[0] <= 1'b1;
      end

      if (linkb) begin
        led[1] <= 1'b1;
      end else begin
        led[1] <= 1'b0;
      end

      if (linkc) begin
        led[2] <= 1'b1;
      end else begin
        led[2] <= 1'b0;
      end

      if (actb) begin
        if (counter <= 25'd249_9999) begin
          led[3] <= 1'b0;
        end else begin
          led[3] <= 1'b1;
        end
      end else begin
        led[3] <= 1'b1;
      end

    end
  end

endmodule
