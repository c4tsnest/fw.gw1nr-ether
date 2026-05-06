#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "soem/soem.h"

static int run = 1;

static void signal_handler(int sig) {
  (void)sig;
  run = 0;
}

int main(int argc, char* argv[]) {
  const char* ifname;
  ecx_contextt context = {0};

  printf("SOEM v2.0.0 master test\n");

  if (argc > 1) {
    ifname = argv[1];
  } else {
    fprintf(stderr, "Usage: %s <ifname>\n", argv[0]);
    return 1;
  }

  signal(SIGINT, signal_handler);
  signal(SIGTERM, signal_handler);

  printf("Initializing on %s...\n", ifname);
  if (ecx_init(&context, ifname) <= 0) {
    fprintf(stderr, "No socket connection on %s. Run as root?\n", ifname);
    return 1;
  }
  printf("ecx_init succeeded.\n");

  printf("Scanning for slaves...\n");
  if (ecx_config_init(&context) <= 0) {
    fprintf(stderr, "No slaves found on %s\n", ifname);
    ecx_close(&context);
    return 1;
  }
  printf("Found %d slave(s).\n", context.slavecount);

  if (context.slavecount < 1) {
    fprintf(stderr, "Expected at least 1 slave, found %d\n", context.slavecount);
    ecx_close(&context);
    return 1;
  }

  uint16 slave = 1;

  printf("\n=== Slave 1 Info ===\n");
  printf("  Name: %s\n", context.slavelist[1].name);
  printf("  State: 0x%04X\n", context.slavelist[1].state);
  printf("  AL status code: 0x%04X\n", context.slavelist[1].ALstatuscode);
  printf("  Configured address (ADR): 0x%04X\n", context.slavelist[1].configadr);

  printf("\n=== Register Read Tests (FPRD) ===\n");

  uint16 type_val = 0, revision_val = 0;
  uint16 configadr = context.slavelist[slave].configadr;
  int rc;

  rc = ecx_FPRD(&context.port, configadr, 0x0000, sizeof(type_val), &type_val, EC_TIMEOUTRET);
  printf("  Read Type   (0x0000): 0x%04X (%s)\n", type_val, rc > 0 ? "OK" : "FAILED");

  rc = ecx_FPRD(&context.port, configadr, 0x0001, sizeof(revision_val), &revision_val,
                EC_TIMEOUTRET);
  printf("  Read Revision (0x0001): 0x%04X (%s)\n", revision_val, rc > 0 ? "OK" : "FAILED");

  printf("\n=== GPIO Write/Read Test (FPWR/FPRD) ===\n");

  uint8 gpio_wr = 0x5A;
  uint8 gpio_rd = 0;

  rc = ecx_FPWR(&context.port, configadr, 0x0F00, sizeof(gpio_wr), &gpio_wr, EC_TIMEOUTRET);
  printf("  Write GPIO  (0x0F00) = 0x%02X: %s\n", gpio_wr, rc > 0 ? "OK" : "FAILED");

  usleep(1000);

  rc = ecx_FPRD(&context.port, configadr, 0x0F00, sizeof(gpio_rd), &gpio_rd, EC_TIMEOUTRET);
  printf("  Read GPIO   (0x0F00) = 0x%02X: %s\n", gpio_rd, rc > 0 ? "OK" : "FAILED");

  if (gpio_rd == gpio_wr) {
    printf("  GPIO loopback: PASS\n");
  } else {
    printf("  GPIO loopback: MISMATCH (expected 0x%02X, got 0x%02X)\n", gpio_wr, gpio_rd);
  }

  printf("\n=== AL State Transitions ===\n");

  uint16 st;
  int state_timeout = 2000000;

  context.slavelist[0].state = EC_STATE_INIT;
  ecx_writestate(&context, 0);
  st = ecx_statecheck(&context, slave, EC_STATE_INIT, state_timeout);
  if (st == EC_STATE_INIT) {
    printf("  INIT:     OK\n");
  } else {
    printf("  INIT:     FAILED (state=0x%04X)\n", st);
  }

  context.slavelist[0].state = EC_STATE_PRE_OP;
  ecx_writestate(&context, 0);
  st = ecx_statecheck(&context, slave, EC_STATE_PRE_OP, state_timeout);
  if (st == EC_STATE_PRE_OP) {
    printf("  PREOP:    OK\n");
  } else {
    printf("  PREOP:    FAILED (state=0x%04X, ALstatuscode=0x%04X)\n", st,
           context.slavelist[0].ALstatuscode);
  }

  context.slavelist[0].state = EC_STATE_SAFE_OP;
  ecx_writestate(&context, 0);
  st = ecx_statecheck(&context, slave, EC_STATE_SAFE_OP, state_timeout);
  if (st == EC_STATE_SAFE_OP) {
    printf("  SAFEOP:   OK\n");
  } else {
    printf("  SAFEOP:   FAILED (state=0x%04X, ALstatuscode=0x%04X)\n", st,
           context.slavelist[0].ALstatuscode);
  }

  context.slavelist[0].state = EC_STATE_OPERATIONAL;
  ecx_writestate(&context, 0);
  st = ecx_statecheck(&context, slave, EC_STATE_OPERATIONAL, state_timeout);
  if (st == EC_STATE_OPERATIONAL) {
    printf("  OP:        OK\n");
  } else {
    printf("  OP:        FAILED (state=0x%04X, ALstatuscode=0x%04X)\n", st,
           context.slavelist[0].ALstatuscode);
    printf("  (This is expected if the slave does not have valid PDO mapping)\n");
  }

  printf("\n  Returning to INIT...\n");
  context.slavelist[0].state = EC_STATE_INIT;
  ecx_writestate(&context, 0);
  ecx_statecheck(&context, slave, EC_STATE_INIT, state_timeout);

  printf("\n=== Test Complete ===\n");
  printf("Final slave state: 0x%04X\n", context.slavelist[0].state);

  ecx_close(&context);
  return 0;
}
