`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_fpu_ops.v — Unit tests for the FPU (fpu_top)
//
// Directly instantiates fpu_top and tests each floating-point operation
// with known IEEE 754 double-precision values.
//
// Protocol: set inputs, pulse start, wait for done, check result.
//////////////////////////////////////////////////////////////////////////////

module tb_fpu_ops;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    reg         clk, rst;
    reg         start;
    reg  [4:0]  fp_op;
    reg  [2:0]  rm;
    reg  [63:0] fp_a, fp_b, fp_c;
    reg  [63:0] int_src;
    wire [63:0] fp_result;
    wire        done;
    wire        busy;
    wire [4:0]  fp_flags;
    wire        result_is_int;

    fpu_top uut (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .fp_op         (fp_op),
        .rm            (rm),
        .fp_a          (fp_a),
        .fp_b          (fp_b),
        .fp_c          (fp_c),
        .int_src       (int_src),
        .fp_result     (fp_result),
        .done          (done),
        .busy          (busy),
        .fp_flags      (fp_flags),
        .result_is_int (result_is_int)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // FP operation codes (must match fpu_top.v)
    // -----------------------------------------------------------------------
    localparam FP_ADD    = 5'd0;
    localparam FP_SUB    = 5'd1;
    localparam FP_MUL    = 5'd2;
    localparam FP_DIV    = 5'd3;
    localparam FP_SQRT   = 5'd4;
    localparam FP_FMADD  = 5'd5;
    localparam FP_FEQ    = 5'd14;
    localparam FP_FLT    = 5'd15;
    localparam FP_FLE    = 5'd16;
    localparam FP_MIN    = 5'd12;
    localparam FP_MAX    = 5'd13;
    localparam FP_SGNJ   = 5'd9;
    localparam FP_SGNJN  = 5'd10;
    localparam FP_FCLASS = 5'd25;
    localparam FP_MVXD   = 5'd26;  // FMV.X.D (fp->int)
    localparam FP_MVDX   = 5'd27;  // FMV.D.X (int->fp)

    // -----------------------------------------------------------------------
    // IEEE 754 double-precision constants
    // -----------------------------------------------------------------------
    localparam [63:0] FP_1_0   = 64'h3FF0000000000000;
    localparam [63:0] FP_2_0   = 64'h4000000000000000;
    localparam [63:0] FP_3_0   = 64'h4008000000000000;
    localparam [63:0] FP_4_0   = 64'h4010000000000000;
    localparam [63:0] FP_5_0   = 64'h4014000000000000;
    localparam [63:0] FP_9_0   = 64'h4022000000000000;
    localparam [63:0] FP_10_0  = 64'h4024000000000000;
    localparam [63:0] FP_12_0  = 64'h4028000000000000;
    localparam [63:0] FP_NEG5  = 64'hC014000000000000;  // -5.0
    localparam [63:0] FP_0_0   = 64'h0000000000000000;  // +0.0

    // -----------------------------------------------------------------------
    // Test tracking
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer test_num;
    integer wait_cycles;

    // -----------------------------------------------------------------------
    // Task: run one FPU operation and check result
    // -----------------------------------------------------------------------
    task run_fpu_test;
        input [4:0]         op;
        input [63:0]        in_a;
        input [63:0]        in_b;
        input [63:0]        in_c;
        input [63:0]        expected;
        input [0:24*8-1]    name;  // 24-char test name
        begin
            test_num = test_num + 1;

            // Setup inputs
            fp_op   = op;
            fp_a    = in_a;
            fp_b    = in_b;
            fp_c    = in_c;
            int_src = 64'h0;
            rm      = 3'b000;  // RNE (round to nearest, ties to even)

            // Pulse start
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for done (with timeout)
            wait_cycles = 0;
            while (!done && wait_cycles < 10000) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (wait_cycles >= 10000) begin
                $display("  TEST %2d %-24s : FAIL (TIMEOUT — no done after %0d cycles)",
                         test_num, name, wait_cycles);
                fail_count = fail_count + 1;
            end else if (fp_result === expected) begin
                $display("  TEST %2d %-24s : PASS  (%0d cycles, result=0x%016h)",
                         test_num, name, wait_cycles + 1, fp_result);
                pass_count = pass_count + 1;
            end else begin
                $display("  TEST %2d %-24s : FAIL  got=0x%016h  exp=0x%016h  (%0d cycles)",
                         test_num, name, fp_result, expected, wait_cycles + 1);
                fail_count = fail_count + 1;
            end

            // Let the FPU return to idle
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: run FPU test expecting integer result (comparison/classify)
    // For comparisons, the result is 0 or 1 in the low bit
    // -----------------------------------------------------------------------
    task run_fpu_int_test;
        input [4:0]         op;
        input [63:0]        in_a;
        input [63:0]        in_b;
        input [63:0]        expected;
        input [0:24*8-1]    name;
        begin
            test_num = test_num + 1;

            fp_op   = op;
            fp_a    = in_a;
            fp_b    = in_b;
            fp_c    = 64'h0;
            int_src = 64'h0;
            rm      = 3'b000;

            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            wait_cycles = 0;
            while (!done && wait_cycles < 10000) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (wait_cycles >= 10000) begin
                $display("  TEST %2d %-24s : FAIL (TIMEOUT)", test_num, name);
                fail_count = fail_count + 1;
            end else if (fp_result === expected) begin
                $display("  TEST %2d %-24s : PASS  (%0d cycles, result=0x%016h)",
                         test_num, name, wait_cycles + 1, fp_result);
                pass_count = pass_count + 1;
            end else begin
                $display("  TEST %2d %-24s : FAIL  got=0x%016h  exp=0x%016h  (%0d cycles)",
                         test_num, name, fp_result, expected, wait_cycles + 1);
                fail_count = fail_count + 1;
            end

            @(posedge clk);
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("================================================================");
        $display(" FPU Unit Tests (fpu_top)");
        $display("================================================================");
        $display("");

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        // Reset
        rst     = 1;
        start   = 0;
        fp_op   = 5'd0;
        fp_a    = 64'd0;
        fp_b    = 64'd0;
        fp_c    = 64'd0;
        int_src = 64'd0;
        rm      = 3'b000;
        #100;
        rst = 0;
        #20;

        // ==== Arithmetic operations ====
        $display("--- Arithmetic Operations ---");

        // FADD: 1.0 + 2.0 = 3.0
        run_fpu_test(FP_ADD, FP_1_0, FP_2_0, 64'h0,
                     FP_3_0, "FADD 1.0 + 2.0 = 3.0   ");

        // FSUB: 5.0 - 3.0 = 2.0
        run_fpu_test(FP_SUB, FP_5_0, FP_3_0, 64'h0,
                     FP_2_0, "FSUB 5.0 - 3.0 = 2.0   ");

        // FMUL: 3.0 * 4.0 = 12.0
        run_fpu_test(FP_MUL, FP_3_0, FP_4_0, 64'h0,
                     FP_12_0, "FMUL 3.0 * 4.0 = 12.0  ");

        // FDIV: 10.0 / 2.0 = 5.0
        run_fpu_test(FP_DIV, FP_10_0, FP_2_0, 64'h0,
                     FP_5_0, "FDIV 10.0 / 2.0 = 5.0  ");

        // FSQRT: sqrt(9.0) = 3.0
        run_fpu_test(FP_SQRT, FP_9_0, 64'h0, 64'h0,
                     FP_3_0, "FSQRT sqrt(9.0) = 3.0  ");

        // FMADD: 2.0 * 3.0 + 4.0 = 10.0
        run_fpu_test(FP_FMADD, FP_2_0, FP_3_0, FP_4_0,
                     FP_10_0, "FMADD 2*3+4 = 10.0     ");

        // ==== Comparison operations ====
        $display("");
        $display("--- Comparison Operations ---");

        // FEQ: 3.0 == 3.0 -> 1
        run_fpu_int_test(FP_FEQ, FP_3_0, FP_3_0,
                         64'h0000000000000001, "FEQ 3.0 == 3.0 -> 1    ");

        // FEQ: 3.0 == 5.0 -> 0
        run_fpu_int_test(FP_FEQ, FP_3_0, FP_5_0,
                         64'h0000000000000000, "FEQ 3.0 == 5.0 -> 0    ");

        // FLT: 2.0 < 3.0 -> 1
        run_fpu_int_test(FP_FLT, FP_2_0, FP_3_0,
                         64'h0000000000000001, "FLT 2.0 < 3.0 -> 1     ");

        // FLT: 3.0 < 2.0 -> 0
        run_fpu_int_test(FP_FLT, FP_3_0, FP_2_0,
                         64'h0000000000000000, "FLT 3.0 < 2.0 -> 0     ");

        // FLE: 3.0 <= 3.0 -> 1
        run_fpu_int_test(FP_FLE, FP_3_0, FP_3_0,
                         64'h0000000000000001, "FLE 3.0 <= 3.0 -> 1    ");

        // FLE: 5.0 <= 3.0 -> 0
        run_fpu_int_test(FP_FLE, FP_5_0, FP_3_0,
                         64'h0000000000000000, "FLE 5.0 <= 3.0 -> 0    ");

        // ==== Min/Max ====
        $display("");
        $display("--- Min/Max Operations ---");

        // FMIN: min(5.0, 3.0) = 3.0
        run_fpu_test(FP_MIN, FP_5_0, FP_3_0, 64'h0,
                     FP_3_0, "FMIN min(5,3) = 3.0     ");

        // FMAX: max(5.0, 3.0) = 5.0
        run_fpu_test(FP_MAX, FP_5_0, FP_3_0, 64'h0,
                     FP_5_0, "FMAX max(5,3) = 5.0     ");

        // ==== Sign manipulation ====
        $display("");
        $display("--- Sign Manipulation ---");

        // FSGNJ: copy sign of +1.0 to 5.0 -> +5.0
        run_fpu_test(FP_SGNJ, FP_5_0, FP_1_0, 64'h0,
                     FP_5_0, "FSGNJ +sign -> +5.0     ");

        // FSGNJ: copy sign of -5.0 to 3.0 -> -3.0
        run_fpu_test(FP_SGNJ, FP_3_0, FP_NEG5, 64'h0,
                     64'hC008000000000000, "FSGNJ -sign -> -3.0     ");

        // FSGNJN: negate sign of 5.0 -> -5.0
        run_fpu_test(FP_SGNJN, FP_5_0, FP_5_0, 64'h0,
                     FP_NEG5, "FSGNJN negate 5 -> -5   ");

        // ==== Summary ====
        $display("");
        $display("================================================================");
        if (fail_count == 0) begin
            $display(" ALL %0d FPU TESTS PASSED", pass_count);
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

    // Watchdog
    initial begin
        #50_000_000;  // 50 ms sim time
        $display("*** FPU TEST WATCHDOG TIMEOUT ***");
        $finish(2);
    end

endmodule
