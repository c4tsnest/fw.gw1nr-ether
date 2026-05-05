module esc_mii_rx (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [3:0] rxd,
    input  logic       rx_dv,
    output logic [7:0] rx_data,
    output logic       rx_valid,
    output logic       rx_frame_start,
    output logic       rx_frame_end
);

  logic [3:0] rx_low_nibble;
  logic       rx_half;
  logic       rx_dv_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_low_nibble  <= '0;
      rx_half        <= 1'b0;
      rx_dv_d        <= 1'b0;
      rx_data        <= '0;
      rx_valid       <= 1'b0;
      rx_frame_start <= 1'b0;
      rx_frame_end   <= 1'b0;
    end else begin
      rx_dv_d <= rx_dv;

      rx_frame_start = rx_dv && !rx_dv_d;
      rx_frame_end   = !rx_dv && rx_dv_d;

      if (rx_dv && !rx_dv_d) begin
        rx_half <= 1'b0;
      end

      if (!rx_dv && rx_dv_d) begin
        rx_half <= 1'b0;
      end

      if (rx_dv) begin
        if (!rx_half) begin
          rx_low_nibble <= rxd;
          rx_half       <= 1'b1;
          rx_data  = '0;
          rx_valid = 1'b0;
        end else begin
          rx_half <= 1'b0;
          rx_data  = {rxd, rx_low_nibble};
          rx_valid = 1'b1;
        end
      end else begin
        rx_data  = '0;
        rx_valid = 1'b0;
      end

    end
  end

endmodule
