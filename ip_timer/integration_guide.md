#  Integration Guide  
## Timer IP Integration using **riscv.v** (VSDSquadron FPGA)

This document is a **clean, cumulative, integration guide** that matches **exactly how you are building and simulating**:

- **Single RTL file**: `riscv.v` (contains Processor + Memory + SoC glue)
- **Peripheral RTL**: `timer_ip.v`
- **Exact toolchain & commands you used**
- **Why each step exists**, not just what to type

This guide assumes **no prior SoC integration experience**.

---

## 1. Required Files (Minimal & Correct)

Only the following files are required.

### RTL
- `riscv.v`  
  → Contains:
  - RISC‑V core
  - Memory
  - SoC interconnect
  - IO decode logic
- `timer_ip.v`  
  → Timer peripheral IP

### Software
- `start.S` – reset vector / entry code  
- `timer_test2.c` – test application  
- `link.ld` – linker script  

### FPGA
- `VSDSquadronFM.pcf` – pin constraints

---

## 2. Why We Use a Single `riscv.v`

VSDSquadron uses a **monolithic SoC RTL style**.

That means:
- CPU
- RAM
- IO decoding
- Top‑level ports  

are **already inside `riscv.v`**.

So:
✅ We **do not** separately compile `processor.v`, `memory.v`, etc.  
✅ We only *extend* `riscv.v` by **adding the timer wires, decode, and instantiation**

This avoids mismatch bugs and simplifies synthesis.

---

## 3. Timer Addressing (Foundation Concept)

### Chosen Base Address
```
TIMER_BASE = 0x0040_0040
```

### Why this address?
- Bit 22 = `1` → IO space
- Does not overlap UART / GPIO
- Word aligned

### Word Address Conversion
```
0x00400040 >> 2 = 0x00100010
```

Timer occupies **4 words**:

| Address | Register |
|------|------|
| +0x00 | CTRL |
| +0x04 | LOAD |
| +0x08 | VALUE |
| +0x0C | STATUS |

---

## 4. What Must Be Added Inside `riscv.v`

> All changes happen **inside the SOC module** in `riscv.v`

---

### 4.1 Wire Declarations (WHY: connect timer to SoC bus)

```verilog
wire        timer_sel;
wire        timer_wr_en;
wire        timer_rd_en;
wire [1:0]  timer_addr;

wire [31:0] timer_rdata;
wire        timer_timeout;
```

**Why each exists**

| Wire | Purpose |
|----|----|
| `timer_sel` | Select timer for its address range |
| `timer_wr_en` | CPU write → timer |
| `timer_rd_en` | CPU read ← timer |
| `timer_addr` | Select CTRL/LOAD/VALUE/STATUS |
| `timer_rdata` | Data returned to CPU |
| `timer_timeout` | Hardware timeout signal |

---

### 4.2 Address Decode Logic (MOST IMPORTANT)

```verilog
localparam TIMER_BASE_WADDR = 30'h00100010;

assign timer_sel =
    isIO &&
    (mem_wordaddr >= TIMER_BASE_WADDR) &&
    (mem_wordaddr <= TIMER_BASE_WADDR + 3);
```

**Why**
- CPU has *one* address bus
- Every peripheral must self‑select
- Prevents accidental register corruption

---

### 4.3 Read / Write Enables

```verilog
assign timer_wr_en = timer_sel && (|mem_wmask);
assign timer_rd_en = timer_sel && mem_rstrb;
```

**Why**
- `mem_wmask` indicates CPU write
- `mem_rstrb` indicates CPU read
- Timer must react only when selected

---

### 4.4 Internal Register Address

```verilog
assign timer_addr = mem_wordaddr[1:0];
```

**Why**
- `addr = 00` → CTRL
- `addr = 01` → LOAD
- `addr = 10` → VALUE
- `addr = 11` → STATUS

---

### 4.5 Timer Instantiation (Where to Place)

> Place **after IO decode**, **before mem_rdata mux**

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

**Why placement matters**
- `timer_rdata` must exist before IO mux
- Clean peripheral grouping

---

### 4.6 IO Readback Mux (CRITICAL)

```verilog
assign IO_rdata =
    timer_sel ? timer_rdata :
    uart_sel  ? uart_rdata :
    32'b0;
```

```verilog
assign mem_rdata = isRAM ? RAM_rdata : IO_rdata;
```

**Why**
- Without this → CPU reads **zero forever**
- Only one peripheral may drive `mem_rdata`

---

### 4.7 LED Toggle on Timeout (Hardware Proof)

```verilog
reg timeout_d;

always @(posedge clk) begin
    if (!resetn) begin
        LEDS <= 5'b0;
        timeout_d <= 1'b0;
    end else begin
        timeout_d <= timer_timeout;
        if (timer_timeout && !timeout_d)
            LEDS[0] <= ~LEDS[0];
    end
end
```

