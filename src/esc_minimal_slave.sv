module esc_minimal_slave #(
    parameter int unsigned CORE_REG_BYTES = 16'h0140,
    parameter int unsigned SM_REG_BYTES = 32,
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
    output logic [GPIO_OUT_WIDTH-1:0] gpio_out,
    output logic                      debug_ethercat,
    output logic                      debug_addr_match,
    output logic                      debug_wkc_inc
);

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
  localparam int unsigned REG_ALIAS        = 16'h0012;
  localparam int unsigned REG_PORTDES      = 16'h0007;
  localparam int unsigned REG_ESCSUP       = 16'h0008;
  localparam int unsigned REG_DL_CONTROL   = 16'h0100;
  localparam int unsigned REG_DL_PORT      = 16'h0101;
  localparam int unsigned REG_DL_ALIAS     = 16'h0103;
  localparam int unsigned REG_DL_STATUS    = 16'h0110;
  localparam int unsigned REG_AL_CONTROL   = 16'h0120;
  localparam int unsigned REG_AL_STATUS    = 16'h0130;
  localparam int unsigned REG_AL_STATUS_CD = 16'h0134;
  localparam int unsigned REG_PDI_CONTROL  = 16'h0140;
  localparam int unsigned REG_IRQ_MASK     = 16'h0200;
  localparam int unsigned REG_EEP_CFG      = 16'h0500;
  localparam int unsigned REG_EEP_STAT     = 16'h0502;
  localparam int unsigned REG_FMMU_BASE    = 16'h0600;
  localparam int unsigned REG_FMMU_BYTES   = 64;
  localparam int unsigned REG_SM_BASE      = 16'h0800;
  localparam int unsigned REG_DC_BASE      = 16'h0900;
  localparam int unsigned REG_DC_END       = 16'h093f;
  localparam int unsigned REG_DC_TIME      = 16'h0910;
  localparam int unsigned REG_DC_SYNC_ACT  = 16'h0981;
  localparam int unsigned REG_GPIO_OUT     = 16'h0f00;
  localparam int unsigned REG_GPIO_IN      = 16'h0f10;
  localparam int unsigned REG_DEBUG_WKC    = 16'h0f20;

  localparam logic [15:0] DLSTATUS_PORT0_LINK = 16'h0200;

  localparam int unsigned GPIO_OUT_BYTES = (GPIO_OUT_WIDTH + 7) / 8;
  localparam int unsigned GPIO_IN_BYTES = (GPIO_IN_WIDTH + 7) / 8;
  localparam int unsigned TX_FIFO_DEPTH = 8;
  localparam int unsigned REG_CORE_BASE = 16'h0000;

  typedef enum logic [1:0] {
    REG_NONE = 2'b00,
    REG_R = 2'b01,
    REG_W = 2'b10,
    REG_RW = 2'b11
  } reg_access_t;

  logic [7:0] reg_core[0:CORE_REG_BYTES-1];
  logic [7:0] reg_sm[0:SM_REG_BYTES-1];
  logic [7:0] reg_fmmu[0:REG_FMMU_BYTES-1];
  logic [7:0] tx_fifo[0:TX_FIFO_DEPTH-1];

  logic [15:0] reg_irq_mask;
  logic [15:0] reg_eep_cfg;
  logic [15:0] reg_eep_stat;
  logic [7:0] reg_pdi_control;
  logic [7:0] reg_dc_sync_act;

  logic [15:0] debug_wkc_value;

  logic [63:0] dc_time_counter;
  logic [3:0] al_state;
  logic [15:0] al_status_code;
  logic al_req_valid;
  logic [3:0] al_req_state;

  logic [3:0] rx_low_nibble;
  logic rx_half;
  logic rx_dv_d;

  logic [7:0] fifo_out_byte;
  logic push_now;
  logic pop_now;
  logic [$clog2(TX_FIFO_DEPTH)-1:0] fifo_wr_ptr;
  logic [$clog2(TX_FIFO_DEPTH)-1:0] fifo_rd_ptr;
  logic [$clog2(TX_FIFO_DEPTH+1)-1:0] fifo_count;

  logic tx_half;

  logic [15:0] byte_idx;
  logic [15:0] frame_offset;
  logic has_preamble;
  logic preamble_valid;
  logic [7:0] eth_type_hi;
  logic is_ethercat;
  logic [7:0] cmd_reg;
  logic [15:0] adp_reg;
  logic [15:0] ado_reg;
  logic [10:0] dlen_reg;
  logic [15:0] data_start_idx;
  logic [15:0] wkc_start_idx;
  logic addr_match;
  logic do_read;
  logic do_write;
  logic read_success;
  logic write_success;
  logic is_auto_inc_cmd;
  logic adp_dec_borrow;
  logic [1:0] wkc_inc_value;
  logic wkc_carry;

  logic [31:0] crc_reg;
  logic [7:0] fcs_delay0;
  logic [7:0] fcs_delay1;
  logic [7:0] fcs_delay2;
  logic [7:0] fcs_delay3;
  logic [2:0] fcs_delay_count;
  logic append_crc_active;
  logic [1:0] append_crc_idx;
  logic [31:0] append_crc_value;

  integer i;

  function automatic logic addr_in_window(
      input int unsigned addr,
      input int unsigned base,
      input int unsigned size
  );
    addr_in_window = (addr >= base) && (addr < (base + size));
  endfunction

  function automatic logic [7:0] reg_rd8(input int unsigned addr);
    if (addr == REG_DL_STATUS) begin
      reg_rd8 = link_up ? DLSTATUS_PORT0_LINK[7:0] : 8'h00;
    end else if (addr == (REG_DL_STATUS + 1)) begin
      reg_rd8 = link_up ? DLSTATUS_PORT0_LINK[15:8] : 8'h00;
    end else if (addr == REG_PDI_CONTROL) begin
      reg_rd8 = reg_pdi_control;
    end else if ((addr >= REG_IRQ_MASK) && (addr < (REG_IRQ_MASK + 2))) begin
      reg_rd8 = reg_irq_mask[(addr - REG_IRQ_MASK) * 8 +: 8];
    end else if ((addr >= REG_EEP_CFG) && (addr < (REG_EEP_CFG + 2))) begin
      reg_rd8 = reg_eep_cfg[(addr - REG_EEP_CFG) * 8 +: 8];
    end else if ((addr >= REG_EEP_STAT) && (addr < (REG_EEP_STAT + 2))) begin
      reg_rd8 = reg_eep_stat[(addr - REG_EEP_STAT) * 8 +: 8];
    end else if (addr == REG_DC_SYNC_ACT) begin
      reg_rd8 = reg_dc_sync_act;
    end else if (addr_in_window(addr, REG_FMMU_BASE, REG_FMMU_BYTES)) begin
      reg_rd8 = reg_fmmu[addr - REG_FMMU_BASE];
    end else if (addr == REG_AL_STATUS) begin
      reg_rd8 = {4'b0, al_state};
    end else if (addr == REG_AL_STATUS_CD) begin
      reg_rd8 = al_status_code[7:0];
    end else if (addr == (REG_AL_STATUS_CD + 1)) begin
      reg_rd8 = al_status_code[15:8];
    end else if ((addr >= REG_DC_TIME) && (addr < (REG_DC_TIME + 8))) begin
      reg_rd8 = dc_time_counter[((addr - REG_DC_TIME) * 8) +: 8];
    end else if ((addr >= REG_GPIO_OUT) && (addr < (REG_GPIO_OUT + GPIO_OUT_BYTES))) begin
      reg_rd8 = gpio_out[((addr - REG_GPIO_OUT) * 8) +: 8];
    end else if ((GPIO_IN_WIDTH > 0) && (addr >= REG_GPIO_IN) && (addr < (REG_GPIO_IN + GPIO_IN_BYTES))) begin
      reg_rd8 = gpio_in[((addr - REG_GPIO_IN) * 8) +: 8];
    end else if ((addr >= REG_DEBUG_WKC) && (addr < (REG_DEBUG_WKC + 2))) begin
      reg_rd8 = debug_wkc_value[((addr - REG_DEBUG_WKC) * 8) +: 8];
    end else if (addr_in_window(addr, REG_CORE_BASE, CORE_REG_BYTES)) begin
      reg_rd8 = reg_core[addr - REG_CORE_BASE];
    end else if (addr_in_window(addr, REG_SM_BASE, SM_REG_BYTES)) begin
      reg_rd8 = reg_sm[addr - REG_SM_BASE];
    end else begin
      reg_rd8 = 8'h00;
    end
  endfunction

  function automatic logic [15:0] reg_rd16(input int unsigned addr);
    reg_rd16 = {reg_rd8(addr + 1), reg_rd8(addr)};
  endfunction

  function automatic reg_access_t reg_access(input int unsigned addr);
    reg_access = REG_NONE;

    if (addr_in_window(addr, REG_CORE_BASE, CORE_REG_BYTES)) begin
      reg_access = REG_RW;
    end
    if (addr_in_window(addr, REG_SM_BASE, SM_REG_BYTES)) begin
      reg_access = REG_RW;
    end
    if ((addr >= REG_GPIO_OUT) && (addr < (REG_GPIO_OUT + GPIO_OUT_BYTES))) begin
      reg_access = REG_RW;
    end
    if ((addr >= REG_IRQ_MASK) && (addr < (REG_IRQ_MASK + 2))) begin
      reg_access = REG_RW;
    end
    if ((addr >= REG_EEP_CFG) && (addr < (REG_EEP_CFG + 2))) begin
      reg_access = REG_RW;
    end
    if (addr_in_window(addr, REG_FMMU_BASE, REG_FMMU_BYTES)) begin
      reg_access = REG_RW;
    end
    if (addr == REG_DC_SYNC_ACT) begin
      reg_access = REG_RW;
    end

    if ((addr == 16'h0000) || (addr == 16'h0001)) begin
      reg_access = REG_R;
    end
    if (addr == REG_PORTDES) begin
      reg_access = REG_R;
    end
    if ((addr == REG_ESCSUP) || (addr == (REG_ESCSUP + 1))) begin
      reg_access = REG_R;
    end
    if (addr == REG_PDI_CONTROL) begin
      reg_access = REG_R;
    end
    if ((addr >= REG_EEP_STAT) && (addr < (REG_EEP_STAT + 2))) begin
      reg_access = REG_R;
    end

    if ((addr >= REG_DC_BASE) && (addr <= REG_DC_END)) begin
      reg_access = REG_R;
    end
    if ((addr == REG_DL_STATUS) || (addr == (REG_DL_STATUS + 1))) begin
      reg_access = REG_R;
    end
    if (addr == REG_AL_STATUS) begin
      reg_access = REG_R;
    end
    if ((addr == REG_AL_STATUS_CD) || (addr == (REG_AL_STATUS_CD + 1))) begin
      reg_access = REG_R;
    end
    if ((addr >= REG_GPIO_IN) && (addr < (REG_GPIO_IN + GPIO_IN_BYTES))) begin
      reg_access = REG_R;
    end

    if (addr == REG_AL_CONTROL) begin
      reg_access = REG_W;
    end
  endfunction

  function automatic logic reg_can_read(input int unsigned addr);
    reg_can_read = (reg_access(addr) == REG_R) || (reg_access(addr) == REG_RW);
  endfunction

  function automatic logic reg_can_write(input int unsigned addr);
    reg_can_write = (reg_access(addr) == REG_W) || (reg_access(addr) == REG_RW);
  endfunction

  function automatic logic [31:0] crc32_update_byte(
      input logic [31:0] crc_in,
      input logic [7:0] data
  );
    logic [31:0] crc_next;
    int bit_idx;
    begin
      crc_next = crc_in;
      for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
        if ((crc_next[0] ^ data[bit_idx]) == 1'b1) begin
          crc_next = (crc_next >> 1) ^ 32'hEDB88320;
        end else begin
          crc_next = (crc_next >> 1);
        end
      end
      crc32_update_byte = crc_next;
    end
  endfunction

  esc_al_fsm u_al_fsm (
      .clk(clk),
      .rst_n(rst_n),
      .req_valid(al_req_valid),
      .req_state(al_req_state),
      .al_state(al_state),
      .al_status_code(al_status_code)
  );

  assign fifo_out_byte = tx_fifo[fifo_rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < CORE_REG_BYTES; i++) begin
        reg_core[i] <= 8'h00;
      end
      for (i = 0; i < SM_REG_BYTES; i++) begin
        reg_sm[i] <= 8'h00;
      end
      for (i = 0; i < REG_FMMU_BYTES; i++) begin
        reg_fmmu[i] <= 8'h00;
      end

      reg_core[16'h0000] <= 8'h11;
      reg_core[16'h0001] <= 8'h01;
      reg_core[REG_PORTDES] <= 8'h01;
      reg_core[REG_ESCSUP] <= 8'h00;
      reg_core[REG_ESCSUP + 1] <= 8'h00;
      reg_core[16'h000a] <= 8'h00;
      reg_core[16'h000b] <= 8'h00;
      reg_core[16'h000c] <= 8'h01;
      reg_core[16'h000d] <= 8'h00;
      reg_core[16'h000e] <= 8'h00;
      reg_core[16'h000f] <= 8'h00;

      reg_sm[0] <= 8'h00;
      reg_sm[1] <= 8'h10;
      reg_sm[8] <= 8'h80;
      reg_sm[9] <= 8'h10;
      reg_sm[16] <= 8'h00;
      reg_sm[17] <= 8'h12;
      reg_sm[24] <= 8'h80;
      reg_sm[25] <= 8'h12;

      dc_time_counter <= 64'd0;
      gpio_out <= '0;
      reg_irq_mask <= 16'h0000;
      reg_eep_cfg <= 16'h0000;
      reg_eep_stat <= 16'h0000;
      reg_pdi_control <= 8'h00;
      reg_dc_sync_act <= 8'h00;

      rx_low_nibble <= 4'h0;
      rx_half <= 1'b0;
      rx_dv_d <= 1'b0;

      txd <= 4'h0;
      tx_en <= 1'b0;
      tx_half <= 1'b0;

      fifo_wr_ptr <= '0;
      fifo_rd_ptr <= '0;
      fifo_count <= '0;
      push_now <= 1'b0;
      pop_now <= 1'b0;

      byte_idx <= 16'd0;
      frame_offset <= 16'd0;
      has_preamble <= 1'b0;
      preamble_valid <= 1'b1;
      eth_type_hi <= 8'h00;
      is_ethercat <= 1'b0;
      cmd_reg <= 8'h00;
      adp_reg <= 16'h0000;
      ado_reg <= 16'h0000;
      dlen_reg <= 11'd0;
      data_start_idx <= 16'd26;
      wkc_start_idx <= 16'd26;
      addr_match <= 1'b0;
      do_read <= 1'b0;
      do_write <= 1'b0;
      read_success <= 1'b0;
      write_success <= 1'b0;
      is_auto_inc_cmd <= 1'b0;
      adp_dec_borrow <= 1'b0;
      wkc_inc_value <= 2'd0;
      wkc_carry <= 1'b0;

      crc_reg <= 32'hFFFF_FFFF;
      fcs_delay0 <= 8'h00;
      fcs_delay1 <= 8'h00;
      fcs_delay2 <= 8'h00;
      fcs_delay3 <= 8'h00;
      fcs_delay_count <= 3'd0;
      append_crc_active <= 1'b0;
      append_crc_idx <= 2'd0;
      append_crc_value <= 32'h0000_0000;

      al_req_valid <= 1'b0;
      al_req_state <= 4'h0;

      debug_ethercat <= 1'b0;
      debug_addr_match <= 1'b0;
      debug_wkc_inc <= 1'b0;
      debug_wkc_value <= 16'h0000;
    end else begin
      dc_time_counter <= dc_time_counter + 64'd1;
      rx_dv_d <= rx_dv;
      al_req_valid <= 1'b0;
      
      // Default: clear all debug pulses each cycle
      debug_ethercat <= 1'b0;
      debug_addr_match <= 1'b0;
      debug_wkc_inc <= 1'b0;
      
      push_now = 1'b0;
      pop_now = 1'b0;

      if (rx_dv && !rx_dv_d) begin
        byte_idx <= 16'd0;
        frame_offset <= 16'd0;
        has_preamble <= 1'b0;
        preamble_valid <= 1'b1;
        eth_type_hi <= 8'h00;
        is_ethercat <= 1'b0;
        cmd_reg <= 8'h00;
        adp_reg <= 16'h0000;
        ado_reg <= 16'h0000;
        dlen_reg <= 11'd0;
        data_start_idx <= 16'd26;
        wkc_start_idx <= 16'd26;
        addr_match <= 1'b0;
        do_read <= 1'b0;
        do_write <= 1'b0;
        read_success <= 1'b0;
        write_success <= 1'b0;
        is_auto_inc_cmd <= 1'b0;
        adp_dec_borrow <= 1'b0;
        wkc_inc_value <= 2'd0;
        wkc_carry <= 1'b0;
        crc_reg <= 32'hFFFF_FFFF;
        fcs_delay0 <= 8'h00;
        fcs_delay1 <= 8'h00;
        fcs_delay2 <= 8'h00;
        fcs_delay3 <= 8'h00;
        fcs_delay_count <= 3'd0;
        append_crc_active <= 1'b0;
        append_crc_idx <= 2'd0;
        append_crc_value <= 32'h0000_0000;
        rx_half <= 1'b0;
      end

      if (rx_dv) begin
        if (!rx_half) begin
          rx_low_nibble <= rxd;
          rx_half <= 1'b1;
        end else begin
          logic [7:0] rx_byte;
          logic [7:0] tx_byte;
          logic [7:0] emit_byte;
          logic emit_valid;
          logic [15:0] byte_addr;
          logic [15:0] station_addr;
          logic [15:0] cmd_idx;
          logic [15:0] adp_lo_idx;
          logic [15:0] adp_hi_idx;
          logic [15:0] ado_lo_idx;
          logic [15:0] ado_hi_idx;
          logic [15:0] dlen_lo_idx;
          logic [15:0] dlen_hi_idx;
          logic [1:0] wkc_inc_calc;
          logic low_overflow;

          rx_byte = {rxd, rx_low_nibble};
          tx_byte = rx_byte;
          emit_byte = 8'h00;
          emit_valid = 1'b0;

          if (!has_preamble && (byte_idx <= 16'd7)) begin
            if (preamble_valid) begin
              if (byte_idx < 16'd7) begin
                if (rx_byte != 8'h55) begin
                  preamble_valid <= 1'b0;
                end
              end else begin
                if (rx_byte == 8'hD5) begin
                  has_preamble <= 1'b1;
                end else begin
                  preamble_valid <= 1'b0;
                end
              end
            end
          end

          if ((byte_idx == 16'd12) || (byte_idx == 16'd20)) begin
            eth_type_hi <= rx_byte;
          end
          if ((byte_idx == 16'd13) && !is_ethercat && !has_preamble) begin
            if ((eth_type_hi == 8'h88) && (rx_byte == 8'hA4)) begin
              is_ethercat <= 1'b1;
              frame_offset <= 16'd0;
              debug_ethercat <= 1'b1;
            end
          end
          if ((byte_idx == 16'd21) && !is_ethercat && has_preamble) begin
            if ((eth_type_hi == 8'h88) && (rx_byte == 8'hA4)) begin
              is_ethercat <= 1'b1;
              frame_offset <= 16'd8;
              debug_ethercat <= 1'b1;
            end
          end

          if (is_ethercat) begin
            cmd_idx = 16'd16 + frame_offset;
            adp_lo_idx = 16'd18 + frame_offset;
            adp_hi_idx = 16'd19 + frame_offset;
            ado_lo_idx = 16'd20 + frame_offset;
            ado_hi_idx = 16'd21 + frame_offset;
            dlen_lo_idx = 16'd22 + frame_offset;
            dlen_hi_idx = 16'd23 + frame_offset;

            if (byte_idx == cmd_idx) begin
                cmd_reg <= rx_byte;
                case (rx_byte)
                  CMD_APRD: begin
                    is_auto_inc_cmd <= 1'b1;
                  end
                  CMD_APWR: begin
                    is_auto_inc_cmd <= 1'b1;
                  end
                  CMD_APRW: begin
                    is_auto_inc_cmd <= 1'b1;
                  end
                  CMD_FPRD, CMD_BRD: begin
                    is_auto_inc_cmd <= 1'b0;
                  end
                  CMD_FPWR, CMD_BWR: begin
                    is_auto_inc_cmd <= 1'b0;
                  end
                  CMD_FPRW, CMD_BRW: begin
                    is_auto_inc_cmd <= 1'b0;
                  end
                  default: begin
                    is_auto_inc_cmd <= 1'b0;
                  end
                endcase
            end else if (byte_idx == adp_lo_idx) begin
                adp_reg[7:0] <= rx_byte;
                if (is_auto_inc_cmd) begin
                  tx_byte = rx_byte - 8'h01;
                  adp_dec_borrow <= (rx_byte == 8'h00);
                end
            end else if (byte_idx == adp_hi_idx) begin
                adp_reg[15:8] <= rx_byte;
                if (is_auto_inc_cmd) begin
                  tx_byte = rx_byte - {7'd0, adp_dec_borrow};
                end
            end else if (byte_idx == ado_lo_idx) begin
              ado_reg[7:0] <= rx_byte;
            end else if (byte_idx == ado_hi_idx) begin
              ado_reg[15:8] <= rx_byte;
            end else if (byte_idx == dlen_lo_idx) begin
              dlen_reg[7:0] <= rx_byte;
            end else if (byte_idx == dlen_hi_idx) begin
                logic addr_match_computed;

                dlen_reg[10:8] <= rx_byte[2:0];
                data_start_idx <= 16'd26 + frame_offset;
                wkc_start_idx <= (16'd26 + frame_offset) + {5'd0, rx_byte[2:0], dlen_reg[7:0]};

                station_addr = reg_rd16(REG_STATION_ADDR);
                do_read <= 1'b0;
                do_write <= 1'b0;
                read_success <= 1'b0;
                write_success <= 1'b0;
                addr_match_computed = 1'b0;
                
                case (cmd_reg)
                  CMD_APRD: begin
                    addr_match_computed = (adp_reg == 16'h0000);
                    do_read <= 1'b1;
                  end
                  CMD_APWR: begin
                    addr_match_computed = (adp_reg == 16'h0000);
                    do_write <= 1'b1;
                  end
                  CMD_APRW: begin
                    addr_match_computed = (adp_reg == 16'h0000);
                    do_read <= 1'b1;
                    do_write <= 1'b1;
                  end
                  CMD_FPRD: begin
                    addr_match_computed = (adp_reg == station_addr);
                    do_read <= 1'b1;
                  end
                  CMD_FPWR: begin
                    addr_match_computed = (adp_reg == station_addr);
                    do_write <= 1'b1;
                  end
                  CMD_FPRW: begin
                    addr_match_computed = (adp_reg == station_addr);
                    do_read <= 1'b1;
                    do_write <= 1'b1;
                  end
                  CMD_BRD: begin
                    addr_match_computed = 1'b1;
                    do_read <= 1'b1;
                  end
                  CMD_BWR: begin
                    addr_match_computed = 1'b1;
                    do_write <= 1'b1;
                  end
                  CMD_BRW: begin
                    addr_match_computed = 1'b1;
                    do_read <= 1'b1;
                    do_write <= 1'b1;
                  end
                  default: begin
                    addr_match_computed = 1'b0;
                    do_read <= 1'b0;
                    do_write <= 1'b0;
                  end
                endcase
                
                addr_match <= addr_match_computed;
                debug_addr_match <= addr_match_computed;
            end

            if (addr_match && (byte_idx >= data_start_idx) &&
                (byte_idx < (data_start_idx + {5'd0, dlen_reg}))) begin
              byte_addr = ado_reg + (byte_idx - data_start_idx);

              if (do_write) begin
                if (reg_can_write(byte_addr)) begin
                  write_success <= 1'b1;
                  if (addr_in_window(byte_addr, REG_CORE_BASE, CORE_REG_BYTES)) begin
                    reg_core[byte_addr - REG_CORE_BASE] <= rx_byte;
                  end else if (addr_in_window(byte_addr, REG_SM_BASE, SM_REG_BYTES)) begin
                    reg_sm[byte_addr - REG_SM_BASE] <= rx_byte;
                  end else if (addr_in_window(byte_addr, REG_FMMU_BASE, REG_FMMU_BYTES)) begin
                    reg_fmmu[byte_addr - REG_FMMU_BASE] <= rx_byte;
                  end else if ((byte_addr >= REG_IRQ_MASK) && (byte_addr < (REG_IRQ_MASK + 2))) begin
                    reg_irq_mask[(byte_addr - REG_IRQ_MASK) * 8 +: 8] <= rx_byte;
                  end else if ((byte_addr >= REG_EEP_CFG) && (byte_addr < (REG_EEP_CFG + 2))) begin
                    reg_eep_cfg[(byte_addr - REG_EEP_CFG) * 8 +: 8] <= rx_byte;
                  end else if (byte_addr == REG_DC_SYNC_ACT) begin
                    reg_dc_sync_act <= rx_byte;
                  end
                end
                if (byte_addr == REG_AL_CONTROL) begin
                  al_req_state <= rx_byte[3:0];
                  al_req_valid <= 1'b1;
                end
                for (i = 0; i < GPIO_OUT_BYTES; i++) begin
                  if (byte_addr == (REG_GPIO_OUT + i)) begin
                    gpio_out[(8*i)+:8] <= rx_byte;
                  end
                end
              end

              if (do_read) begin
                if (reg_can_read(byte_addr)) begin
                  read_success <= 1'b1;
                  tx_byte = reg_rd8(byte_addr);
                end else begin
                  tx_byte = 8'h00;
                end
              end
            end

            if (addr_match && (byte_idx == wkc_start_idx)) begin
              case (cmd_reg)
                CMD_APRD, CMD_FPRD, CMD_BRD: begin
                  wkc_inc_calc = read_success ? 2'd1 : 2'd0;
                end
                CMD_APWR, CMD_FPWR, CMD_BWR: begin
                  wkc_inc_calc = write_success ? 2'd1 : 2'd0;
                end
                CMD_APRW, CMD_FPRW, CMD_BRW: begin
                  wkc_inc_calc = 2'd0;
                  if (read_success) begin
                    wkc_inc_calc = wkc_inc_calc + 2'd1;
                  end
                  if (write_success) begin
                    wkc_inc_calc = wkc_inc_calc + 2'd2;
                  end
                end
                default: begin
                  wkc_inc_calc = 2'd0;
                end
              endcase

              wkc_inc_value <= wkc_inc_calc;
              tx_byte = rx_byte + {6'd0, wkc_inc_calc};
              low_overflow = ({1'b0, rx_byte} + {7'd0, wkc_inc_calc}) > 9'h0ff;
              wkc_carry <= low_overflow;
              // Capture WKC low byte for later assembly
              debug_wkc_value[7:0] <= tx_byte;
              debug_wkc_inc <= 1'b1;
            end else if (addr_match && (byte_idx == (wkc_start_idx + 16'd1))) begin
              tx_byte = rx_byte + {7'd0, wkc_carry};
              // Capture WKC high byte
              debug_wkc_value[15:8] <= tx_byte;
              debug_wkc_inc <= 1'b1;
            end else begin
              debug_wkc_inc <= 1'b0;
            end
          end else begin
            debug_wkc_inc <= 1'b0;
          end

          if (fcs_delay_count < 3'd4) begin
            case (fcs_delay_count)
              3'd0: fcs_delay0 <= tx_byte;
              3'd1: fcs_delay1 <= tx_byte;
              3'd2: fcs_delay2 <= tx_byte;
              default: fcs_delay3 <= tx_byte;
            endcase
            fcs_delay_count <= fcs_delay_count + 3'd1;
          end else begin
            emit_byte = fcs_delay0;
            emit_valid = 1'b1;
            fcs_delay0 <= fcs_delay1;
            fcs_delay1 <= fcs_delay2;
            fcs_delay2 <= fcs_delay3;
            fcs_delay3 <= tx_byte;
          end

          if (emit_valid && (fifo_count < TX_FIFO_DEPTH)) begin
            tx_fifo[fifo_wr_ptr] <= emit_byte;
            fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            push_now = 1'b1;
            if (!(preamble_valid && (byte_idx < 16'd12))) begin
              crc_reg <= crc32_update_byte(crc_reg, emit_byte);
            end
          end

          byte_idx <= byte_idx + 16'd1;
          rx_half <= 1'b0;
        end
      end

      if (!rx_dv && rx_dv_d) begin
        rx_half <= 1'b0;
        append_crc_active <= 1'b1;
        append_crc_idx <= 2'd0;
        append_crc_value <= ~crc_reg;
        fcs_delay_count <= 3'd0;
      end

      if (append_crc_active && (fifo_count < TX_FIFO_DEPTH)) begin
        case (append_crc_idx)
          2'd0: tx_fifo[fifo_wr_ptr] <= append_crc_value[7:0];
          2'd1: tx_fifo[fifo_wr_ptr] <= append_crc_value[15:8];
          2'd2: tx_fifo[fifo_wr_ptr] <= append_crc_value[23:16];
          default: tx_fifo[fifo_wr_ptr] <= append_crc_value[31:24];
        endcase
        fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
        push_now = 1'b1;

        if (append_crc_idx == 2'd3) begin
          append_crc_active <= 1'b0;
        end else begin
          append_crc_idx <= append_crc_idx + 2'd1;
        end
      end

      if (fifo_count != 0) begin
        tx_en <= 1'b1;
        if (!tx_half) begin
          txd <= fifo_out_byte[3:0];
          tx_half <= 1'b1;
        end else begin
          txd <= fifo_out_byte[7:4];
          tx_half <= 1'b0;
          fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
          pop_now = 1'b1;
        end
      end else begin
        tx_en <= 1'b0;
        txd <= 4'h0;
        tx_half <= 1'b0;
      end

      case ({push_now, pop_now})
        2'b10: fifo_count <= fifo_count + 1'b1;
        2'b01: fifo_count <= fifo_count - 1'b1;
        default: begin
        end
      endcase
    end
  end

endmodule
