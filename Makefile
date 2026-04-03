GW_SH            ?= /opt/gowin/IDE/bin/gw_sh
GOWIN_IDE_ROOT   ?= /opt/gowin/IDE
GOWIN_XDG_SESSION ?= xcb
QT_QPA_PLATFORM  ?= xcb
GOWIN_LD_LIB     ?= $(GOWIN_IDE_ROOT)/lib
GOWIN_QT_PLUGINS ?= $(GOWIN_IDE_ROOT)/lib/Qt/plugins
GOWIN_PROJECT    ?= gowin/ether.gprj
GOWIN_FLOW_TCL   ?= gowin/run_flow.tcl
BITSTREAM_FS     ?= gowin/impl/pnr/ether.fs
BOARD            ?= tangnano9k

SIM_OUT_DIR      ?= sim/out
SIM_TB           ?= sim/tb_esc_minimal.sv
SIM_SRCS         ?= src/esc_al_fsm.sv src/esc_minimal_slave.sv
SIM_BIN          ?= $(SIM_OUT_DIR)/esc_sim.out
SIM_VCD          ?= $(SIM_OUT_DIR)/waveform.vcd

.PHONY: all help check-tools check-sim-tools synth pnr impl write write-flash sim sim-view clean

all: impl

help:
	@echo "Targets:"
	@echo "  make synth       - Run Gowin synthesis via gw_sh"
	@echo "  make pnr         - Run Gowin synthesis + place&route via gw_sh"
	@echo "  make impl        - Alias for full Gowin run (pnr target)"
	@echo "  make write       - Program FPGA SRAM (openFPGALoader)"
	@echo "  make write-flash - Program external flash"
	@echo "  make sim         - Run Icarus simulation and emit VCD"
	@echo "  make sim-view    - Open GTKWave for latest VCD"
	@echo "  make clean       - Remove simulation outputs"
	@echo ""
	@echo "Useful overrides:"
	@echo "  GW_SH=/opt/gowin/IDE/bin/gw_sh"
	@echo "  GOWIN_IDE_ROOT=/opt/gowin/IDE"
	@echo "  GOWIN_XDG_SESSION=xcb"
	@echo "  QT_QPA_PLATFORM=xcb"
	@echo "  GOWIN_PROJECT=gowin/ether.gprj"
	@echo "  BITSTREAM_FS=gowin/impl/pnr/ether.fs"
	@echo "  BOARD=tangnano9k"

check-tools:
	@test -x "$(GW_SH)" || (echo "ERROR: gw_sh not found at $(GW_SH)" && exit 1)
	@command -v openFPGALoader >/dev/null || (echo "ERROR: openFPGALoader not found in PATH" && exit 1)

check-sim-tools:
	@command -v iverilog >/dev/null || (echo "ERROR: iverilog not found in PATH" && exit 1)
	@command -v vvp >/dev/null || (echo "ERROR: vvp not found in PATH" && exit 1)


synth: check-tools
	XDG_SESSION_TYPE=$(GOWIN_XDG_SESSION) LD_LIBRARY_PATH="$(GOWIN_LD_LIB):$$LD_LIBRARY_PATH" QT_PLUGIN_PATH="$(GOWIN_QT_PLUGINS)" QT_QPA_PLATFORM=$(QT_QPA_PLATFORM) "$(GW_SH)" "$(GOWIN_FLOW_TCL)" "$(GOWIN_PROJECT)" synth

pnr: check-tools
	XDG_SESSION_TYPE=$(GOWIN_XDG_SESSION) LD_LIBRARY_PATH="$(GOWIN_LD_LIB):$$LD_LIBRARY_PATH" QT_PLUGIN_PATH="$(GOWIN_QT_PLUGINS)" QT_QPA_PLATFORM=$(QT_QPA_PLATFORM) "$(GW_SH)" "$(GOWIN_FLOW_TCL)" "$(GOWIN_PROJECT)" pnr

impl: pnr

write: check-tools
	@test -f "$(BITSTREAM_FS)" || (echo "ERROR: bitstream not found: $(BITSTREAM_FS)" && exit 1)
	openFPGALoader -b "$(BOARD)" "$(BITSTREAM_FS)"

write-flash: check-tools
	@test -f "$(BITSTREAM_FS)" || (echo "ERROR: bitstream not found: $(BITSTREAM_FS)" && exit 1)
	openFPGALoader -b "$(BOARD)" -f --external-flash "$(BITSTREAM_FS)"

$(SIM_OUT_DIR):
	@mkdir -p "$(SIM_OUT_DIR)"

sim: check-sim-tools $(SIM_OUT_DIR)
	rm -f "$(SIM_BIN)" "$(SIM_VCD)"
	iverilog -g2012 -o "$(SIM_BIN)" $(SIM_SRCS) "$(SIM_TB)"
	vvp "$(SIM_BIN)"

sim-view:
	@test -f "$(SIM_VCD)" || (echo "ERROR: waveform not found: $(SIM_VCD). Run 'make sim' first." && exit 1)
	gtkwave "$(SIM_VCD)" -A

clean:
	rm -rf "$(SIM_OUT_DIR)"
