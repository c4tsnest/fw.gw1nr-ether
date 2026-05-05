# AGENTS.md

## Project Overview

Verilog EtherCAT slave controller targeting Gowin GW1NR-9C (Tang Nano 9K). Implements a minimal ESC (EtherCAT Slave Controller) with three ports (A/B/C), where port B is the active EtherCAT port.

## Key Commands

```makefile
make sim              # Run Verilator simulation (default), outputs sim/verilator/out/waveform.vcd
make sim-iverilog     # Run Icarus simulation (iverilog+vvp), outputs sim/iverilog/out/waveform.vcd
make sim-verilator    # Alias for Verilator simulation
make synth            # Gowin synthesis (requires GW_SH, proprietary)
make impl / make pnr  # Synthesis + place&route (requires GW_SH)
make write            # Program SRAM via openFPGALoader
make write-flash      # Program external flash
make sim-view         # Open GTKWave with latest VCD
```

## Build Dependencies

- **Simulation (Verilator)**: `verilator`, C++ toolchain (g++/make)
- **Simulation (Icarus)**: `iverilog`, `vvp`, `gtkwave`
- **Synthesis/PnR**: Gowin IDE at `/opt/gowin/IDE/bin/gw_sh` (Linux + X11/Qt only)
- **Programming**: `openFPGALoader`
- **Linting/Formatting (SV)**: `verible-verilog-lint`, `verible-verilog-format`
- **Linting/Formatting (C++)**: `clang-format`

## Source Structure

| File | Role |
|------|------|
| `src/esc_minimal_slave.sv` | Main ESC module (register file, EtherCAT frame parsing, WKC) |
| `src/esc_al_fsm.sv` | Application Layer state machine |
| `src/top.sv` | Top-level, PHY reset hold, LED controller, port B active |
| `src/led.sv` | LED blink controller |
| `sim/iverilog/tb_esc_minimal.sv` | Self-checking SystemVerilog testbench (15 tests) |
| `sim/verilator/tb_esc_minimal.cpp` | Self-checking C++ testbench for Verilator (15 tests) |
| `gowin/ether.gprj` | Gowin IDE project file (device: GW1NR-9C) |
| `gowin/ether.cst` | Pin constraints |

## Verible Lint/Format (Verilog)

No pre-commit or CI enforcement. Run manually:
```bash
make format            # Format all SystemVerilog files
verible-verilog-lint --ruleset .rules.verible_lint src/*.sv sim/iverilog/*.sv
```

## Simulation

Two simulation backends are supported:

**Verilator (default)**: `make sim`
- Compile: `verilator --cc --build -j --top-module esc_minimal_slave --exe sim/verilator/tb_esc_minimal.cpp src/esc_al_fsm.sv src/esc_minimal_slave.sv`
- VCD output: `sim/verilator/out/waveform.vcd` (enable with `make sim VERILATOR_TRACE=1`)
- C++ testbench formatting: `clang-format -i -style=file:sim/verilator/.clang-format sim/verilator/tb_esc_minimal.cpp`

**Icarus (legacy)**: `make sim-iverilog`
- Compile: `iverilog -g2012 -o sim/iverilog/out/esc_sim.out src/esc_al_fsm.sv src/esc_minimal_slave.sv sim/iverilog/tb_esc_minimal.sv`
- VCD output: `sim/iverilog/out/waveform.vcd`

Both testbenches cover the same 15 tests using 4-bit `rxd` half-byte serialization (byte = {rxd[7:4], rxd[3:0]}).

## No CI/Lint Enforcement

This repo has no automated lint checks, no pre-commit hooks, and no GitHub Actions. Manual verification only.