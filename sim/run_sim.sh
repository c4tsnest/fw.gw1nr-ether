#!/bin/bash

set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
mkdir -p "$OUT_DIR"

MODULE_FILES=(
    "$SCRIPT_DIR/../src/esc_al_fsm.sv"
    "$SCRIPT_DIR/../src/esc_minimal_slave.sv"
)
TB_FILE="$SCRIPT_DIR/tb_esc_minimal.sv"
OUTPUT_BIN="$OUT_DIR/esc_sim.out"
WAVE_FILE="$OUT_DIR/waveform.vcd"

if [ -f "$OUTPUT_BIN" ]; then
    rm "$OUTPUT_BIN"
fi
if [ -f "$WAVE_FILE" ]; then
    rm "$WAVE_FILE"
fi

echo "--- Compiling split ESC modules and $TB_FILE ---"
iverilog -g2012 -o "$OUTPUT_BIN" "${MODULE_FILES[@]}" "$TB_FILE"

echo "--- Running Simulation ---"
vvp "$OUTPUT_BIN"

if [ -f "$WAVE_FILE" ]; then
    echo "--- Opening GTKWave ---"
    # The '&' runs it in the background so the terminal doesn't freeze
    gtkwave "$WAVE_FILE" -A &
else
    echo "Error: Waveform file ($WAVE_FILE) was not generated."
fi
