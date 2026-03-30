module ecat_mii_nibble_tx #(
    parameter int unsigned FRAME_MAX_BYTES = 1536
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   tx_start,
    input  logic [10:0]            tx_len,
    input  logic [7:0]             tx_data [0:FRAME_MAX_BYTES-1],
    output logic                   tx_busy,
    output logic [3:0]             txd,
    output logic                   tx_en
);

  logic [10:0] tx_idx;
  logic tx_nibble_sel;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_busy <= 1'b0;
      tx_idx <= '0;
      tx_nibble_sel <= 1'b0;
      txd <= 4'h0;
      tx_en <= 1'b0;
    end else begin
      if (tx_start && !tx_busy && (tx_len != 0)) begin
        tx_busy <= 1'b1;
        tx_idx <= '0;
        tx_nibble_sel <= 1'b0;
      end

      if (tx_busy) begin
        tx_en <= 1'b1;
        txd <= tx_data[tx_idx][(4*tx_nibble_sel)+:4];
        tx_nibble_sel <= ~tx_nibble_sel;

        if (tx_nibble_sel) begin
          if (tx_idx + 11'd1 >= tx_len) begin
            tx_busy <= 1'b0;
          end
          tx_idx <= tx_idx + 11'd1;
        end
      end else begin
        tx_en <= 1'b0;
        txd <= 4'h0;
      end
    end
  end

endmodule