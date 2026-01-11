# Complete Integration Guide — Timer IP into VSDSquadron SoC
**Purpose:** Detailed, step-by-step guide for a beginner to integrate `timer_ip.v` into `soc.v`. Includes full code blocks, all wire declarations, where to instantiate, why each signal exists, build & simulation commands, expected outputs, and common errors / fixes. Downloadable file.

---

## Table of Contents
1. Required files
2. Quick overview (what and why)
3. Full modified `soc.v` (complete listing)
4. Where and why each wire/statement is added (line-by-line explanation)
5. Timer instantiation: exact place and reasoning
6. IO readback mux and mem_rdata logic (why it's required)
7. LED toggling logic (how it verifies timer)
8. `timer_ip.v` summary (quick reference)
9. `link.ld` (full file) and why it matters
10. `constraints.pcf` (PCF) and pin mapping
11. Example software (`main.c`) — full example
12. Build, simulate, synthesize & program commands (step-by-step)
13. Common errors and fixes
14. Appendix: Makefile & yosys script snippets

---

## 1. Required files

Place these files in your project directory:

- `soc.v` — Top-level SoC (modified; full file included below)
- `timer_ip.v` — Timer IP (you already have this)
- `processor.v` — RISC-V core
- `memory.v` — On-chip RAM
- `clockworks.v` — Clock/reset helper
- `corescore_emitter_uart.v` — UART module used by SoC
- `link.ld` — Linker script (provided below)
- `constraints.pcf` or `top.pcf` — Pin assignments
- `main.c` — Example firmware
- `Makefile` (optional) — build helper (snippet included)
- Simulation testbench files (optional) — for iverilog or Verilator

---

## 2. Quick overview (what and why)

- The CPU accesses peripherals using **memory-mapped IO**. The timer is exposed via a fixed base address.
- `soc.v` must:
  - Decode CPU addresses and select timer when appropriate.
  - Present `wr_en` and `rd_en` signals to the timer.
  - Provide `wdata` and read back `rdata` to the CPU on reads.
  - Optionally use `timeout_o` as a direct hardware signal (e.g., toggle LED).
- The `link.ld` places program and data into on-chip RAM so the CPU can execute code.

---

## 3. Full modified `soc.v` (complete listing)

> This is a self-contained `SOC` module adapted from your earlier file with *all* wire declarations, address decoding, timer instantiation, and LED logic included. Use this as your top-level SoC.

```verilog
// soc.v - Top-level SoC including timer integration
`timescale 1ns / 1ps

module SOC (
    input        CLK,    // board/system clock
    input        RESET,  // board reset (active high push button)
    output reg [4:0] LEDS, // LED outputs
    input        RXD,    // UART RX (unused in this example)
    output       TXD     // UART TX
);

`ifdef BENCH
reg clk;
wire resetn;
`else
wire clk;
wire resetn;
`endif

// -----------------------------
// CPU <-> Memory interface (word-addressed externally)
// -----------------------------
wire [31:0] mem_addr;   // byte address from CPU
wire [31:0] mem_rdata;  // data returned to CPU
wire        mem_rstrb;  // read strobe (CPU read)
wire [31:0] mem_wdata;  // CPU write data
wire [3:0]  mem_wmask;  // byte write mask (per byte lanes)

// -----------------------------
// CPU instantiation
// -----------------------------
Processor CPU(
   .clk(clk),
   .resetn(resetn),
   .mem_addr(mem_addr),
   .mem_rdata(mem_rdata),
   .mem_rstrb(mem_rstrb),
   .mem_wdata(mem_wdata),
   .mem_wmask(mem_wmask)
);

// -----------------------------
// Memory mapping helpers
// mem_wordaddr is the CPU address >> 2 (word address)
// isIO indicates access to IO region (mem_addr[22] == 1)
// isRAM indicates RAM access
// -----------------------------
wire [29:0] mem_wordaddr = mem_addr[31:2];
wire isIO  = mem_addr[22];
wire isRAM = !isIO;
wire mem_wstrb = |mem_wmask; // any byte lane asserted => write

// -----------------------------
// On-chip RAM instantiation
// -----------------------------
wire [31:0] RAM_rdata;

Memory RAM(
    .clk(clk),
    .mem_addr(mem_addr),
    .mem_rdata(RAM_rdata),
    .mem_rstrb(isRAM & mem_rstrb),
    .mem_wdata(mem_wdata),
    .mem_wmask({4{isRAM}} & mem_wmask)
);

// -----------------------------
// UART definitions (existing)
// -----------------------------
localparam IO_LEDS_bit      = 0;  // Not used for timer, kept for completeness
localparam IO_UART_DAT_bit  = 1;  // Write data to UART
localparam IO_UART_CNTL_bit = 2;  // Read-only UART status bit

wire uart_valid = isIO & mem_wstrb & mem_wordaddr[IO_UART_DAT_bit];
wire uart_ready;

corescore_emitter_uart #(
    .clk_freq_hz(12*1000000),
    .baud_rate(9600)
) UART (
    .i_clk(clk),
    .i_rst(!resetn),
    .i_data(mem_wdata[7:0]),
    .i_valid(uart_valid),
    .o_ready(uart_ready),
    .o_uart_tx(TXD)
);

// -----------------------------
// TIMER definitions and address decode
// Base address chosen: 0x00400040 (word addr = 0x00100010)
// Registers cover 4 word addresses: 0x00100010..0x00100013
// -----------------------------
localparam TIMER_BASE_WADDR = 30'h00100010; // 0x00400040 >> 2

// Timer select: true when mem access is IO and within the timer window
wire timer_sel = isIO &&
                 (mem_wordaddr >= TIMER_BASE_WADDR) &&
                 (mem_wordaddr <= (TIMER_BASE_WADDR + 3));

// Timer read / write strobes
wire timer_wr_en = timer_sel && mem_wstrb;  // write when any byte lane asserted
wire timer_rd_en = timer_sel && mem_rstrb;  // read when CPU read strobe

// Register address inside timer (2 LSBs of word address)
wire [1:0] timer_addr = timer_sel ? mem_wordaddr[1:0] : 2'b00;

// Timer wires for instantiation
wire [31:0] timer_rdata;
wire        timer_timeout;

// -----------------------------
// Timer instantiation
// -----------------------------
timer_ip TIMER (
    .clk      (clk),
    .resetn   (resetn),
    .sel      (timer_sel),
    .wr_en    (timer_wr_en),
    .rd_en    (timer_rd_en),
    .addr     (timer_addr),
    .wdata    (mem_wdata),
    .rdata    (timer_rdata),
    .timeout_o(timer_timeout)
);

// -----------------------------
// IO read data multiplexer
// Combine all IO reads here. If an IO peripheral is selected, its data must appear on mem_rdata.
// The CPU reads mem_rdata after mem_rstrb = 1 for IO accesses.
// -----------------------------
wire [31:0] IO_rdata =
    timer_sel ? timer_rdata :
    mem_wordaddr[IO_UART_CNTL_bit] ? {22'b0, !uart_ready, 9'b0} :
    32'b0;

assign mem_rdata = isRAM ? RAM_rdata : IO_rdata;

// -----------------------------
// Optional: Use timer_timeout to toggle an LED (hardware-demonstration)
// Toggling happens on rising edge of timeout.
// -----------------------------
reg timeout_d;

always @(posedge clk) begin
    if (!resetn) begin
        LEDS <= 5'b00000;
        timeout_d <= 1'b0;
    end else begin
        timeout_d <= timer_timeout;
        if (timer_timeout && !timeout_d) begin
            LEDS[0] <= ~LEDS[0];
        end
    end
end

// -----------------------------
// Clock and reset glue (Clockworks)
`ifndef BENCH
Clockworks CW(
    .CLK(CLK),
    .RESET(RESET),
    .clk(clk),
    .resetn(resetn)
);
`endif

// -----------------------------
// Testbench support and dump (if BENCH defined)
`ifdef BENCH
initial begin
    $dumpfile("soc.vcd");
    $dumpvars(0, SOC);
end
`endif

`ifdef BENCH
// Reset generation and clock for testbench
reg resetn_reg;
assign resetn = resetn_reg;
initial clk = 0;
always #5 clk = ~clk;
initial begin
    resetn_reg = 0;
    #20;
    resetn_reg = 1;
end
`endif

endmodule
```

---

## 4. Where and why each wire/statement is added (detailed explanation)

Below we go line-by-line for the **critical additions** (the timer-related parts). Read these slowly — the "why" is as important as the "what".

### a) `mem_wordaddr`, `isIO`, `isRAM`, `mem_wstrb`
```verilog
wire [29:0] mem_wordaddr = mem_addr[31:2];
wire isIO  = mem_addr[22];
wire isRAM = !isIO;
wire mem_wstrb = |mem_wmask;
```
**Why:**  
- `mem_wordaddr` converts CPU byte address into a word index (the peripheral uses the word index to address registers).  
- `isIO` is the SoC convention — bit 22 high means this is an IO access (not RAM).  
- `mem_wstrb` is true when any byte-lane of `mem_wmask` is enabled (a write).

### b) Timer base and select
```verilog
localparam TIMER_BASE_WADDR = 30'h00100010;
wire timer_sel = isIO &&
                 (mem_wordaddr >= TIMER_BASE_WADDR) &&
                 (mem_wordaddr <= (TIMER_BASE_WADDR + 3));
```
**Why:**  
This pins a contiguous 4-word window to the timer registers. `timer_sel` must only be true for addresses belonging to the timer.

### c) Read/write enables & addr decode
```verilog
wire timer_wr_en = timer_sel && mem_wstrb;
wire timer_rd_en = timer_sel && mem_rstrb;
wire [1:0] timer_addr = timer_sel ? mem_wordaddr[1:0] : 2'b00;
```
**Why:**  
- Distinguish read/write cycles to send to the timer.  
- Extract low 2 bits of word address to pick CTRL/LOAD/VALUE/STATUS inside the timer.

### d) Timer instantiation
```verilog
timer_ip TIMER (
    .clk      (clk),
    .resetn   (resetn),
    .sel      (timer_sel),
    .wr_en    (timer_wr_en),
    .rd_en    (timer_rd_en),
    .addr     (timer_addr),
    .wdata    (mem_wdata),
    .rdata    (timer_rdata),
    .timeout_o(timer_timeout)
);
```
**Why:**  
This connects the SoC bus to the peripheral. The `timeout_o` output gives an immediate hardware observable event.

### e) IO readback mux
```verilog
wire [31:0] IO_rdata =
    timer_sel ? timer_rdata :
    mem_wordaddr[IO_UART_CNTL_bit] ? {22'b0, !uart_ready, 9'b0} :
    32'b0;

assign mem_rdata = isRAM ? RAM_rdata : IO_rdata;
```
**Why:**  
When CPU performs a read in IO space, it expects the selected peripheral's data on `mem_rdata`. This mux ensures the correct peripheral contributes to the CPU read data bus.

### f) LED toggling logic
```verilog
reg timeout_d;
always @(posedge clk) begin
    if (!resetn) begin
        LEDS <= 5'b00000;
        timeout_d <= 1'b0;
    end else begin
        timeout_d <= timer_timeout;
        if (timer_timeout && !timeout_d) begin
            LEDS[0] <= ~LEDS[0];
        end
    end
end
```
**Why:**  
Proves the timer is functioning by toggling an LED on a rising edge of `timeout_o`, without requiring CPU intervention.

---

## 5. Timer instantiation: exact placement advice

**Where to put the instantiation in `soc.v`:**
- After RAM instantiation and after other IO (like UART) is declared.
- Before the IO read multiplexing logic and before `assign mem_rdata = ...`.
- This ordering ensures `timer_rdata` is available when building `IO_rdata`.

**Why this placement matters:**
- If you put the timer instantiation after `mem_rdata` logic, you might accidentally use an uninitialized wire or create a compile-time error due to missing symbol.
- Keeping all peripheral instantiations together makes debugging and verification much easier.

---

## 6. IO readback mux and mem_rdata logic (why required)

- The CPU will ignore `timer_rdata` unless `IO_rdata` places it onto `mem_rdata`.
- If you forget to include `timer_sel ? timer_rdata : ...`, CPU reads to the timer's address will return garbage (often 0).
- The `isRAM ? RAM_rdata : IO_rdata` final assignment ensures RAM accesses return RAM, while IO accesses return peripheral data.

---

## 7. LED toggling logic (how it verifies timer)

- Hardware-driven toggling of LED on `timeout_o` rising edge demonstrates timer expiry *without software*. This is the simplest hardware validation.
- If LED toggles with the expected period after you program the FPGA and run the firmware that enables the timer, the timer is working.

---

## 8. `timer_ip.v` quick summary (what it expects/exports)

- Inputs:
  - `clk`, `resetn`
  - `sel`, `wr_en`, `rd_en`, `addr[1:0]`
  - `wdata[31:0]`
- Outputs:
  - `rdata[31:0]` — registered readback
  - `timeout_o` — hardware timeout output

Registers inside:
- `CTRL` (R/W): [0]=EN, [1]=MODE, [2]=PRESC_EN, [15:8]=PRESC_DIV
- `LOAD` (R/W)
- `VALUE` (R)
- `STATUS` (R, W1C at bit 0)

Behavior:
- When EN=0, VALUE is preloaded with LOAD and timeout cleared.
- When EN=1, counts down using prescaler if enabled. On expiry, sets STATUS[0] and either reloads (periodic) or zeroes (one-shot).

---

## 9. `link.ld` (full file) and why it matters

`link.ld`:
```ld
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 6K
}

SECTIONS
{
  .text : {
    *(.text*)
    *(.rodata*)
  } > RAM

  .data : {
    *(.data*)
  } > RAM

  .bss : {
    *(.bss*)
    *(COMMON)
  } > RAM
}
```

**Why:**  
This tells the linker to place code and data starting at `0x00000000` (the RAM origin used by `Memory` module). Without a correct linker script the binary won't run because vector/entry addresses will be incorrect.

---

## 10. `constraints.pcf` (PCF)

Minimal PCF:
```
# Minimal test PCF for HX8K-CB132
set_io LEDS[0] A5
```

**Why:**  
Binds the top-level `LEDS[0]` signal to a physical FPGA pin (A5 here). Replace `A5` with the correct pin for your board.

---

## 11. Example software (`main.c`) — full example

```c
// main.c - Example firmware to set up timer and clear status
#include <stdint.h>

#define TIMER_BASE   0x00400040U
#define TIMER_CTRL   (*(volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIMER_LOAD   (*(volatile uint32_t *)(TIMER_BASE + 0x04))
#define TIMER_VALUE  (*(volatile uint32_t *)(TIMER_BASE + 0x08))
#define TIMER_STAT   (*(volatile uint32_t *)(TIMER_BASE + 0x0C))

void _start(void) {
    // Load value for ~1 second (adjust for your clock rate)
    // If your system clock is 12 MHz:
    TIMER_LOAD = 12000000U;

    // CTRL bits:
    // [0] EN = 1
    // [1] MODE = 1 (periodic)
    // [2] PRESC_EN = 0 (disabled)
    TIMER_CTRL = (1 << 0) | (1 << 1);

    // main loop (we clear status in software as well)
    while (1) {
        if (TIMER_STAT & 1U) {
            // Clear W1C
            TIMER_STAT = 1U;
        }
    }
}
```

**Notes:**
- Adjust `TIMER_LOAD` if your clock freq differs.
- `_start` is the entry symbol expected by `link.ld`. If your toolchain uses `main`, adapt accordingly and ensure the runtime is set up (this example avoids libc).

---

## 12. Build, simulate, synthesize & program commands

Below are example commands. Adjust tool names and paths to your environment.

### A. Cross-compile firmware (RISC-V toolchain)
```bash
# Assuming riscv32-unknown-elf toolchain in PATH
riscv32-unknown-elf-gcc -march=rv32im -mabi=ilp32 -Os -nostdlib -T link.ld main.c -o firmware.elf
riscv32-unknown-elf-objdump -D firmware.elf > firmware.dis
riscv32-unknown-elf-objcopy -O binary firmware.elf firmware.bin
```

If you need a memory initialization file (`mem_init.hex`) for Verilog memory:
```bash
riscv32-unknown-elf-objcopy -O verilog firmware.elf firmware.mem
# Or create a simple hex with:
xxd -p -c 4 firmware.bin | awk '{print "32'h"$1","}' > firmware_init.vh
```

### B. Simulate with Icarus Verilog
```bash
# example invocation - include all RTL and a testbench file 'tb_soc.v'
iverilog -g2012 -o sim.vvp soc.v timer_ip.v memory.v processor.v clockworks.v corescore_emitter_uart.v tb_soc.v
vvp sim.vvp
# Use $dumpfile/$dumpvars in testbench to produce VCD for GTKWave
```

### C. Synthesize, place & route for iCE40 (icestorm + nextpnr)
Create a simple `build.sh` or run:

```bash
# 1. Synthesis with Yosys
yosys -p "read_verilog *.v; synth_ice40 -top SOC -json build/soc.json"

# 2. Place and route with nextpnr-ice40
nextpnr-ice40 --hx8k --package cb132 --json build/soc.json --pcf constraints.pcf --asc build/soc.asc --pnr-threads 4

# 3. Create bitstream
icepack build/soc.asc build/soc.bin

# 4. Program FPGA (requires iceprog)
iceprog build/soc.bin
```

**Note:** Replace `--hx8k --package cb132` with your device and package (HX8K-CB132 used earlier).

### D. Quick FPGA debug with GDB/qemu (optional)
If you have a soft debug adapter, you can load ELF into RAM using a JTAG loader or memory init.

---

## 13. Common errors and fixes

### Error: `Undefined symbol: timer_rdata` or similar compile error
**Cause:** Timer instantiation or wire declaration missing or misspelled.
**Fix:** Ensure `wire [31:0] timer_rdata;` and `wire timer_timeout;` are declared before instantiation, and module ports match names/types.

### Error: CPU reads zeros from timer registers
**Cause:** IO read mux not returning `timer_rdata`.
**Fix:** Confirm `IO_rdata` includes `timer_sel ? timer_rdata : ...` and `assign mem_rdata = isRAM ? RAM_rdata : IO_rdata;`.

### Symptom: LED never toggles
**Cause possibilities:**
- Timer never enabled in software (CTRL.EN == 0)
- Wrong base address used in software
- `timer_sel` decode mismatch (e.g., using byte address vs word address)
**Fixes:**
- Verify the base address in `main.c` is `0x00400040`
- In simulation/prints, check `mem_wordaddr` and `mem_addr` values
- Ensure software writes `TIMER_CTRL` with EN bit set

### Symptom: VALUE stuck at LOAD
**Cause:** EN=0 or prescaler issues
**Fixes:**
- Set CTRL.EN = 1 in software
- Verify prescaler fields and presc_en are set as expected

### Symptom: STATUS stays high
**Cause:** STATUS is write-1-to-clear and never cleared in software/hardware
**Fix:** Write `1` to the STATUS register (address +0x0C) to clear. For example: `TIMER_STAT = 1;`

### Error: Synthesis fails complaining about unconnected pins or top-level ports
**Cause:** Your top-level `SOC` ports don't match the expected top-level entity in your build scripts or constraints.
**Fix:** Ensure the `SOC` module ports (`CLK`, `RESET`, `LEDS`, `RXD`, `TXD`) match the signals used in your constraints/board wrapper.

### Error: `mem_rdata` conflicting driver (multiple drivers)
**Cause:** Two sources driving `mem_rdata` (e.g., both RAM and IO).
**Fix:** Use a single assignment that selects between RAM and IO (`assign mem_rdata = isRAM ? RAM_rdata : IO_rdata;`) and ensure RAM isn't driving `mem_rdata` elsewhere as a reg.

---

## 14. Appendix: Makefile & Yosys script snippets

### Minimal `Makefile` targets
```makefile
VERILOG := soc.v timer_ip.v memory.v processor.v clockworks.v corescore_emitter_uart.v

all: synth

firmware:
    riscv32-unknown-elf-gcc -march=rv32im -mabi=ilp32 -Os -nostdlib -T link.ld main.c -o firmware.elf
    riscv32-unknown-elf-objcopy -O binary firmware.elf firmware.bin

sim:
    iverilog -g2012 -o sim.vvp $(VERILOG) tb_soc.v
    vvp sim.vvp

synth:
    yosys -p "read_verilog $(VERILOG); synth_ice40 -top SOC -json build/soc.json"
    nextpnr-ice40 --hx8k --package cb132 --json build/soc.json --pcf constraints.pcf --asc build/soc.asc
    icepack build/soc.asc build/soc.bin

program: synth
    iceprog build/soc.bin
```

### Yosys one-liner (already shown above)
```bash
yosys -p "read_verilog *.v; synth_ice40 -top SOC -json build/soc.json"
```

---

## Final notes and recommended workflow (for beginners)

1. **Start with simulation.** Write a small TB that clocks the design and runs small memory writes from a simulated CPU (or emulate CPU writes) to test timer behavior. This avoids wasting FPGA cycles.
2. **Build and run the firmware in simulation** (create a mem_init file to pre-load RAM with firmware).
3. **Synthesize and program** only after simulation works.
4. **Verify on FPGA** with the `LEDS[0]` toggling and optional UART prints.
5. **Iterate**: if something fails, compare simulation waveforms and inspect the address lines to ensure the CPU is hitting the expected addresses.

---

## Download
This file is saved as `integration_detailed.md`. Download it from the environment:

**[Download the integration_detailed.md file](/mnt/data/integration_detailed.md)**

---

If you want, I can also:
- Produce `integration_detailed.pdf`
- Create a simulation testbench for Icarus Verilog that drives writes to the timer registers and shows VALUE decrement in the waveform
- Provide a step-by-step screencast script you can record

Happy to help further — tell me which of the follow-ups you'd like! 😊
