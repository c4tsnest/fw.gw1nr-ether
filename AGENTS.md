# AGENTS.md

## Project Overview

Verilog EtherCAT slave controller targeting Gowin GW1NR-9C (Tang Nano 9K). Implements a minimal ESC (EtherCAT Slave Controller) with three ports (A/B/C), where port B is the active EtherCAT port.

## Key Commands

```makefile
make sim              # Run Icarus simulation (iverilog+vvp), outputs sim/out/waveform.vcd
make synth            # Gowin synthesis (requires GW_SH, proprietary)
make impl / make pnr  # Synthesis + place&route (requires GW_SH)
make write            # Program SRAM via openFPGALoader
make write-flash      # Program external flash
make sim-view         # Open GTKWave with latest VCD
```

## Build Dependencies

- **Simulation**: `iverilog`, `vvp`, `gtkwave`
- **Synthesis/PnR**: Gowin IDE at `/opt/gowin/IDE/bin/gw_sh` (Linux + X11/Qt only)
- **Programming**: `openFPGALoader`
- **Linting/Formatting**: `verible-verilog-lint`, `verible-verilog-format`

## Source Structure

| File | Role |
|------|------|
| `src/esc_minimal_slave.sv` | Main ESC module (register file, EtherCAT frame parsing, WKC) |
| `src/esc_al_fsm.sv` | Application Layer state machine |
| `src/top.sv` | Top-level, PHY reset hold, LED controller, port B active |
| `src/led.sv` | LED blink controller |
| `sim/tb_esc_minimal.sv` | Self-checking testbench (15 tests, uses `$fatal` on failure) |
| `gowin/ether.gprj` | Gowin IDE project file (device: GW1NR-9C) |
| `gowin/ether.cst` | Pin constraints |

## Verible Lint/Format

Config files exist (`.verible-verilog-format.yaml`, `.rules.verible_lint`) but no pre-commit or CI enforcement. Run manually:
```bash
verible-verilog-format --files src/*.sv sim/*.sv
verible-verilog-lint --ruleset .rules.verible_lint src/*.sv sim/*.sv
```

## Simulation

- Compile: `iverilog -g2012 -o sim/out/esc_sim.out src/esc_al_fsm.sv src/esc_minimal_slave.sv sim/tb_esc_minimal.sv`
- VCD output: `sim/out/waveform.vcd`
- Testbench uses 4-bit `rxd` half-byte serialization (byte = {rxd[7:4], rxd[3:0]})

## No CI/Lint Enforcement

This repo has no automated lint checks, no pre-commit hooks, and no GitHub Actions. Manual verification only.