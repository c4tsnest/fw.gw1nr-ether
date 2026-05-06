module esc_regfile #(
    parameter int unsigned GPIO_OUT_WIDTH = 8,
    parameter int unsigned GPIO_IN_WIDTH  = 0
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   link_up,
           esc_reg_if.slave        reg_if,
    output logic            [15:0] station_addr,
    output esc_pkg::byte_t         gpio_out,
    input  logic            [15:0] debug_wkc_value
);

  import esc_pkg::*;

  localparam int unsigned GPIO_OUT_BYTES = (GPIO_OUT_WIDTH + 7) / 8;
  localparam int unsigned GPIO_IN_BYTES = (GPIO_IN_WIDTH + 7) / 8;

  byte_t                      reg_core        [0:CORE_REG_BYTES-1];
  byte_t                      reg_sm          [  0:SM_REG_BYTES-1];
  byte_t                      reg_fmmu        [0:FMMU_REG_BYTES-1];

  logic  [GPIO_OUT_WIDTH-1:0] gpio_out_reg;

  word_t                      reg_irq_mask;
  word_t                      reg_eep_cfg;
  eep_stat_t                  eep_stat;
  logic  [              31:0] reg_eep_addr;
  logic  [              31:0] reg_eep_data;
  byte_t                      reg_pdi_control;
  byte_t                      reg_dc_sync_act;

  logic  [              63:0] dc_time_counter;
  logic  [               3:0] al_state;
  logic  [              15:0] al_status_code;
  logic                       al_req_valid;
  logic  [               3:0] al_req_state;

  logic  [               3:0] eep_busy_count;
  logic                       eep_cmd_pending;

  int                         i;

  function automatic byte_t reg_rd8(input addr_t a);
    if (a == REG_DL_STATUS) begin
      reg_rd8 = link_up ? DLSTATUS_PORT0_LINK[7:0] : 8'h00;
    end else if (a == (REG_DL_STATUS + 1)) begin
      reg_rd8 = link_up ? DLSTATUS_PORT0_LINK[15:8] : 8'h00;
    end else if (a == REG_PDI_CONTROL) begin
      reg_rd8 = reg_pdi_control;
    end else if ((a >= REG_IRQ_MASK) && (a < (REG_IRQ_MASK + 2))) begin
      reg_rd8 = reg_irq_mask[(a-REG_IRQ_MASK)*8+:8];
    end else if ((a >= REG_EEP_CFG) && (a < (REG_EEP_CFG + 2))) begin
      reg_rd8 = reg_eep_cfg[(a-REG_EEP_CFG)*8+:8];
    end else if ((a >= REG_EEP_STAT) && (a < (REG_EEP_STAT + 2))) begin
      reg_rd8 = eep_stat.raw[(a-REG_EEP_STAT)*8+:8];
    end else if ((a >= REG_EEP_ADDR) && (a < (REG_EEP_ADDR + 4))) begin
      reg_rd8 = reg_eep_addr[(a-REG_EEP_ADDR)*8+:8];
    end else if ((a >= REG_EEP_DATA) && (a < (REG_EEP_DATA + 4))) begin
      reg_rd8 = reg_eep_data[(a-REG_EEP_DATA)*8+:8];
    end else if (a == REG_DC_SYNC_ACT) begin
      reg_rd8 = reg_dc_sync_act;
    end else if (addr_in_window(a, REG_FMMU_BASE, FMMU_REG_BYTES)) begin
      reg_rd8 = reg_fmmu[a-REG_FMMU_BASE];
    end else if (a == REG_AL_STATUS) begin
      reg_rd8 = {4'b0, al_state};
    end else if (a == REG_AL_STATUS_CD) begin
      reg_rd8 = al_status_code[7:0];
    end else if (a == (REG_AL_STATUS_CD + 1)) begin
      reg_rd8 = al_status_code[15:8];
    end else if ((a >= REG_DC_TIME) && (a < (REG_DC_TIME + 8))) begin
      reg_rd8 = dc_time_counter[((a-REG_DC_TIME)*8)+:8];
    end else if ((a >= REG_GPIO_OUT) && (a < (REG_GPIO_OUT + GPIO_OUT_BYTES))) begin
      reg_rd8 = gpio_out_reg[((a-REG_GPIO_OUT)*8)+:8];
    end else if ((GPIO_IN_WIDTH > 0) && (a >= REG_GPIO_IN) &&
                 (a < (REG_GPIO_IN + GPIO_IN_BYTES))) begin
      reg_rd8 = 8'h00;
    end else if ((a >= REG_DEBUG_WKC) && (a < (REG_DEBUG_WKC + 2))) begin
      reg_rd8 = debug_wkc_value[((a-REG_DEBUG_WKC)*8)+:8];
    end else if (addr_in_window(a, '0, CORE_REG_BYTES)) begin
      reg_rd8 = reg_core[a-'0];
    end else if (addr_in_window(a, REG_SM_BASE, SM_REG_BYTES)) begin
      reg_rd8 = reg_sm[a-REG_SM_BASE];
    end else begin
      reg_rd8 = 8'h00;
    end
  endfunction

  function automatic logic reg_can_write_addr(input addr_t a);
    reg_access_t ra = esc_reg_access(a, GPIO_OUT_BYTES, GPIO_IN_BYTES);
    reg_can_write_addr = (ra == REG_W) || (ra == REG_RW);
  endfunction

  always_comb begin
    reg_if.write_hit_cmb = reg_can_write_addr(reg_if.wr_addr) &&
        !(reg_eep_cfg[8] == 1'b1 &&
          ((reg_if.wr_addr >= REG_EEP_STAT && reg_if.wr_addr < (REG_EEP_STAT + 2)) ||
           (reg_if.wr_addr >= REG_EEP_ADDR && reg_if.wr_addr < (REG_EEP_ADDR + 4)) ||
           (reg_if.wr_addr >= REG_EEP_DATA && reg_if.wr_addr < (REG_EEP_DATA + 4))));
  end

  function automatic logic [31:0] eeprom_fixed_read(input logic [31:0] a);
    case (a[15:0])
      16'h0000: eeprom_fixed_read = 32'hA55A_EC11;
      16'h0001: eeprom_fixed_read = 32'h0001_0001;
      16'h0002: eeprom_fixed_read = 32'h0000_0000;
      16'h0004: eeprom_fixed_read = 32'h0000_0001;
      default:  eeprom_fixed_read = {16'hEC00, a[15:0]};
    endcase
  endfunction

  always_comb begin
    reg_if.rd_data = reg_rd8(reg_if.rd_addr);
  end

  assign gpio_out = byte_t'(gpio_out_reg);
  assign station_addr = {reg_core[REG_STATION_ADDR+1], reg_core[REG_STATION_ADDR]};

  logic write_hit;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < CORE_REG_BYTES; i++) reg_core[i] <= '0;
      for (i = 0; i < SM_REG_BYTES; i++) reg_sm[i] <= '0;
      for (i = 0; i < FMMU_REG_BYTES; i++) reg_fmmu[i] <= '0;

      gpio_out_reg           <= '0;

      reg_core[REG_TYPE]     <= 8'h11;
      reg_core[REG_TYPE+1]   <= 8'h01;
      reg_core[REG_PORTDES]  <= 8'h01;
      reg_core[REG_ESCSUP]   <= 8'h00;
      reg_core[REG_ESCSUP+1] <= 8'h00;
      reg_core[16'h000a]     <= 8'h00;
      reg_core[16'h000b]     <= 8'h00;
      reg_core[16'h000c]     <= 8'h01;
      reg_core[16'h000d]     <= 8'h00;
      reg_core[16'h000e]     <= 8'h00;
      reg_core[16'h000f]     <= 8'h00;

      reg_sm[0]              <= 8'h00;
      reg_sm[1]              <= 8'h10;
      reg_sm[8]              <= 8'h80;
      reg_sm[9]              <= 8'h10;
      reg_sm[16]             <= 8'h00;
      reg_sm[17]             <= 8'h12;
      reg_sm[24]             <= 8'h80;
      reg_sm[25]             <= 8'h12;

      dc_time_counter        <= 64'd0;
      reg_irq_mask           <= '0;
      reg_eep_cfg            <= '0;
      eep_stat.raw           <= '0;
      reg_eep_addr           <= '0;
      reg_eep_data           <= '0;
      eep_busy_count         <= '0;
      eep_cmd_pending        <= 1'b0;
      reg_pdi_control        <= '0;
      reg_dc_sync_act        <= '0;

      al_req_valid           <= 1'b0;
      al_req_state           <= '0;
    end else begin
      dc_time_counter <= dc_time_counter + 64'd1;
      al_req_valid    <= 1'b0;
      reg_if.wr_ack   <= 1'b0;

      if (eep_busy_count != 4'd0) begin
        eep_busy_count   <= eep_busy_count - 4'd1;
        eep_stat.fields.busy <= 1'b1;
        if (eep_busy_count == 4'd1) begin
          eep_stat.fields.busy <= 1'b0;
          if (eep_cmd_pending) begin
            case (eep_stat.fields.command)
              3'b001: reg_eep_data <= eeprom_fixed_read(reg_eep_addr); // Read
              3'b010: ; // TODO: Write command - store to embedded flash
              default: ; // Reserved / no-op
            endcase
            eep_cmd_pending       <= 1'b0;
            eep_stat.fields.command <= 3'b000;
          end
        end
      end

      if (reg_if.wr_en) begin
        write_hit = 1'b0;

        if (reg_can_write_addr(reg_if.wr_addr)) begin
          if (addr_in_window(reg_if.wr_addr, '0, CORE_REG_BYTES)) begin
            reg_core[reg_if.wr_addr-'0] <= reg_if.wr_data;
            write_hit = 1'b1;
          end else if (addr_in_window(reg_if.wr_addr, REG_SM_BASE, SM_REG_BYTES)) begin
            reg_sm[reg_if.wr_addr-REG_SM_BASE] <= reg_if.wr_data;
            write_hit = 1'b1;
          end else if (addr_in_window(reg_if.wr_addr, REG_FMMU_BASE, FMMU_REG_BYTES)) begin
            reg_fmmu[reg_if.wr_addr-REG_FMMU_BASE] <= reg_if.wr_data;
            write_hit = 1'b1;
          end else if ((reg_if.wr_addr >= REG_IRQ_MASK) &&
                       (reg_if.wr_addr < (REG_IRQ_MASK + 2))) begin
            reg_irq_mask[(reg_if.wr_addr-REG_IRQ_MASK)*8+:8] <= reg_if.wr_data;
            write_hit = 1'b1;
          end else if ((reg_if.wr_addr >= REG_EEP_CFG) &&
                       (reg_if.wr_addr < (REG_EEP_CFG + 2))) begin
            if (reg_if.wr_addr == REG_EEP_CFG) begin
              if (reg_if.wr_data[1]) begin
                reg_eep_cfg[0] <= 1'b0;
                reg_eep_cfg[8] <= 1'b0;
              end else if (reg_if.wr_data[0]) begin
                reg_eep_cfg[0] <= 1'b1;
                reg_eep_cfg[8] <= 1'b1;
              end
              write_hit = reg_if.wr_data[1] | reg_if.wr_data[0];
            end
          end else if ((reg_if.wr_addr >= REG_EEP_STAT) &&
                       (reg_if.wr_addr < (REG_EEP_STAT + 2))) begin
            if (reg_eep_cfg[8] == 1'b0) begin
              if (reg_if.wr_addr == REG_EEP_STAT) begin
                eep_stat.fields.ecat_we <= reg_if.wr_data[0];
                write_hit = 1'b1;
              end else begin
                // REG_EEP_STAT + 1: upper byte carries command type in bits [2:0]
                eep_stat.fields.command <= reg_if.wr_data[2:0];
                if ((reg_if.wr_data[2:0] != 3'b000) && !eep_stat.fields.busy) begin
                  eep_stat.fields.busy <= 1'b1;
                  eep_busy_count       <= 4'd8;
                  eep_cmd_pending      <= 1'b1;
                end
                write_hit = 1'b1;
              end
            end
          end else if ((reg_if.wr_addr >= REG_EEP_ADDR) &&
                       (reg_if.wr_addr < (REG_EEP_ADDR + 4))) begin
            if (reg_eep_cfg[8] == 1'b0) begin
              reg_eep_addr[(reg_if.wr_addr-REG_EEP_ADDR)*8+:8] <= reg_if.wr_data;
              write_hit = 1'b1;
            end
          end else if ((reg_if.wr_addr >= REG_EEP_DATA) &&
                       (reg_if.wr_addr < (REG_EEP_DATA + 4))) begin
            if (reg_eep_cfg[8] == 1'b0) begin
              reg_eep_data[(reg_if.wr_addr-REG_EEP_DATA)*8+:8] <= reg_if.wr_data;
              write_hit = 1'b1;
            end
          end else if (reg_if.wr_addr == REG_DC_SYNC_ACT) begin
            reg_dc_sync_act <= reg_if.wr_data;
            write_hit = 1'b1;
          end

          if (write_hit) reg_if.wr_ack <= 1'b1;
        end

        if (reg_if.wr_addr == REG_AL_CONTROL) begin
          al_req_state <= reg_if.wr_data[3:0];
          al_req_valid <= 1'b1;
        end

        for (i = 0; i < GPIO_OUT_BYTES; i++) begin
          if (reg_if.wr_addr == (REG_GPIO_OUT + i)) begin
            gpio_out_reg[(i*8)+:8] <= reg_if.wr_data;
          end
        end
      end
    end
  end

  esc_al_fsm u_al_fsm (
      .clk           (clk),
      .rst_n         (rst_n),
      .req_valid     (al_req_valid),
      .req_state     (esc_pkg::al_state_t'(al_req_state)),
      .al_state      (al_state),
      .al_status_code(al_status_code)
  );

endmodule
