#!/bin/bash

set -e

MODULE_FILES=(
    "../ether/src/esc_al_fsm.sv"
    "../ether/src/esc_minimal_slave.sv"
)
TB_FILE="../ether/src/tb_esc_minimal.sv"
OUTPUT_BIN="esc_sim.out"
WAVE_FILE="waveform.vcd"

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
