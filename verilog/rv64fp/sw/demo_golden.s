# demo_golden.s - Compute the golden ratio phi = (1 + sqrt(5)) / 2
# phi = 1.61803... * 1000 = 1618 = 0x0652
# Expected: 1618 on LEDs

_start:
    # Build GPIO address 0xFF00
    addi x1, x0, 255
    slli x1, x1, 8         # x1 = 0xFF00

    # Create 5.0
    addi x2, x0, 5
    fcvt.d.w f1, x2        # f1 = 5.0

    # sqrt(5)
    fsqrt.d f2, f1          # f2 = 2.2360679...

    # Create 1.0
    addi x3, x0, 1
    fcvt.d.w f3, x3        # f3 = 1.0

    # 1 + sqrt(5)
    fadd.d f4, f3, f2      # f4 = 3.2360679...

    # Create 2.0
    addi x4, x0, 2
    fcvt.d.w f5, x4        # f5 = 2.0

    # phi = (1 + sqrt(5)) / 2
    fdiv.d f6, f4, f5      # f6 = 1.6180339...

    # Multiply by 1000
    addi x5, x0, 1000
    fcvt.d.w f7, x5        # f7 = 1000.0
    fmul.d f8, f6, f7      # f8 = 1618.0339...

    # Convert to integer
    fcvt.w.d x6, f8        # x6 = 1618

    # Display on LEDs
    sd x6, 0(x1)

    # Hold forever
hold:
    jal x0, hold
