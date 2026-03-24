# demo_sqrt.s - Compute sqrt(2) * 1000, display on LEDs
# Expected: sqrt(2) = 1.41421... * 1000 = 1414 = 0x0586
#
# LEDs show: 0000010110000110

_start:
    # Build GPIO address 0xFF00
    addi x1, x0, 255
    slli x1, x1, 8         # x1 = 0xFF00

    # Create 2.0 in f1
    addi x2, x0, 2
    fcvt.d.w f1, x2        # f1 = 2.0

    # Compute sqrt(2.0)
    fsqrt.d f2, f1          # f2 = 1.41421356...

    # Create 1000.0 in f3
    addi x3, x0, 1000
    fcvt.d.w f3, x3        # f3 = 1000.0

    # Multiply: f4 = sqrt(2) * 1000
    fmul.d f4, f2, f3      # f4 = 1414.21356...

    # Convert to integer (truncates toward zero)
    fcvt.w.d x5, f4        # x5 = 1414

    # Display on LEDs
    sd x5, 0(x1)

    # Hold forever
hold:
    jal x0, hold
