interface esc_rx_byte_if;
  logic [7:0] data;
  logic       valid;
  logic       frame_start;
  logic       frame_end;

  modport source(output data, valid, frame_start, frame_end);

  modport sink(input data, valid, frame_start, frame_end);
endinterface

interface esc_tx_byte_if;
  logic [7:0] data;
  logic       valid;

  modport source(output data, valid);

  modport sink(input data, valid);
endinterface

interface esc_reg_if #(
    parameter int unsigned ADDR_W = 16,
    parameter int unsigned DATA_W = 8
);
  logic [ADDR_W-1:0] rd_addr;
  logic [DATA_W-1:0] rd_data;
  logic [ADDR_W-1:0] wr_addr;
  logic [DATA_W-1:0] wr_data;
  logic              wr_en;
  logic              wr_ack;
  logic              write_hit_cmb;

  modport master(output rd_addr, wr_addr, wr_data, wr_en, input rd_data, wr_ack, write_hit_cmb);

  modport slave(input rd_addr, wr_addr, wr_data, wr_en, output rd_data, wr_ack, write_hit_cmb);
endinterface

interface esc_fifo_if #(
    parameter int unsigned DATA_W = 8
);
  logic [DATA_W-1:0] wr_data;
  logic              wr_en;
  logic              full;

  modport source(output wr_data, wr_en, input full);

  modport sink(input wr_data, wr_en, output full);
endinterface

interface esc_phy_if;
  logic [3:0] rxd;
  logic       rx_dv;
  logic [3:0] txd;
  logic       tx_en;

  modport source(output rxd, rx_dv, input txd, tx_en);

  modport sink(input rxd, rx_dv, output txd, tx_en);
endinterface
