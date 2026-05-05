package esc_pkg;

  typedef logic [7:0]  byte_t;
  typedef logic [15:0] word_t;
  typedef logic [3:0]  nibble_t;
  typedef logic [15:0] addr_t;

  typedef enum logic [7:0] {
    CMD_APRD = 8'h01,
    CMD_APWR = 8'h02,
    CMD_APRW = 8'h03,
    CMD_FPRD = 8'h04,
    CMD_FPWR = 8'h05,
    CMD_FPRW = 8'h06,
    CMD_BRD  = 8'h07,
    CMD_BWR  = 8'h08,
    CMD_BRW  = 8'h09
  } ecat_cmd_t;

  typedef enum logic [1:0] {
    REG_NONE = 2'b00,
    REG_R    = 2'b01,
    REG_W    = 2'b10,
    REG_RW   = 2'b11
  } reg_access_t;

  typedef enum logic [3:0] {
    AL_INIT   = 4'h1,
    AL_PREOP  = 4'h2,
    AL_SAFEOP = 4'h4,
    AL_OP     = 4'h8
  } al_state_t;

  localparam addr_t REG_TYPE           = 16'h0000;
  localparam addr_t REG_PORTDES        = 16'h0007;
  localparam addr_t REG_ESCSUP         = 16'h0008;
  localparam addr_t REG_STATION_ADDR   = 16'h0010;
  localparam addr_t REG_ALIAS          = 16'h0012;
  localparam addr_t REG_DL_CONTROL     = 16'h0100;
  localparam addr_t REG_DL_PORT        = 16'h0101;
  localparam addr_t REG_DL_ALIAS       = 16'h0103;
  localparam addr_t REG_DL_STATUS      = 16'h0110;
  localparam addr_t REG_AL_CONTROL     = 16'h0120;
  localparam addr_t REG_AL_STATUS      = 16'h0130;
  localparam addr_t REG_AL_STATUS_CD   = 16'h0134;
  localparam addr_t REG_PDI_CONTROL    = 16'h0140;
  localparam addr_t REG_IRQ_MASK       = 16'h0200;
  localparam addr_t REG_EEP_CFG        = 16'h0500;
  localparam addr_t REG_EEP_STAT       = 16'h0502;
  localparam addr_t REG_EEP_ADDR       = 16'h0504;
  localparam addr_t REG_EEP_DATA       = 16'h0508;
  localparam addr_t REG_FMMU_BASE      = 16'h0600;
  localparam addr_t REG_SM_BASE        = 16'h0800;
  localparam addr_t REG_DC_BASE        = 16'h0900;
  localparam addr_t REG_DC_END         = 16'h093f;
  localparam addr_t REG_DC_TIME        = 16'h0910;
  localparam addr_t REG_DC_SYNC_ACT    = 16'h0981;
  localparam addr_t REG_GPIO_OUT       = 16'h0f00;
  localparam addr_t REG_GPIO_IN        = 16'h0f10;
  localparam addr_t REG_DEBUG_WKC      = 16'h0f20;

  localparam int unsigned CORE_REG_BYTES  = 16'h0140;
  localparam int unsigned SM_REG_BYTES    = 32;
  localparam int unsigned FMMU_REG_BYTES  = 64;
  localparam int unsigned TX_FIFO_DEPTH   = 8;
  localparam int unsigned FCS_DELAY       = 4;

  localparam word_t DLSTATUS_PORT0_LINK = 16'h0200;

  localparam byte_t ETHERTYPE_HI = 8'h88;
  localparam byte_t ETHERTYPE_LO = 8'hA4;
  localparam byte_t PREAMBLE_BYTE = 8'h55;
  localparam byte_t SFD_BYTE      = 8'hD5;
  localparam int unsigned PREAMBLE_LEN = 8;

  localparam int unsigned ECAT_ETHERTYPE_OFFSET       = 12;
  localparam int unsigned ECAT_PREAMBLE_ETHERTYPE_OFS = 20;
  localparam int unsigned ECAT_DATA_START             = 26;

  localparam logic [31:0] CRC_POLY = 32'hEDB88320;
  localparam logic [31:0] CRC_INIT = 32'hFFFF_FFFF;

  function automatic logic addr_in_window(
      input addr_t addr, input addr_t base, input int unsigned size
  );
    addr_in_window = (addr >= base) && (addr < (base + addr_t'(size)));
  endfunction

  function automatic reg_access_t esc_reg_access(input addr_t addr,
      input int unsigned gpio_out_bytes, input int unsigned gpio_in_bytes);
    esc_reg_access = REG_NONE;

    if (addr_in_window(addr, '0, CORE_REG_BYTES))                          esc_reg_access = REG_RW;
    if (addr_in_window(addr, REG_SM_BASE, SM_REG_BYTES))                  esc_reg_access = REG_RW;
    if ((addr >= REG_GPIO_OUT) && (addr < (REG_GPIO_OUT + addr_t'(gpio_out_bytes)))) esc_reg_access = REG_RW;
    if ((addr >= REG_IRQ_MASK) && (addr < (REG_IRQ_MASK + 2)))            esc_reg_access = REG_RW;
    if ((addr >= REG_EEP_CFG) && (addr < (REG_EEP_CFG + 2)))              esc_reg_access = REG_RW;
    if ((addr >= REG_EEP_STAT) && (addr < (REG_EEP_STAT + 2)))            esc_reg_access = REG_RW;
    if ((addr >= REG_EEP_ADDR) && (addr < (REG_EEP_ADDR + 4)))            esc_reg_access = REG_RW;
    if ((addr >= REG_EEP_DATA) && (addr < (REG_EEP_DATA + 4)))            esc_reg_access = REG_RW;
    if (addr_in_window(addr, REG_FMMU_BASE, FMMU_REG_BYTES))               esc_reg_access = REG_RW;
    if (addr == REG_DC_SYNC_ACT)                                            esc_reg_access = REG_RW;

    if ((addr == REG_TYPE) || (addr == (REG_TYPE + 1)))                    esc_reg_access = REG_R;
    if (addr == REG_PORTDES)                                                esc_reg_access = REG_R;
    if ((addr == REG_ESCSUP) || (addr == (REG_ESCSUP + 1)))               esc_reg_access = REG_R;
    if (addr == REG_PDI_CONTROL)                                            esc_reg_access = REG_R;
    if ((addr >= REG_DC_BASE) && (addr <= REG_DC_END))                     esc_reg_access = REG_R;
    if ((addr == REG_DL_STATUS) || (addr == (REG_DL_STATUS + 1)))          esc_reg_access = REG_R;
    if (addr == REG_AL_STATUS)                                              esc_reg_access = REG_R;
    if ((addr == REG_AL_STATUS_CD) || (addr == (REG_AL_STATUS_CD + 1)))   esc_reg_access = REG_R;
    if ((addr >= REG_GPIO_IN) && (addr < (REG_GPIO_IN + addr_t'(gpio_in_bytes)))) esc_reg_access = REG_R;

    if (addr == REG_AL_CONTROL) esc_reg_access = REG_W;
  endfunction

endpackage