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

## Terminal Output
<img width="1920" height="982" alt="t3terminaloutput" src="https://github.com/user-attachments/assets/0d4d8c6f-172c-4f3c-837b-b013574bc4bd" />

## Write Behaviour
<img width="1029" height="447" alt="t3writeoutput" src="https://github.com/user-attachments/assets/90ae5078-ee43-4c86-90c7-9523d8057dc8" />

#### The firmware first configures GPIO direction and then writes output data
```c
GPIO_DIR  = 0x0000001F;   // Lower 5 GPIOs as outputs
GPIO_DATA = 0x0000000A;   // Write output pattern
```
#### What Happens in RTL
#### gpio_wr_en is asserted when:
-  CPU accesses ```IO space```
-  Address matches ```GPIO region```
- ``` mem_wmask ```is non-zero (store instruction)
#### Based on the decoded register offset:
-  Offset ```0x00``` → ```gpio_data``` is updated
-  Offset ```0x04``` → ```gpio_dir``` is updated
#### Simulation behaviour
```c
gpio_data becomes 0x0000000A
gpio_dir becomes 0x0000001F 
gpio_out = gpio_data & gpio_dir
```
### LEDS BEHAVIOR
#### In the SoC, LEDs are directly driven from GPIO outputs:
```c
always @(posedge clk)
    LEDS <= gpio_out[4:0];
```
#### What This Means
- LEDs reflect only output pins
- Input pins never affect LEDs
- LEDs show the physical output state
#### Simulation Observation
```c
gpio_out[4:0] = 01010
LEDS = 01010
```
#### This confirms
- GPIO write propagated correctly
- Output pins are driven as expected
- LEDs validate write functionality only

## Readback behaviour
<img width="1160" height="417" alt="t3readback" src="https://github.com/user-attachments/assets/5f4ad627-6b01-4d2a-b176-deabd0802e76" />

### GPIO READBACK Behavior (GPIO_READ)
#### Purpose of GPIO_READ
- GPIO_READ returns the actual pin state, not just the stored data.
####
- ```GPIO_DATA```   --   Stores last written output value
- ```GPIO_READ```	  --   Returns real pin state

#### RTL Read Logic
```c
rdata <= (gpio_out | (gpio_in & ~gpio_dir));
```
#### How This Works
- Output pins ```gpio_dir``` = 1 → reflect ```gpio_out```
- Input pins ```gpio_dir``` = 0 → reflect ```gpio_in```
#### Simulation Values
```c
gpio_out = 00001010
gpio_dir = 00001111
gpio_in  = 10101010
```
#### Caluculation:
```c
~gpio_dir       = 11110000
gpio_in & ~dir  = 10100000
--------------------------------
GPIO_READ       = 10101010 (0xAA)
```
#### Terminal output:
```GPIO READ = 000000AA```
#### simulation completeness
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
