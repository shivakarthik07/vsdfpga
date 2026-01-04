#include "io.h"

/* GPIO base (must match RTL) */
#define GPIO_BASE   0x00400020

#define GPIO_DATA   (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR    (*(volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_READ   (*(volatile unsigned int *)(GPIO_BASE + 0x08))

int main(void)
{
    /* Configure lower 5 GPIOs as outputs */
    GPIO_DIR = 0x0000001F;

    /* Write value 0b01010 */
    GPIO_DATA = 0x0000000A;

    /* Small delay */
    for (volatile int i = 0; i < 1000; i++);

    /* Read back GPIO */
    unsigned int val = GPIO_READ;

    /* Print via UART */
    print_string("GPIO READ = ");
    print_hex(val);
    print_string("\n");

    /* End simulation */
    asm volatile ("ecall");

    return 0;
}

