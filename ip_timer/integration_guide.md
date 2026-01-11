#  Integration Guide  
## Timer IP Integration using **riscv.v** (VSDSquadron FPGA)

This document is a **clean, cumulative, integration guide** that matches **exactly how you are building and simulating**:

- **Single RTL file**: `riscv.v` (contains Processor + Memory + SoC glue)
- **Peripheral RTL**: `timer_ip.v`
- **Exact toolchain & commands you used**
- **Why each step exists**, not just what to type

This guide assumes **no prior SoC integration experience**.

---

## 1. Required Files 

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
We only *extend* `riscv.v` by **adding the timer wires, decode, and instantiation**

This avoids mismatch bugs and simplifies synthesis.

---

## 3. Timer Addressing 

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

### 4.1 Wire Declarations 

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

### 4.2 Address Decode Logic 

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

### 4.5 Timer Instantiation 

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

### 4.6 IO Readback Mux 

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

### 4.7 LED Toggle on Timeout 

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

### 5.1 `link.ld` 

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

### 5.2 Timer Test Program 

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




