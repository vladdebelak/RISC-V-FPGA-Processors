`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_alu.v — Unit test for the rv64fp integer ALU
//
// Tests all 15 ALU operations with known input/output vectors.
// Pure combinational: no clock needed. Applies inputs, waits for propagation,
// checks result. Reports pass/fail for each operation.
//////////////////////////////////////////////////////////////////////////////

module tb_alu;

    reg  [63:0] a, b;
    reg  [4:0]  alu_op;
    wire [63:0] result;
    wire        zero, lt_signed, lt_unsigned;

    alu uut (
        .a           (a),
        .b           (b),
        .alu_op      (alu_op),
        .result      (result),
        .zero        (zero),
        .lt_signed   (lt_signed),
        .lt_unsigned (lt_unsigned)
    );

    // ALU operation encodings (must match alu.v)
    localparam [4:0] OP_ADD   = 5'b00000;
    localparam [4:0] OP_SUB   = 5'b00001;
    localparam [4:0] OP_AND   = 5'b00010;
    localparam [4:0] OP_OR    = 5'b00011;
    localparam [4:0] OP_XOR   = 5'b00100;
    localparam [4:0] OP_SLL   = 5'b00101;
    localparam [4:0] OP_SRL   = 5'b00110;
    localparam [4:0] OP_SRA   = 5'b00111;
    localparam [4:0] OP_SLT   = 5'b01000;
    localparam [4:0] OP_SLTU  = 5'b01001;
    localparam [4:0] OP_PASSB = 5'b01010;
    localparam [4:0] OP_ADDW  = 5'b10000;
    localparam [4:0] OP_SUBW  = 5'b10001;
    localparam [4:0] OP_SLLW  = 5'b10101;
    localparam [4:0] OP_SRLW  = 5'b10110;
    localparam [4:0] OP_SRAW  = 5'b10111;

    integer pass_count;
    integer fail_count;
    integer test_num;

    // -----------------------------------------------------------------------
    // Task: check one ALU operation
    // -----------------------------------------------------------------------
    task check;
        input [4:0]    op;
        input [63:0]   in_a;
        input [63:0]   in_b;
        input [63:0]   expected;
        input [0:12*8-1] name;   // 12-char operation name
        begin
            alu_op = op;
            a      = in_a;
            b      = in_b;
            #10;  // combinational propagation delay

            test_num = test_num + 1;
            if (result === expected) begin
                $display("  TEST %2d %-12s : PASS  (0x%016h)", test_num, name, result);
                pass_count = pass_count + 1;
            end else begin
                $display("  TEST %2d %-12s : FAIL  got=0x%016h  exp=0x%016h",
                         test_num, name, result, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: check comparison flags
    // -----------------------------------------------------------------------
    task check_flags;
        input [63:0]   in_a;
        input [63:0]   in_b;
        input          exp_zero;
        input          exp_lt_s;
        input          exp_lt_u;
        input [0:20*8-1] name;
        begin
            a      = in_a;
            b      = in_b;
            alu_op = OP_ADD;  // doesn't matter for flag checks
            #10;

            test_num = test_num + 1;
            if (zero === exp_zero && lt_signed === exp_lt_s && lt_unsigned === exp_lt_u) begin
                $display("  TEST %2d %-20s : PASS  (z=%b lt_s=%b lt_u=%b)",
                         test_num, name, zero, lt_signed, lt_unsigned);
                pass_count = pass_count + 1;
            end else begin
                $display("  TEST %2d %-20s : FAIL  z=%b/%b lt_s=%b/%b lt_u=%b/%b",
                         test_num, name,
                         zero, exp_zero, lt_signed, exp_lt_s, lt_unsigned, exp_lt_u);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("================================================================");
        $display(" ALU Unit Test");
        $display("================================================================");
        $display("");

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        // ---- RV64I basic operations ----
        $display("--- RV64I Operations ---");

        check(OP_ADD,  64'h0000000000000005, 64'h0000000000000003,
                        64'h0000000000000008, "ADD         ");

        check(OP_ADD,  64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001,
                        64'h0000000000000000, "ADD overflow");

        check(OP_SUB,  64'h0000000000000005, 64'h0000000000000003,
                        64'h0000000000000002, "SUB         ");

        check(OP_SUB,  64'h0000000000000003, 64'h0000000000000005,
                        64'hFFFFFFFFFFFFFFFE, "SUB negative");

        check(OP_AND,  64'hFF00FF00FF00FF00, 64'h0F0F0F0F0F0F0F0F,
                        64'h0F000F000F000F00, "AND         ");

        check(OP_OR,   64'hFF00FF00FF00FF00, 64'h0F0F0F0F0F0F0F0F,
                        64'hFF0FFF0FFF0FFF0F, "OR          ");

        check(OP_XOR,  64'hFF00FF00FF00FF00, 64'h0F0F0F0F0F0F0F0F,
                        64'hF00FF00FF00FF00F, "XOR         ");

        check(OP_SLL,  64'h0000000000000001, 64'h0000000000000010,
                        64'h0000000000010000, "SLL         ");

        check(OP_SRL,  64'h0000000000010000, 64'h0000000000000010,
                        64'h0000000000000001, "SRL         ");

        check(OP_SRA,  64'hFFFFFFFFFFFF0000, 64'h0000000000000010,
                        64'hFFFFFFFFFFFFFFFF, "SRA         ");

        check(OP_SRA,  64'h0000000000FF0000, 64'h0000000000000010,
                        64'h00000000000000FF, "SRA positive");

        check(OP_SLT,  64'hFFFFFFFFFFFFFFFE, 64'h0000000000000001,
                        64'h0000000000000001, "SLT (neg<pos)");

        check(OP_SLT,  64'h0000000000000001, 64'hFFFFFFFFFFFFFFFE,
                        64'h0000000000000000, "SLT (pos>neg)");

        check(OP_SLTU, 64'h0000000000000001, 64'hFFFFFFFFFFFFFFFE,
                        64'h0000000000000001, "SLTU        ");

        check(OP_SLTU, 64'hFFFFFFFFFFFFFFFE, 64'h0000000000000001,
                        64'h0000000000000000, "SLTU reverse");

        check(OP_PASSB,64'hDEADBEEFDEADBEEF, 64'h123456789ABCDEF0,
                        64'h123456789ABCDEF0, "PASS_B      ");

        // ---- RV64 W-variant operations ----
        $display("");
        $display("--- RV64 W-variant Operations ---");

        // ADDW: 5 + 3 = 8, sign-extended from 32-bit
        check(OP_ADDW, 64'h0000000000000005, 64'h0000000000000003,
                        64'h0000000000000008, "ADDW        ");

        // ADDW with 32-bit overflow: 0x7FFFFFFF + 1 = 0x80000000 -> sign-ext negative
        check(OP_ADDW, 64'h000000007FFFFFFF, 64'h0000000000000001,
                        64'hFFFFFFFF80000000, "ADDW ovflw  ");

        // SUBW: 5 - 3 = 2
        check(OP_SUBW, 64'h0000000000000005, 64'h0000000000000003,
                        64'h0000000000000002, "SUBW        ");

        // SLLW: 1 << 16 = 0x10000
        check(OP_SLLW, 64'h0000000000000001, 64'h0000000000000010,
                        64'h0000000000010000, "SLLW        ");

        // SLLW with sign extension: 1 << 31 = 0x80000000 -> sign-ext
        check(OP_SLLW, 64'h0000000000000001, 64'h000000000000001F,
                        64'hFFFFFFFF80000000, "SLLW sign   ");

        // SRLW: 0x10000 >> 16 = 1
        check(OP_SRLW, 64'h0000000000010000, 64'h0000000000000010,
                        64'h0000000000000001, "SRLW        ");

        // SRAW: 0xFFFF0000 >> 16 = 0xFFFFFFFF (sign-extended)
        check(OP_SRAW, 64'h00000000FFFF0000, 64'h0000000000000010,
                        64'hFFFFFFFFFFFFFFFF, "SRAW        ");

        // ---- Comparison flag tests ----
        $display("");
        $display("--- Comparison Flags ---");

        check_flags(64'h5, 64'h5,  1, 0, 0, "equal values        ");
        check_flags(64'h3, 64'h5,  0, 1, 1, "3 < 5 (both pos)    ");
        check_flags(64'hFFFFFFFFFFFFFFFE, 64'h5,
                                   0, 1, 0, "-2 < 5 (signed only) ");
        check_flags(64'h5, 64'hFFFFFFFFFFFFFFFE,
                                   0, 0, 1, "5 < big (unsigned)   ");

        // ---- Summary ----
        $display("");
        $display("================================================================");
        if (fail_count == 0) begin
            $display(" ALL %0d ALU TESTS PASSED", pass_count);
        end else begin
            $display(" %0d PASSED, %0d FAILED out of %0d tests",
                     pass_count, fail_count, pass_count + fail_count);
        end
        $display("================================================================");

        if (fail_count == 0)
            $finish(0);
        else
            $finish(1);
    end

endmodule
