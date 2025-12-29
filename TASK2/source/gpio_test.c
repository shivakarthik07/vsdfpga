#include "io.h"

#define IO_BASE     0x00400000
#define UART_ADDR   (IO_BASE + 0x04)
#define GPIO_ADDR   (IO_BASE + 0x20)

int main(void);

void _start(void)
{
    main();
    while (1);   // never reached in simulation
}

static inline void uart_putc(char c)
{
    volatile uint32_t *uart = (uint32_t *)UART_ADDR;
    *uart = (uint32_t)c;
}

static void print_hex(uint32_t v)
{
    const char hex[] = "0123456789ABCDEF";
    for (int i = 7; i >= 0; i--)
        uart_putc(hex[(v >> (i * 4)) & 0xF]);
}

static void print_string(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

int main(void)
{
    volatile uint32_t *gpio = (uint32_t *)GPIO_ADDR;

    *gpio = 0xA5;
    asm volatile ("" ::: "memory");

    uint32_t val = *gpio;

    print_string("GPIO readback = ");
    print_hex(val);
    print_string("\n");

    asm volatile ("ecall");   // <-- correct place

    return 0;
}

