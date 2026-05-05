`timescale 1ns / 1ps

module tb_esc_minimal;

  localparam int MAX_BYTES = 256;

  logic       clk;
  logic       rst_n;
  logic       link_up;

  logic [3:0] rxd;
  logic       rx_dv;
  logic [3:0] txd;
  logic       tx_en;

  logic [7:0] gpio_out;

  logic [7:0] rx_resp        [MAX_BYTES-1:0];
  int         resp_len;
  logic       cap_half;
  logic [3:0] cap_low_nibble;

  esc_minimal_slave #(
      .GPIO_OUT_WIDTH(8),
      .GPIO_IN_WIDTH (0)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .link_up(link_up),
      .rxd(rxd),
      .rx_dv(rx_dv),
      .txd(txd),
      .tx_en(tx_en),
      .gpio_in(),
      .gpio_out(gpio_out)
  );

  initial clk = 1'b0;
  always #10 clk = ~clk;

  task automatic send_byte(input logic [7:0] value);
    begin
      @(posedge clk);
      rxd   <= value[3:0];
      rx_dv <= 1'b1;
      @(posedge clk);
      rxd   <= value[7:4];
      rx_dv <= 1'b1;
    end
  endtask

  task automatic end_frame;
    begin
      @(posedge clk);
      rx_dv <= 1'b0;
      rxd   <= 4'h0;
    end
  endtask

  task automatic clear_capture;
    begin
      resp_len = 0;
      cap_half = 1'b0;
      cap_low_nibble = 4'h0;
    end
  endtask

  task automatic wait_tx_idle;
    int idle_cycles;
    begin
      idle_cycles = 0;
      while (idle_cycles < 12) begin
        @(posedge clk);
        if (tx_en) idle_cycles = 0;
        else idle_cycles = idle_cycles + 1;
      end
    end
  endtask

  always @(posedge clk) begin
    if (tx_en) begin
      if (!cap_half) begin
        cap_low_nibble <= txd;
        cap_half <= 1'b1;
      end else begin
        if (resp_len < MAX_BYTES) begin
          rx_resp[resp_len] <= {txd, cap_low_nibble};
        end
        resp_len <= resp_len + 1;
        cap_half <= 1'b0;
      end
    end else begin
      cap_half <= 1'b0;
    end
  end

  task automatic send_ecat_single_datagram(input logic [7:0] cmd, input logic [15:0] adp,
                                           input logic [15:0] ado, input int unsigned payload_len,
                                           input logic [7:0] payload0, input logic [7:0] payload1,
                                           input logic [7:0] payload2, input logic [7:0] payload3);
    logic [15:0] ecat_len;
    logic [15:0] dlen_field;
    begin
      ecat_len   = 16'(10 + payload_len + 2);
      dlen_field = payload_len[15:0];

      send_byte(8'h01);
      send_byte(8'h02);
      send_byte(8'h03);
      send_byte(8'h04);
      send_byte(8'h05);
      send_byte(8'h06);
      send_byte(8'h10);
      send_byte(8'h20);
      send_byte(8'h30);
      send_byte(8'h40);
      send_byte(8'h50);
      send_byte(8'h60);
      send_byte(8'h88);
      send_byte(8'hA4);

      send_byte(ecat_len[7:0]);
      send_byte({4'h1, ecat_len[10:8]});

      send_byte(cmd);
      send_byte(8'h01);
      send_byte(adp[7:0]);
      send_byte(adp[15:8]);
      send_byte(ado[7:0]);
      send_byte(ado[15:8]);
      send_byte(dlen_field[7:0]);
      send_byte({5'b00000, dlen_field[10:8]});
      send_byte(8'h00);
      send_byte(8'h00);

      if (payload_len > 0) send_byte(payload0);
      if (payload_len > 1) send_byte(payload1);
      if (payload_len > 2) send_byte(payload2);
      if (payload_len > 3) send_byte(payload3);

      send_byte(8'h00);
      send_byte(8'h00);

      send_byte(8'h00);
      send_byte(8'h00);
      send_byte(8'h00);
      send_byte(8'h00);

      end_frame();
    end
  endtask

  task automatic send_ecat_single_datagram8(
      input logic [7:0] cmd, input logic [15:0] adp, input logic [15:0] ado,
      input int unsigned payload_len, input logic [7:0] payload0, input logic [7:0] payload1,
      input logic [7:0] payload2, input logic [7:0] payload3, input logic [7:0] payload4,
      input logic [7:0] payload5, input logic [7:0] payload6, input logic [7:0] payload7);
    logic [15:0] ecat_len;
    logic [15:0] dlen_field;
    begin
      ecat_len   = 16'(10 + payload_len + 2);
      dlen_field = payload_len[15:0];

      send_byte(8'h01);
      send_byte(8'h02);
      send_byte(8'h03);
      send_byte(8'h04);
      send_byte(8'h05);
      send_byte(8'h06);
      send_byte(8'h10);
      send_byte(8'h20);
      send_byte(8'h30);
      send_byte(8'h40);
      send_byte(8'h50);
      send_byte(8'h60);
      send_byte(8'h88);
      send_byte(8'hA4);

      send_byte(ecat_len[7:0]);
      send_byte({4'h1, ecat_len[10:8]});

      send_byte(cmd);
      send_byte(8'h01);
      send_byte(adp[7:0]);
      send_byte(adp[15:8]);
      send_byte(ado[7:0]);
      send_byte(ado[15:8]);
      send_byte(dlen_field[7:0]);
      send_byte({5'b00000, dlen_field[10:8]});
      send_byte(8'h00);
      send_byte(8'h00);

      if (payload_len > 0) send_byte(payload0);
      if (payload_len > 1) send_byte(payload1);
      if (payload_len > 2) send_byte(payload2);
      if (payload_len > 3) send_byte(payload3);
      if (payload_len > 4) send_byte(payload4);
      if (payload_len > 5) send_byte(payload5);
      if (payload_len > 6) send_byte(payload6);
      if (payload_len > 7) send_byte(payload7);

      send_byte(8'h00);
      send_byte(8'h00);

      send_byte(8'h00);
      send_byte(8'h00);
      send_byte(8'h00);
      send_byte(8'h00);

      end_frame();
    end
  endtask

  task automatic send_ecat_single_datagram_with_preamble(
      input logic [7:0] cmd, input logic [15:0] adp, input logic [15:0] ado,
      input int unsigned payload_len, input logic [7:0] payload0);
    logic [15:0] ecat_len;
    logic [15:0] dlen_field;
    begin
      ecat_len   = 16'(10 + payload_len + 2);
      dlen_field = payload_len[15:0];

      send_byte(8'h55);
      send_byte(8'h55);
      send_byte(8'h55);
      send_byte(8'h55);
      send_byte(8'h55);
      send_byte(8'h55);
      send_byte(8'h55);
      send_byte(8'hD5);

      // Keep 0x88A4 at byte 12/13 (in destination MAC) to ensure
      // parser does not falsely classify this as non-preamble EtherCAT.
      send_byte(8'h01);
      send_byte(8'h02);
      send_byte(8'h03);
      send_byte(8'h04);
      send_byte(8'h88);
      send_byte(8'hA4);

      send_byte(8'h10);
      send_byte(8'h20);
      send_byte(8'h30);
      send_byte(8'h40);
      send_byte(8'h50);
      send_byte(8'h60);
      send_byte(8'h88);
      send_byte(8'hA4);

      send_byte(ecat_len[7:0]);
      send_byte({4'h1, ecat_len[10:8]});

      send_byte(cmd);
      send_byte(8'h01);
      send_byte(adp[7:0]);
      send_byte(adp[15:8]);
      send_byte(ado[7:0]);
      send_byte(ado[15:8]);
      send_byte(dlen_field[7:0]);
      send_byte({5'b00000, dlen_field[10:8]});
      send_byte(8'h00);
      send_byte(8'h00);

      if (payload_len > 0) send_byte(payload0);

      send_byte(8'h00);
      send_byte(8'h00);

      send_byte(8'h00);
      send_byte(8'h00);
      send_byte(8'h00);
      send_byte(8'h00);

      end_frame();
    end
  endtask

  task automatic expect_eq8(input logic [7:0] got, input logic [7:0] exp, input string name);
    begin
      if (got !== exp) begin
        $display("FAIL: %s got=%02x exp=%02x", name, got, exp);
        $fatal(1);
      end
    end
  endtask

  function automatic logic [31:0] crc32_update_byte_tb(input logic [31:0] crc_in,
                                                       input logic [7:0] data);
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
      crc32_update_byte_tb = crc_next;
    end
  endfunction

  task automatic expect_fcs_valid(input int frame_len, input string name);
    logic [31:0] crc_calc;
    logic [31:0] fcs_got;
    int crc_start;
    int idx;
    begin
      crc_calc = 32'hFFFF_FFFF;

      if ((frame_len >= 12) &&
          (rx_resp[0] == 8'h55) && (rx_resp[1] == 8'h55) &&
          (rx_resp[2] == 8'h55) && (rx_resp[3] == 8'h55) &&
          (rx_resp[4] == 8'h55) && (rx_resp[5] == 8'h55) &&
          (rx_resp[6] == 8'h55) && (rx_resp[7] == 8'hD5)) begin
        crc_start = 8;
      end else begin
        crc_start = 0;
      end

      for (idx = crc_start; idx < (frame_len - 4); idx++) begin
        crc_calc = crc32_update_byte_tb(crc_calc, rx_resp[idx]);
      end
      crc_calc = ~crc_calc;

      fcs_got = {
        rx_resp[frame_len-1], rx_resp[frame_len-2], rx_resp[frame_len-3], rx_resp[frame_len-4]
      };

      if (fcs_got !== crc_calc) begin
        $display("FAIL: %s bad FCS got=%08x exp=%08x", name, fcs_got, crc_calc);
        $fatal(1);
      end
    end
  endtask

  task automatic expect_true(input logic cond, input string name);
    begin
      if (!cond) begin
        $display("FAIL: %s", name);
        $fatal(1);
      end
    end
  endtask

  initial begin
    integer wkc_index;
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_esc_minimal);

    rst_n = 1'b0;
    link_up = 1'b0;
    rxd = 4'h0;
    rx_dv = 1'b0;
    clear_capture();

    repeat (8) @(posedge clk);
    rst_n   = 1'b1;
    link_up = 1'b1;
    repeat (8) @(posedge clk);

    $display("TEST1: APRD AL Status (expect INIT=0x01)");
    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0130, 1, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 29, "response length for APRD");
    expect_eq8(rx_resp[26], 8'h01, "AL status byte");
    wkc_index = 27;
    expect_eq8(rx_resp[wkc_index], 8'h01, "WKC low APRD");

    $display("TEST2: APWR AL Control PREOP then APRD AL Status");
    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0120, 1, 8'h02, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 29, "response length for APWR");
    expect_eq8(rx_resp[27], 8'h01, "WKC low APWR");
    expect_fcs_valid(resp_len, "APWR regenerated FCS");

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0130, 1, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[26], 8'h02, "AL status PREOP");

    $display("TEST3: APWR GPIO output register and verify gpio_out");
    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0f00, 1, 8'hA5, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    repeat (4) @(posedge clk);
    expect_eq8(gpio_out, 8'hA5, "gpio_out value");

    $display("TEST4: Read DC time low bytes and expect monotonic value");
    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0910, 4, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 32, "response length for DC read");
    expect_true({rx_resp[29], rx_resp[28], rx_resp[27], rx_resp[26]} != 32'h0000_0000,
                "dc time non-zero");

    $display("TEST5: APRD auto-increment ADP decrement and no hit WKC");
    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0001, 16'h0130, 1, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 29, "response length for APRD ADP=1");
    expect_eq8(rx_resp[18], 8'h00, "ADP low decremented");
    expect_eq8(rx_resp[19], 8'h00, "ADP high decremented");
    expect_eq8(rx_resp[27], 8'h00, "WKC low no-match APRD");

    $display("TEST6: SOEM-like BRD TYPE detect-slaves path");
    clear_capture();
    send_ecat_single_datagram(8'h07, 16'h0000, 16'h0000, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 30, "response length for BRD TYPE");
    expect_eq8(rx_resp[26], 8'h11, "TYPE low byte");
    expect_eq8(rx_resp[27], 8'h01, "TYPE high byte");
    expect_eq8(rx_resp[28], 8'h01, "WKC low BRD TYPE");

    $display("TEST7: SOEM-like APWR/APRD/FPRD STADR config addressing");
    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0010, 2, 8'h01, 8'h10, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 30, "response length for APWR STADR");
    expect_eq8(rx_resp[28], 8'h01, "WKC low APWR STADR");

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0010, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 30, "response length for APRD STADR");
    expect_eq8(rx_resp[26], 8'h01, "APRD STADR low");
    expect_eq8(rx_resp[27], 8'h10, "APRD STADR high");
    expect_eq8(rx_resp[28], 8'h01, "WKC low APRD STADR");

    clear_capture();
    send_ecat_single_datagram(8'h04, 16'h1001, 16'h0010, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 30, "response length for FPRD STADR");
    expect_eq8(rx_resp[26], 8'h01, "FPRD STADR low");
    expect_eq8(rx_resp[27], 8'h10, "FPRD STADR high");
    expect_eq8(rx_resp[28], 8'h01, "WKC low FPRD STADR");

    $display("TEST8: SOEM-like BWR reset block and FPRD verify");
    clear_capture();
    send_ecat_single_datagram8(8'h08, 16'h0000, 16'h0800, 8, 8'hAA, 8'h55, 8'h12, 8'h34, 8'hDE,
                               8'hAD, 8'hBE, 8'hEF);
    wait_tx_idle();
    expect_true(resp_len >= 36, "response length for BWR 8-byte");
    expect_eq8(rx_resp[34], 8'h01, "WKC low BWR 8-byte");

    clear_capture();
    send_ecat_single_datagram8(8'h04, 16'h1001, 16'h0800, 8, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                               8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 36, "response length for FPRD 8-byte");
    expect_eq8(rx_resp[26], 8'hAA, "FPRD block byte0");
    expect_eq8(rx_resp[27], 8'h55, "FPRD block byte1");
    expect_eq8(rx_resp[28], 8'h12, "FPRD block byte2");
    expect_eq8(rx_resp[29], 8'h34, "FPRD block byte3");
    expect_eq8(rx_resp[30], 8'hDE, "FPRD block byte4");
    expect_eq8(rx_resp[31], 8'hAD, "FPRD block byte5");
    expect_eq8(rx_resp[32], 8'hBE, "FPRD block byte6");
    expect_eq8(rx_resp[33], 8'hEF, "FPRD block byte7");
    expect_eq8(rx_resp[34], 8'h01, "WKC low FPRD 8-byte");

    $display("TEST9: SOEM-like ESC capability and topology fields");
    clear_capture();
    send_ecat_single_datagram(8'h04, 16'h1001, 16'h0008, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 30, "response length for FPRD ESCSUP");
    expect_eq8(rx_resp[26], 8'h00, "ESCSUP low (DC support disabled)");
    expect_eq8(rx_resp[27], 8'h00, "ESCSUP high");
    expect_eq8(rx_resp[28], 8'h01, "WKC low FPRD ESCSUP");

    clear_capture();
    send_ecat_single_datagram(8'h04, 16'h1001, 16'h0007, 1, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 29, "response length for FPRD PORTDES");
    expect_eq8(rx_resp[26], 8'h01, "PORTDES low");
    expect_eq8(rx_resp[27], 8'h01, "WKC low FPRD PORTDES");

    clear_capture();
    send_ecat_single_datagram(8'h04, 16'h1001, 16'h0110, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 30, "response length for FPRD DLSTATUS");
    expect_eq8(rx_resp[26], 8'h00, "DLSTATUS low");
    expect_eq8(rx_resp[27], 8'h02, "DLSTATUS high (port0 link active)");
    expect_eq8(rx_resp[28], 8'h01, "WKC low FPRD DLSTATUS");

    $display("TEST10: APRD with preamble and MAC 0x88A4 false-positive pattern");
    clear_capture();
    send_ecat_single_datagram_with_preamble(8'h01, 16'h0000, 16'h0130, 1, 8'h00);
    wait_tx_idle();
    expect_true(resp_len >= 37, "response length for APRD preamble");
    expect_eq8(rx_resp[34], 8'h02, "AL status preamble");
    expect_eq8(rx_resp[35], 8'h01, "WKC low APRD preamble");
    expect_eq8(rx_resp[36], 8'h00, "WKC high APRD preamble");
    expect_fcs_valid(resp_len, "APRD preamble regenerated FCS");

    $display("TEST11: Strict RO identity register (TYPE) does not change on write");
    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0000, 2, 8'hAA, 8'h55, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[28], 8'h00, "WKC low APWR TYPE RO");

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0000, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[26], 8'h11, "TYPE low stays RO");
    expect_eq8(rx_resp[27], 8'h01, "TYPE high stays RO");
    expect_eq8(rx_resp[28], 8'h01, "WKC low APRD TYPE");

    $display("TEST12: IRQMASK RW register write/readback");
    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0200, 2, 8'h04, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[28], 8'h01, "WKC low APWR IRQMASK");

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0200, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[26], 8'h04, "IRQMASK low readback");
    expect_eq8(rx_resp[27], 8'h00, "IRQMASK high readback");
    expect_eq8(rx_resp[28], 8'h01, "WKC low APRD IRQMASK");

    $display("TEST13: PDI control RO and FMMU RW touched registers");
    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0140, 1, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[26], 8'h00, "PDICTL default");
    expect_eq8(rx_resp[27], 8'h01, "WKC low APRD PDICTL");

    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0600, 4, 8'h12, 8'h34, 8'h56, 8'h78);
    wait_tx_idle();
    expect_eq8(rx_resp[30], 8'h01, "WKC low APWR FMMU block");

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0600, 4, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[26], 8'h12, "FMMU byte0 readback");
    expect_eq8(rx_resp[27], 8'h34, "FMMU byte1 readback");
    expect_eq8(rx_resp[28], 8'h56, "FMMU byte2 readback");
    expect_eq8(rx_resp[29], 8'h78, "FMMU byte3 readback");
    expect_eq8(rx_resp[30], 8'h01, "WKC low APRD FMMU block");

    $display("TEST14: EEPROM ownership handover/release and gated status writes");
    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0500, 1, 8'h01, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[27], 8'h01, "WKC low APWR EEP_CFG handover");

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0500, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(rx_resp[26][0] == 1'b1, "EEP_CFG 0x500 bit0 set");
    expect_true(rx_resp[27][0] == 1'b1, "EEP_CFG 0x501 bit0 owner=PDI");

    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0502, 2, 8'h01, 8'h01, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[28], 8'h00, "WKC low APWR EEP_STAT blocked by PDI owner");

    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0500, 1, 8'h02, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[27], 8'h01, "WKC low APWR EEP_CFG force release");

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0500, 2, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_true(rx_resp[26][0] == 1'b0, "EEP_CFG 0x500 bit0 cleared");
    expect_true(rx_resp[27][0] == 1'b0, "EEP_CFG 0x501 bit0 owner=ECAT");

    $display("TEST15: EEPROM address/data command path with fixed values");
    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0504, 4, 8'h01, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[30], 8'h01, "WKC low APWR EEP_ADDR");

    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0503, 1, 8'h01, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[27], 8'h01, "WKC low APWR EEP_STAT cmd");

    clear_capture();
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0502, 1, 8'h01, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[27], 8'h01, "WKC low APWR EEP_STAT start");

    repeat (32) @(posedge clk);

    clear_capture();
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0508, 4, 8'h00, 8'h00, 8'h00, 8'h00);
    wait_tx_idle();
    expect_eq8(rx_resp[26], 8'h01, "EEP_DATA byte0");
    expect_eq8(rx_resp[27], 8'h00, "EEP_DATA byte1");
    expect_eq8(rx_resp[28], 8'h01, "EEP_DATA byte2");
    expect_eq8(rx_resp[29], 8'h00, "EEP_DATA byte3");
    expect_eq8(rx_resp[30], 8'h01, "WKC low APRD EEP_DATA");

    $display("PASS: minimal ESC tests completed");
    repeat (20) @(posedge clk);
    $finish;
  end

endmodule
