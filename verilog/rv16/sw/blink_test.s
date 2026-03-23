# LED Blink Program for rv16 MCU - SHORT DELAY VERSION FOR SIMULATION
# GPIO LED register at address 0xFF00
# Strategy: ADDI x1, x0, -256 gives 0xFF00 in 16-bit

_start:
    addi x1, x0, -256      # x1 = 0xFF00 (GPIO LED address)
    nop
    nop

loop:
    addi x2, x0, -1        # x2 = 0xFFFF (all LEDs on)
    nop
    nop
    sw x2, 0(x1)           # Write to LED register

    # Short delay for simulation: outer=2, inner=3
    addi x3, x0, 2         # x3 = outer loop counter (short)
    nop
    nop
delay1_outer:
    addi x4, x0, 3         # x4 = 3 (inner counter, short)
    nop
    nop
delay1_inner:
    addi x4, x4, -1        # x4--
    nop
    nop
    bne x4, x0, delay1_inner
    nop
    nop
    addi x3, x3, -1        # x3--
    nop
    nop
    bne x3, x0, delay1_outer
    nop
    nop

    # LEDs off
    sw x0, 0(x1)           # Write 0 to LED register

    # Second delay (same structure)
    addi x3, x0, 2
    nop
    nop
delay2_outer:
    addi x4, x0, 3
    nop
    nop
delay2_inner:
    addi x4, x4, -1
    nop
    nop
    bne x4, x0, delay2_inner
    nop
    nop
    addi x3, x3, -1
    nop
    nop
    bne x3, x0, delay2_outer
    nop
    nop

    jal x0, loop            # Jump back to loop (discard return addr in x0)
    nop
    nop
