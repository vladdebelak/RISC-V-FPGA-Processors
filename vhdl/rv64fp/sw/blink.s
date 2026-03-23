# RV64IFD LED Blink (forwarding eliminates NOPs)
_start:
    addi x1, x0, 255
    slli x1, x1, 8         # x1 = 0xFF00
loop:
    addi x2, x0, -1        # all LEDs on
    sd x2, 0(x1)
    lui x3, 0x400           # delay counter (~4M iterations, adjust for ~0.5s)
delay1:
    addi x3, x3, -1
    bne x3, x0, delay1
    sd x0, 0(x1)            # LEDs off
    lui x3, 0x400
delay2:
    addi x3, x3, -1
    bne x3, x0, delay2
    jal x0, loop
