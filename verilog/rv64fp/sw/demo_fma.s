# demo_fma.s - Demonstrate fused multiply-add
# Compute 7.0 * 8.0 + 6.0 = 62 using FMADD.D
# Expected: 62 on LEDs = 0x003E

_start:
    # Build GPIO address 0xFF00
    addi x1, x0, 255
    slli x1, x1, 8         # x1 = 0xFF00

    # Create constants
    addi x2, x0, 7
    fcvt.d.w f1, x2        # f1 = 7.0

    addi x3, x0, 8
    fcvt.d.w f2, x3        # f2 = 8.0

    addi x4, x0, 6
    fcvt.d.w f3, x4        # f3 = 6.0

    # FMADD: f4 = f1 * f2 + f3 = 7*8+6 = 62
    fmadd.d f4, f1, f2, f3

    # Also demonstrate FMSUB: f5 = f1 * f2 - f3 = 56 - 6 = 50
    fmsub.d f5, f1, f2, f3

    # Convert FMADD result to integer
    fcvt.w.d x5, f4        # x5 = 62

    # Display on LEDs
    sd x5, 0(x1)

    # Hold forever
hold:
    jal x0, hold
