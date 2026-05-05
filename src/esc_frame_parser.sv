module esc_frame_parser (
    input  logic          clk,
    input  logic          rst_n,
    input  esc_pkg::byte_t rx_data,
    input  logic          rx_valid,
    input  logic          rx_frame_start,
    output logic [15:0]   byte_idx,
    output logic          is_ethercat,
    output logic          has_preamble,
    output logic [15:0]   frame_offset,
    output logic          preamble_valid
);

  import esc_pkg::*;

  byte_t eth_type_hi;
  logic first_byte;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      byte_idx        <= '0;
      frame_offset    <= '0;
      has_preamble    <= 1'b0;
      preamble_valid  <= 1'b1;
      eth_type_hi     <= '0;
      is_ethercat     <= 1'b0;
      first_byte      <= 1'b0;
    end else begin
      if (rx_frame_start) begin
        byte_idx        <= '0;
        frame_offset    <= '0;
        has_preamble    <= 1'b0;
        preamble_valid  <= 1'b1;
        eth_type_hi     <= '0;
        is_ethercat     <= 1'b0;
        first_byte      <= 1'b1;
      end else if (rx_valid) begin
        if (!first_byte) begin
          byte_idx <= byte_idx + 16'd1;
        end else begin
          first_byte <= 1'b0;
        end

        if (!has_preamble && (byte_idx <= 16'd7)) begin
          if (preamble_valid) begin
            if (byte_idx < 16'd7) begin
              if (rx_data != PREAMBLE_BYTE) preamble_valid <= 1'b0;
            end else begin
              if (rx_data == SFD_BYTE) has_preamble <= 1'b1;
              else preamble_valid <= 1'b0;
            end
          end
        end

        if (byte_idx == 16'(ECAT_ETHERTYPE_OFFSET)) begin
          eth_type_hi <= rx_data;
        end

        if (byte_idx == 16'(ECAT_PREAMBLE_ETHERTYPE_OFS)) begin
          eth_type_hi <= rx_data;
        end

        if ((byte_idx == 16'(ECAT_ETHERTYPE_OFFSET + 1)) &&
            !is_ethercat && !has_preamble) begin
          $display("FP: check ether bi=%d eth=%02x data=%02x", byte_idx, eth_type_hi, rx_data);
          if ((eth_type_hi == ETHERTYPE_HI) && (rx_data == ETHERTYPE_LO)) begin
            is_ethercat  <= 1'b1;
            frame_offset <= '0;
            $display("FP: ETHERCAT DETECTED!");
          end
        end

        if ((byte_idx == 16'(ECAT_PREAMBLE_ETHERTYPE_OFS + 1)) &&
            !is_ethercat && has_preamble) begin
          if ((eth_type_hi == ETHERTYPE_HI) && (rx_data == ETHERTYPE_LO)) begin
            is_ethercat  <= 1'b1;
            frame_offset <= 16'(PREAMBLE_LEN);
          end
        end
      end
    end
  end

endmodule