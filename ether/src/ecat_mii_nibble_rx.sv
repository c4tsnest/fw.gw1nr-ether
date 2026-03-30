module ecat_mii_nibble_rx #(
    parameter int unsigned FRAME_MAX_BYTES = 1536
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic [3:0]             rxd,
    input  logic                   rx_dv,
    output logic                   frame_done,
    output logic [10:0]            frame_len,
    output logic [7:0]             frame_data [0:FRAME_MAX_BYTES-1]
);

  logic rx_dv_d;
  logic rx_byte_half;
  logic [3:0] rx_low_nibble;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_dv_d <= 1'b0;
      rx_byte_half <= 1'b0;
      rx_low_nibble <= 4'h0;
      frame_done <= 1'b0;
      frame_len <= '0;
    end else begin
      frame_done <= 1'b0;
      rx_dv_d <= rx_dv;

      if (rx_dv) begin
        if (!rx_byte_half) begin
          rx_low_nibble <= rxd;
          rx_byte_half <= 1'b1;
        end else begin
          if (frame_len < FRAME_MAX_BYTES) begin
            frame_data[frame_len] <= {rxd, rx_low_nibble};
            frame_len <= frame_len + 11'd1;
          end
          rx_byte_half <= 1'b0;
        end
      end

      if ((!rx_dv) && rx_dv_d) begin
        frame_done <= 1'b1;
        rx_byte_half <= 1'b0;
      end

      if (frame_done) begin
        frame_len <= '0;
      end
    end
  end

endmodule