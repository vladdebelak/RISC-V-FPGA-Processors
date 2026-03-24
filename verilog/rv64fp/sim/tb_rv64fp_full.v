`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_rv64fp_full.v — Full-system integration testbench for rv64fp processor
//
// Instantiates rv64fp_top (core + BRAM + bus + GPIO), loads demo_all_ops
// program, runs until LEDs stabilize or timeout, and reports pass/fail
// for each of the 16 FPU verification tests.
//
// Usage:  xsim sim_full -R
//////////////////////////////////////////////////////////////////////////////

module tb_rv64fp_full;

    // -----------------------------------------------------------------------
    // Clock and reset
    // -----------------------------------------------------------------------
    reg         clk;
    reg         rst;
    wire [15:0] led;

    rv64fp_top uut (
        .CLK100MHZ (clk),
        .BTNC      (rst),
        .LED       (led)
    );

    // 100 MHz clock: 10 ns period, 5 ns half-period
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Test name table — one entry per LED bit
    // -----------------------------------------------------------------------
    reg [0:20*8-1] test_name [0:15];  // 20-char strings

    initial begin
        test_name[ 0] = "FADD.D              ";
        test_name[ 1] = "FSUB.D              ";
        test_name[ 2] = "FMUL.D              ";
        test_name[ 3] = "FDIV.D              ";
        test_name[ 4] = "FSQRT.D             ";
        test_name[ 5] = "FMADD.D             ";
        test_name[ 6] = "FEQ.D               ";
        test_name[ 7] = "FLT.D               ";
        test_name[ 8] = "FMIN.D              ";
        test_name[ 9] = "FMAX.D              ";
        test_name[10] = "FCVT round-trip     ";
        test_name[11] = "FSGNJ.D             ";
        test_name[12] = "FCLASS.D            ";
        test_name[13] = "FMV round-trip      ";
        test_name[14] = "FNEG (FSGNJN.D)     ";
        test_name[15] = "ALL-PASSED flag     ";
    end

    // -----------------------------------------------------------------------
    // Simulation control
    // -----------------------------------------------------------------------
    integer cycle_count;
    integer stable_count;
    reg [15:0] prev_led;
    integer pass_count;
    integer i;
    integer led_changed_at;

    // Timeout parameters
    localparam STABLE_THRESHOLD = 1000;    // cycles with no LED change => done
    localparam TIMEOUT          = 5000000; // max cycles before giving up

    initial begin
        // Optional: dump waveforms for debugging
        // $dumpfile("rv64fp_full.vcd");
        // $dumpvars(0, tb_rv64fp_full);

        $display("================================================================");
        $display(" rv64fp Full-System Integration Test");
        $display(" Clock: 100 MHz (10 ns period)");
        $display(" Timeout: %0d cycles (%0d us)", TIMEOUT, TIMEOUT / 100);
        $display("================================================================");
        $display("");

        // ---------------------------------------------------------------
        // Reset phase: hold BTNC high for 20 cycles (200 ns)
        // ---------------------------------------------------------------
        rst          = 1;
        cycle_count  = 0;
        stable_count = 0;
        prev_led     = 16'h0000;
        led_changed_at = 0;

        #200;  // 20 cycles at 10 ns each
        rst = 0;
        $display("[%0t] Reset released.", $time);
        $display("");

        // ---------------------------------------------------------------
        // Run until LEDs stabilize or we hit timeout
        // ---------------------------------------------------------------
        while (stable_count < STABLE_THRESHOLD && cycle_count < TIMEOUT) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Debug: trace pipeline during first 300 cycles
            if (cycle_count <= 300) begin
                if (uut.u_core.u_execute.u_fpu.u_fp_conv.done) begin
                    $display("[cycle %0d] FP_CONV DONE: result=%h flags=%b result_is_int=%b op_r=%0d",
                        cycle_count,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.result,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.flags,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.result_is_int,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.op_r);
                end
                if (uut.u_core.u_execute.u_fpu.u_fp_conv.state == 2'd2 && cycle_count <= 15) begin
                    $display("[cycle %0d] FP_CONV S_CYCLE2: int_abs=%h lzc_data=%h lzc_count=%0d int_sign=%b",
                        cycle_count,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.int_abs,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.lzc_data,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.u_lzc.count,
                        uut.u_core.u_execute.u_fpu.u_fp_conv.int_sign);
                end
                if (uut.u_core.u_execute.u_fpu.u_fp_add.done) begin
                    $display("[cycle %0d] FP_ADD DONE: result=%h flags=%b",
                        cycle_count,
                        uut.u_core.u_execute.u_fpu.u_fp_add.result,
                        uut.u_core.u_execute.u_fpu.u_fp_add.flags);
                end
                if (uut.u_core.u_execute.u_fpu.u_fp_div.done) begin
                    $display("[cycle %0d] FP_DIV DONE: result=%h flags=%b",
                        cycle_count,
                        uut.u_core.u_execute.u_fpu.u_fp_div.result,
                        uut.u_core.u_execute.u_fpu.u_fp_div.flags);
                end
                if (uut.u_core.u_execute.u_fpu.u_fp_sqrt.done) begin
                    $display("[cycle %0d] FP_SQRT DONE: result=%h flags=%b",
                        cycle_count,
                        uut.u_core.u_execute.u_fpu.u_fp_sqrt.result,
                        uut.u_core.u_execute.u_fpu.u_fp_sqrt.flags);
                end
                if (uut.u_core.u_execute.u_fpu.u_fp_fma.done) begin
                    $display("[cycle %0d] FP_FMA DONE: result=%h flags=%b",
                        cycle_count,
                        uut.u_core.u_execute.u_fpu.u_fp_fma.result,
                        uut.u_core.u_execute.u_fpu.u_fp_fma.flags);
                end
                if (uut.u_core.u_execute.idex_fp_en && uut.u_core.u_execute.idex_valid) begin
                    $display("[cycle %0d] EX: fp_op=%0d rd=%0d fp_reg_we=%b reg_we=%b | fpu_busy=%b fpu_done=%b stall_ex=%b | fpu_result=%h | int_src(rs1_data)=%h fp_a=%h fp_b=%h",
                        cycle_count,
                        uut.u_core.u_execute.idex_fp_op,
                        uut.u_core.u_execute.idex_rd,
                        uut.u_core.u_execute.idex_fp_reg_we,
                        uut.u_core.u_execute.idex_reg_we,
                        uut.u_core.u_execute.fpu_busy,
                        uut.u_core.u_execute.fpu_done,
                        uut.u_core.u_hazard.stall_ex,
                        uut.u_core.u_execute.fpu_result,
                        uut.u_core.u_execute.idex_rs1_data,
                        uut.u_core.u_execute.idex_fp_rs1_data,
                        uut.u_core.u_execute.idex_fp_rs2_data);
                end
                // Debug: show fetch/decode state
                if (cycle_count >= 40 && cycle_count <= 55) begin
                    $display("[cycle %0d] FETCH: pc_reg=%h instr_data=%h ifid_pc=%h ifid_valid=%b stall_if=%b",
                        cycle_count,
                        uut.u_core.u_fetch.pc_reg,
                        uut.u_core.u_decode.instr,
                        uut.u_core.u_fetch.ifid_pc,
                        uut.u_core.u_fetch.ifid_valid,
                        uut.u_core.u_hazard.stall_if);
                end
                // Debug forwarding around cycle 12-14
                if (cycle_count >= 11 && cycle_count <= 16) begin
                    $display("[cycle %0d] FWD-DEBUG: fwd_rs1_sel=%b id_rs1_addr=%0d id_rs1_used=%b | idex_rd=%0d idex_reg_we=%b idex_fp_reg_we=%b idex_mem_re=%b | stall_id=%b stall_ex=%b | ex_result_comb=%h",
                        cycle_count,
                        uut.u_core.u_hazard.fwd_rs1_sel,
                        uut.u_core.u_hazard.id_rs1_addr,
                        uut.u_core.u_hazard.id_rs1_used,
                        uut.u_core.u_hazard.idex_rd,
                        uut.u_core.u_hazard.idex_reg_we,
                        uut.u_core.u_hazard.idex_fp_reg_we,
                        uut.u_core.u_hazard.idex_mem_re,
                        uut.u_core.u_hazard.stall_id,
                        uut.u_core.u_hazard.stall_ex,
                        uut.u_core.u_execute.ex_result_comb);
                end
                if (uut.u_core.u_writeback.wb_fp_reg_we) begin
                    $display("[cycle %0d] WB-FP: rd=%0d data=%h",
                        cycle_count,
                        uut.u_core.u_writeback.wb_rd,
                        uut.u_core.u_writeback.wb_fp_data);
                end
                if (uut.u_core.u_writeback.wb_reg_we) begin
                    $display("[cycle %0d] WB-INT: rd=%0d data=%h",
                        cycle_count,
                        uut.u_core.u_writeback.wb_rd,
                        uut.u_core.u_writeback.wb_data);
                end
            end

            if (led !== prev_led) begin
                stable_count   = 0;
                prev_led       = led;
                led_changed_at = cycle_count;
                $display("[cycle %0d] LED changed to 0x%04h", cycle_count, led);
            end else begin
                stable_count = stable_count + 1;
            end

            // Progress indicator every 500k cycles
            if (cycle_count % 500000 == 0)
                $display("[cycle %0d] Still running... LED = 0x%04h",
                         cycle_count, led);
        end

        // ---------------------------------------------------------------
        // Determine termination reason
        // ---------------------------------------------------------------
        $display("");
        if (stable_count >= STABLE_THRESHOLD) begin
            $display("Simulation stopped: LEDs stable for %0d cycles at 0x%04h",
                     STABLE_THRESHOLD, led);
            $display("Last LED change at cycle %0d", led_changed_at);
        end else begin
            $display("*** TIMEOUT after %0d cycles! LEDs = 0x%04h ***",
                     TIMEOUT, led);
        end
        $display("Total cycles executed: %0d (%0d ns)",
                 cycle_count, cycle_count * 10);
        $display("");

        // ---------------------------------------------------------------
        // Report per-test results
        // ---------------------------------------------------------------
        $display("================================================================");
        $display(" TEST RESULTS");
        $display("================================================================");

        pass_count = 0;
        for (i = 0; i < 16; i = i + 1) begin
            if (led[i]) begin
                $display("  TEST %2d (%0s): PASS", i, test_name[i]);
                pass_count = pass_count + 1;
            end else begin
                $display("  TEST %2d (%0s): *** FAIL ***", i, test_name[i]);
            end
        end

        $display("");
        $display("================================================================");
        if (pass_count == 16) begin
            $display(" ALL 16 TESTS PASSED  --  LED = 0x%04h", led);
            $display(" Processor is VERIFIED and ready for synthesis.");
        end else begin
            $display(" %0d/16 tests passed  --  LED = 0x%04h", pass_count, led);
            $display(" FAILURES DETECTED. Debug required before synthesis.");
        end
        $display("================================================================");

        // Exit code: 0 = all pass, 1 = failure
        if (pass_count == 16)
            $finish(0);
        else
            $finish(1);
    end

    // -----------------------------------------------------------------------
    // Watchdog: abort if simulation hangs
    // -----------------------------------------------------------------------
    initial begin
        #100_000_000;  // 100 ms sim time = 10M cycles absolute max
        $display("");
        $display("*** WATCHDOG TIMEOUT at %0t — aborting simulation ***", $time);
        $display("    LED = 0x%04h", led);
        $finish(2);
    end

endmodule
