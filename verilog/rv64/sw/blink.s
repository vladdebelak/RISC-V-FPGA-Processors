# RV64I LED Blink
# GPIO at 0xFF00

_start:
    addi x1, x0, 255       # x1 = 0xFF
    nop
    nop
    slli x1, x1, 8         # x1 = 0xFF00
    nop
    nop

loop:
    addi x2, x0, -1        # x2 = all 1s
    nop
    nop
    sd x2, 0(x1)            # LEDs on (lower 16 bits = 0xFFFF)

    lui x3, 0x800           # x3 = 0x800000 = 8388608 (~0.5s at 100MHz with ~6 cyc/iter)
    nop
    nop
delay1:
    addi x3, x3, -1
    nop
    nop
    bne x3, x0, delay1
    nop
    nop

    sd x0, 0(x1)            # LEDs off

    lui x3, 0x800
    nop
    nop
delay2:
    addi x3, x3, -1
    nop
    nop
    bne x3, x0, delay2
    nop
    nop

    jal x0, loop
    nop
    nop
