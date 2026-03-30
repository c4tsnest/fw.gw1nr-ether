#!/bin/bash

MODULE_FILE="../ether/src/switch.v"
TB_FILE="../ether/src/tb_switch.v"
OUTPUT_BIN="switch_sim.out"
WAVE_FILE="waveform.vcd"

if [ -f "$OUTPUT_BIN" ]; then
    rm "$OUTPUT_BIN"
fi
if [ -f "$WAVE_FILE" ]; then
    rm "$WAVE_FILE"
fi

echo "--- Compiling $MODULE_FILE and $TB_FILE ---"
iverilog -o "$OUTPUT_BIN" "$MODULE_FILE" "$TB_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Compilation failed!"
    exit 1
fi

echo "--- Running Simulation ---"
vvp "$OUTPUT_BIN"

if [ -f "$WAVE_FILE" ]; then
    echo "--- Opening GTKWave ---"
    # The '&' runs it in the background so the terminal doesn't freeze
    gtkwave "$WAVE_FILE" -A &
else
    echo "Error: Waveform file ($WAVE_FILE) was not generated."
fi