**Why**
- Confirms timer expiry **without software**
- Rising‑edge detection avoids double toggles

---

## 5. Software Files

### 5.1 `link.ld` (Required)

```ld
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 6K
}

SECTIONS {
  .text : { *(.text*) *(.rodata*) } > RAM
  .data : { *(.data*) } > RAM
  .bss  : { *(.bss*) *(COMMON) } > RAM
}
```

**Why**
- Matches RAM in `riscv.v`
- Without this → code runs from wrong address

---

### 5.2 Timer Test Program (`timer_test2.c`)

```c
#define TIMER_BASE  0x00400040
#define TIMER_CTRL  (*(volatile unsigned int*)(TIMER_BASE + 0x00))
#define TIMER_LOAD  (*(volatile unsigned int*)(TIMER_BASE + 0x04))
#define TIMER_STAT  (*(volatile unsigned int*)(TIMER_BASE + 0x0C))

void main() {
    TIMER_LOAD = 12000000;
    TIMER_CTRL = (1<<0) | (1<<1);   // enable + periodic

    while (1) {
        if (TIMER_STAT & 1)
            TIMER_STAT = 1;         // clear timeout
    }
}
```

---

## 6. Creating and Editing Files using `gedit`

`gedit` is a **graphical text editor** available on most Linux systems.  
It is recommended for beginners because it avoids command‑mode complexity.

---

### 6.1 Create Required Files

```bash
touch riscv.v
touch timer_ip.v
touch start.S
touch timer_test2.c
touch link.ld
touch VSDSquadronFM.pcf
```

---

### 6.2 Open Files in `gedit`

```bash
gedit riscv.v
gedit timer_ip.v
gedit start.S
gedit timer_test2.c
gedit link.ld
gedit VSDSquadronFM.pcf
```

Open multiple files together:

```bash
gedit riscv.v timer_ip.v link.ld timer_test2.c start.S VSDSquadronFM.pcf
```

---

### 6.3 Save and Exit

- Save: **Ctrl + S**
- Close window: **Ctrl + Q**

---

### 6.4 Verify Files Exist

```bash
ls -l
```

---

## 7. Simulation Commands (Copy‑Paste)

### 7.1 Compile Firmware

```bash
riscv64-unknown-elf-gcc -Os   -march=rv32i -mabi=ilp32   -ffreestanding -nostdlib   start.S timer_test2.c   -Wl,-T,link.ld   -o firmware.elf
```

---

### 7.2 Convert ELF to HEX

```bash
riscv64-unknown-elf-objcopy -O ihex firmware.elf firmware.hex
```

---

### 7.3 RTL Simulation

```bash
iverilog -g2012 -DBENCH -o sim.vvp riscv.v timer_ip.v
```

```bash
vvp sim.vvp
```

---

### 7.4 View Waveforms

```bash
gtkwave soc.vcd
```

---

## 8. FPGA Synthesis → P&R → Bitstream

### 8.1 Synthesis

```bash
yosys -p "
read_verilog riscv.v timer_ip.v
synth_ice40 -top SOC -json soc.json
"
```

---

### 8.2 Place & Route

```bash
nextpnr-ice40   --hx8k   --package cb132   --pcf VSDSquadronFM.pcf   --pcf-allow-unconstrained   --json soc.json   --asc soc.asc
```

---

### 8.3 Bitstream Generation

```bash
icepack soc.asc soc.bin
```

---

### 8.4 Program FPGA

```bash
iceprog soc.bin
```

---

## 8.5. Clean Build Artifacts

```bash
rm -f sim.vvp soc.vcd soc.json soc.asc soc.bin firmware.elf firmware.hex
```

## 9. Expected Results

| Observation | Meaning |
|----|----|
| LED0 toggles | Timer expiry works |
| VALUE decreases | Timer counting |
| STATUS[0] pulses | Correct timeout |
| No CPU hang | IO decode correct |

---

## 10. Common Errors & Fixes

### ❌ Timer reads always zero
✔ Missing IO read mux  
✔ `timer_sel` incorrect  

---

### ❌ LED never toggles
✔ CTRL.EN not set  
✔ Wrong base address  
✔ Clock/reset issue  

---

### ❌ STATUS stuck high
✔ STATUS is W1C → write `1` to clear  

---

## 11. Final Understanding (Key Takeaway)

You now understand:

- How CPU ↔ peripheral communication works
- Why **address decode is everything**
- Why readback muxes are mandatory
- How to validate hardware without software
- How firmware, linker, and RTL must align

This is **real SoC‑level design**, not a toy example.

---


