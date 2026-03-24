`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for fpu_top module — protocol verification
// Verifies busy/done handshake, single-cycle done pulses, bounded liveness.
//////////////////////////////////////////////////////////////////////////////

module sva_fpu_protocol_props (
    input logic        clk,
    input logic        rst,
    input logic        start,
    input logic [4:0]  fp_op,
    input logic [2:0]  rm,
    input logic [63:0] fp_a,
    input logic [63:0] fp_b,
    input logic [63:0] fp_c,
    input logic [63:0] int_src,
    input logic [63:0] fp_result,
    input logic        done,
    input logic        busy,
    input logic [4:0]  fp_flags,
    input logic        result_is_int
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // FP operation codes
    // -----------------------------------------------------------------------
    localparam [4:0] FP_ADD    = 5'd0,  FP_SUB    = 5'd1,
                     FP_MUL    = 5'd2,  FP_DIV    = 5'd3,
                     FP_SQRT   = 5'd4,  FP_FMADD  = 5'd5,
                     FP_FMSUB  = 5'd6,  FP_FNMSUB = 5'd7,
                     FP_FNMADD = 5'd8,  FP_SGNJ   = 5'd9,
                     FP_SGNJN  = 5'd10, FP_SGNJX  = 5'd11,
                     FP_MIN    = 5'd12, FP_MAX    = 5'd13,
                     FP_FEQ    = 5'd14, FP_FLT    = 5'd15,
                     FP_FLE    = 5'd16, FP_CVTWD  = 5'd17,
                     FP_CVTWUD = 5'd18, FP_CVTDW  = 5'd19,
                     FP_CVTDWU = 5'd20, FP_CVTLD  = 5'd21,
                     FP_CVTLUD = 5'd22, FP_CVTDL  = 5'd23,
                     FP_CVTDLU = 5'd24, FP_FCLASS = 5'd25,
                     FP_MVXD   = 5'd26, FP_MVDX   = 5'd27;

    // -----------------------------------------------------------------------
    // Helper: classify combinational (single-cycle) operations
    // -----------------------------------------------------------------------
    function automatic logic is_combinational(input logic [4:0] op);
        return (op == FP_SGNJ)   || (op == FP_SGNJN)  || (op == FP_SGNJX) ||
               (op == FP_MIN)    || (op == FP_MAX)     ||
               (op == FP_FEQ)    || (op == FP_FLT)     || (op == FP_FLE)   ||
               (op == FP_FCLASS) || (op == FP_MVXD)    || (op == FP_MVDX);
    endfunction

    wire is_comb_op = is_combinational(fp_op);

    // -----------------------------------------------------------------------
    // P_BUSY_ON_START: Multicycle ops assert busy on the next cycle
    // -----------------------------------------------------------------------
    P_BUSY_ON_START: assert property (
        @(posedge clk) disable iff (rst)
        !busy && start && !is_comb_op |=> busy
    ) else $error("P_BUSY_ON_START: busy did not assert after multicycle start");

    // -----------------------------------------------------------------------
    // P_DONE_ENDS_BUSY: After done pulses, busy deasserts next cycle
    // -----------------------------------------------------------------------
    P_DONE_ENDS_BUSY: assert property (
        @(posedge clk) disable iff (rst)
        done |=> !busy
    ) else $error("P_DONE_ENDS_BUSY: busy remained high after done");

    // -----------------------------------------------------------------------
    // P_DONE_PULSE_WIDTH: done is a single-cycle pulse unless a new op starts
    // (back-to-back combinational ops may keep done high across cycles)
    // -----------------------------------------------------------------------
    P_DONE_PULSE_WIDTH: assert property (
        @(posedge clk) disable iff (rst)
        done |=> !done || start
    ) else $error("P_DONE_PULSE_WIDTH: done persisted without a new start");

    // -----------------------------------------------------------------------
    // P_NO_DONE_IDLE: No spurious done when truly idle (idle for 2+ cycles)
    // A multicycle done fires at the same cycle busy drops, so we require
    // the FPU to have been non-busy on the previous cycle as well.
    // -----------------------------------------------------------------------
    P_NO_DONE_IDLE: assert property (
        @(posedge clk) disable iff (rst)
        !busy && !start && $past(!busy && !start) |-> !done
    ) else $error("P_NO_DONE_IDLE: spurious done while idle");

    // -----------------------------------------------------------------------
    // P_EVENTUAL_DONE: Multicycle ops complete within 100 cycles
    // -----------------------------------------------------------------------
    P_EVENTUAL_DONE: assert property (
        @(posedge clk) disable iff (rst)
        start && !is_comb_op |-> ##[1:100] done
    ) else $error("P_EVENTUAL_DONE: multicycle op did not complete within 100 cycles");

    // -----------------------------------------------------------------------
    // P_RESULT_STABLE_ON_DONE: Result is valid (not X) when done
    // (In simulation, this checks for X; in formal, it's vacuously true)
    // -----------------------------------------------------------------------
    P_RESULT_STABLE_ON_DONE: assert property (
        @(posedge clk) disable iff (rst)
        done |-> !$isunknown(fp_result)
    ) else $error("P_RESULT_STABLE_ON_DONE: fp_result contains X when done");

    // -----------------------------------------------------------------------
    // C_ALL_MULTICYCLE_OPS: Cover each multicycle fp_op with start
    // -----------------------------------------------------------------------
    C_MC_ADD: cover property (
        @(posedge clk) start && fp_op == FP_ADD ##[1:100] done
    );
    C_MC_SUB: cover property (
        @(posedge clk) start && fp_op == FP_SUB ##[1:100] done
    );
    C_MC_MUL: cover property (
        @(posedge clk) start && fp_op == FP_MUL ##[1:100] done
    );
    C_MC_DIV: cover property (
        @(posedge clk) start && fp_op == FP_DIV ##[1:100] done
    );
    C_MC_SQRT: cover property (
        @(posedge clk) start && fp_op == FP_SQRT ##[1:100] done
    );
    C_MC_FMADD: cover property (
        @(posedge clk) start && fp_op == FP_FMADD ##[1:100] done
    );
    C_MC_FMSUB: cover property (
        @(posedge clk) start && fp_op == FP_FMSUB ##[1:100] done
    );
    C_MC_FNMSUB: cover property (
        @(posedge clk) start && fp_op == FP_FNMSUB ##[1:100] done
    );
    C_MC_FNMADD: cover property (
        @(posedge clk) start && fp_op == FP_FNMADD ##[1:100] done
    );
    C_MC_CVTWD: cover property (
        @(posedge clk) start && fp_op == FP_CVTWD ##[1:100] done
    );
    C_MC_CVTWUD: cover property (
        @(posedge clk) start && fp_op == FP_CVTWUD ##[1:100] done
    );
    C_MC_CVTDW: cover property (
        @(posedge clk) start && fp_op == FP_CVTDW ##[1:100] done
    );
    C_MC_CVTDWU: cover property (
        @(posedge clk) start && fp_op == FP_CVTDWU ##[1:100] done
    );
    C_MC_CVTLD: cover property (
        @(posedge clk) start && fp_op == FP_CVTLD ##[1:100] done
    );
    C_MC_CVTLUD: cover property (
        @(posedge clk) start && fp_op == FP_CVTLUD ##[1:100] done
    );
    C_MC_CVTDL: cover property (
        @(posedge clk) start && fp_op == FP_CVTDL ##[1:100] done
    );
    C_MC_CVTDLU: cover property (
        @(posedge clk) start && fp_op == FP_CVTDLU ##[1:100] done
    );

endmodule
