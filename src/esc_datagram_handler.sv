module esc_datagram_handler (
    input  logic            clk,
    input  logic            rst_n,
    input  esc_pkg::byte_t  rx_data,
    input  logic            rx_valid,
    input  logic            rx_frame_start,
    input  logic            is_ethercat,
    input  logic            has_preamble,
    input  logic            preamble_valid,
    input  logic [15:0]     byte_idx,
    input  logic [15:0]     frame_offset,
    esc_reg_if.master       reg_if,
    input  logic [15:0]     station_addr,
    esc_tx_byte_if.source   tx_out,
    output logic            crc_exclude,
    output logic [15:0]     debug_wkc_value
);

  import esc_pkg::*;

  localparam int unsigned GPIO_OUT_BYTES = 1;

  byte_t  cmd_reg;
  logic   is_auto_inc_cmd;
  addr_t  adp_reg;
  addr_t  ado_reg;
  logic [10:0] dlen_reg;
  addr_t  data_start_idx;
  addr_t  wkc_start_idx;
  logic   addr_match;
  logic   do_read;
  logic   do_write;
  logic   read_success;
  logic   write_success;
  logic   adp_dec_borrow;
  logic [1:0] wkc_inc_value;
  logic   wkc_carry;

  addr_t  cmd_idx;
  addr_t  adp_lo_idx, adp_hi_idx;
  addr_t  ado_lo_idx, ado_hi_idx;
  addr_t  dlen_lo_idx, dlen_hi_idx;
  addr_t  byte_addr;



  logic read_allowed;

  always_comb begin
    cmd_idx     = 16'(ECAT_DATA_START - 10) + frame_offset;
    adp_lo_idx  = 16'(ECAT_DATA_START - 8)  + frame_offset;
    adp_hi_idx  = 16'(ECAT_DATA_START - 7)  + frame_offset;
    ado_lo_idx  = 16'(ECAT_DATA_START - 6)  + frame_offset;
    ado_hi_idx  = 16'(ECAT_DATA_START - 5)  + frame_offset;
    dlen_lo_idx = 16'(ECAT_DATA_START - 4)  + frame_offset;
    dlen_hi_idx = 16'(ECAT_DATA_START - 3)  + frame_offset;

    byte_addr = ado_reg + (byte_idx - data_start_idx);

    crc_exclude = preamble_valid && (byte_idx < 16'd12);

    reg_if.rd_addr = byte_addr;

    read_allowed = (esc_reg_access(byte_addr, GPIO_OUT_BYTES, 0) == REG_R) ||
                   (esc_reg_access(byte_addr, GPIO_OUT_BYTES, 0) == REG_RW);
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      cmd_reg         <= '0;
      is_auto_inc_cmd <= 1'b0;
      adp_reg         <= '0;
      ado_reg         <= '0;
      dlen_reg        <= '0;
      data_start_idx  <= 16'(ECAT_DATA_START);
      wkc_start_idx   <= 16'(ECAT_DATA_START);
      addr_match      <= 1'b0;
      do_read         <= 1'b0;
      do_write        <= 1'b0;
      read_success    <= 1'b0;
      write_success   <= 1'b0;
      adp_dec_borrow  <= 1'b0;
      wkc_inc_value   <= '0;
      wkc_carry       <= 1'b0;

      reg_if.wr_en    <= 1'b0;
      reg_if.wr_addr  <= '0;
      reg_if.wr_data  <= '0;

      tx_out.valid    <= 1'b0;
      tx_out.data     <= '0;
      debug_wkc_value <= '0;
    end else begin
      tx_out.valid    <= 1'b0;
      reg_if.wr_en    <= 1'b0;

      if (rx_frame_start) begin
        cmd_reg         <= '0;
        is_auto_inc_cmd <= 1'b0;
        adp_reg         <= '0;
        ado_reg         <= '0;
        dlen_reg        <= '0;
        data_start_idx  <= 16'(ECAT_DATA_START);
        wkc_start_idx   <= 16'(ECAT_DATA_START);
        addr_match      <= 1'b0;
        do_read         <= 1'b0;
        do_write        <= 1'b0;
        read_success    <= 1'b0;
        write_success   <= 1'b0;
        adp_dec_borrow  <= 1'b0;
        wkc_inc_value   <= '0;
        wkc_carry       <= 1'b0;
      end

      if (rx_valid) begin
        byte_t rx_byte = rx_data;
        byte_t tx_byte = rx_byte;
        $display("HDL: bi=%d rx=%02x is_ecat=%b", byte_idx, rx_byte, is_ethercat);

        if (is_ethercat) begin
          if (byte_idx == cmd_idx) begin
            cmd_reg         <= rx_byte;
            case (rx_byte)
              CMD_APRD, CMD_APWR, CMD_APRW:
                is_auto_inc_cmd <= 1'b1;
              CMD_FPRD, CMD_FPWR, CMD_FPRW,
              CMD_BRD,  CMD_BWR,  CMD_BRW:
                is_auto_inc_cmd <= 1'b0;
              default:
                is_auto_inc_cmd <= 1'b0;
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
            data_start_idx  <= 16'(ECAT_DATA_START) + frame_offset;
            wkc_start_idx   <= (16'(ECAT_DATA_START) + frame_offset) +
                               {5'd0, rx_byte[2:0], dlen_reg[7:0]};

            do_read           <= 1'b0;
            do_write          <= 1'b0;
            read_success      <= 1'b0;
            write_success     <= 1'b0;
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
                do_read  <= 1'b1;
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
                do_read  <= 1'b1;
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
                do_read  <= 1'b1;
                do_write <= 1'b1;
              end
              default: begin
                addr_match_computed = 1'b0;
              end
            endcase

            addr_match <= addr_match_computed;
          end

          if (addr_match && (byte_idx >= data_start_idx) &&
              (byte_idx < (data_start_idx + {5'd0, dlen_reg}))) begin
            if (do_write) begin
              reg_if.wr_addr <= byte_addr;
              reg_if.wr_data <= rx_byte;
              reg_if.wr_en   <= 1'b1;
              if (reg_if.write_hit_cmb) begin
                write_success <= 1'b1;
              end
            end

            if (do_read) begin
              tx_byte = reg_if.rd_data;
              read_success <= read_allowed;
            end
          end

          if (addr_match && (byte_idx == wkc_start_idx)) begin
            logic [1:0] wkc_calc;

            case (cmd_reg)
              CMD_APRD, CMD_FPRD, CMD_BRD:
                wkc_calc = read_success ? 2'd1 : 2'd0;
              CMD_APWR, CMD_FPWR, CMD_BWR:
                wkc_calc = write_success ? 2'd1 : 2'd0;
              CMD_APRW, CMD_FPRW, CMD_BRW: begin
                wkc_calc = 2'd0;
                if (read_success)  wkc_calc = wkc_calc + 2'd1;
                if (write_success) wkc_calc = wkc_calc + 2'd2;
              end
              default:
                wkc_calc = 2'd0;
            endcase

            wkc_inc_value <= wkc_calc;
            tx_byte = rx_byte + {6'd0, wkc_calc};
            wkc_carry <= ({1'b0, rx_byte} +
                          {7'd0, wkc_calc} > 9'h0ff);
            debug_wkc_value[7:0] <= tx_byte;
          end else if (addr_match &&
                       (byte_idx == (wkc_start_idx + 16'd1))) begin
            tx_byte = rx_byte + {7'd0, wkc_carry};
            debug_wkc_value[15:8] <= tx_byte;
          end
        end

        tx_out.data  <= tx_byte;
        tx_out.valid <= 1'b1;
      end
    end
  end

endmodule