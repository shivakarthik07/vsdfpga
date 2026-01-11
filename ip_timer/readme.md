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

