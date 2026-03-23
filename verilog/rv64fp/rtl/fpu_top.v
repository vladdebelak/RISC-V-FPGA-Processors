`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// fpu_top.v - RV64IFD Floating-Point Unit Top-Level Wrapper
//
// Routes FP operations to the correct subunit and manages busy/done protocol.
// Vivado 2020.2 compatible, pure Verilog (no SystemVerilog constructs).
//////////////////////////////////////////////////////////////////////////////

module fpu_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,          // pulse to begin FP operation
    input  wire [4:0]  fp_op,          // FPU operation code
    input  wire [2:0]  rm,             // rounding mode
    input  wire [63:0] fp_a,           // FP operand A
    input  wire [63:0] fp_b,           // FP operand B
    input  wire [63:0] fp_c,           // FP operand C (FMA only)
    input  wire [63:0] int_src,        // integer source for FMV.D.X / FCVT.D.*
    output wire [63:0] fp_result,      // FP or integer result
    output wire        done,           // pulses when result ready
    output wire        busy,           // high while computing
    output wire [4:0]  fp_flags,       // IEEE 754 exception flags {NV,DZ,OF,UF,NX}
    output wire        result_is_int   // 1 if result goes to integer register
);

    // -----------------------------------------------------------------------
    // FP operation codes
    // -----------------------------------------------------------------------
    localparam FP_ADD     = 5'd0;
    localparam FP_SUB     = 5'd1;
    localparam FP_MUL     = 5'd2;
    localparam FP_DIV     = 5'd3;
    localparam FP_SQRT    = 5'd4;
    localparam FP_FMADD   = 5'd5;
    localparam FP_FMSUB   = 5'd6;
    localparam FP_FNMSUB  = 5'd7;
    localparam FP_FNMADD  = 5'd8;
    localparam FP_SGNJ    = 5'd9;
    localparam FP_SGNJN   = 5'd10;
    localparam FP_SGNJX   = 5'd11;
    localparam FP_MIN     = 5'd12;
    localparam FP_MAX     = 5'd13;
    localparam FP_FEQ     = 5'd14;
    localparam FP_FLT     = 5'd15;
    localparam FP_FLE     = 5'd16;
    localparam FP_CVTWD   = 5'd17;
    localparam FP_CVTWUD  = 5'd18;
    localparam FP_CVTDW   = 5'd19;
    localparam FP_CVTDWU  = 5'd20;
    localparam FP_CVTLD   = 5'd21;
    localparam FP_CVTLUD  = 5'd22;
    localparam FP_CVTDL   = 5'd23;
    localparam FP_CVTDLU  = 5'd24;
    localparam FP_FCLASS  = 5'd25;
    localparam FP_MVXD    = 5'd26;
    localparam FP_MVDX    = 5'd27;

    // -----------------------------------------------------------------------
    // Active-unit encoding (registered to track which multicycle unit is busy)
    // -----------------------------------------------------------------------
    localparam UNIT_NONE  = 3'd0;
    localparam UNIT_ADD   = 3'd1;
    localparam UNIT_MUL   = 3'd2;
    localparam UNIT_FMA   = 3'd3;
    localparam UNIT_DIV   = 3'd4;
    localparam UNIT_SQRT  = 3'd5;
    localparam UNIT_CONV  = 3'd6;

    reg [2:0] active_unit;

    // -----------------------------------------------------------------------
    // Operation classification
    // -----------------------------------------------------------------------
    wire op_is_add   = (fp_op == FP_ADD)  || (fp_op == FP_SUB);
    wire op_is_mul   = (fp_op == FP_MUL);
    wire op_is_fma   = (fp_op == FP_FMADD) || (fp_op == FP_FMSUB) ||
                       (fp_op == FP_FNMSUB) || (fp_op == FP_FNMADD);
    wire op_is_div   = (fp_op == FP_DIV);
    wire op_is_sqrt  = (fp_op == FP_SQRT);
    wire op_is_cmp   = (fp_op == FP_FEQ) || (fp_op == FP_FLT) ||
                       (fp_op == FP_FLE) || (fp_op == FP_MIN) ||
                       (fp_op == FP_MAX);
    wire op_is_conv  = (fp_op >= FP_CVTWD && fp_op <= FP_CVTDLU) ||
                       (fp_op == FP_MVXD)  || (fp_op == FP_MVDX);
    wire op_is_misc  = (fp_op == FP_SGNJ) || (fp_op == FP_SGNJN) ||
                       (fp_op == FP_SGNJX) || (fp_op == FP_FCLASS);

    wire op_is_combinational = op_is_cmp || op_is_misc;

    // -----------------------------------------------------------------------
    // Start signal routing (only pulse the relevant subunit)
    // -----------------------------------------------------------------------
    wire add_start  = start & op_is_add;
    wire mul_start  = start & op_is_mul;
    wire fma_start  = start & op_is_fma;
    wire div_start  = start & op_is_div;
    wire sqrt_start = start & op_is_sqrt;
    wire conv_start = start & op_is_conv;
    // cmp and misc are combinational -- no start needed

    // -----------------------------------------------------------------------
    // Subunit wires
    // -----------------------------------------------------------------------
    // fp_add
    wire [63:0] add_result;
    wire        add_done;
    wire        add_busy;
    wire [4:0]  add_flags;

    // fp_mul
    wire [63:0] mul_result;
    wire        mul_done;
    wire        mul_busy;
    wire [4:0]  mul_flags;

    // fp_fma
    wire [63:0] fma_result;
    wire        fma_done;
    wire        fma_busy;
    wire [4:0]  fma_flags;

    // fp_div
    wire [63:0] div_result;
    wire        div_done;
    wire        div_busy;
    wire [4:0]  div_flags;

    // fp_sqrt
    wire [63:0] sqrt_result;
    wire        sqrt_done;
    wire        sqrt_busy;
    wire [4:0]  sqrt_flags;

    // fp_cmp (combinational)
    wire [63:0] cmp_result;
    wire [4:0]  cmp_flags;
    wire        cmp_result_is_int;

    // fp_conv
    wire [63:0] conv_result;
    wire        conv_done;
    wire        conv_busy;
    wire [4:0]  conv_flags;
    wire        conv_result_is_int;

    // fp_misc (combinational, no flags output)
    wire [63:0] misc_result;
    wire [4:0]  misc_flags = 5'd0;  // fp_misc generates no exception flags
    wire        misc_result_is_int;

    // -----------------------------------------------------------------------
    // Subunit operation code mappings
    // -----------------------------------------------------------------------

    // fp_add: is_sub
    wire add_is_sub = (fp_op == FP_SUB);

    // fp_fma: op[1:0] -- FMADD=0, FMSUB=1, FNMSUB=2, FNMADD=3
    reg [1:0] fma_op;
    always @(*) begin
        case (fp_op)
            FP_FMADD:  fma_op = 2'd0;
            FP_FMSUB:  fma_op = 2'd1;
            FP_FNMSUB: fma_op = 2'd2;
            FP_FNMADD: fma_op = 2'd3;
            default:   fma_op = 2'd0;
        endcase
    end

    // fp_cmp: op -- FEQ=0, FLT=1, FLE=2, MIN=3, MAX=4
    reg [2:0] cmp_op;
    always @(*) begin
        case (fp_op)
            FP_FEQ:  cmp_op = 3'd0;
            FP_FLT:  cmp_op = 3'd1;
            FP_FLE:  cmp_op = 3'd2;
            FP_MIN:  cmp_op = 3'd3;
            FP_MAX:  cmp_op = 3'd4;
            default: cmp_op = 3'd0;
        endcase
    end

    // fp_conv: op -- CVTWD=0, CVTWUD=1, CVTLD=2, CVTLUD=3,
    //                CVTDW=4, CVTDWU=5, CVTDL=6, CVTDLU=7,
    //                MVXD=8, MVDX=9
    reg [3:0] conv_op;
    always @(*) begin
        case (fp_op)
            FP_CVTWD:  conv_op = 4'd0;
            FP_CVTWUD: conv_op = 4'd1;
            FP_CVTLD:  conv_op = 4'd2;
            FP_CVTLUD: conv_op = 4'd3;
            FP_CVTDW:  conv_op = 4'd4;
            FP_CVTDWU: conv_op = 4'd5;
            FP_CVTDL:  conv_op = 4'd6;
            FP_CVTDLU: conv_op = 4'd7;
            FP_MVXD:   conv_op = 4'd8;
            FP_MVDX:   conv_op = 4'd9;
            default:   conv_op = 4'd0;
        endcase
    end

    // fp_misc: op -- SGNJ=0, SGNJN=1, SGNJX=2, FCLASS=3
    reg [2:0] misc_op;
    always @(*) begin
        case (fp_op)
            FP_SGNJ:   misc_op = 3'd0;
            FP_SGNJN:  misc_op = 3'd1;
            FP_SGNJX:  misc_op = 3'd2;
            FP_FCLASS: misc_op = 3'd3;
            default:   misc_op = 3'd0;
        endcase
    end

    // -----------------------------------------------------------------------
    // Subunit instantiations
    // -----------------------------------------------------------------------

    // 1. fp_add -- handles FP_ADD and FP_SUB
    fp_add u_fp_add (
        .clk       (clk),
        .rst       (rst),
        .start     (add_start),
        .rm        (rm),
        .is_sub    (add_is_sub),
        .a         (fp_a),
        .b         (fp_b),
        .result    (add_result),
        .done      (add_done),
        .busy      (add_busy),
        .flags     (add_flags)
    );

    // 2. fp_mul -- handles FP_MUL
    fp_mul u_fp_mul (
        .clk       (clk),
        .rst       (rst),
        .start     (mul_start),
        .rm        (rm),
        .a         (fp_a),
        .b         (fp_b),
        .result    (mul_result),
        .done      (mul_done),
        .busy      (mul_busy),
        .flags     (mul_flags)
    );

    // 3. fp_fma -- handles FMADD, FMSUB, FNMSUB, FNMADD
    fp_fma u_fp_fma (
        .clk       (clk),
        .rst       (rst),
        .start     (fma_start),
        .rm        (rm),
        .op        (fma_op),
        .a         (fp_a),
        .b         (fp_b),
        .c         (fp_c),
        .result    (fma_result),
        .done      (fma_done),
        .busy      (fma_busy),
        .flags     (fma_flags)
    );

    // 4. fp_div -- handles FP_DIV
    fp_div u_fp_div (
        .clk       (clk),
        .rst       (rst),
        .start     (div_start),
        .rm        (rm),
        .a         (fp_a),
        .b         (fp_b),
        .result    (div_result),
        .done      (div_done),
        .busy      (div_busy),
        .flags     (div_flags)
    );

    // 5. fp_sqrt -- handles FP_SQRT
    fp_sqrt u_fp_sqrt (
        .clk       (clk),
        .rst       (rst),
        .start     (sqrt_start),
        .rm        (rm),
        .a         (fp_a),
        .result    (sqrt_result),
        .done      (sqrt_done),
        .busy      (sqrt_busy),
        .flags     (sqrt_flags)
    );

    // 6. fp_cmp -- combinational, handles FEQ, FLT, FLE, MIN, MAX
    fp_cmp u_fp_cmp (
        .op             (cmp_op),
        .a              (fp_a),
        .b              (fp_b),
        .result         (cmp_result),
        .flags          (cmp_flags),
        .result_is_int  (cmp_result_is_int)
    );

    // 7. fp_conv -- handles all FCVT and FMV instructions
    fp_conv u_fp_conv (
        .clk            (clk),
        .rst            (rst),
        .start          (conv_start),
        .rm             (rm),
        .op             (conv_op),
        .fp_in          (fp_a),
        .int_in         (int_src),
        .result         (conv_result),
        .done           (conv_done),
        .busy           (conv_busy),
        .flags          (conv_flags),
        .result_is_int  (conv_result_is_int)
    );

    // 8. fp_misc -- combinational, handles SGNJ, SGNJN, SGNJX, FCLASS
    fp_misc u_fp_misc (
        .op             (misc_op),
        .a              (fp_a),
        .b              (fp_b),
        .result         (misc_result),
        .result_is_int  (misc_result_is_int)
    );

    // -----------------------------------------------------------------------
    // Active-unit register
    // Tracks which multicycle subunit was started so we know whose done/result
    // to forward. Cleared when that unit asserts done.
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            active_unit <= UNIT_NONE;
        end else if (start && !op_is_combinational) begin
            // Latch which multicycle unit is being started
            if (op_is_add)       active_unit <= UNIT_ADD;
            else if (op_is_mul)  active_unit <= UNIT_MUL;
            else if (op_is_fma)  active_unit <= UNIT_FMA;
            else if (op_is_div)  active_unit <= UNIT_DIV;
            else if (op_is_sqrt) active_unit <= UNIT_SQRT;
            else if (op_is_conv) active_unit <= UNIT_CONV;
            else                 active_unit <= UNIT_NONE;
        end else if (done) begin
            active_unit <= UNIT_NONE;
        end
    end

    // -----------------------------------------------------------------------
    // Combinational op detection (registered for one cycle so we can output
    // done in the same cycle as start for combinational ops)
    // -----------------------------------------------------------------------
    // For combinational ops, done = start (same cycle).
    // We also need to remember if the current cycle is a combinational start
    // so the output mux selects the right source.
    wire comb_active = start & op_is_combinational;

    // -----------------------------------------------------------------------
    // Busy: high if any multicycle subunit is busy
    // -----------------------------------------------------------------------
    assign busy = add_busy | mul_busy | fma_busy | div_busy | sqrt_busy | conv_busy;

    // -----------------------------------------------------------------------
    // Done: combinational ops complete immediately; multicycle ops signal done
    // -----------------------------------------------------------------------
    reg multicycle_done;
    always @(*) begin
        case (active_unit)
            UNIT_ADD:  multicycle_done = add_done;
            UNIT_MUL:  multicycle_done = mul_done;
            UNIT_FMA:  multicycle_done = fma_done;
            UNIT_DIV:  multicycle_done = div_done;
            UNIT_SQRT: multicycle_done = sqrt_done;
            UNIT_CONV: multicycle_done = conv_done;
            default:   multicycle_done = 1'b0;
        endcase
    end

    assign done = comb_active | multicycle_done;

    // -----------------------------------------------------------------------
    // Result mux
    // -----------------------------------------------------------------------
    reg [63:0] result_mux;
    reg [4:0]  flags_mux;
    reg        rint_mux;

    always @(*) begin
        // Defaults
        result_mux = 64'd0;
        flags_mux  = 5'd0;
        rint_mux   = 1'b0;

        if (comb_active) begin
            // Combinational path -- select based on current fp_op
            if (op_is_cmp) begin
                result_mux = cmp_result;
                flags_mux  = cmp_flags;
                rint_mux   = cmp_result_is_int;
            end else if (op_is_misc) begin
                result_mux = misc_result;
                flags_mux  = misc_flags;
                rint_mux   = misc_result_is_int;
            end
        end else begin
            // Multicycle path -- select based on registered active_unit
            case (active_unit)
                UNIT_ADD: begin
                    result_mux = add_result;
                    flags_mux  = add_flags;
                    rint_mux   = 1'b0;
                end
                UNIT_MUL: begin
                    result_mux = mul_result;
                    flags_mux  = mul_flags;
                    rint_mux   = 1'b0;
                end
                UNIT_FMA: begin
                    result_mux = fma_result;
                    flags_mux  = fma_flags;
                    rint_mux   = 1'b0;
                end
                UNIT_DIV: begin
                    result_mux = div_result;
                    flags_mux  = div_flags;
                    rint_mux   = 1'b0;
                end
                UNIT_SQRT: begin
                    result_mux = sqrt_result;
                    flags_mux  = sqrt_flags;
                    rint_mux   = 1'b0;
                end
                UNIT_CONV: begin
                    result_mux = conv_result;
                    flags_mux  = conv_flags;
                    rint_mux   = conv_result_is_int;
                end
                default: begin
                    result_mux = 64'd0;
                    flags_mux  = 5'd0;
                    rint_mux   = 1'b0;
                end
            endcase
        end
    end

    assign fp_result    = result_mux;
    assign fp_flags     = flags_mux;
    assign result_is_int = rint_mux;

endmodule
