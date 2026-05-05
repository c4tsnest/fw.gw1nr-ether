GW_SH            := $(shell echo $${GW_SH:-/opt/gowin/IDE/bin/gw_sh})
GOWIN_IDE_ROOT   := $(shell echo $${GOWIN_IDE_ROOT:-/opt/gowin/IDE})
GOWIN_XDG_SESSION := $(shell echo $${GOWIN_XDG_SESSION:-xcb})
QT_QPA_PLATFORM  := $(shell echo $${QT_QPA_PLATFORM:-xcb})
GOWIN_LD_LIB     := $(shell echo $${GOWIN_LD_LIB:-$(GOWIN_IDE_ROOT)/lib})
GOWIN_QT_PLUGINS := $(shell echo $${GOWIN_QT_PLUGINS:-$(GOWIN_IDE_ROOT)/lib/Qt/plugins})
GOWIN_PROJECT    ?= gowin/ether.gprj
GOWIN_FLOW_TCL   ?= gowin/run_flow.tcl
BITSTREAM_FS     ?= gowin/impl/pnr/ether.fs
BOARD            ?= tangnano9k

# ---- Icarus (iverilog) simulation ----
IVERILOG_OUT_DIR  ?= sim/iverilog/out
IVERILOG_TB       ?= sim/iverilog/tb_esc_minimal.sv
IVERILOG_SRCS     ?= src/pkg/esc_pkg.sv src/if/esc_if.sv src/esc_al_fsm.sv src/esc_mii_rx.sv src/esc_mii_tx.sv src/esc_frame_parser.sv src/esc_crc.sv src/esc_regfile.sv src/esc_datagram_handler.sv src/esc_minimal_slave.sv
IVERILOG_BIN      ?= $(IVERILOG_OUT_DIR)/esc_sim.out
IVERILOG_VCD      ?= $(IVERILOG_OUT_DIR)/waveform.vcd

# ---- Verilator simulation ----
VERILATOR_SRCS     ?= src/pkg/esc_pkg.sv src/if/esc_if.sv src/esc_al_fsm.sv src/esc_mii_rx.sv src/esc_mii_tx.sv src/esc_frame_parser.sv src/esc_crc.sv src/esc_regfile.sv src/esc_datagram_handler.sv src/esc_minimal_slave.sv
VERILATOR_TOP      ?= esc_minimal_slave
VERILATOR_TB_CPP   ?= sim/verilator/tb_esc_minimal.cpp
VERILATOR_OUT_DIR  ?= sim/verilator/out
VERILATOR_OBJ_DIR  ?= sim/verilator/obj_dir
VERILATOR_BIN      ?= $(VERILATOR_OBJ_DIR)/V$(VERILATOR_TOP)
VERILATOR_CFLAGS   += -CFLAGS "-O2 -Wall -Wextra"

SV_FILES := $(shell find src sim -name '*.sv')

.PHONY: all help check-tools check-sim-tools check-verilator-tools synth pnr impl write write-flash
.PHONY: sim sim-iverilog sim-verilator sim-view clean format

all: impl

help:
	@echo "Targets:"
	@echo "  make synth         - Run Gowin synthesis via gw_sh"
	@echo "  make pnr           - Run Gowin synthesis + place&route via gw_sh"
	@echo "  make impl          - Alias for full Gowin run (pnr target)"
	@echo "  make write         - Program FPGA SRAM (openFPGALoader)"
	@echo "  make write-flash   - Program external flash"
	@echo ""
	@echo "  make sim           - Run Verilator simulation (default)"
	@echo "  make sim-iverilog  - Run Icarus simulation"
	@echo "  make sim-verilator - Run Verilator simulation"
	@echo "  make sim-view      - Open GTKWave for latest VCD"
	@echo "  make clean         - Remove simulation outputs"
	@echo "  make format        - Format all SystemVerilog files with verible-verilog-format"
	@echo ""
	@echo "Useful overrides:"
	@echo "  GW_SH              - Path to Gowin gw_sh"
	@echo "  BOARD              - openFPGALoader board name (default: tangnano9k)"
	@echo "  VERILATOR_TRACE=1  - Enable VCD tracing in verilator sim"

check-tools:
	@test -x "$(GW_SH)" || (echo "ERROR: gw_sh not found at $(GW_SH)" && exit 1)
	@command -v openFPGALoader >/dev/null || (echo "ERROR: openFPGALoader not found in PATH" && exit 1)

check-iverilog-tools:
	@command -v iverilog >/dev/null || (echo "ERROR: iverilog not found in PATH" && exit 1)
	@command -v vvp >/dev/null || (echo "ERROR: vvp not found in PATH" && exit 1)

check-verilator-tools:
	@command -v verilator >/dev/null || (echo "ERROR: verilator not found in PATH" && exit 1)

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

# ---- Verilator flow (default) ----
$(VERILATOR_OUT_DIR):
	@mkdir -p "$(VERILATOR_OUT_DIR)"

$(VERILATOR_BIN): check-verilator-tools $(VERILATOR_OUT_DIR) $(VERILATOR_SRCS) $(VERILATOR_TB_CPP)
	rm -rf "$(VERILATOR_OBJ_DIR)"
	verilator --cc --build -j \
		$(if $(VERILATOR_TRACE),--trace,) \
		$(VERILATOR_CFLAGS) \
		-Wno-fatal \
		--top-module $(VERILATOR_TOP) \
		--exe $(VERILATOR_TB_CPP) \
		-Mdir $(VERILATOR_OBJ_DIR) \
		$(VERILATOR_SRCS)

sim: sim-verilator

sim-verilator: $(VERILATOR_BIN)
	@mkdir -p "$(VERILATOR_OUT_DIR)"
	cd "$(VERILATOR_OUT_DIR)" && \
	../obj_dir/V$(VERILATOR_TOP) $(if $(VERILATOR_TRACE),+trace,) 2>&1

# ---- Icarus flow ----
$(IVERILOG_OUT_DIR):
	@mkdir -p "$(IVERILOG_OUT_DIR)"

sim-iverilog: check-iverilog-tools $(IVERILOG_OUT_DIR)
	rm -f "$(IVERILOG_BIN)" "$(IVERILOG_VCD)"
	iverilog -g2012 -o "$(IVERILOG_BIN)" $(IVERILOG_SRCS) "$(IVERILOG_TB)"
	vvp "$(IVERILOG_BIN)" && mv waveform.vcd "$(IVERILOG_VCD)"

sim-view:
	@( test -f "$(VERILATOR_OUT_DIR)/waveform.vcd" || test -f "$(IVERILOG_VCD)" ) || \
		(echo "ERROR: no waveform found. Run 'make sim' or 'make sim-iverilog' first." && exit 1)
	@if [ -f "$(VERILATOR_OUT_DIR)/waveform.vcd" ]; then \
		gtkwave "$(VERILATOR_OUT_DIR)/waveform.vcd" -A; \
	elif [ -f "$(IVERILOG_VCD)" ]; then \
		gtkwave "$(IVERILOG_VCD)" -A; \
	fi

format:
	verible-verilog-format --inplace $(SV_FILES)

clean:
	rm -rf "$(VERILATOR_OBJ_DIR)" "$(VERILATOR_OUT_DIR)" "$(IVERILOG_OUT_DIR)"

# Keep backward-compatible aliases for old paths
check-sim-tools: check-iverilog-tools