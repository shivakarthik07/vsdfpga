# GPIO Control IP – RISC-V SoC Integration

## Overview
This project implements and validates a **GPIO Control IP (Direction + Data)** integrated into a simple RISC-V SoC.  
The goal is to demonstrate **memory-mapped peripheral access**, **correct read/write behavior**, and **simulation-based validation** using C firmware.

---

## System Architecture
- **CPU**: RV32I RISC-V core
- **Memory**: On-chip BRAM loaded using `firmware.hex`
- **Peripherals**:
  - UART (for print/debug)
  - GPIO Control IP
  - LEDs (mapped to GPIO output)

The CPU communicates with peripherals using **memory-mapped IO**.

---

## Address Map
All peripherals live in the IO region:
```
IO Base Address = 0x0040_0000  (mem_addr[22] = 1)
```

### GPIO Register Map
| Offset | Register     | Address       | Description |
|------:|--------------|---------------|-------------|
| 0x00  | GPIO_DATA    | 0x00400020    | Output data register |
| 0x04  | GPIO_DIR     | 0x00400024    | Direction register (1=output, 0=input) |
| 0x08  | GPIO_READ    | 0x00400028    | Pin state readback |

Address decoding in RTL is done using **word address comparison**:
```verilog
wire gpio_sel = isIO &&
               (mem_wordaddr >= 30'h00100008) &&
               (mem_wordaddr <= 30'h0010000A);
```

---

## GPIO Control IP Design

### Internal Registers
- `gpio_data` : stores last written output value
- `gpio_dir`  : controls direction per bit
- `gpio_out`  : driven output pins
- `gpio_in`   : external input pins (constant in simulation)

### Write Behavior
- Writing `GPIO_DATA` updates output value
- Writing `GPIO_DIR` configures pin direction

```verilog
if (sel && wr_en) begin
    case (addr)
        2'b00: gpio_data <= wdata;
        2'b01: gpio_dir  <= wdata;
    endcase
end
```

---

## Readback Behavior (Key Explanation)

### 1. Reading GPIO_DATA
Returns **last written value**, regardless of direction:
```verilog
2'b00: rdata <= gpio_data;
```

### 2. Reading GPIO_DIR
Returns direction configuration:
```verilog
2'b01: rdata <= gpio_dir;
```

### 3. Reading GPIO_READ (Pin State)
Returns **actual pin state**:
- Output pins → driven value
- Input pins → external pin value

```verilog
2'b10: rdata <= (gpio_out | (gpio_in & ~gpio_dir));
```

#### Example:
```
gpio_out = 00001010
gpio_dir = 00001111
gpio_in  = 10101010

READ = gpio_out | (gpio_in & ~gpio_dir)
     = 10101010 (0xAA)
```

✔ This matches real hardware GPIO behavior.

---

## LED Behavior
- LEDs are connected to `gpio_out[4:0]`
- LEDs reflect **only output pins**
- Input pins do not drive LEDs

```verilog
always @(posedge clk)
    LEDS <= gpio_out[4:0];
```

---

## SoC Integration Changes

### What Was Modified

* Added GPIO address decode in IO region
* Added GPIO read/write strobes from CPU bus
* Added GPIO readback into IO data mux
* Disabled FPGA clocks for simulation
* Added internal clock/reset for BENCH mode

### IO Read Mux
```verilog
assign mem_rdata = isRAM ? RAM_rdata :
    (gpio_sel ? gpio_rdata :
     mem_wordaddr[IO_UART_CNTL_bit] ? {22'b0, !uart_ready, 9'b0} : 32'b0);
```
---

## Firmware (C Code) Explanation

### Peripheral Access Model
Firmware accesses peripherals using **full 32-bit memory-mapped addresses**.

```c
#define GPIO_BASE 0x00400020
#define GPIO_DATA (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR  (*(volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_READ (*(volatile unsigned int *)(GPIO_BASE + 0x08))
```

### Test Flow
1. Configure GPIO direction
2. Write output pattern
3. Read back GPIO_READ
4. Print result via UART
5. Exit using `ecall`

---

## Simulation Output Explanation
- `GPIO_DATA` = last written value (e.g. `0x0A`)
- `GPIO_DIR`  = configured directions
- `GPIO_READ` = merged pin state (`0xAA`)
- UART prints correct value
- Simulation ends cleanly

✔ All functional requirements are validated.

---

## Challenges Faced & Fixes

### 1. Incorrect Readback (X values)
**Fix**: Used synchronous read logic to hold stable values

### 2. Wrong Address Decode
**Fix**: Used word-aligned decoding (`mem_addr[31:2]`)

### 3. GPIO Read vs Write Confusion
**Fix**: Separated DATA and READ registers clearly

### 4. stdint.h Compilation Errors
**Fix**: Switched to project-specific `io.h`

```c
#include "io.h"
```

---

## Build & Simulation Flow
```bash
make clean
make gpio_ctrl_test.bram.elf
make gpio_ctrl_test.bram.hex
iverilog -g2012 -DBENCH -o sim.out ...
vvp sim.out
gtkwave soc.vcd
```

---

## Conclusion
This project demonstrates:
- Clean GPIO IP design
- Correct SoC integration
- Realistic read/write semantics
- Full firmware-to-RTL validation

✅ Ready for academic and professional review.
