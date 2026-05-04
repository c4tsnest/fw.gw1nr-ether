# EtherCAT Slave Controller for Gowin GW1NR-9C

A minimal EtherCAT Slave Controller (ESC) implemented in Verilog, targeting the Gowin GW1NR-9C FPGA (Tang Nano 9K). Supports three ports (A/B/C) with port B as the active EtherCAT port.

## Hardware

- **FPGA**: Gowin GW1NR-9C (GW1NR-LV9QN88PC6/I5)
- **Board**: Tang Nano 9K
- **Ports**: Port B (EtherCAT active), Ports A/C (loopback/disabled)

## Features

- EtherCAT register file emulation (EtherCAT slave register map)
- Frame parsing: APRD, APWR, APRW, FPRD, FPWR, FPRW, BRD, BWR, BRW commands
- Working Counter (WKC) generation
- Auto-increment (ADP) addressing support
- FMMU and Sync Manager register windows
- EEPROM emulation (fixed read-only values)
- DC (Distributed Clock) time counter
- PHY reset hold on startup (~5ms)
- LED activity indicator

## Project Structure

```
src/
  esc_minimal_slave.sv   # Main ESC core with EtherCAT frame parsing
  esc_al_fsm.sv          # Application Layer state machine (INIT, PREOP, SAFEOP, OP)
  top.sv                 # Top-level, PHY reset, LED control, port B active
  led.sv                 # LED blink controller

sim/
  iverilog/
    tb_esc_minimal.sv     # Self-checking SV testbench (15 tests)
  verilator/
    tb_esc_minimal.cpp    # Self-checking C++ testbench (15 tests)

gowin/
  ether.gprj             # Gowin IDE project file
  ether.cst              # Pin constraints (Tang Nano 9K)
  run_flow.tcl           # Synthesis/PnR flow script

doc/
  ethercatconfig.c       # EtherCAT configuration definitions
  ethercattype.h         # EtherCAT type definitions
```

## Quick Start

### Prerequisites

- **Simulation**: Verilator (default) or Icarus Verilog (`iverilog`, `vvp`), GTKWave
- **Synthesis/PnR**: Gowin IDE (`/opt/gowin/IDE/bin/gw_sh`)
- **Programming**: openFPGALoader

### Simulation

```bash
make sim          # Verilator (default)
make sim-iverilog # Icarus
make sim-view     # Open waveform in GTKWave
```

### Synthesis and Programming

```bash
make impl         # Synthesis + place&route
make write        # Program SRAM
make write-flash  # Program external flash
```

## EtherCAT Register Map

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x0000-0x013F | Core Registers | RW | Type, Revision, FMMU, SM, etc. |
| 0x0500-0x050F | EEPROM | RW | EEPROM configuration and data |
| 0x0600-0x063F | FMMU | RW | FMMU register window |
| 0x0800-0x081F | SM | RW | Sync Manager register window |
| 0x0910-0x093F | DC | R | Distributed Clock time |
| 0x0F00-0x0F1F | GPIO | RW | General Purpose I/O |

## EtherCAT Commands

| Cmd | Name | Description |
|-----|------|-------------|
| 0x01 | APRD | Auto-increment physical read |
| 0x02 | APWR | Auto-increment physical write |
| 0x03 | APRW | Auto-increment physical read/write |
| 0x04 | FPRD | Configured address read |
| 0x05 | FPWR | Configured address write |
| 0x06 | FPRW | Configured address read/write |
| 0x07 | BRD | Broadcast read |
| 0x08 | BWR | Broadcast write |
| 0x09 | BRW | Broadcast read/write |

## Application Layer States

- **INIT (0x01)**: Initialization state
- **PREOP (0x02)**: Pre-operational (mailbox communication)
- **SAFEOP (0x04)**: Safe-operational (process data stopped)
- **OP (0x08)**: Operational (process data active)

## Configuration

### Environment Variables (for .envrc)

```bash
export GW_SH=/opt/gowin/IDE/bin/gw_sh
export GOWIN_IDE_ROOT=/opt/gowin/IDE
export GOWIN_XDG_SESSION=xcb
export QT_QPA_PLATFORM=xcb
```

### Toolchain Overrides

```bash
make BOARD=tangnano9k BITSTREAM_FS=path/to/bitstream.fs GW_SH=/custom/path/gw_sh
```

## Datasheet Reference

The register layout follows the ET1100 EtherCAT Slave Controller datasheet. Key documents:
- `doc/ethercat_esc_datasheet_sec2_registers_3i0.pdf`
- `doc/ethercattype.h`
- `doc/ethercatconfig.c`

## License

[To be determined]