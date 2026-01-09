# RISC-V SoC Timer IP – Design, Integration, and Testing

## Overview

This project extends a minimal **RV32I RISC-V SoC** with a **memory-mapped timer peripheral (`timer_ip`)**.  
The timer is integrated into the SoC address space, accessed from C firmware, and validated through simulation and FPGA deployment.

The main goals were:
- Implement a **clean, synthesizable timer IP**
- Support **one-shot**, **periodic (reload)**, and **prescaled** operation
- Expose a **hardware timeout signal** for direct logic (LED toggle)
- Verify behavior using **bare‑metal C tests**

---

## Timer IP  – Design Explanation

### Register Map

| Offset | Name   | Access | Description |
|------:|--------|--------|-------------|
| 0x00  | CTRL   | R/W    | Control register |
| 0x04  | LOAD   | R/W    | Reload / start value |
| 0x08  | VALUE  | R      | Current countdown value |
| 0x0C  | STATUS | R/W1C  | Timeout flag (bit 0) |

### CTRL Register Fields

| Bit(s) | Name | Description |
|------:|------|-------------|
| 0 | EN | Enable timer |
| 1 | MODE | 0 = one-shot, 1 = periodic |
| 2 | PRESC_EN | Enable prescaler |
| 15:8 | PRESC_DIV | Prescaler divider value |

### Key Design Choices

#### 1. **Write‑1‑to‑Clear (W1C) STATUS**
- Timeout flag is cleared only when software writes `1` to STATUS[0]
- Prevents accidental clears from normal reads

#### 2. **Preload on Disable**
- When `EN = 0`, the timer automatically loads `LOAD` into `VALUE`
- Guarantees deterministic startup behavior

#### 3. **Prescaler**
- Optional prescaler allows slow timer ticks without changing system clock
- Divider stored in CTRL[15:8]

#### 4. **One‑Shot vs Periodic**
- **One‑shot**: timer stops at zero after timeout
- **Periodic**: timer reloads automatically from `LOAD`

#### 5. **Hardware Timeout Output**
- `timeout_o` is asserted when VALUE transitions from `1 → 0`
- Used directly in SoC logic (LED toggle)

---

## SoC Integration 

### Address Decode

The timer is mapped at:

```
TIMER_BASE = 0x0040_0040
```

Decoded in hardware using:
- `mem_addr[22]` → IO page
- `mem_wordaddr[1:0]` → register select

### Connections

- `rdata` → CPU load path
- `timeout_o` → hardware logic
- Timer shares system clock and reset

### LED Debug Logic

A rising edge detector toggles LED[0] on every timeout event:

```verilog
if (timer_timeout && !timeout_d)
    LEDS[0] <= ~LEDS[0];
```

This allows **hardware‑visible verification** even without UART output.

---

## Firmware Tests – Behavior Explained

### 1. `timer_test.c` – One‑Shot Timeout

**Purpose**
- Verify basic countdown and timeout flag

**Expected Behavior**
- Timer starts with a large LOAD value
- VALUE decreases over time
- STATUS[0] becomes `1` once
- Program prints timeout message and exits

**Result**
- Confirms correct one‑shot operation
  
**IMAGES**

**TIMER_LOAD**
<img width="1598" height="375" alt="loadtimer" src="https://github.com/user-attachments/assets/78d8df5d-2b0a-4125-9f55-293c46e6f164" />
**TIMER_DECREMENT**
<img width="1598" height="375" alt="timerfunctioning" src="https://github.com/user-attachments/assets/1214b75b-402c-43f3-98ae-88e49b1c123d" />
**TIMEOUT_HIGH**
<img width="1317" height="114" alt="timeout_high_timer" src="https://github.com/user-attachments/assets/73b3097b-f7af-4423-b149-ebfbe626e3a7" />

---

### 2. `timer_periodic.c` – Reload (Periodic) Mode

**Purpose**
- Verify automatic reload after timeout

**Configuration**
- MODE = 1 (periodic)

**Expected Behavior**
- STATUS[0] asserts repeatedly
- Software clears STATUS each time
- Multiple timeout messages printed

**Result**
- Confirms reload logic and W1C behavior
  
**IMAGES**

**TESTING RELOADING PROPERTY OF ```TIMER_IP```**

