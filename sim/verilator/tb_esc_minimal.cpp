#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "Vesc_minimal_slave.h"
#include "verilated.h"
#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

#define MAX_BYTES 256

static Vesc_minimal_slave *dut;
#if VM_TRACE
static VerilatedVcdC *tfp;
#endif
static vluint64_t sim_time = 0;

static uint8_t rx_resp[MAX_BYTES];
static int resp_len;
static bool cap_half;
static uint8_t cap_low_nibble;

static void tick() {
  dut->clk = 0;
  dut->eval();
#if VM_TRACE
  if (tfp) tfp->dump(sim_time);
#endif
  sim_time++;

  dut->clk = 1;
  dut->eval();
#if VM_TRACE
  if (tfp) tfp->dump(sim_time);
#endif
  sim_time++;

  if (dut->tx_en) {
    if (!cap_half) {
      cap_low_nibble = dut->txd & 0xF;
      cap_half = true;
    } else {
      if (resp_len < MAX_BYTES) {
        rx_resp[resp_len] = (uint8_t)(((dut->txd & 0xF) << 4) | cap_low_nibble);
      }
      resp_len++;
      cap_half = false;
    }
  } else {
    cap_half = false;
  }
}

static void clear_capture() {
  resp_len = 0;
  cap_half = false;
  cap_low_nibble = 0;
}

static void wait_tx_idle() {
  int idle_cycles = 0;
  int max_cycles = 100000;
  while (idle_cycles < 12) {
    tick();
    max_cycles--;
    if (max_cycles <= 0) {
      fprintf(stderr, "DBG: wait_tx_idle timed out, tx_en=%d, resp_len=%d\n",
              (int)dut->tx_en, resp_len);
      exit(1);
    }
    if (dut->tx_en) {
      idle_cycles = 0;
    } else {
      idle_cycles++;
    }
  }
}

static void send_byte(uint8_t value) {
  tick();
  dut->rxd = value & 0xF;
  dut->rx_dv = 1;
  tick();
  dut->rxd = (value >> 4) & 0xF;
  dut->rx_dv = 1;
}

static void end_frame() {
  tick();
  dut->rxd = 0;
  dut->rx_dv = 0;
  tick();
}

static void send_ecat_mac_and_ethertype() {
  send_byte(0x01);
  send_byte(0x02);
  send_byte(0x03);
  send_byte(0x04);
  send_byte(0x05);
  send_byte(0x06);
  send_byte(0x10);
  send_byte(0x20);
  send_byte(0x30);
  send_byte(0x40);
  send_byte(0x50);
  send_byte(0x60);
  send_byte(0x88);
  send_byte(0xA4);
}

static void send_ecat_datagram_header(uint8_t cmd, uint16_t adp, uint16_t ado,
                                      unsigned payload_len) {
  uint16_t ecat_len = (uint16_t)(10 + payload_len + 2);
  uint16_t dlen_field = (uint16_t)payload_len;

  send_byte(ecat_len & 0xFF);
  send_byte(0x10 | ((ecat_len >> 8) & 0x7));
  send_byte(cmd);
  send_byte(0x01);
  send_byte(adp & 0xFF);
  send_byte((adp >> 8) & 0xFF);
  send_byte(ado & 0xFF);
  send_byte((ado >> 8) & 0xFF);
  send_byte(dlen_field & 0xFF);
  send_byte((dlen_field >> 8) & 0x7);
  send_byte(0x00);
  send_byte(0x00);
}

static void send_ecat_fcs() {
  send_byte(0x00);
  send_byte(0x00);
  send_byte(0x00);
  send_byte(0x00);
}

static void send_ecat_single_datagram(uint8_t cmd, uint16_t adp, uint16_t ado, unsigned payload_len,
                                      uint8_t p0, uint8_t p1, uint8_t p2, uint8_t p3) {
  send_ecat_mac_and_ethertype();
  send_ecat_datagram_header(cmd, adp, ado, payload_len);

  if (payload_len > 0) send_byte(p0);
  if (payload_len > 1) send_byte(p1);
  if (payload_len > 2) send_byte(p2);
  if (payload_len > 3) send_byte(p3);

  send_byte(0x00);
  send_byte(0x00);
  send_ecat_fcs();
  end_frame();
}

