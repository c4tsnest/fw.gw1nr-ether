module esc_mii_tx (
    input  logic             clk,
    input  logic             rst_n,
    esc_fifo_if.sink         fifo_in,
    output logic [3:0]       txd,
    output logic             tx_en
);

  import esc_pkg::*;

  localparam int PTR_W = $clog2(TX_FIFO_DEPTH);
  localparam int CNT_W = $clog2(TX_FIFO_DEPTH + 1);

  byte_t tx_fifo [0:TX_FIFO_DEPTH-1];
  logic [PTR_W-1:0] fifo_wr_ptr;
  logic [PTR_W-1:0] fifo_rd_ptr;
  logic [CNT_W-1:0] fifo_count;
  byte_t            fifo_out_byte;
  logic             tx_half;

  assign fifo_out_byte = tx_fifo[fifo_rd_ptr];
  assign fifo_in.full  = (fifo_count == CNT_W'(TX_FIFO_DEPTH));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fifo_wr_ptr <= '0;
      fifo_rd_ptr <= '0;
      fifo_count  <= '0;
      txd         <= '0;
      tx_en       <= 1'b0;
      tx_half     <= 1'b0;
    end else begin
      if (fifo_in.wr_en && !fifo_in.full) begin
        tx_fifo[fifo_wr_ptr] <= fifo_in.wr_data;
        fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
      end

      if (fifo_count != 0) begin
        tx_en <= 1'b1;
        if (!tx_half) begin
          txd     <= fifo_out_byte[3:0];
          tx_half <= 1'b1;
        end else begin
          txd     <= fifo_out_byte[7:4];
          tx_half <= 1'b0;
          fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
        end
      end else begin
        tx_en   <= 1'b0;
        txd     <= '0;
        tx_half <= 1'b0;
      end

      case ({fifo_in.wr_en && !fifo_in.full, (fifo_count != 0) && tx_half})
        2'b10:   fifo_count <= fifo_count + CNT_W'(1);
        2'b01:   fifo_count <= fifo_count - CNT_W'(1);
        default: ;
      endcase
    end
  end

endmodule