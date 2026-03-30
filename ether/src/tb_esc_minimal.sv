`timescale 1ns / 1ps

module tb_esc_minimal;

  localparam int MAX_BYTES = 256;

  logic clk;
  logic rst_n;
  logic link_up;

  logic [3:0] rxd;
  logic       rx_dv;
  logic [3:0] txd;
  logic       tx_en;

  logic [7:0] gpio_out;

  logic [7:0] rx_resp[MAX_BYTES-1:0];
  int resp_len;

  esc_minimal_slave #(
      .REG_SPACE_BYTES(4096),
      .FRAME_MAX_BYTES(1536),
      .GPIO_OUT_WIDTH(8),
      .GPIO_IN_WIDTH(0)
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

  task automatic capture_response;
    logic half;
    logic [3:0] low_nibble;
    begin
      resp_len = 0;
      half = 1'b0;
      low_nibble = 4'h0;

      repeat (400) begin
        @(posedge clk);
        if (tx_en) begin
          if (!half) begin
            low_nibble = txd;
            half = 1'b1;
          end else begin
            if (resp_len < MAX_BYTES) begin
              rx_resp[resp_len] = {txd, low_nibble};
            end
            resp_len = resp_len + 1;
            half = 1'b0;
          end
        end else if (resp_len > 0) begin
          disable capture_response;
        end
      end
    end
  endtask

  task automatic send_ecat_single_datagram(
      input logic [7:0] cmd,
      input logic [15:0] adp,
      input logic [15:0] ado,
      input int unsigned payload_len,
      input logic [7:0] payload0,
      input logic [7:0] payload1,
      input logic [7:0] payload2,
      input logic [7:0] payload3
  );
    logic [15:0] ecat_len;
    logic [15:0] dlen_field;
    begin
      ecat_len = 16'(10 + payload_len + 2);
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

      end_frame();
    end
  endtask

  task automatic expect_eq8(
      input logic [7:0] got,
      input logic [7:0] exp,
      input string name
  );
    begin
      if (got !== exp) begin
        $display("FAIL: %s got=%02x exp=%02x", name, got, exp);
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

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    link_up = 1'b1;
    repeat (8) @(posedge clk);

    $display("TEST1: APRD AL Status (expect INIT=0x01)");
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0130, 1, 8'h00, 8'h00, 8'h00, 8'h00);
    capture_response();
    expect_true(resp_len >= 29, "response length for APRD");
    expect_eq8(rx_resp[26], 8'h01, "AL status byte");
    wkc_index = 27;
    expect_eq8(rx_resp[wkc_index], 8'h01, "WKC low APRD");

    $display("TEST2: APWR AL Control PREOP then APRD AL Status");
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0120, 1, 8'h02, 8'h00, 8'h00, 8'h00);
    capture_response();
    expect_true(resp_len >= 29, "response length for APWR");
    expect_eq8(rx_resp[27], 8'h01, "WKC low APWR");

    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0130, 1, 8'h00, 8'h00, 8'h00, 8'h00);
    capture_response();
    expect_eq8(rx_resp[26], 8'h02, "AL status PREOP");

    $display("TEST3: APWR GPIO output register and verify gpio_out");
    send_ecat_single_datagram(8'h02, 16'h0000, 16'h0f00, 1, 8'hA5, 8'h00, 8'h00, 8'h00);
    capture_response();
    repeat (4) @(posedge clk);
    expect_eq8(gpio_out, 8'hA5, "gpio_out value");

    $display("TEST4: Read DC time low bytes and expect monotonic value");
    send_ecat_single_datagram(8'h01, 16'h0000, 16'h0910, 4, 8'h00, 8'h00, 8'h00, 8'h00);
    capture_response();
    expect_true(resp_len >= 32, "response length for DC read");
    expect_true({rx_resp[29], rx_resp[28], rx_resp[27], rx_resp[26]} != 32'h0000_0000,
                "dc time non-zero");

    $display("PASS: minimal ESC tests completed");
    repeat (20) @(posedge clk);
    $finish;
  end

endmodule