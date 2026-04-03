# Open-source build flow for Gowin GW1NR-9 (Tang Nano 9K compatible)
# Usage examples:
#   make synth
#   make pnr
#   make pack
#   make flash
#   make clean

OSS_CAD_SUITE ?= /opt/oss-cad-suite
export PATH := $(OSS_CAD_SUITE)/bin:$(PATH)

TOP            ?= top
BUILD_DIR      ?= impl_oss
CST            ?= gowin/ether.cst
DEVICE         ?= GW1NR-LV9QN88PC6/I5
PACK_DEVICE    ?= GW1NR-9C
NEXTPNR_DEVICE ?= GW1NR-9
NEXTPNR_FAMILY ?= GW1NR-9C
BOARD          ?= tangnano9k
FREQ_MHZ       ?= 27

NEXTPNR ?= $(shell command -v nextpnr-himbaechel 2>/dev/null || command -v nextpnr-gowin 2>/dev/null)

RTL_SRCS := $(filter-out src/tb_%.sv src/ecat_%.sv,$(wildcard src/*.sv)) $(wildcard src/*.v)

JSON_NETLIST   := $(BUILD_DIR)/$(TOP).json
PNR_ASC        := $(BUILD_DIR)/$(TOP).asc
BITSTREAM_FS   := $(BUILD_DIR)/$(TOP).fs

.PHONY: all check-tools synth pnr pack flash write clean help

all: pack

help:
	@echo "Targets:"
	@echo "  make synth   - Run Yosys synthesis"
	@echo "  make pnr     - Run nextpnr-gowin place & route"
	@echo "  make pack    - Build Gowin .fs bitstream"
	@echo "  make flash   - Program FPGA with openFPGALoader"
	@echo "  make clean   - Remove generated files"
	@echo ""
	@echo "Useful overrides:"
	@echo "  OSS_CAD_SUITE=/opt/oss-cad-suite"
	@echo "  BUILD_DIR=impl_oss"
	@echo "  TOP=top"
	@echo "  NEXTPNR=nextpnr-himbaechel"
	@echo "  DEVICE=GW1NR-LV9QN88PC6/I5"
	@echo "  NEXTPNR_DEVICE=GW1NR-9"
	@echo "  NEXTPNR_FAMILY=GW1NR-9C"
	@echo "  PACK_DEVICE=GW1NR-9C"
	@echo "  BOARD=tangnano9k"

check-tools:
	@command -v yosys >/dev/null || (echo "ERROR: yosys not found in PATH" && exit 1)
	@test -n "$(NEXTPNR)" || (echo "ERROR: no nextpnr for Gowin found (tried nextpnr-himbaechel, nextpnr-gowin)" && exit 1)
	@command -v gowin_pack >/dev/null || (echo "ERROR: gowin_pack not found in PATH" && exit 1)
	@command -v openFPGALoader >/dev/null || (echo "ERROR: openFPGALoader not found in PATH" && exit 1)

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(JSON_NETLIST): $(RTL_SRCS) | $(BUILD_DIR)
	yosys -p "read_verilog -sv $(RTL_SRCS); synth_gowin -top $(TOP) -json $(JSON_NETLIST)"

synth: check-tools $(JSON_NETLIST)

$(PNR_ASC): $(JSON_NETLIST) $(CST)
	@if [ "$(notdir $(NEXTPNR))" = "nextpnr-himbaechel" ]; then \
		$(NEXTPNR) --json $(JSON_NETLIST) --write $(BUILD_DIR)/$(TOP)_pnr.json --device $(NEXTPNR_DEVICE) --vopt family=$(NEXTPNR_FAMILY) --vopt cst=$(CST) --freq $(FREQ_MHZ) --asc $(PNR_ASC); \
	else \
		$(NEXTPNR) --json $(JSON_NETLIST) --write $(BUILD_DIR)/$(TOP)_pnr.json --device $(DEVICE) --cst $(CST) --freq $(FREQ_MHZ) --asc $(PNR_ASC); \
	fi

pnr: check-tools $(PNR_ASC)

$(BITSTREAM_FS): $(PNR_ASC)
	gowin_pack -d $(PACK_DEVICE) -o $(BITSTREAM_FS) $(PNR_ASC)

pack: check-tools $(BITSTREAM_FS)

flash: check-tools pack
	openFPGALoader -b $(BOARD) $(BITSTREAM_FS)

write: flash

clean:
	rm -rf $(BUILD_DIR)
