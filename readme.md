# GPIO Integration and Simulation – RISC-V SoC

## Overview
This project extends a simple RV32I RISC‑V SoC by integrating a memory‑mapped GPIO peripheral, validating it through C firmware, and verifying correct behavior via simulation (GTKWave).

---

## 1. GPIO RTL Design (gpio_ip.v)

The GPIO is implemented as a single 32‑bit register with synchronous write and registered readback .

### Code:

```bash
`timescale 1ns/1ps

module gpio_ip (
    input clk,
    input resetn,
    input wr_en,
    input rd_en,
    input [31:0] wdata,
    output reg  [31:0] rdata,
    output reg  [31:0] gpio_data
);
    reg [31:0] gpio_reg;
    // Write logic (clocked)
    always @(posedge clk) begin
        if (!resetn) begin
            gpio_reg  <= 32'b0;
            gpio_data <= 32'b0;
        end else if (wr_en) begin
            gpio_reg  <= wdata;
            gpio_data <= wdata;
        end
    end
  // Read logic (registered, holds value)
always @(posedge clk) begin
    if (!resetn) begin
        rdata <= 32'b0;
    end else if (rd_en) begin
        rdata <= gpio_reg;
    end
end
endmodule
```

EXPLANATION:
- Write on posedge clk
- Registered read data
- Active‑low reset
- GPIO value is stored in an internal register, so data persists until overwritten.
- Clocked write logic ensures reliable and glitch-free updates.
- Registered read logic guarantees stable and correct readback.
- Separate read and write enables simplify address decoding and control.
- Design matches standard memory-mapped peripheral behavior used in SoCs.


## 2. SoC Integration (riscv.v)
 

### 1. GPIO Address Decode
```bash
// GPIO_ADDR = 0x00400020
// word address = 0x00400020 >> 2 = 0x00100008
wire gpio_wr_en = gpio_sel && |mem_wmask;
wire gpio_rd_en = gpio_sel && mem_rstrb;
wire gpio_sel   = isIO     && (mem_wordaddr == 30'h00100008);
```
### EXPLANATION:
- GPIO is selected only when CPU accesses 0x00400020.
- This exactly matches the C macro #define GPIO_ADDR (0x00400000 + 0x20).
- Write enable depends on mem_wmask; read enable depends on mem_rstrb.

### 2. GPIO IP Instantiation
```bash
gpio_ip GPIO (
    .clk(clk),
    .resetn(resetn),
    .wr_en(gpio_wr_en),
    .rd_en(gpio_rd_en),
    .wdata(mem_wdata),
    .rdata(gpio_rdata),
    .gpio_data(gpio_data)
);
```
### EXPLANATION:
- CPU write data (mem_wdata) feeds directly into GPIO.
- Readback data (gpio_rdata) is returned to the CPU.
- GPIO state is held internally, guaranteeing stable reads.

### 3. Readback MUX
```bash
wire [31:0] IO_rdata =
    mem_wordaddr[IO_UART_CNTL_bit] ? {22'b0, !uart_ready, 9'b0} :
    gpio_sel ? gpio_rdata :
    32'b0;

assign mem_rdata = isRAM ? RAM_rdata : IO_rdata;
```
### EXPLANATION :
- CPU sees only one data source on loads (``` mem_rdata ```).
- If address is RAM → RAM data returned.
- If address is GPIO → ```gpio_rdata ``` returned.

### 4. Simulation Clock & Reset
```bash
`ifdef BENCH
    // Reset generation
    reg resetn_reg;
    assign resetn = resetn_reg;

    // Clock generation (100 MHz equivalent)
    initial clk = 0;
    always #5 clk = ~clk;

    // Proper reset pulse
    initial begin
        resetn_reg = 0;
        #20;              // reset asserted for 2 clock cycles
        resetn_reg = 1;
    end
`endif
```
### EXPLANATION
- A deterministic clock is generated using always #5 clk = ~clk.
- Reset is asserted for a few cycles and then released.
- Ensures CPU, memory, and GPIO start in a known state.
- Makes waveform debugging reliable and repeatable.


## 3. Firmware Addressing and gpio access 

### The firmware:
```bash
#define IO_BASE   0x00400000
#define GPIO_ADDR (IO_BASE + 0x20)

volatile uint32_t *gpio = (uint32_t *)GPIO_ADDR;
```
- Writes 0xA5 to GPIO
- The firmware accesses peripherals using full 32-bit memory-mapped addresses.
- A fixed IO base address 0x00400000 is used, matching the RTL IO region.
- GPIO is accessed at address 0x00400020, derived as IO_BASE + 0x20.
- Ends simulation using ECALL


## 4. Simulation Result

### Observed signals:
- clk, resetn
- mem_addr, mem_wmask
- gpio_wr_en, gpio_rd_en
- gpio_data, gpio_rdata
-
### output flow:
- The firmware accesses peripherals using memory-mapped I/O with a fixed IO base address ``` 0x00400000 ```.
- GPIO is mapped at address ``` 0x00400020 (IO_BASE + 0x20) ```, which matches the RTL IO decode region.
- When the C code writes to this address, the CPU generates:
   ```bash
   mem_addr = 0x00400020
   mem_wdata = 0xA5
   mem_wmask ≠ 0 (write operation)
  ```
- In the SoC,``` mem_addr[22] ```identifies the access as IO, and the full word address decode selects the GPIO block.
- The GPIO IP captures the written value into an internal register on the clock edge.
- On a read access, the GPIO IP returns the stored register value through ```rdata```, ensuring stable and correct readback.
- The SoC routes this GPIO read data to``` mem_rdata```, which the CPU loads using a ```lw``` instruction.
- The firmware prints the read value via UART, confirming correct write and readback behavior.
- The simulation exits cleanly using ```ecall```, proving successful end-to-end operation.

### All behaviors matched expectations.

## 5. Challenges & Fixes

### 1. Initial GPIO Read Returned Undefined (X) Values
### solution:
#### 
- The GPIO read path was made synchronous, registering rdata on the clock when rd_en is asserted.
- This guarantees stable and valid readback during CPU load operations.

### 2. Incorrect GPIO Address Decoding
### solution:
#### 
- GPIO selection was fixed by decoding the full word address
```bash
wire gpio_sel = isIO && (mem_wordaddr == 30'h00100008);
```
### 3. Write Enable (wr_en) Never Asserted
#### GPIO write enable was never going high even though firmware executed store instructions.
### solution:
#### 
- wr_en was correctly derived from the write mask
```bash
wire gpio_wr_en = gpio_sel && |mem_wmask;
```  
### 4. Simulation Not Terminating Automatically
### solution:
####
- An ecall instruction was added in firmware, and the CPU exits simulation on SYSTEM instruction when compiled with BENCH.

### 5. Makefile Build Failures

### 1. Multiple Library Objects Caused Build Errors
### solution:
- used minimal required objects
```bash
LIBOBJECTS = putchar.o wait.o print.o
```
### 2. Missing Standard C Headers in Bare-Metal Toolchain 
###
- Bare-metal RISC-V toolchain does not provide full standard C headers.
- Using <stdint.h> caused compilation failures.
### solution:
#### Use project-specific io.h
  ```bash
  #define IO_BASE       0x400000
  #define IO_IN(port)       *(volatile unsigned int*)(IO_BASE + port)
  #define IO_OUT(port,val)  *(volatile unsigned int*)(IO_BASE + port) = (val)
  ```
  
## 6. Conclusion

All mandatory validation steps were completed:
- GPIO write & readback
- UART verification
- Simulation waveform proof




