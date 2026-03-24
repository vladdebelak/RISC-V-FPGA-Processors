# demo_all_ops.s - Comprehensive FPU verification test
# Tests every FP operation, sets corresponding LED bit if correct
# All 16 LEDs on (0xFFFF) = full pass
#
# LED 0:  FADD.D   (1.0 + 2.0 == 3.0)
# LED 1:  FSUB.D   (5.0 - 3.0 == 2.0)
# LED 2:  FMUL.D   (3.0 * 4.0 == 12.0)
# LED 3:  FDIV.D   (10.0 / 2.0 == 5.0)
# LED 4:  FSQRT.D  (sqrt(9.0) == 3.0)
# LED 5:  FMADD.D  (2.0 * 3.0 + 4.0 == 10.0)
# LED 6:  FEQ.D    (3.0 == 3.0)
# LED 7:  FLT.D    (2.0 < 3.0)
# LED 8:  FMIN.D   (min(5.0, 3.0) == 3.0)
# LED 9:  FMAX.D   (max(5.0, 3.0) == 5.0)
# LED 10: FCVT     round-trip (42 -> double -> int == 42)
# LED 11: FSGNJ.D  (sign inject)
# LED 12: FCLASS.D (classify positive zero)
# LED 13: FMV      round-trip (move to int and back)
# LED 14: FNEG     (negate via FSGNJN.D)
# LED 15: All above passed

