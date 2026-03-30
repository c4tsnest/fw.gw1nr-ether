module esc_minimal_slave #(
    parameter int unsigned REG_SPACE_BYTES = 4096,
    parameter int unsigned FRAME_MAX_BYTES = 1536,
    parameter int unsigned GPIO_OUT_WIDTH = 8,
    parameter int unsigned GPIO_IN_WIDTH = 0
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      link_up,
    input  logic [3:0]                rxd,
    input  logic                      rx_dv,
    output logic [3:0]                txd,
    output logic                      tx_en,
    input  logic [GPIO_IN_WIDTH-1:0]  gpio_in,
    output logic [GPIO_OUT_WIDTH-1:0] gpio_out
);

  localparam logic [7:0] CMD_NOP  = 8'h00;
  localparam logic [7:0] CMD_APRD = 8'h01;
  localparam logic [7:0] CMD_APWR = 8'h02;
  localparam logic [7:0] CMD_APRW = 8'h03;
  localparam logic [7:0] CMD_FPRD = 8'h04;
  localparam logic [7:0] CMD_FPWR = 8'h05;
  localparam logic [7:0] CMD_FPRW = 8'h06;
  localparam logic [7:0] CMD_BRD  = 8'h07;
  localparam logic [7:0] CMD_BWR  = 8'h08;
  localparam logic [7:0] CMD_BRW  = 8'h09;

  localparam int unsigned REG_STATION_ADDR = 16'h0010;
  localparam int unsigned REG_DL_STATUS    = 16'h0110;
  localparam int unsigned REG_AL_CONTROL   = 16'h0120;
  localparam int unsigned REG_AL_STATUS    = 16'h0130;
  localparam int unsigned REG_AL_STATUS_CD = 16'h0134;
  localparam int unsigned REG_SM_BASE      = 16'h0800;
  localparam int unsigned REG_SM_END       = 16'h081f;
  localparam int unsigned REG_DC_BASE      = 16'h0900;
  localparam int unsigned REG_DC_END       = 16'h093f;
  localparam int unsigned REG_DC_TIME      = 16'h0910;
  localparam int unsigned REG_GPIO_OUT     = 16'h0f00;
  localparam int unsigned REG_GPIO_IN      = 16'h0f10;

  localparam int unsigned GPIO_OUT_BYTES = (GPIO_OUT_WIDTH + 7) / 8;
  localparam int unsigned GPIO_IN_BYTES = (GPIO_IN_WIDTH + 7) / 8;

  logic [7:0] reg_mem[0:REG_SPACE_BYTES-1];
  logic [7:0] rx_frame[0:FRAME_MAX_BYTES-1];
  logic [7:0] tx_frame[0:FRAME_MAX_BYTES-1];
  logic [10:0] rx_len;
  logic [10:0] tx_len;
  logic frame_done;
  logic tx_start;
  logic tx_busy;

  logic [63:0] dc_time_counter;

  logic [3:0] al_state;
  logic [15:0] al_status_code;
  logic al_req_valid;
  logic [3:0] al_req_state;

  integer i;
  integer s;

  function automatic logic [7:0] reg_rd8(input int unsigned addr);
    if (addr < REG_SPACE_BYTES) reg_rd8 = reg_mem[addr];
    else reg_rd8 = 8'h00;
  endfunction

  function automatic logic [15:0] reg_rd16(input int unsigned addr);
    reg_rd16 = {reg_rd8(addr + 1), reg_rd8(addr)};
  endfunction

  ecat_mii_nibble_rx #(
      .FRAME_MAX_BYTES(FRAME_MAX_BYTES)
  ) u_mii_rx (
      .clk(clk),
      .rst_n(rst_n),
      .rxd(rxd),
      .rx_dv(rx_dv),
      .frame_done(frame_done),
      .frame_len(rx_len),
      .frame_data(rx_frame)
  );

  ecat_mii_nibble_tx #(
      .FRAME_MAX_BYTES(FRAME_MAX_BYTES)
  ) u_mii_tx (
      .clk(clk),
      .rst_n(rst_n),
      .tx_start(tx_start),
      .tx_len(tx_len),
      .tx_data(tx_frame),
      .tx_busy(tx_busy),
      .txd(txd),
      .tx_en(tx_en)
  );

  esc_al_fsm u_al_fsm (
      .clk(clk),
      .rst_n(rst_n),
      .req_valid(al_req_valid),
      .req_state(al_req_state),
      .al_state(al_state),
      .al_status_code(al_status_code)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < REG_SPACE_BYTES; i++) begin
        reg_mem[i] <= 8'h00;
      end

      reg_mem[16'h0000] <= 8'h11;
      reg_mem[16'h0001] <= 8'h01;
      reg_mem[16'h0008] <= 8'h34;
      reg_mem[16'h0009] <= 8'h12;
      reg_mem[16'h000a] <= 8'h00;
      reg_mem[16'h000b] <= 8'h00;
      reg_mem[16'h000c] <= 8'h01;
      reg_mem[16'h000d] <= 8'h00;
      reg_mem[16'h000e] <= 8'h00;
      reg_mem[16'h000f] <= 8'h00;

      reg_mem[REG_SM_BASE + 0] <= 8'h00;
      reg_mem[REG_SM_BASE + 1] <= 8'h10;
      reg_mem[REG_SM_BASE + 8] <= 8'h80;
      reg_mem[REG_SM_BASE + 9] <= 8'h10;
      reg_mem[REG_SM_BASE + 16] <= 8'h00;
      reg_mem[REG_SM_BASE + 17] <= 8'h12;
      reg_mem[REG_SM_BASE + 24] <= 8'h80;
      reg_mem[REG_SM_BASE + 25] <= 8'h12;

      tx_len        <= '0;
      tx_start      <= 1'b0;
      al_req_valid  <= 1'b0;
      al_req_state  <= 4'h0;

      dc_time_counter <= 64'd0;

      gpio_out <= '0;
    end else begin
      dc_time_counter <= dc_time_counter + 64'd1;
      tx_start <= 1'b0;
      al_req_valid <= 1'b0;

      reg_mem[REG_DL_STATUS] <= {7'b0, link_up};
      reg_mem[REG_AL_STATUS] <= {4'b0, al_state};
      reg_mem[REG_AL_STATUS_CD] <= al_status_code[7:0];
      reg_mem[REG_AL_STATUS_CD+1] <= al_status_code[15:8];

      for (i = 0; i < 8; i++) begin
        reg_mem[REG_DC_TIME + i] <= dc_time_counter[(8*i)+:8];
      end

      for (i = 0; i < GPIO_OUT_BYTES; i++) begin
        reg_mem[REG_GPIO_OUT + i] <= gpio_out[(8*i)+:8];
      end

      if (GPIO_IN_WIDTH > 0) begin
        for (i = 0; i < GPIO_IN_BYTES; i++) begin
          reg_mem[REG_GPIO_IN + i] <= gpio_in[(8*i)+:8];
        end
      end

      if (frame_done) begin
        int unsigned frame_start;
        int unsigned frame_len;
        logic is_ethercat;
        logic [7:0] cmd;
        logic [15:0] adp;
        logic [15:0] ado;
        logic [10:0] dlen;
        int unsigned dg_start;
        int unsigned data_ofs;
        int unsigned wkc_ofs;
        logic addr_match;
        logic do_read;
        logic do_write;
        logic [15:0] current_wkc;

        frame_start = 0;
        frame_len = rx_len;
        if ((rx_len > 16) && (rx_frame[0] == 8'h55)) begin
          for (s = 0; s + 8 < rx_len; s++) begin
            if ((rx_frame[s + 0] == 8'h55) && (rx_frame[s + 1] == 8'h55) && (rx_frame[s + 2] == 8'h55) &&
                (rx_frame[s + 3] == 8'h55) && (rx_frame[s + 4] == 8'h55) && (rx_frame[s + 5] == 8'h55) &&
                (rx_frame[s + 6] == 8'h55) && (rx_frame[s + 7] == 8'hd5)) begin
              frame_start = s + 8;
              break;
            end
          end
          frame_len = rx_len - frame_start;
        end

        for (i = 0; i < frame_len; i++) begin
          tx_frame[i] <= rx_frame[frame_start + i];
        end
        tx_len <= frame_len[10:0];

        is_ethercat = 1'b0;
        if (frame_len >= 28) begin
          if ((rx_frame[frame_start + 12] == 8'h88) && (rx_frame[frame_start + 13] == 8'ha4)) begin
            is_ethercat = 1'b1;
          end
        end

        if (is_ethercat) begin
          dg_start = 16;
          cmd = rx_frame[frame_start + dg_start + 0];
          adp = {rx_frame[frame_start + dg_start + 3], rx_frame[frame_start + dg_start + 2]};
          ado = {rx_frame[frame_start + dg_start + 5], rx_frame[frame_start + dg_start + 4]};
          dlen = {rx_frame[frame_start + dg_start + 7], rx_frame[frame_start + dg_start + 6]} & 11'h7ff;
          data_ofs = dg_start + 10;
          wkc_ofs = data_ofs + dlen;

          addr_match = 1'b0;
          do_read = 1'b0;
          do_write = 1'b0;

          case (cmd)
            CMD_APRD: begin
              addr_match = (adp == 16'h0000);
              do_read = 1'b1;
            end
            CMD_APWR: begin
              addr_match = (adp == 16'h0000);
              do_write = 1'b1;
            end
            CMD_APRW: begin
              addr_match = (adp == 16'h0000);
              do_read = 1'b1;
              do_write = 1'b1;
            end
            CMD_FPRD: begin
              addr_match = (adp == reg_rd16(REG_STATION_ADDR));
              do_read = 1'b1;
            end
            CMD_FPWR: begin
              addr_match = (adp == reg_rd16(REG_STATION_ADDR));
              do_write = 1'b1;
            end
            CMD_FPRW: begin
              addr_match = (adp == reg_rd16(REG_STATION_ADDR));
              do_read = 1'b1;
              do_write = 1'b1;
            end
            CMD_BRD: begin
              addr_match = 1'b1;
              do_read = 1'b1;
            end
            CMD_BWR: begin
              addr_match = 1'b1;
              do_write = 1'b1;
            end
            CMD_BRW: begin
              addr_match = 1'b1;
              do_read = 1'b1;
              do_write = 1'b1;
            end
            default: begin
              addr_match = 1'b0;
              do_read = 1'b0;
              do_write = 1'b0;
            end
          endcase

          if (addr_match && (frame_len >= (wkc_ofs + 2))) begin
            if (do_write) begin
              logic [3:0] requested_al_state;
              for (i = 0; i < dlen; i++) begin
                int unsigned target_addr;
                target_addr = ado + i;
                if ((target_addr < REG_SPACE_BYTES) &&
                    !((target_addr == REG_DL_STATUS) ||
                      (target_addr == REG_AL_STATUS) ||
                      (target_addr == REG_AL_STATUS_CD) ||
                      (target_addr == (REG_AL_STATUS_CD + 1)) ||
                      ((target_addr >= REG_DC_BASE) && (target_addr <= REG_DC_END)) ||
                      ((target_addr >= REG_GPIO_IN) && (target_addr < (REG_GPIO_IN + GPIO_IN_BYTES))))) begin
                  reg_mem[target_addr] <= rx_frame[frame_start + data_ofs + i];
                end
              end

              if ((ado <= REG_AL_CONTROL) && ((ado + dlen) > REG_AL_CONTROL)) begin
                requested_al_state = rx_frame[frame_start + data_ofs + (REG_AL_CONTROL - ado)][3:0];
                al_req_state <= requested_al_state;
                al_req_valid <= 1'b1;
              end

              for (i = 0; i < GPIO_OUT_BYTES; i++) begin
                if ((ado <= (REG_GPIO_OUT + i)) && ((ado + dlen) > (REG_GPIO_OUT + i))) begin
                  gpio_out[(8*i)+:8] <= rx_frame[frame_start + data_ofs + (REG_GPIO_OUT + i - ado)];
                end
              end
            end

            if (do_read) begin
              for (i = 0; i < dlen; i++) begin
                int unsigned src_addr;
                src_addr = ado + i;
                if (src_addr < REG_SPACE_BYTES) tx_frame[data_ofs+i] <= reg_mem[src_addr];
                else tx_frame[data_ofs+i] <= 8'h00;
              end
            end

            current_wkc = {rx_frame[frame_start + wkc_ofs + 1], rx_frame[frame_start + wkc_ofs]};
            current_wkc = current_wkc + 16'h0001;
            tx_frame[wkc_ofs] <= current_wkc[7:0];
            tx_frame[wkc_ofs+1] <= current_wkc[15:8];
          end
        end

        if (!tx_busy && (frame_len != 0)) begin
          tx_len <= frame_len[10:0];
          tx_start <= 1'b1;
        end
      end
    end
  end

endmodule