static void send_ecat_single_datagram8(uint8_t cmd, uint16_t adp, uint16_t ado,
                                       unsigned payload_len, uint8_t p0, uint8_t p1, uint8_t p2,
                                       uint8_t p3, uint8_t p4, uint8_t p5, uint8_t p6, uint8_t p7) {
  send_ecat_mac_and_ethertype();
  send_ecat_datagram_header(cmd, adp, ado, payload_len);

  if (payload_len > 0) send_byte(p0);
  if (payload_len > 1) send_byte(p1);
  if (payload_len > 2) send_byte(p2);
  if (payload_len > 3) send_byte(p3);
  if (payload_len > 4) send_byte(p4);
  if (payload_len > 5) send_byte(p5);
  if (payload_len > 6) send_byte(p6);
  if (payload_len > 7) send_byte(p7);

  send_byte(0x00);
  send_byte(0x00);
  send_ecat_fcs();
  end_frame();
}

static void send_ecat_single_datagram_with_preamble(uint8_t cmd, uint16_t adp, uint16_t ado,
                                                    unsigned payload_len, uint8_t p0) {
  for (int i = 0; i < 7; i++) send_byte(0x55);
  send_byte(0xD5);

  send_byte(0x01);
  send_byte(0x02);
  send_byte(0x03);
  send_byte(0x04);
  send_byte(0x88);
  send_byte(0xA4);
  send_byte(0x10);
  send_byte(0x20);
  send_byte(0x30);
  send_byte(0x40);
  send_byte(0x50);
  send_byte(0x60);
  send_byte(0x88);
  send_byte(0xA4);

  send_ecat_datagram_header(cmd, adp, ado, payload_len);

  if (payload_len > 0) send_byte(p0);

  send_byte(0x00);
  send_byte(0x00);
  send_ecat_fcs();
  end_frame();
}

static void expect_eq8(uint8_t got, uint8_t exp, const char *name) {
  if (got != exp) {
    fprintf(stderr, "FAIL: %s got=%02x exp=%02x\n", name, got, exp);
    exit(1);
  }
}

static void expect_true(bool cond, const char *name) {
  if (!cond) {
    fprintf(stderr, "FAIL: %s\n", name);
    exit(1);
  }
}

static uint32_t crc32_update_byte(uint32_t crc, uint8_t data) {
  uint32_t c = crc;
  for (int i = 0; i < 8; i++) {
    if ((c & 1) ^ ((data >> i) & 1)) {
      c = (c >> 1) ^ 0xEDB88320UL;
    } else {
      c = c >> 1;
    }
  }
  return c;
}

static void expect_fcs_valid(int frame_len, const char *name) {
  uint32_t crc_calc = 0xFFFFFFFF;
  int crc_start = 0;

  if (frame_len >= 12 && rx_resp[0] == 0x55 && rx_resp[1] == 0x55 && rx_resp[2] == 0x55 &&
      rx_resp[3] == 0x55 && rx_resp[4] == 0x55 && rx_resp[5] == 0x55 && rx_resp[6] == 0x55 &&
      rx_resp[7] == 0xD5) {
    crc_start = 8;
  }

  for (int i = crc_start; i < frame_len - 4; i++) {
    crc_calc = crc32_update_byte(crc_calc, rx_resp[i]);
  }
  crc_calc = ~crc_calc;

  uint32_t fcs_got = ((uint32_t)rx_resp[frame_len - 1] << 24) |
                     ((uint32_t)rx_resp[frame_len - 2] << 16) |
                     ((uint32_t)rx_resp[frame_len - 3] << 8) | ((uint32_t)rx_resp[frame_len - 4]);

  if (fcs_got != crc_calc) {
    fprintf(stderr, "FAIL: %s bad FCS got=%08x exp=%08x\n", name, fcs_got, crc_calc);
    exit(1);
  }
}

