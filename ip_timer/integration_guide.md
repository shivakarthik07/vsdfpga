# Timer IP – Integration Guide (VSDSquadron SoC)

This guide explains how to integrate the **Timer IP** into a **VSDSquadron RISC-V SoC** design. 

---

## Required RTL Files

Copy the following RTL file into your SoC RTL project:

<details>
<summary> Timer IP (click to expand) </summary>

```verilog
module timer_ip (
    input  wire        clk,
    input  wire        resetn,

    // Bus interface
    input  wire        sel,
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [1:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    // Hardware output
    output wire        timeout_o
);
    ...
endmodule
```

</details>

---

## Where to Instantiate the IP

Instantiate the Timer IP inside the **SoC top-level module** where other **memory-mapped peripherals** (GPIO, UART, SPI) are connected.

The Timer IP must be instantiated in the **IO page section** of the SoC.

---

### Timer IP Instantiation Template

```verilog
wire [31:0] timer_rdata;
wire        timer_timeout;

timer_ip TIMER (
    .clk      (clk),
    .resetn   (resetn),

    // Bus interface
    .sel      (timer_sel),
    .wr_en    (timer_wr_en),
    .rd_en    (timer_rd_en),
    .addr     (timer_addr),
    .wdata    (mem_wdata),
    .rdata    (timer_rdata),

    // Hardware output
    .timeout_o(timer_timeout)
);
```

---

## Defining New Timer Signals in SoC Module

```verilog
wire        timer_sel;
wire        timer_wr_en;
wire        timer_rd_en;
wire [1:0]  timer_addr;
wire [31:0] timer_rdata;
wire        timer_timeout;
```

---

## Address Decoding Expectations

### IO Page Selection

```verilog
isIO = mem_addr[22];
```

### Timer Select Logic

```verilog
localparam TIMER_BASE_WADDR = 30'h00100010; // 0x00400040 >> 2

assign timer_sel =
    isIO &&
    (mem_wordaddr >= TIMER_BASE_WADDR) &&
    (mem_wordaddr <= TIMER_BASE_WADDR + 3);
```

### Read / Write Enables

```verilog
assign timer_wr_en = timer_sel && (|mem_wmask);
assign timer_rd_en = timer_sel && mem_rstrb;
```

### Register Offset Selection

```verilog
assign timer_addr = mem_wordaddr[1:0];
```

---

## Software Base Address

```text
TIMER_BASE = 0x00400040
```

---

## IO Read Data Mux Update

```verilog
wire [31:0] IO_rdata =
    timer_sel ? timer_rdata :
    mem_wordaddr[IO_UART_CNTL_bit] ? {22'b0, !uart_ready, 9'b0} :
    mem_wordaddr[IO_gpio_bit] ? gpio_rdata :
    32'b0;

assign mem_rdata = isRAM ? RAM_rdata : IO_rdata;
```

---

## Signals Exposed to SoC Top-Level

| Signal | Direction | Description |
|------|----------|-------------|
| timeout_o | output | Timer expiration pulse |
| clk | input | System clock |
| resetn | input | Active-low reset |

---

## Board-Level Connections (VSDSquadron FPGA)

### Board-Level Signal Mapping

| Timer IP Signal | SoC Signal | FPGA Pin | Board Connection | Purpose |
|---------------|-----------|---------|-----------------|---------|
| timeout_o | LEDS[0] | A5 | On-board LED0 | Visual timeout indication |
| clk | CLK | — | System clock | Timer clock |
| resetn | RESET | — | Reset button | Reset timer |

---

### Example Constraint File Entry

```pcf
set_io LEDS[0] A5
```

---

