module esc_crc (
    input  logic            clk,
    input  logic            rst_n,
    input  esc_pkg::byte_t  tx_byte,
    input  logic            tx_byte_valid,
    input  logic            crc_exclude,
    input  logic            frame_start,
    input  logic            frame_end,
    esc_fifo_if.source      fifo_out
);

  import esc_pkg::*;

  logic [31:0] crc_reg;
  byte_t fcs_delay [0:FCS_DELAY-1];
  logic [$clog2(FCS_DELAY+1)-1:0] fcs_count;
  logic       append_active;
  logic [1:0] append_idx;
  logic [31:0] append_value;
  logic       frame_active;

  logic [31:0] crc_next;
  int          bit_idx;

  always_comb begin
    crc_next = crc_reg;
    for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
      if ((crc_next[0] ^ fcs_delay[0][bit_idx]) == 1'b1)
        crc_next = (crc_next >> 1) ^ CRC_POLY;
      else
        crc_next = crc_next >> 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_reg       <= CRC_INIT;
      fcs_delay     <= '{default: '0};
      fcs_count     <= '0;
      append_active <= 1'b0;
      append_idx    <= '0;
      append_value  <= '0;
      frame_active  <= 1'b0;
      fifo_out.wr_en    <= 1'b0;
      fifo_out.wr_data  <= '0;
    end else begin
      fifo_out.wr_en <= 1'b0;

      if (frame_start) begin
        crc_reg       <= CRC_INIT;
        fcs_count     <= '0;
        append_active <= 1'b0;
        frame_active  <= 1'b1;
      end

      if (frame_end) begin
        append_active <= 1'b1;
        append_idx    <= 2'd0;
        append_value  <= ~crc_reg;
        fcs_count     <= '0;
        frame_active  <= 1'b0;
      end

      if (fcs_count < FCS_DELAY'(FCS_DELAY)) begin
        fcs_delay[fcs_count] <= tx_byte;
        fcs_count <= fcs_count + 1'b1;
        if (tx_byte != 8'h00 || tx_byte_valid)
          $display("CRC: fill[%0d] = %02x (valid=%b)", fcs_count, tx_byte, tx_byte_valid);
      end else if (!fifo_out.full && frame_active) begin
        fifo_out.wr_data <= fcs_delay[0];
        fifo_out.wr_en   <= 1'b1;

        fcs_delay[0] <= fcs_delay[1];
        fcs_delay[1] <= fcs_delay[2];
        fcs_delay[2] <= fcs_delay[3];
        fcs_delay[3] <= tx_byte;

        if (tx_byte_valid && !crc_exclude) crc_reg <= crc_next;
      end

      if (!fifo_out.full && append_active) begin
        case (append_idx)
          2'd0: fifo_out.wr_data <= append_value[7:0];
          2'd1: fifo_out.wr_data <= append_value[15:8];
          2'd2: fifo_out.wr_data <= append_value[23:16];
          2'd3: fifo_out.wr_data <= append_value[31:24];
        endcase
        fifo_out.wr_en <= 1'b1;

        if (append_idx == 2'd3)
          append_active <= 1'b0;
        else
          append_idx <= append_idx + 2'd1;
      end
    end
  end

endmodule
