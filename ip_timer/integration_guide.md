# Timer IP – Integration & Usage Guide (VSDSquadron SoC)

### This document explains **how to integrate, use, and validate the `timer_ip`** inside the VSDSquadron RISC‑V SoC,it is written for **beginners**, but structured to match **industry-grade IP documentation**.

---

##  Integration Guide (Very Important)

### Goal
**Plug `timer_ip` into the existing VSDSquadron SoC and make it usable from software.**

---

##  Required RTL Files

The following RTL files are **mandatory**:

| File | Purpose |
|----|----|
| `timer_ip.v` | Timer IP core |
| `riscv.v` / `soc.v` | SoC top-level |
| `clockworks.v` | Clock & reset conditioning |
| `emitter_uart.v` | UART for debug |
| `memory.v` | Instruction/data memory |

📌 **Rule:**  
`timer_ip.v` must be added to **Yosys synthesis inputs**.

---

##  Where to Instantiate the IP

### Location
Instantiate `timer_ip` **inside the SoC module**, alongside other memory‑mapped peripherals.

**Correct placement:**
```verilog
module SOC ( ... );

// CPU
Processor CPU ( ... );

// RAM
Memory RAM ( ... );

// Timer IP
timer_ip TIMER ( ... );

endmodule
```

---

##  Address Decoding Expectations

The Timer IP is **memory-mapped**.

### Base Address
```c
#define TIMER_BASE 0x00400040
```

### Address Decode Logic (RTL)
```verilog
wire isIO = mem_addr[22];

wire timer_sel =
    isIO &&
    (mem_wordaddr >= 30'h00100010) &&
    (mem_wordaddr <= 30'h00100013);
```

### Register Address Mapping

| Offset | Register |
|----|----|
| `+0x00` | CTRL |
| `+0x04` | LOAD |
| `+0x08` | VALUE |
| `+0x0C` | STATUS |

📌 **Important:**  
Address decoding must be **word-aligned** (`mem_addr[31:2]`).

---

##  Signals Exposed to Top-Level

### Timer IP Ports

| Signal | Direction | Description |
|----|----|----|
| `clk` | Input | System clock |
| `resetn` | Input | Active‑low reset |
| `sel` | Input | Peripheral select |
| `wr_en` | Input | Write enable |
| `rd_en` | Input | Read enable |
| `addr[1:0]` | Input | Register select |
| `wdata[31:0]` | Input | Write data |
| `rdata[31:0]` | Output | Read data |
| `timeout_o` | Output | Timeout event (level) |

---

##  Top-Level Wiring Example

```verilog
wire [31:0] timer_rdata;
wire        timer_timeout;

timer_ip TIMER (
    .clk(clk),
    .resetn(resetn),
    .sel(timer_sel),
    .wr_en(timer_wr_en),
    .rd_en(timer_rd_en),
    .addr(timer_addr),
    .wdata(mem_wdata),
    .rdata(timer_rdata),
    .timeout_o(timer_timeout)
);
```

---

##  Board-Level Usage (VSDSquadron FPGA)

###  FPGA Signals Used

| Signal | Board Connection |
|----|----|
| `clk` | On-board system clock |
| `resetn` | Reset button |
| `timeout_o` | Internal (mapped to LED) |
| `TXD` | USB‑UART TX |
| `RXD` | USB‑UART RX |

---

##  LED Connection Example

```verilog
always @(posedge clk) begin
    if (!resetn)
        LEDS[0] <= 1'b0;
    else if (timer_timeout)
        LEDS[0] <= ~LEDS[0];
end
```

**Result:**  
LED0 toggles on every timer expiration.

---

##  Constraint File (PCF)

```pcf
set_io LEDS[0] <pin_number>
set_io RESET   <pin_number>
set_io TXD     <pin_number>
set_io RXD     <pin_number>
```

📌 Replace `<pin_number>` with VSDSquadron pinout values.

---

##  Example Software (Mandatory)

### Example: One‑Shot Timer (Bare‑Metal C)

```c
#include "io.h"

#define TIMER_BASE   0x00400040
#define TIMER_CTRL   (*(volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIMER_LOAD   (*(volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIMER_STAT   (*(volatile unsigned int *)(TIMER_BASE + 0x0C))

int main(void)
{
    TIMER_CTRL = 0x0;        // Disable
    TIMER_LOAD = 500000;    // Load count
    TIMER_CTRL = 0x1;        // Enable (one-shot)

    while ((TIMER_STAT & 1) == 0);  // Poll timeout

    asm volatile("ecall");
}
```

---

##  Validation & Expected Output

###  Expected Behavior

| Observation | Meaning |
|----|----|
| LED toggles | Timer expired |
| STATUS[0] = 1 | Timeout event |
| VALUE counts down | Timer active |

---

###  UART / Simulation Output

- Optional UART print: `"Timer expired"`
- Simulation ends on `ecall`
- Waveform shows:
  - `value_reg → 0`
  - `timeout_o → 1`

---

##  Common Failure Symptoms

| Symptom | Cause |
|----|----|
| Timer never expires | CTRL.EN not set |
| VALUE stuck | LOAD not written |
| LED never toggles | timeout_o not connected |
| Immediate timeout | LOAD = 0 |

---

## Summary

This Timer IP is:
- **Drop‑in compatible** with VSDSquadron SoC
- Controlled entirely by **memory‑mapped registers**
- Suitable for **LED timing, delays, periodic events, and system tick generation**

This guide enables **plug‑and‑play usage** without internal knowledge of the SoC internals.

