# Hardware Timer IP 

- In commercial SoC and FPGA designs, a hardware timer is a foundational infrastructure IP , it is essential for deterministic behavior, functional safety, power management, and long-term maintainability of complex systems.
  
##  Purposes 

- **Deterministic Time Reference**  
  
- **Hardware-Enforced Time Boundaries**  
   
- **Precise Periodic Event Generation**  
  
- **Low-Power and Idle-State Timekeeping**  
  
- **Offloading Timing Responsibility from Software**  
  

---

##  Use Cases 

- **Peripheral Communication Timeouts**  
 
- **Operating System Scheduler Tick**  
  
- **Periodic Sampling and Control Systems**  
  
- **Safety and Supervision Logic**  
  
- **Non-Blocking Delay and Pacing**  
 

---

##  Why the Timer Is Used 

-   Hardware timers provide predictable timing unaffected by software variability.

-   Prevents deadlocks and uncontrolled execution paths in failure scenarios.

-   Eliminates fragile software delay loops and ad-hoc timing constructs.

-   Enables sleep-based designs instead of continuous polling.

-   Provides a reusable, standardized timing primitive across multiple designs and products.

---
## FEATURE SUMMARY

## Supported Modes:

The Timer IP supports multiple operating modes to accommodate a wide range of timing requirements in embedded and SoC designs.

### One-Shot Mode
- In one-shot mode, the timer counts down from a programmed load value to zero and asserts a timeout event once. After the timeout event:

### Periodic (Auto-Reload) Mode
- In periodic mode, the timer automatically reloads the programmed load value upon reaching zero:

### Prescaled Operation
- Both one-shot and periodic modes may optionally operate with a programmable prescaler:

---
##  Limitations

While the Timer IP is intentionally general-purpose, certain limitations should be considered during system design.

### Single Timer Instance

### No Interrupt Controller Integration

### No Capture or Compare

### Software-Driven Control

---
## BLOCK DIAGRAM
<img width="1236" height="2928" alt="image" src="https://github.com/user-attachments/assets/f020b3f0-2f65-457e-a70f-339234eda4cc" />

##  RTL 

<details>
<summary> Timer IP (click to expand) </summary>

```verilog

`timescale 1ns / 1ps

module timer_ip (
    input  wire        clk,
    input  wire        resetn,

    // Bus interface
    input  wire        sel,        // timer selected
    input  wire        wr_en,       // write enable
    input  wire        rd_en,       // read enable
    input  wire [1:0]  addr,       // register select
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    // Hardware output
    output wire        timeout_o
);

    // -------------------------------------------------
    // Registers
    // -------------------------------------------------
    reg [31:0] ctrl_reg;    // CTRL
    reg [31:0] load_reg;    // LOAD
    reg [31:0] value_reg;   // VALUE
    reg        timeout;     // STATUS[0]

    // Prescaler
    reg [15:0] presc_cnt;

    // CTRL fields
    wire en        = ctrl_reg[0];
    wire mode      = ctrl_reg[1];   // 0 = one-shot, 1 = periodic
    wire presc_en  = ctrl_reg[2];
    wire [7:0] presc_div = ctrl_reg[15:8];

    // -------------------------------------------------
    // WRITE LOGIC (CTRL & LOAD only)
    // -------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            ctrl_reg <= 32'b0;
            load_reg <= 32'b0;
        end else if (sel && wr_en) begin
            case (addr)
                2'b00: ctrl_reg <= wdata;   // CTRL
                2'b01: load_reg <= wdata;   // LOAD
                default: ;
            endcase
        end
    end

    // -------------------------------------------------
    // TIMER CORE LOGIC (VALUE + TIMEOUT)
    // -------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            value_reg <= 32'b0;
            presc_cnt <= 16'b0;
            timeout   <= 1'b0;

        end else begin
            // STATUS W1C clear
            if (sel && wr_en && addr == 2'b11 && wdata[0])
                timeout <= 1'b0;

            if (en) begin
                // Prescaler tick
                if (!presc_en || presc_cnt == presc_div) begin
                    presc_cnt <= 16'b0;

                    if (value_reg > 1) begin
                        value_reg <= value_reg - 1;

                    end else if (value_reg == 1) begin
                        timeout <= 1'b1;
                        value_reg <= mode ? load_reg : 32'b0;

                    end else begin
                        // value_reg == 0
                        value_reg <= load_reg;
                    end
                end else begin
                    presc_cnt <= presc_cnt + 1;
                end
            end else begin
                // EN = 0 → preload
                value_reg <= load_reg;
                presc_cnt <= 16'b0;
                timeout   <= 1'b0;
            end
        end
    end

    // -------------------------------------------------
    // READ LOGIC (registered)
    // -------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            rdata <= 32'b0;
        end else if (sel && rd_en) begin
            case (addr)
                2'b00: rdata <= ctrl_reg;              // CTRL
                2'b01: rdata <= load_reg;              // LOAD
                2'b10: rdata <= value_reg;             // VALUE
                2'b11: rdata <= {31'b0, timeout};      // STATUS
                default: rdata <= 32'b0;
            endcase
        end
    end

    // -------------------------------------------------
    // Hardware output
    // -------------------------------------------------
    assign timeout_o = timeout;

