# demo_pi.s - Approximate pi using Leibniz series
# pi/4 = 1 - 1/3 + 1/5 - 1/7 + ...
# Run 1000 iterations, multiply by 4000, convert to int
# Expected: ~3141 on LEDs (0x0C45)

_start:
    # Build GPIO address 0xFF00
    addi x1, x0, 255
    slli x1, x1, 8         # x1 = 0xFF00

    # f1 = sum = 0.0
    fcvt.d.w f1, x0        # f1 = 0.0

    # f2 = 1.0 (current term sign * magnitude)
    addi x2, x0, 1
    fcvt.d.w f2, x2        # f2 = 1.0

    # f3 = 1.0 (denominator)
    fcvt.d.w f3, x2        # f3 = 1.0

    # f4 = 2.0 (denominator increment)
    addi x3, x0, 2
    fcvt.d.w f4, x3        # f4 = 2.0

    # f5 = -1.0 (sign flip)
    addi x4, x0, -1
    fcvt.d.w f5, x4        # f5 = -1.0

    # x5 = loop counter (1000 iterations)
    addi x5, x0, 1000

    # f6 = current term value
loop:
    # f6 = f2 / f3  (sign / denominator)
    fdiv.d f6, f2, f3

    # sum += term
    fadd.d f1, f1, f6

    # denominator += 2
    fadd.d f3, f3, f4

    # flip sign: f2 = f2 * -1
    fmul.d f2, f2, f5

    # Decrement counter
    addi x5, x5, -1
    bne x5, x0, loop

    # Now f1 = pi/4 approximately
    # Multiply by 4000 to get pi * 1000
    addi x6, x0, 4
    fcvt.d.w f7, x6        # f7 = 4.0
    addi x7, x0, 1000
    fcvt.d.w f8, x7        # f8 = 1000.0
    fmul.d f7, f7, f8      # f7 = 4000.0
    fmul.d f9, f1, f7      # f9 = pi * 1000

    # Convert to integer
    fcvt.w.d x8, f9        # x8 = ~3141

    # Display on LEDs
    sd x8, 0(x1)

    # Hold forever
hold:
    jal x0, hold