**TIMER LOADED**
<img width="1597" height="191" alt="reload_timer_load" src="https://github.com/user-attachments/assets/f0952aa7-10a9-43aa-8009-a6a3cb5d3d14" />
**TIMER DECREMENT**
<img width="1597" height="191" alt="reload_timer_decrement" src="https://github.com/user-attachments/assets/14fa6f59-6fdd-480b-9702-0167ef03f908" />
**TIMER RELOADED**
<img width="1597" height="191" alt="reload_timer_reloaded" src="https://github.com/user-attachments/assets/ddca9c74-dece-4955-b13b-c2c0a487be0f" />
**TIMER READBACK**
<img width="1609" height="217" alt="reload_timer_readback" src="https://github.com/user-attachments/assets/35c47bf4-3b13-4bd1-b818-73b136d13d0d" />

---

### 3. `timer_clear_test.c` – Timeout Clear Validation

**Purpose**
- Verify STATUS W1C semantics

**Expected Behavior**
1. Timer expires → STATUS = 1
2. Software writes `1` to STATUS
3. STATUS clears back to `0`

**Result**
- Confirms reliable timeout clearing

**IMAGES**

**ONESHOT_LOAD & TIMEOUT_CLEAR_TEST**

**TIMER_LOADED**
<img width="1162" height="183" alt="timer_clear_png" src="https://github.com/user-attachments/assets/76d8a85d-ffe3-47fb-9c45-dcd4c1304fc8" />
**TIMER_DECREMENT & TIMEOUT_HIGH**
<img width="1612" height="198" alt="timer_cleaar_decrementing" src="https://github.com/user-attachments/assets/067047e9-a845-4ad1-a56c-c9075d1f5467" />
**TIMEOUT_RESET**
<img width="1612" height="198" alt="timeout_reset" src="https://github.com/user-attachments/assets/2de73b79-b9fa-487b-a403-18459c2394cc" />

---

### 4. `timer_test2.c` – Hardware Validation (FPGA)

**Purpose**
- Validate timer on real FPGA hardware

**Behavior**
- Timer runs continuously
- `timeout_o` toggles LED[0] on each expiration
- No UART required

**Result**
- LED visibly blinks
- Confirms correct synthesis, timing, and IO mapping

*(A demonstration video is attached separately.)*

**led blinks after some time when timeout goes high**
[LED_BLINK](https://drive.google.com/file/d/1M_fXuN6hM9jtkfFzpWRU5EPvglLoG621/view?usp=drive_link)


---

## Build & Implementation Flow

### 1. Firmware Build

```bash
riscv64-unknown-elf-gcc -Os   -march=rv32i -mabi=ilp32   -ffreestanding -nostdlib   start.S timer_test2.c   -Wl,-T,link.ld   -o firmware.elf

riscv64-unknown-elf-objcopy -O ihex firmware.elf firmware.hex
```

### 2. RTL Synthesis (Yosys)

```bash
yosys -p
read_verilog riscv.v
read_verilog timer_ip.v
read_verilog ice40_stubs.v
synth_ice40 -top SOC -json soc.json
```

### 3. Place & Route (nextpnr)

```bash
nextpnr-ice40   --hx8k   --package cb132   --pcf VSDSquadronFM.pcf   --json soc.json   --asc soc.asc   --pcf-allow-unconstrained
```

### 4. Bitstream Generation

```bash
icepack soc.asc soc.bin
```

### 5. FPGA Programming

```bash
iceprog soc.bin
```

---

## Issues Faced & Fixes

| Issue | Fix |
|-----|-----|
| Module redefinition | Avoid reading included files twice in Yosys |
| HFOSC placement failure | Disabled HFOSC, used external clock |
| Unconstrained IO errors | Added PCF entries / allowed unconstrained |
| Timer double decrement | Reworked VALUE update logic |
| Timeout glitching | Added edge detection in SoC |

---

## Conclusion

This project demonstrates:
- A **cleanly designed hardware timer**
- Correct **memory‑mapped peripheral integration**
- Robust **bare‑metal software testing**
- Successful **simulation and FPGA validation**

The timer is reusable, scalable, and suitable for interrupts or RTOS tick generation in future extensions.

---