endmodule

```

</details>

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

## Address Decoding 

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


# Register Map

---

## Register Summary

| Offset | Register | Access | Description |
|------:|----------|:------:|-------------|
| 0x00 | CTRL   | R/W | Control register (enable, mode, prescaler control) |
| 0x04 | LOAD   | R/W | Load value (initial / reload count) |
| 0x08 | VALUE  | R   | Current counter value |
| 0x0C | STATUS | R/W1C | Timeout status (write-1-to-clear) |

---

## CTRL Register (Offset 0x00)

**Reset Value:** `0x0000_0000`  
**Access:** Read / Write

| Bit(s) | Name | Description |
|------:|------|-------------|
| [0] | EN | Timer enable. `1` = timer runs, `0` = timer stopped and preloaded |
| [1] | MODE | Operating mode: `0` = one-shot, `1` = periodic |
| [2] | PRESC_EN | Prescaler enable. `1` = prescaler active, `0` = bypass |
| [15:8] | PRESC_DIV | Prescaler divider value |
| [31:16] | RSVD | Reserved, read as 0 |

**Behavior:**
- When `EN=0`, the counter is preloaded with `LOAD`.
- When `EN=1`, the timer counts based on the prescaler configuration.
- MODE controls reload behavior after timeout.

## HOW TO USE THE IP

- create a firmware for test

---

###  Use this commands 

---

### Firmware Build (ELF + HEX)
```bash
riscv64-unknown-elf-gcc -Os   -march=rv32i -mabi=ilp32   -ffreestanding -nostdlib   start.S timer_test2.c   -Wl,-T,link.ld   -o firmware.elf
```
```bash
riscv64-unknown-elf-objcopy -O ihex firmware.elf firmware.hex
```
### Simulation with Icarus Verilog (BENCH mode)

```bash
iverilog -g2012 -DBENCH   -o sim.vvp   riscv.v timer_ip.v
```

###  Run Simulation

```bash
vvp sim.vvp
```

###  View Waveforms

```bash
gtkwave soc.vcd
```
###  Simulation with Yosys 

```bash
yosys -p "
read_verilog riscv.v timer_ip.v
prep -top SOC
stat
"
```
### FPGA Synthesis & Bitstream 

```bash
yosys -p "
read_verilog riscv.v timer_ip.v
synth_ice40 -top SOC -json soc.json
"
```

```bash
nextpnr-ice40   --hx8k   --package cb132   --pcf VSDSquadronFM.pcf   --pcf-allow-unconstrained   --json soc.json   --asc soc.asc
```

```bash
icepack soc.asc soc.bin
```

### Program FPGA

```bash
iceprog soc.bin
```

### Board-Level Signal Mapping

| Timer IP Signal | SoC Signal | FPGA Pin | Board Connection | Purpose |
|---------------|-----------|---------|-----------------|---------|
| timeout_o | LEDS[0] | A5 | On-board LED0 | Visual timeout indication |


---

### pins

```pcf
set_io LEDS[0] A5
```

