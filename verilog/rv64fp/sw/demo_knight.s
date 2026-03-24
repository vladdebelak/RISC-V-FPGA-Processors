# demo_knight.s - Knight Rider LED chaser pattern
# A single lit LED bounces left and right across 16 LEDs
# Demonstrates integer shift instructions (SLL, SRL) and branching

_start:
    # Build GPIO address 0xFF00
    addi x1, x0, 255
    slli x1, x1, 8         # x1 = 0xFF00

    # x2 = current LED pattern (start with bit 0)
    addi x2, x0, 1

    # x3 = direction: 0 = left, 1 = right
    addi x3, x0, 0

    # x4 = max bit position (bit 15)
    lui x4, 0x00008         # x4 = 0x8000 = 32768 (bit 15 set)

    # x5 = min bit position (bit 0)
    addi x5, x0, 1

    # x6 = delay counter limit
    # Use a large count for visible speed on FPGA
    lui x6, 0x40            # x6 = 0x40000 = 262144

main_loop:
    # Write current pattern to LEDs
    sd x2, 0(x1)

    # Delay loop
    addi x7, x0, 0
delay:
    addi x7, x7, 1
    bne x7, x6, delay

    # Check direction
    bne x3, x0, go_right

go_left:
    # Shift left by 1
    slli x2, x2, 1
    # Check if we hit bit 15
    beq x2, x4, switch_to_right
    jal x0, main_loop

switch_to_right:
    addi x3, x0, 1
    jal x0, main_loop

go_right:
    # Shift right by 1
    srli x2, x2, 1
    # Check if we hit bit 0
    beq x2, x5, switch_to_left
    jal x0, main_loop

switch_to_left:
    addi x3, x0, 0
    jal x0, main_loop
