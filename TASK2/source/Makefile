# ===============================
# basicRISCV Makefile
# FPGA flow is COMMENTED for Task-2
# Simulation-only validation
# ===============================

# -------- Project variables --------
TOP=SOC
PCF_FILE=VSDSquadronFM
BOARD_FREQ=10
CPU_FREQ=12
FPGA_VARIANT=up5k
FPGA_PACKAGE=sg48
VERILOG_FILE=riscv.v

# -------- UART variables (FPGA only) --------
PICO_DEVICE=/dev/ttyUSB0   # Used ONLY for real hardware
BAUDS=9600

# -------- BUILD TARGET --------
build:
	# FPGA SYNTHESIS (NOT needed for Task-2)
	# yosys -q -p "synth_ice40 -abc9 -device u -dsp -top $(TOP) -json $(TOP).json" $(VERILOG_FILE)

	# FPGA PLACE & ROUTE (NOT needed for Task-2)
	# nextpnr-ice40 --force --json $(TOP).json --pcf $(PCF_FILE).pcf \
	#               --asc $(TOP).asc --freq $(BOARD_FREQ) \
	#               --$(FPGA_VARIANT) --package $(FPGA_PACKAGE) --opt-timing

	# FPGA TIMING ANALYSIS (NOT needed for Task-2)
	# icetime -p $(PCF_FILE).pcf -P $(FPGA_PACKAGE) \
	#         -r $(TOP).timings -d $(FPGA_VARIANT) -t $(TOP).asc

	# FPGA BITSTREAM GENERATION (NOT needed for Task-2)
	# icepack -s $(TOP).asc $(TOP).bin

	@echo "FPGA build steps are commented out for Task-2 (simulation only)"

# -------- FLASH TARGET (FPGA only) --------
flash:
	# iceprog $(TOP).bin

# -------- CLEAN TARGET --------
clean:
	rm -rf $(TOP).blif $(TOP).asc $(TOP).bin \
	       $(TOP).json $(TOP).timings \
	       sim.out *.vcd

# -------- UART TERMINAL (FPGA only) --------
terminal:
	# sudo picocom -b $(BAUDS) $(PICO_DEVICE) \
	# --imap lfcrlf,crcrlf --omap delbs,crlf \
	# --send-cmd "ascii-xfr -s -l 30 -n"

