
# Answers – GPIO Integration and Simulation Validation

## 1. Identify where memory-mapped peripherals are decoded
Memory-mapped peripherals are decoded inside the `SOC` module using the CPU address bus.
The signal `isIO = mem_addr[22]` selects the IO region starting at `0x0040_0000`.
Specific peripherals are selected by decoding the **word address** (`mem_addr[31:2]`).

Example (GPIO decode):
```verilog
wire [29:0] mem_wordaddr = mem_addr[31:2];
wire gpio_sel = isIO && (mem_wordaddr == 30'h00100008); // 0x00400020
```

---

## 2. Understand how the CPU reads and writes registers
The CPU uses a simple load/store interface:
- `mem_addr`   : target address
- `mem_wdata`  : data to write
- `mem_wmask`  : write enable (non-zero means write)
- `mem_rstrb`  : read strobe
- `mem_rdata`  : readback data

Writes happen when `mem_wmask != 0`.
Reads happen when `mem_rstrb == 1`, and data is returned on `mem_rdata`.

---

## 3. Locate existing simple peripherals (LED / UART)
Two existing peripherals were already present:
- **LEDs**: write-only register selected using `IO_LEDS_bit`
- **UART**: write data register and read status register

GPIO was added in the same IO region, following the same memory-mapped approach as LED and UART.

---

## 4. Address used for GPIO access
The firmware accesses GPIO using a **full 32-bit memory-mapped address**.

```c
#define IO_BASE   0x00400000
#define GPIO_ADDR (IO_BASE + 0x20)  // 0x00400020
```

This matches the RTL decode:
- `mem_addr[22] = 1` → IO region
- `mem_addr = 0x00400020` → GPIO register

---

## 5. How the CPU accesses the GPIO IP
- CPU executes `sw` instruction → asserts `mem_wmask`
- GPIO write enable is generated when `gpio_sel && mem_wmask`
- Data is stored in a GPIO register on the rising clock edge
- CPU executes `lw` instruction → asserts `mem_rstrb`
- GPIO returns stored value on `gpio_rdata`
- `gpio_rdata` is multiplexed onto `mem_rdata`

```verilog
assign mem_rdata = isRAM ? RAM_rdata :
                   gpio_sel ? gpio_rdata : 32'b0;
```

---

## 6. What was validated in simulation
The following were validated using simulation and GTKWave:
- GPIO register updates correctly on write
- Same value is read back on read
- UART prints the readback value (`GPIO readback = 000000A5`)
- Clock, reset, `mem_addr`, `mem_wdata`, `gpio_wr_en`, and `gpio_rdata` behave as expected
- Simulation ends cleanly using the `ecall` instruction

This confirms correct end-to-end operation from C firmware to RTL output.