_start:
    # Build GPIO address 0xFF00
    addi x1, x0, 255
    slli x1, x1, 8         # x1 = 0xFF00

    # x30 = result accumulator (LED bits)
    addi x30, x0, 0

    # ==============================
    # Create FP constants from integers
    # ==============================
    addi x2, x0, 1
    fcvt.d.w f1, x2        # f1 = 1.0

    addi x2, x0, 2
    fcvt.d.w f2, x2        # f2 = 2.0

    addi x2, x0, 3
    fcvt.d.w f3, x2        # f3 = 3.0

    addi x2, x0, 4
    fcvt.d.w f4, x2        # f4 = 4.0

    addi x2, x0, 5
    fcvt.d.w f5, x2        # f5 = 5.0

    addi x2, x0, 9
    fcvt.d.w f9, x2        # f9 = 9.0

    addi x2, x0, 10
    fcvt.d.w f10, x2       # f10 = 10.0

    addi x2, x0, 12
    fcvt.d.w f12, x2       # f12 = 12.0

    addi x2, x0, 42
    fcvt.d.w f14, x2       # f14 = 42.0

    # Also keep f0 = 0.0
    fcvt.d.w f0, x0        # f0 = 0.0

    # ==============================
    # TEST 0: FADD.D (1.0 + 2.0 == 3.0)
    # ==============================
    fadd.d f20, f1, f2     # f20 = 3.0
    feq.d x3, f20, f3      # x3 = 1 if equal
    or x30, x30, x3        # set LED 0

    # ==============================
    # TEST 1: FSUB.D (5.0 - 3.0 == 2.0)
    # ==============================
    fsub.d f20, f5, f3     # f20 = 2.0
    feq.d x3, f20, f2      # x3 = 1 if equal
    slli x3, x3, 1
    or x30, x30, x3        # set LED 1

    # ==============================
    # TEST 2: FMUL.D (3.0 * 4.0 == 12.0)
    # ==============================
    fmul.d f20, f3, f4     # f20 = 12.0
    feq.d x3, f20, f12     # x3 = 1 if equal
    slli x3, x3, 2
    or x30, x30, x3        # set LED 2

    # ==============================
    # TEST 3: FDIV.D (10.0 / 2.0 == 5.0)
    # ==============================
    fdiv.d f20, f10, f2    # f20 = 5.0
    feq.d x3, f20, f5      # x3 = 1 if equal
    slli x3, x3, 3
    or x30, x30, x3        # set LED 3

    # ==============================
    # TEST 4: FSQRT.D (sqrt(9.0) == 3.0)
    # ==============================
    fsqrt.d f20, f9        # f20 = 3.0
    feq.d x3, f20, f3      # x3 = 1 if equal
    slli x3, x3, 4
    or x30, x30, x3        # set LED 4

    # ==============================
    # TEST 5: FMADD.D (2.0 * 3.0 + 4.0 == 10.0)
    # ==============================
    fmadd.d f20, f2, f3, f4  # f20 = 2*3+4 = 10.0
    feq.d x3, f20, f10     # x3 = 1 if equal
    slli x3, x3, 5
    or x30, x30, x3        # set LED 5

    # ==============================
    # TEST 6: FEQ.D (3.0 == 3.0)
    # ==============================
    feq.d x3, f3, f3       # x3 = 1 (3.0 equals itself)
    slli x3, x3, 6
    or x30, x30, x3        # set LED 6

    # ==============================
    # TEST 7: FLT.D (2.0 < 3.0)
    # ==============================
    flt.d x3, f2, f3       # x3 = 1 (2.0 < 3.0)
    slli x3, x3, 7
    or x30, x30, x3        # set LED 7

    # ==============================
    # TEST 8: FMIN.D (min(5.0, 3.0) == 3.0)
    # ==============================
    fmin.d f20, f5, f3     # f20 = 3.0
    feq.d x3, f20, f3      # x3 = 1 if equal
    slli x3, x3, 8
    or x30, x30, x3        # set LED 8

    # ==============================
    # TEST 9: FMAX.D (max(5.0, 3.0) == 5.0)
    # ==============================
    fmax.d f20, f5, f3     # f20 = 5.0
    feq.d x3, f20, f5      # x3 = 1 if equal
    slli x3, x3, 9
    or x30, x30, x3        # set LED 9

    # ==============================
    # TEST 10: FCVT round-trip (int 42 -> double -> int == 42)
    # ==============================
    # f14 already = 42.0 from setup
    fcvt.w.d x4, f14       # x4 = 42
    addi x5, x0, 42
    sub x3, x4, x5         # x3 = 0 if equal
    sltiu x3, x3, 1        # x3 = 1 if x3==0 (equal)
    slli x3, x3, 10
    or x30, x30, x3        # set LED 10

    # ==============================
    # TEST 11: FSGNJ.D (copy sign of f1=+1.0 to f5=+5.0)
    # Result should be +5.0
    # ==============================
    fsgnj.d f20, f5, f1    # f20 = +5.0 (magnitude of f5, sign of f1)
    feq.d x3, f20, f5      # x3 = 1 if equal to +5.0
    slli x3, x3, 11
    or x30, x30, x3        # set LED 11

    # ==============================
    # TEST 12: FCLASS.D (classify +0.0)
    # Positive zero -> bit 4 (value 16 = 0x10)
    # ==============================
    fclass.d x3, f0        # classify 0.0
    addi x4, x0, 16        # expected: bit 4 = positive zero
    sub x3, x3, x4
    sltiu x3, x3, 1        # x3 = 1 if equal
    slli x3, x3, 12
    or x30, x30, x3        # set LED 12

    # ==============================
    # TEST 13: FMV round-trip (FP -> int -> FP)
    # Move f3 (3.0) to integer, then back, compare
    # ==============================
    fmv.x.d x4, f3         # x4 = bit pattern of 3.0
    fmv.d.x f20, x4        # f20 = 3.0 (from bit pattern)
    feq.d x3, f20, f3      # x3 = 1 if equal
    slli x3, x3, 13
    or x30, x30, x3        # set LED 13

    # ==============================
    # TEST 14: FNEG via FSGNJN.D
    # Negate 5.0 -> -5.0, then negate again -> 5.0, compare
    # ==============================
    fsgnjn.d f20, f5, f5   # f20 = -5.0 (negate f5)
    fsgnjn.d f21, f20, f20 # f21 = +5.0 (negate -5.0)
    feq.d x3, f21, f5      # x3 = 1 if equal
    slli x3, x3, 14
    or x30, x30, x3        # set LED 14

    # ==============================
    # TEST 15: All passed check
    # If bits 14:0 are all set (0x7FFF), set bit 15
    # ==============================
    # Build 0x7FFF
    addi x4, x0, 0x7FF     # x4 = 2047
    slli x4, x4, 4         # x4 = 32752 = 0x7FF0
    ori x4, x4, 0xF        # x4 = 32767 = 0x7FFF
    and x3, x30, x4        # mask bits 14:0
    sub x3, x3, x4         # 0 if all set
    sltiu x3, x3, 1        # 1 if equal
    slli x3, x3, 15
    or x30, x30, x3        # set LED 15

    # Write final result to LEDs
    sd x30, 0(x1)

    # Hold forever
hold:
    jal x0, hold
