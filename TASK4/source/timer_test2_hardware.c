#include "io.h"

#define TIMER_BASE   0x00400040
#define TIMER_CTRL   (*(volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIMER_LOAD   (*(volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIMER_STAT   (*(volatile unsigned int *)(TIMER_BASE + 0x0C))

int main(void)
{
    /* Stop timer */
    TIMER_CTRL = 0;

    /* Load value (adjust if blink is too fast/slow) */
    TIMER_LOAD = 12000000;   // ~1 second at 12 MHz

    /* Enable timer, periodic mode */
    TIMER_CTRL = 0x3;        // bit0=EN, bit1=MODE(periodic)

    while (1) {
        if (TIMER_STAT & 0x1) {
            TIMER_STAT = 0x1;   // clear TIMEOUT (W1C)
        }
    }
}

