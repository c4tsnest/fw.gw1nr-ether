`timescale 1ns / 1ps

module tb_ecat_switch;

  // ========================================================================
  // Signal Declarations
  // ========================================================================
  reg        sys_clk;
  reg        rst_n;

  // Port A (PC)
  reg  [3:0] rxd_a;
  reg        rx_dv_a;
  wire [3:0] txd_a;
  wire       tx_en_a;

  // Port B (EtherCAT)
  reg  [3:0] rxd_b;
  reg        rx_dv_b;
  wire [3:0] txd_b;
  wire       tx_en_b;

  // Port C (Ethernet Node)
  reg  [3:0] rxd_c;
  reg        rx_dv_c;
  wire [3:0] txd_c;
  wire       tx_en_c;

  // ========================================================================
  // DUT Instantiation
  // ========================================================================
  ecat_switch_top dut (
      .sys_clk(sys_clk),
      .rst_n  (rst_n),

      // Port A
      .rxd_a  (rxd_a),
      .rx_dv_a(rx_dv_a),
      .txd_a  (txd_a),
      .tx_en_a(tx_en_a),

      // Port B
      .rxd_b  (rxd_b),
      .rx_dv_b(rx_dv_b),
      .txd_b  (txd_b),
      .tx_en_b(tx_en_b),

      // Port C
      .rxd_c  (rxd_c),
      .rx_dv_c(rx_dv_c),
      .txd_c  (txd_c),
      .tx_en_c(tx_en_c)
  );

  // ========================================================================
  // Clock Generation (50MHz)
  // ========================================================================
  initial sys_clk = 0;
  always #10 sys_clk = ~sys_clk;  // 20ns period

  integer idx;
  initial begin
    $dumpfile("waveform.vcd");  // The file name to output
    $dumpvars(0, tb_ecat_switch);  // Dump all variables in this module and below

    // --- MEMORY DUMP TRICK ---
    // VCD files don't store arrays by default. We must manually loop 
    // through the indices we want to see.
    // Dumping first 32 entries of Downstream FIFO (C)
    for (idx = 0; idx < 32; idx = idx + 1) begin
      $dumpvars(0, dut.u_fifo_down_c.mem[idx]);
    end
    // Dumping first 32 entries of Upstream FIFO (C)
    for (idx = 0; idx < 32; idx = idx + 1) begin
      $dumpvars(0, dut.u_fifo_up_c.mem[idx]);
    end
  end
  // ========================================================================
  // Simulation Tasks
  // ========================================================================

  // Task: Send MII Nibble
  task send_nibble(input [1:0] port_sel, input [3:0] data);
    begin
      @(posedge sys_clk);
      case (port_sel)
        0: begin
          rxd_a   <= data;
          rx_dv_a <= 1;
        end  // Port A
        1: begin
          rxd_b   <= data;
          rx_dv_b <= 1;
        end  // Port B
        2: begin
          rxd_c   <= data;
          rx_dv_c <= 1;
        end  // Port C
      endcase
    end
  endtask

  // Task: Send Complete Frame
  // Generates Preamble + MACs + EtherType + Payload
  task send_frame(input [1:0] port_sel, input [15:0] ethertype, input [7:0] len,
                  input [7:0] pattern_start);
    integer i;
    reg [7:0] byte_data;
    begin
      // 1. Preamble (7 bytes 0x55) + SFD (1 byte 0xD5)
      for (i = 0; i < 7; i = i + 1) begin
        send_nibble(port_sel, 4'h5);  // Low nibble
        send_nibble(port_sel, 4'h5);  // High nibble
      end
      send_nibble(port_sel, 4'h5);  // SFD Low
      send_nibble(port_sel, 4'hD);  // SFD High

      // 2. Dest MAC (6 bytes) - Arbitrary
      for (i = 0; i < 6; i = i + 1) begin
        byte_data = 8'hAA;
        send_nibble(port_sel, byte_data[3:0]);
        send_nibble(port_sel, byte_data[7:4]);
      end

      // 3. Src MAC (6 bytes) - Arbitrary
      for (i = 0; i < 6; i = i + 1) begin
        byte_data = 8'hBB;
        send_nibble(port_sel, byte_data[3:0]);
        send_nibble(port_sel, byte_data[7:4]);
      end

      // 4. EtherType (2 bytes)
      // Send High Byte first in stream logical order, but MII is byte-serial
      // Note: Design expects Byte 20 then Byte 21.
      // Sending ethertype[15:8] (First byte on wire)
      send_nibble(port_sel, ethertype[11:8]);  // Low nibble of High Byte
      send_nibble(port_sel, ethertype[15:12]);  // High nibble of High Byte

      // Sending ethertype[7:0] (Second byte on wire)
      send_nibble(port_sel, ethertype[3:0]);
      send_nibble(port_sel, ethertype[7:4]);

      // 5. Payload
      for (i = 0; i < len; i = i + 1) begin
        byte_data = pattern_start + i;
        send_nibble(port_sel, byte_data[3:0]);
        send_nibble(port_sel, byte_data[7:4]);
      end

      // 6. End of Packet
      @(posedge sys_clk);
      case (port_sel)
        0: rx_dv_a <= 0;
        1: rx_dv_b <= 0;
        2: rx_dv_c <= 0;
      endcase
      // Inter-Frame Gap
      repeat (20) @(posedge sys_clk);
    end
  endtask

  // ========================================================================
  // Main Test Sequence
  // ========================================================================
  initial begin
    // Initialize
    rst_n   = 0;
    rxd_a   = 0;
    rx_dv_a = 0;
    rxd_b   = 0;
    rx_dv_b = 0;
    rxd_c   = 0;
    rx_dv_c = 0;

    repeat (5) @(posedge sys_clk);
    rst_n = 1;
    repeat (5) @(posedge sys_clk);

    $display("---------------------------------------------------------------");
    $display("TEST 1: DOWNSTREAM ROUTING (Port A -> B/C)");
    $display("---------------------------------------------------------------");

    // 1. Send EtherCAT Frame (0x88A4) from A
    // Expectation: Should appear on Port B, NOT on Port C (or partial on C then stop)
    $display("[Time %0t] Sending EtherCAT Frame (0x88A4) to Port A...", $time);
    send_frame(0, 16'h88A4, 10, 8'h10);

    // 2. Send Standard IPv4 Frame (0x0800) from A
    // Expectation: Should appear on Port C (Buffered), NOT on Port B
    $display("[Time %0t] Sending IPv4 Frame (0x0800) to Port A...", $time);
    send_frame(0, 16'h0800, 10, 8'h20);

    repeat (100) @(posedge sys_clk);

    $display("---------------------------------------------------------------");
    $display("TEST 2: UPSTREAM PRIORITY & PREEMPTION (B/C -> Port A)");
    $display("---------------------------------------------------------------");

    // 3. Simple Upstream from B (High Priority)
    $display("[Time %0t] Sending Upstream Traffic from B (High Prio)...", $time);
    send_frame(1, 16'h88A4, 10, 8'hAA);

    repeat (50) @(posedge sys_clk);

    // 4. Preemption Scenario
    // Start sending a LONG packet on C (Low Priority)
    // Interrupt it halfway with a packet from B
    $display("[Time %0t] START Preemption Test: Sending Long Packet on C...", $time);

    // Manually drive C to control timing
    // fork
    begin : send_c_long
      integer i;
      // Start C Packet
      for (i = 0; i < 60; i = i + 1) begin
        send_nibble(2, (i[3:0]));  // Dummy data
        send_nibble(2, (i[3:0]));
      end
      // rx_dv_c = 0;
    end

    // begin : interrupt_with_b
    // Wait for C to start transmitting on Output A
    // repeat (40) @(posedge sys_clk);
    $display("[Time %0t] !!! INTERRUPTING WITH PORT B !!!", $time);
    // Send B Packet
    send_frame(1, 16'h88A4, 10, 8'hFF);
    $display("[Time %0t] Port B Interrupt Complete.", $time);
    // end
    // join
    begin : send_c_long_2
      integer i;
      for (i = 0; i < 60; i = i + 1) begin
        send_nibble(2, (i[3:0]));  // Dummy data
        send_nibble(2, (i[3:0]));
      end
    end
    rx_dv_c = 0;

    $display("[Time %0t] Test Complete. Check Waveforms.", $time);

    repeat (100) @(posedge sys_clk);
    $finish;
  end

  // ========================================================================
  // Monitoring
  // ========================================================================
  always @(posedge sys_clk) begin
    if (tx_en_a) $display("[Monitor A-OUT] Data: %h (Time: %0t)", txd_a, $time);
    // Note: You can uncomment these to see other ports
    if (tx_en_b) $display("[Monitor B-OUT] Data: %h", txd_b);
    if (tx_en_c) $display("[Monitor C-OUT] Data: %h", txd_c);
  end

endmodule