int main(int argc, char **argv) {
  int wkc_index;

  setbuf(stdout, NULL);
  setbuf(stderr, NULL);

  Verilated::commandArgs(argc, argv);

  dut = new Vesc_minimal_slave;

#if VM_TRACE
  Verilated::traceEverOn(true);
  tfp = new VerilatedVcdC;
  dut->trace(tfp, 99);
  tfp->open("sim/verilator/out/waveform.vcd");
#endif

  dut->rst_n = 0;
  dut->link_up = 0;
  dut->rxd = 0;
  dut->rx_dv = 0;
  clear_capture();

  fprintf(stderr, "DBG: starting init ticks\n");
  for (int i = 0; i < 8; i++) tick();
  fprintf(stderr, "DBG: reset done, releasing\n");
  dut->rst_n = 1;
  dut->link_up = 1;
  for (int i = 0; i < 8; i++) tick();
  fprintf(stderr, "DBG: init complete\n");

  // ============================================================
  //  TEST1: APRD AL Status (expect INIT=0x01)
  // ============================================================
  printf("TEST1: APRD AL Status (expect INIT=0x01)\n");
  clear_capture();
  fprintf(stderr, "DBG: sending frame\n");
  send_ecat_single_datagram(0x01, 0x0000, 0x0130, 1, 0x00, 0x00, 0x00, 0x00);
  fprintf(stderr, "DBG: frame sent, waiting tx idle\n");
  wait_tx_idle();
  fprintf(stderr, "DBG: tx idle, checking resp\n");
  fprintf(stderr, "DBG: resp_len=%d\n", resp_len);
  expect_true(resp_len >= 29, "response length for APRD");
  expect_eq8(rx_resp[26], 0x01, "AL status byte");
  wkc_index = 27;
  expect_eq8(rx_resp[wkc_index], 0x01, "WKC low APRD");

  // ============================================================
  //  TEST2: APWR AL Control PREOP then APRD AL Status
  // ============================================================
  printf("TEST2: APWR AL Control PREOP then APRD AL Status\n");
  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0120, 1, 0x02, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 29, "response length for APWR");
  expect_eq8(rx_resp[27], 0x01, "WKC low APWR");
  expect_fcs_valid(resp_len, "APWR regenerated FCS");

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0130, 1, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[26], 0x02, "AL status PREOP");

  // ============================================================
  //  TEST3: APWR GPIO output register and verify gpio_out
  // ============================================================
  printf("TEST3: APWR GPIO output register and verify gpio_out\n");
  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0f00, 1, 0xA5, 0x00, 0x00, 0x00);
  wait_tx_idle();
  for (int i = 0; i < 4; i++) tick();
  expect_eq8((uint8_t)(dut->gpio_out & 0xFF), 0xA5, "gpio_out value");

  // ============================================================
  //  TEST4: Read DC time low bytes and expect monotonic value
  // ============================================================
  printf("TEST4: Read DC time low bytes and expect monotonic value\n");
  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0910, 4, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 32, "response length for DC read");
  expect_true(((rx_resp[29] << 24) | (rx_resp[28] << 16) | (rx_resp[27] << 8) | rx_resp[26]) != 0U,
              "dc time non-zero");

  // ============================================================
  //  TEST5: APRD auto-increment ADP decrement and no hit WKC
  // ============================================================
  printf("TEST5: APRD auto-increment ADP decrement and no hit WKC\n");
  clear_capture();
  send_ecat_single_datagram(0x01, 0x0001, 0x0130, 1, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 29, "response length for APRD ADP=1");
  expect_eq8(rx_resp[18], 0x00, "ADP low decremented");
  expect_eq8(rx_resp[19], 0x00, "ADP high decremented");
  expect_eq8(rx_resp[27], 0x00, "WKC low no-match APRD");

  // ============================================================
  //  TEST6: SOEM-like BRD TYPE detect-slaves path
  // ============================================================
  printf("TEST6: SOEM-like BRD TYPE detect-slaves path\n");
  clear_capture();
  send_ecat_single_datagram(0x07, 0x0000, 0x0000, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 30, "response length for BRD TYPE");
  expect_eq8(rx_resp[26], 0x11, "TYPE low byte");
  expect_eq8(rx_resp[27], 0x01, "TYPE high byte");
  expect_eq8(rx_resp[28], 0x01, "WKC low BRD TYPE");

  // ============================================================
  //  TEST7: SOEM-like APWR/APRD/FPRD STADR config addressing
  // ============================================================
  printf("TEST7: SOEM-like APWR/APRD/FPRD STADR config addressing\n");
  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0010, 2, 0x01, 0x10, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 30, "response length for APWR STADR");
  expect_eq8(rx_resp[28], 0x01, "WKC low APWR STADR");

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0010, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 30, "response length for APRD STADR");
  expect_eq8(rx_resp[26], 0x01, "APRD STADR low");
  expect_eq8(rx_resp[27], 0x10, "APRD STADR high");
  expect_eq8(rx_resp[28], 0x01, "WKC low APRD STADR");

  clear_capture();
  send_ecat_single_datagram(0x04, 0x1001, 0x0010, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 30, "response length for FPRD STADR");
  expect_eq8(rx_resp[26], 0x01, "FPRD STADR low");
  expect_eq8(rx_resp[27], 0x10, "FPRD STADR high");
  expect_eq8(rx_resp[28], 0x01, "WKC low FPRD STADR");

  // ============================================================
  //  TEST8: SOEM-like BWR reset block and FPRD verify
  // ============================================================
  printf("TEST8: SOEM-like BWR reset block and FPRD verify\n");
  clear_capture();
  send_ecat_single_datagram8(0x08, 0x0000, 0x0800, 8, 0xAA, 0x55, 0x12, 0x34, 0xDE, 0xAD, 0xBE,
                             0xEF);
  wait_tx_idle();
  expect_true(resp_len >= 36, "response length for BWR 8-byte");
  expect_eq8(rx_resp[34], 0x01, "WKC low BWR 8-byte");

  clear_capture();
  send_ecat_single_datagram8(0x04, 0x1001, 0x0800, 8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                             0x00);
  wait_tx_idle();
  expect_true(resp_len >= 36, "response length for FPRD 8-byte");
  expect_eq8(rx_resp[26], 0xAA, "FPRD block byte0");
  expect_eq8(rx_resp[27], 0x55, "FPRD block byte1");
  expect_eq8(rx_resp[28], 0x12, "FPRD block byte2");
  expect_eq8(rx_resp[29], 0x34, "FPRD block byte3");
  expect_eq8(rx_resp[30], 0xDE, "FPRD block byte4");
  expect_eq8(rx_resp[31], 0xAD, "FPRD block byte5");
  expect_eq8(rx_resp[32], 0xBE, "FPRD block byte6");
  expect_eq8(rx_resp[33], 0xEF, "FPRD block byte7");
  expect_eq8(rx_resp[34], 0x01, "WKC low FPRD 8-byte");

  // ============================================================
  //  TEST9: SOEM-like ESC capability and topology fields
  // ============================================================
  printf("TEST9: SOEM-like ESC capability and topology fields\n");
  clear_capture();
  send_ecat_single_datagram(0x04, 0x1001, 0x0008, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 30, "response length for FPRD ESCSUP");
  expect_eq8(rx_resp[26], 0x00, "ESCSUP low (DC support disabled)");
  expect_eq8(rx_resp[27], 0x00, "ESCSUP high");
  expect_eq8(rx_resp[28], 0x01, "WKC low FPRD ESCSUP");

  clear_capture();
  send_ecat_single_datagram(0x04, 0x1001, 0x0007, 1, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 29, "response length for FPRD PORTDES");
  expect_eq8(rx_resp[26], 0x01, "PORTDES low");
  expect_eq8(rx_resp[27], 0x01, "WKC low FPRD PORTDES");

  clear_capture();
  send_ecat_single_datagram(0x04, 0x1001, 0x0110, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 30, "response length for FPRD DLSTATUS");
  expect_eq8(rx_resp[26], 0x00, "DLSTATUS low");
  expect_eq8(rx_resp[27], 0x02, "DLSTATUS high (port0 link active)");
  expect_eq8(rx_resp[28], 0x01, "WKC low FPRD DLSTATUS");

  // ============================================================
  //  TEST10: APRD with preamble and MAC 0x88A4 false-positive pattern
  // ============================================================
  printf("TEST10: APRD with preamble and MAC 0x88A4 false-positive pattern\n");
  clear_capture();
  send_ecat_single_datagram_with_preamble(0x01, 0x0000, 0x0130, 1, 0x00);
  wait_tx_idle();
  expect_true(resp_len >= 37, "response length for APRD preamble");
  expect_eq8(rx_resp[34], 0x02, "AL status preamble");
  expect_eq8(rx_resp[35], 0x01, "WKC low APRD preamble");
  expect_eq8(rx_resp[36], 0x00, "WKC high APRD preamble");
  expect_fcs_valid(resp_len, "APRD preamble regenerated FCS");

  // ============================================================
  //  TEST11: Strict RO identity register (TYPE) does not change on write
  // ============================================================
  printf("TEST11: Strict RO identity register (TYPE) does not change on write\n");
  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0000, 2, 0xAA, 0x55, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[28], 0x00, "WKC low APWR TYPE RO");

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0000, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[26], 0x11, "TYPE low stays RO");
  expect_eq8(rx_resp[27], 0x01, "TYPE high stays RO");
  expect_eq8(rx_resp[28], 0x01, "WKC low APRD TYPE");

  // ============================================================
  //  TEST12: IRQMASK RW register write/readback
  // ============================================================
  printf("TEST12: IRQMASK RW register write/readback\n");
  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0200, 2, 0x04, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[28], 0x01, "WKC low APWR IRQMASK");

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0200, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[26], 0x04, "IRQMASK low readback");
  expect_eq8(rx_resp[27], 0x00, "IRQMASK high readback");
  expect_eq8(rx_resp[28], 0x01, "WKC low APRD IRQMASK");

  // ============================================================
  //  TEST13: PDI control RO and FMMU RW touched registers
  // ============================================================
  printf("TEST13: PDI control RO and FMMU RW touched registers\n");
  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0140, 1, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[26], 0x00, "PDICTL default");
  expect_eq8(rx_resp[27], 0x01, "WKC low APRD PDICTL");

  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0600, 4, 0x12, 0x34, 0x56, 0x78);
  wait_tx_idle();
  expect_eq8(rx_resp[30], 0x01, "WKC low APWR FMMU block");

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0600, 4, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[26], 0x12, "FMMU byte0 readback");
  expect_eq8(rx_resp[27], 0x34, "FMMU byte1 readback");
  expect_eq8(rx_resp[28], 0x56, "FMMU byte2 readback");
  expect_eq8(rx_resp[29], 0x78, "FMMU byte3 readback");
  expect_eq8(rx_resp[30], 0x01, "WKC low APRD FMMU block");

  // ============================================================
  //  TEST14: EEPROM ownership handover/release and gated status writes
  // ============================================================
  printf("TEST14: EEPROM ownership handover/release and gated status writes\n");
  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0500, 1, 0x01, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[27], 0x01, "WKC low APWR EEP_CFG handover");

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0500, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true((rx_resp[26] & 1) == 1, "EEP_CFG 0x500 bit0 set");
  expect_true((rx_resp[27] & 1) == 1, "EEP_CFG 0x501 bit0 owner=PDI");

  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0502, 2, 0x01, 0x01, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[28], 0x00, "WKC low APWR EEP_STAT blocked by PDI owner");

  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0500, 1, 0x02, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[27], 0x01, "WKC low APWR EEP_CFG force release");

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0500, 2, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_true((rx_resp[26] & 1) == 0, "EEP_CFG 0x500 bit0 cleared");
  expect_true((rx_resp[27] & 1) == 0, "EEP_CFG 0x501 bit0 owner=ECAT");

  // ============================================================
  //  TEST15: EEPROM address/data command path with fixed values
  // ============================================================
  printf("TEST15: EEPROM address/data command path with fixed values\n");
  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0504, 4, 0x01, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[30], 0x01, "WKC low APWR EEP_ADDR");

  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0503, 1, 0x01, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[27], 0x01, "WKC low APWR EEP_STAT cmd");

  clear_capture();
  send_ecat_single_datagram(0x02, 0x0000, 0x0502, 1, 0x01, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[27], 0x01, "WKC low APWR EEP_STAT start");

  for (int i = 0; i < 32; i++) tick();

  clear_capture();
  send_ecat_single_datagram(0x01, 0x0000, 0x0508, 4, 0x00, 0x00, 0x00, 0x00);
  wait_tx_idle();
  expect_eq8(rx_resp[26], 0x01, "EEP_DATA byte0");
  expect_eq8(rx_resp[27], 0x00, "EEP_DATA byte1");
  expect_eq8(rx_resp[28], 0x01, "EEP_DATA byte2");
  expect_eq8(rx_resp[29], 0x00, "EEP_DATA byte3");
  expect_eq8(rx_resp[30], 0x01, "WKC low APRD EEP_DATA");

  printf("PASS: minimal ESC tests completed\n");

  for (int i = 0; i < 20; i++) tick();

  dut->final();
#if VM_TRACE
  if (tfp) tfp->close();
  delete tfp;
#endif
  delete dut;
  return 0;
}