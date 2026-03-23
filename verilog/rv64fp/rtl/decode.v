// ============================================================================
// decode.v - Instruction Decode (ID) Stage
// RV64IFD 5-Stage Pipeline
// Integer regfile + FP regfile + immediate gen + control decode + forwarding
// Target: Vivado 2020.2
// ============================================================================

module decode (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_id,
    input  wire        flush_id,
    input  wire [31:0] instr,
    input  wire [63:0] ifid_pc,
    input  wire        ifid_valid,

    // FCSR rounding mode
    input  wire [2:0]  fcsr_frm,

    // Writeback from WB stage
    input  wire [4:0]  wb_rd,
    input  wire [63:0] wb_data,
    input  wire        wb_reg_we,
    input  wire        wb_fp_reg_we,
    input  wire [63:0] wb_fp_data,

    // Forwarding selects from hazard unit
    input  wire [1:0]  fwd_rs1_sel,
    input  wire [1:0]  fwd_rs2_sel,
    input  wire [1:0]  fwd_fp_rs1_sel,
    input  wire [1:0]  fwd_fp_rs2_sel,
    input  wire [1:0]  fwd_fp_rs3_sel,

    // Forwarded data from EX (combinational), EX/MEM, and MEM/WB
    input  wire [63:0] ex_result,        // combinational from EX stage
    input  wire [63:0] exmem_result,
    input  wire [63:0] memwb_result,
    input  wire [63:0] ex_fp_result,     // combinational FP from EX stage
    input  wire [63:0] exmem_fp_result,
    input  wire [63:0] memwb_fp_result,

    // Outputs for hazard unit
    output wire [4:0]  id_rs1_addr,
    output wire [4:0]  id_rs2_addr,
    output wire        id_rs1_used,
    output wire        id_rs2_used,
    output wire [4:0]  id_fp_rs1_addr,
    output wire [4:0]  id_fp_rs2_addr,
    output wire [4:0]  id_fp_rs3_addr,
    output wire        id_fp_rs1_used,
    output wire        id_fp_rs2_used,
    output wire        id_fp_rs3_used,

    // ID/EX pipeline outputs
    output reg  [63:0] idex_rs1_data,
    output reg  [63:0] idex_rs2_data,
    output reg  [63:0] idex_imm,
    output reg  [63:0] idex_pc,
    output reg  [63:0] idex_fp_rs1_data,
    output reg  [63:0] idex_fp_rs2_data,
    output reg  [63:0] idex_fp_rs3_data,
    output reg  [4:0]  idex_rd,
    output reg  [4:0]  idex_alu_op,
    output reg         idex_alu_src,
    output reg         idex_alu_a_sel,
    output reg         idex_reg_we,
    output reg         idex_fp_reg_we,
    output reg         idex_mem_we,
    output reg         idex_mem_re,
    output reg  [3:0]  idex_branch_op,
    output reg  [2:0]  idex_wb_sel,
    output reg  [1:0]  idex_mem_size,
    output reg         idex_mem_unsigned,
    output reg         idex_valid,
    output reg         idex_fp_en,
    output reg  [4:0]  idex_fp_op,
    output reg  [2:0]  idex_fp_rm,
    output reg         idex_is_fp_load,
    output reg         idex_is_fp_store
);

    // ========================================================================
    // Constants
    // ========================================================================

    // ALU operations (5-bit)
    localparam [4:0] ADD   = 5'd0,  SUB  = 5'd1,  AND  = 5'd2,  OR   = 5'd3,
                     XOR   = 5'd4,  SLL  = 5'd5,  SRL  = 5'd6,  SRA  = 5'd7,
                     SLT   = 5'd8,  SLTU = 5'd9,  PASS_B = 5'd10,
                     ADDW  = 5'd16, SUBW = 5'd17, SLLW = 5'd21, SRLW = 5'd22,
                     SRAW  = 5'd23;

    // Immediate types
    localparam [2:0] IMM_I = 3'd0, IMM_S = 3'd1, IMM_B = 3'd2,
                     IMM_U = 3'd3, IMM_J = 3'd4;

    // Branch operations (4-bit)
    localparam [3:0] BR_NONE = 4'd0, BR_BEQ  = 4'd1, BR_BNE  = 4'd2,
                     BR_JAL  = 4'd3, BR_JALR = 4'd4, BR_BLT  = 4'd5,
                     BR_BGE  = 4'd6, BR_BLTU = 4'd7, BR_BGEU = 4'd8;

    // Writeback select (3-bit)
    localparam [2:0] WB_ALU = 3'd0, WB_MEM = 3'd1, WB_PC4 = 3'd2, WB_FPU = 3'd3;

    // Opcodes
    localparam [6:0] OP_RTYPE  = 7'b0110011, OP_ITYPE  = 7'b0010011,
                     OP_LOAD   = 7'b0000011, OP_STORE  = 7'b0100011,
                     OP_LUI    = 7'b0110111, OP_AUIPC  = 7'b0010111,
                     OP_JAL    = 7'b1101111, OP_JALR   = 7'b1100111,
                     OP_BRANCH = 7'b1100011, OP_RW     = 7'b0111011,
                     OP_IW     = 7'b0011011;

    // FP opcodes
    localparam [6:0] OP_FP_LOAD  = 7'b0000111, OP_FP_STORE = 7'b0100111,
                     OP_FP_OP    = 7'b1010011, OP_FP_MADD  = 7'b1000011,
                     OP_FP_MSUB  = 7'b1000111, OP_FP_NMSUB = 7'b1001011,
                     OP_FP_NMADD = 7'b1001111;

    // FP operation codes (match fpu_top.v)
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

    // ========================================================================
    // Instruction field extraction
    // ========================================================================
    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [6:0]  funct7 = instr[31:25];
    wire [4:0]  rs3    = instr[31:27];  // for FP fused ops

    // ========================================================================
    // Integer Register File (32 x 64-bit, x0 hardwired to 0)
    // ========================================================================
    reg [63:0] int_regfile [0:31];

    // Synchronous write
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                int_regfile[i] <= 64'd0;
        end else if (wb_reg_we && (wb_rd != 5'd0)) begin
            int_regfile[wb_rd] <= wb_data;
        end
    end

    // Combinational read
    wire [63:0] rs1_raw = (rs1 == 5'd0) ? 64'd0 : int_regfile[rs1];
    wire [63:0] rs2_raw = (rs2 == 5'd0) ? 64'd0 : int_regfile[rs2];

    // ========================================================================
    // FP Register File (32 x 64-bit, f0 NOT hardwired)
    // ========================================================================
    reg [63:0] fp_regfile [0:31];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                fp_regfile[i] <= 64'd0;
        end else if (wb_fp_reg_we) begin
            fp_regfile[wb_rd] <= wb_fp_data;
        end
    end

    // Combinational read
    wire [63:0] fp_rs1_raw = fp_regfile[rs1];
    wire [63:0] fp_rs2_raw = fp_regfile[rs2];
    wire [63:0] fp_rs3_raw = fp_regfile[rs3];

    // ========================================================================
    // Immediate Generator
    // ========================================================================
    reg [2:0] imm_type;
    reg [63:0] imm_val;

    always @(*) begin
        imm_val = 64'd0;
        case (imm_type)
            IMM_I: imm_val = {{52{instr[31]}}, instr[31:20]};
            IMM_S: imm_val = {{52{instr[31]}}, instr[31:25], instr[11:7]};
            IMM_B: imm_val = {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            IMM_U: imm_val = {{32{instr[31]}}, instr[31:12], 12'd0};
            IMM_J: imm_val = {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default: imm_val = 64'd0;
        endcase
    end

    // ========================================================================
    // Control Decode
    // ========================================================================
    reg [4:0]  ctrl_alu_op;
    reg        ctrl_alu_src;      // 0=rs2, 1=imm
    reg        ctrl_alu_a_sel;    // 0=rs1, 1=PC (AUIPC)
    reg        ctrl_reg_we;
    reg        ctrl_fp_reg_we;
    reg        ctrl_mem_we;
    reg        ctrl_mem_re;
    reg [3:0]  ctrl_branch_op;
    reg [2:0]  ctrl_wb_sel;
    reg [1:0]  ctrl_mem_size;
    reg        ctrl_mem_unsigned;
    reg        ctrl_rs1_used;
    reg        ctrl_rs2_used;
    reg        ctrl_fp_rs1_used;
    reg        ctrl_fp_rs2_used;
    reg        ctrl_fp_rs3_used;
    reg        ctrl_fp_en;
    reg [4:0]  ctrl_fp_op;
    reg [2:0]  ctrl_fp_rm;
    reg        ctrl_is_fp_load;
    reg        ctrl_is_fp_store;

    always @(*) begin
        // Defaults
        ctrl_alu_op      = ADD;
        ctrl_alu_src     = 1'b0;
        ctrl_alu_a_sel   = 1'b0;
        ctrl_reg_we      = 1'b0;
        ctrl_fp_reg_we   = 1'b0;
        ctrl_mem_we      = 1'b0;
        ctrl_mem_re      = 1'b0;
        ctrl_branch_op   = BR_NONE;
        ctrl_wb_sel      = WB_ALU;
        ctrl_mem_size    = 2'b11;
        ctrl_mem_unsigned = 1'b0;
        imm_type         = IMM_I;
        ctrl_rs1_used    = 1'b0;
        ctrl_rs2_used    = 1'b0;
        ctrl_fp_rs1_used = 1'b0;
        ctrl_fp_rs2_used = 1'b0;
        ctrl_fp_rs3_used = 1'b0;
        ctrl_fp_en       = 1'b0;
        ctrl_fp_op       = 5'd0;
        ctrl_fp_rm       = 3'd0;
        ctrl_is_fp_load  = 1'b0;
        ctrl_is_fp_store = 1'b0;

        case (opcode)
            // ----- R-type (integer) -----
            OP_RTYPE: begin
                ctrl_reg_we   = 1'b1;
                ctrl_rs1_used = 1'b1;
                ctrl_rs2_used = 1'b1;
                case (funct3)
                    3'b000: ctrl_alu_op = (funct7[5]) ? SUB : ADD;
                    3'b001: ctrl_alu_op = SLL;
                    3'b010: ctrl_alu_op = SLT;
                    3'b011: ctrl_alu_op = SLTU;
                    3'b100: ctrl_alu_op = XOR;
                    3'b101: ctrl_alu_op = (funct7[5]) ? SRA : SRL;
                    3'b110: ctrl_alu_op = OR;
                    3'b111: ctrl_alu_op = AND;
                    default: ctrl_alu_op = ADD;
                endcase
            end

            // ----- I-type (integer) -----
            OP_ITYPE: begin
                ctrl_reg_we   = 1'b1;
                ctrl_alu_src  = 1'b1;
                ctrl_rs1_used = 1'b1;
                imm_type      = IMM_I;
                case (funct3)
                    3'b000: ctrl_alu_op = ADD;
                    3'b001: ctrl_alu_op = SLL;
                    3'b010: ctrl_alu_op = SLT;
                    3'b011: ctrl_alu_op = SLTU;
                    3'b100: ctrl_alu_op = XOR;
                    3'b101: ctrl_alu_op = (funct7[5]) ? SRA : SRL;
                    3'b110: ctrl_alu_op = OR;
                    3'b111: ctrl_alu_op = AND;
                    default: ctrl_alu_op = ADD;
                endcase
            end

            // ----- LOAD -----
            OP_LOAD: begin
                ctrl_reg_we      = 1'b1;
                ctrl_alu_src     = 1'b1;
                ctrl_alu_op      = ADD;
                ctrl_mem_re      = 1'b1;
                ctrl_wb_sel      = WB_MEM;
                ctrl_rs1_used    = 1'b1;
                imm_type         = IMM_I;
                case (funct3)
                    3'b000: begin ctrl_mem_size = 2'b00; ctrl_mem_unsigned = 1'b0; end // LB
                    3'b001: begin ctrl_mem_size = 2'b01; ctrl_mem_unsigned = 1'b0; end // LH
                    3'b010: begin ctrl_mem_size = 2'b10; ctrl_mem_unsigned = 1'b0; end // LW
                    3'b011: begin ctrl_mem_size = 2'b11; ctrl_mem_unsigned = 1'b0; end // LD
                    3'b100: begin ctrl_mem_size = 2'b00; ctrl_mem_unsigned = 1'b1; end // LBU
                    3'b101: begin ctrl_mem_size = 2'b01; ctrl_mem_unsigned = 1'b1; end // LHU
                    3'b110: begin ctrl_mem_size = 2'b10; ctrl_mem_unsigned = 1'b1; end // LWU
                    default: begin ctrl_mem_size = 2'b11; ctrl_mem_unsigned = 1'b0; end
                endcase
            end

            // ----- STORE -----
            OP_STORE: begin
                ctrl_alu_src  = 1'b1;
                ctrl_alu_op   = ADD;
                ctrl_mem_we   = 1'b1;
                ctrl_rs1_used = 1'b1;
                ctrl_rs2_used = 1'b1;
                imm_type      = IMM_S;
                case (funct3)
                    3'b000: ctrl_mem_size = 2'b00; // SB
                    3'b001: ctrl_mem_size = 2'b01; // SH
                    3'b010: ctrl_mem_size = 2'b10; // SW
                    3'b011: ctrl_mem_size = 2'b11; // SD
                    default: ctrl_mem_size = 2'b11;
                endcase
            end

            // ----- LUI -----
            OP_LUI: begin
                ctrl_reg_we  = 1'b1;
                ctrl_alu_op  = PASS_B;
                ctrl_alu_src = 1'b1;
                imm_type     = IMM_U;
            end

            // ----- AUIPC -----
            OP_AUIPC: begin
                ctrl_reg_we    = 1'b1;
                ctrl_alu_op    = ADD;
                ctrl_alu_src   = 1'b1;
                ctrl_alu_a_sel = 1'b1;
                imm_type       = IMM_U;
            end

            // ----- JAL -----
            OP_JAL: begin
                ctrl_reg_we    = 1'b1;
                ctrl_branch_op = BR_JAL;
                ctrl_wb_sel    = WB_PC4;
                ctrl_alu_op    = ADD;
                ctrl_alu_a_sel = 1'b1;
                ctrl_alu_src   = 1'b1;
                imm_type       = IMM_J;
            end

            // ----- JALR -----
            OP_JALR: begin
                ctrl_reg_we    = 1'b1;
                ctrl_branch_op = BR_JALR;
                ctrl_wb_sel    = WB_PC4;
                ctrl_alu_op    = ADD;
                ctrl_alu_a_sel = 1'b1;
                ctrl_alu_src   = 1'b1;
                ctrl_rs1_used  = 1'b1;
                imm_type       = IMM_I;
            end

            // ----- BRANCH -----
            OP_BRANCH: begin
                ctrl_rs1_used = 1'b1;
                ctrl_rs2_used = 1'b1;
                imm_type      = IMM_B;
                case (funct3)
                    3'b000: ctrl_branch_op = BR_BEQ;
                    3'b001: ctrl_branch_op = BR_BNE;
                    3'b100: ctrl_branch_op = BR_BLT;
                    3'b101: ctrl_branch_op = BR_BGE;
                    3'b110: ctrl_branch_op = BR_BLTU;
                    3'b111: ctrl_branch_op = BR_BGEU;
                    default: ctrl_branch_op = BR_NONE;
                endcase
            end

            // ----- RW (32-bit R-type: ADDW, SUBW, etc.) -----
            OP_RW: begin
                ctrl_reg_we   = 1'b1;
                ctrl_rs1_used = 1'b1;
                ctrl_rs2_used = 1'b1;
                case (funct3)
                    3'b000: ctrl_alu_op = (funct7[5]) ? SUBW : ADDW;
                    3'b001: ctrl_alu_op = SLLW;
                    3'b101: ctrl_alu_op = (funct7[5]) ? SRAW : SRLW;
                    default: ctrl_alu_op = ADDW;
                endcase
            end

            // ----- IW (32-bit I-type: ADDIW, SLLIW, SRLIW, SRAIW) -----
            OP_IW: begin
                ctrl_reg_we   = 1'b1;
                ctrl_alu_src  = 1'b1;
                ctrl_rs1_used = 1'b1;
                imm_type      = IMM_I;
                case (funct3)
                    3'b000: ctrl_alu_op = ADDW;
                    3'b001: ctrl_alu_op = SLLW;
                    3'b101: ctrl_alu_op = (funct7[5]) ? SRAW : SRLW;
                    default: ctrl_alu_op = ADDW;
                endcase
            end

            // ----- FP LOAD (FLD) -----
            OP_FP_LOAD: begin
                ctrl_alu_src    = 1'b1;
                ctrl_alu_op     = ADD;
                ctrl_mem_re     = 1'b1;
                ctrl_wb_sel     = WB_MEM;
                ctrl_rs1_used   = 1'b1;
                ctrl_is_fp_load = 1'b1;
                ctrl_fp_reg_we  = 1'b1;  // write to FP rd
                ctrl_reg_we     = 1'b0;  // NOT integer rd
                ctrl_mem_size   = 2'b11; // doubleword
                imm_type        = IMM_I;
            end

            // ----- FP STORE (FSD) -----
            OP_FP_STORE: begin
                ctrl_alu_src     = 1'b1;
                ctrl_alu_op      = ADD;
                ctrl_mem_we      = 1'b1;
                ctrl_rs1_used    = 1'b1;
                ctrl_fp_rs2_used = 1'b1;
                ctrl_is_fp_store = 1'b1;
                ctrl_mem_size    = 2'b11; // doubleword
                imm_type         = IMM_S;
            end

            // ----- FP OP (all OP-FP arithmetic) -----
            OP_FP_OP: begin
                ctrl_fp_en       = 1'b1;
                ctrl_wb_sel      = WB_FPU;
                // Resolve rounding mode: DYN (3'b111) uses FCSR.frm
                ctrl_fp_rm       = (funct3 == 3'b111) ? fcsr_frm : funct3;
                ctrl_fp_rs1_used = 1'b1;
                ctrl_fp_rs2_used = 1'b1;

                case (funct7[6:2])
                    5'b00000: begin // FADD.D (funct7=0000001)
                        ctrl_fp_op     = FP_ADD;
                        ctrl_fp_reg_we = 1'b1;
                    end
                    5'b00001: begin // FSUB.D (funct7=0000101)
                        ctrl_fp_op     = FP_SUB;
                        ctrl_fp_reg_we = 1'b1;
                    end
                    5'b00010: begin // FMUL.D (funct7=0001001)
                        ctrl_fp_op     = FP_MUL;
                        ctrl_fp_reg_we = 1'b1;
                    end
                    5'b00011: begin // FDIV.D (funct7=0001101)
                        ctrl_fp_op     = FP_DIV;
                        ctrl_fp_reg_we = 1'b1;
                    end
                    5'b01011: begin // FSQRT.D (funct7=0101101)
                        ctrl_fp_op       = FP_SQRT;
                        ctrl_fp_reg_we   = 1'b1;
                        ctrl_fp_rs2_used = 1'b0; // rs2 unused (must be 00000)
                    end
                    5'b00100: begin // FSGNJ.D / FSGNJN.D / FSGNJX.D (funct7=0010001)
                        ctrl_fp_reg_we = 1'b1;
                        case (funct3)
                            3'b000: ctrl_fp_op = FP_SGNJ;
                            3'b001: ctrl_fp_op = FP_SGNJN;
                            3'b010: ctrl_fp_op = FP_SGNJX;
                            default: ctrl_fp_op = FP_SGNJ;
                        endcase
                    end
                    5'b00101: begin // FMIN.D / FMAX.D (funct7=0010101)
                        ctrl_fp_reg_we = 1'b1;
                        case (funct3)
                            3'b000: ctrl_fp_op = FP_MIN;
                            3'b001: ctrl_fp_op = FP_MAX;
                            default: ctrl_fp_op = FP_MIN;
                        endcase
                    end
                    5'b10100: begin // FEQ.D / FLT.D / FLE.D (funct7=1010001)
                        ctrl_reg_we    = 1'b1;  // integer rd
                        ctrl_fp_reg_we = 1'b0;
                        case (funct3)
                            3'b010: ctrl_fp_op = FP_FEQ;
                            3'b001: ctrl_fp_op = FP_FLT;
                            3'b000: ctrl_fp_op = FP_FLE;
                            default: ctrl_fp_op = FP_FEQ;
                        endcase
                    end
                    5'b11000: begin // FCVT.W.D / WU / L / LU (funct7=1100001)
                        ctrl_reg_we      = 1'b1;  // integer rd
                        ctrl_fp_reg_we   = 1'b0;
                        ctrl_fp_rs2_used = 1'b0;
                        case (rs2)
                            5'b00000: ctrl_fp_op = FP_CVTWD;
                            5'b00001: ctrl_fp_op = FP_CVTWUD;
                            5'b00010: ctrl_fp_op = FP_CVTLD;
                            5'b00011: ctrl_fp_op = FP_CVTLUD;
                            default:  ctrl_fp_op = FP_CVTWD;
                        endcase
                    end
                    5'b11010: begin // FCVT.D.W / WU / L / LU (funct7=1101001)
                        ctrl_fp_reg_we   = 1'b1;  // FP rd
                        ctrl_fp_rs1_used = 1'b0;  // source is integer rs1
                        ctrl_fp_rs2_used = 1'b0;
                        ctrl_rs1_used    = 1'b1;  // integer rs1 source
                        case (rs2)
                            5'b00000: ctrl_fp_op = FP_CVTDW;
                            5'b00001: ctrl_fp_op = FP_CVTDWU;
                            5'b00010: ctrl_fp_op = FP_CVTDL;
                            5'b00011: ctrl_fp_op = FP_CVTDLU;
                            default:  ctrl_fp_op = FP_CVTDW;
                        endcase
                    end
                    5'b11100: begin // FMV.X.D or FCLASS.D (funct7=1110001)
                        ctrl_reg_we      = 1'b1;  // integer rd
                        ctrl_fp_reg_we   = 1'b0;
                        ctrl_fp_rs2_used = 1'b0;
                        case (funct3)
                            3'b000: ctrl_fp_op = FP_MVXD;   // FMV.X.D
                            3'b001: ctrl_fp_op = FP_FCLASS;  // FCLASS.D
                            default: ctrl_fp_op = FP_MVXD;
                        endcase
                    end
                    5'b11110: begin // FMV.D.X (funct7=1111001)
                        ctrl_fp_reg_we   = 1'b1;  // FP rd
                        ctrl_fp_rs1_used = 1'b0;  // source is integer rs1
                        ctrl_fp_rs2_used = 1'b0;
                        ctrl_rs1_used    = 1'b1;  // integer rs1 source
                        ctrl_fp_op       = FP_MVDX;
                    end
                    default: begin
                        ctrl_fp_en = 1'b0; // Unknown FP op
                    end
                endcase
            end

            // ----- FP FUSED (FMADD, FMSUB, FNMSUB, FNMADD) -----
            OP_FP_MADD: begin
                ctrl_fp_en       = 1'b1;
                ctrl_fp_op       = FP_FMADD;
                ctrl_fp_rm       = (funct3 == 3'b111) ? fcsr_frm : funct3;
                ctrl_fp_rs1_used = 1'b1;
                ctrl_fp_rs2_used = 1'b1;
                ctrl_fp_rs3_used = 1'b1;
                ctrl_fp_reg_we   = 1'b1;
                ctrl_wb_sel      = WB_FPU;
            end
            OP_FP_MSUB: begin
                ctrl_fp_en       = 1'b1;
                ctrl_fp_op       = FP_FMSUB;
                ctrl_fp_rm       = (funct3 == 3'b111) ? fcsr_frm : funct3;
                ctrl_fp_rs1_used = 1'b1;
                ctrl_fp_rs2_used = 1'b1;
                ctrl_fp_rs3_used = 1'b1;
                ctrl_fp_reg_we   = 1'b1;
                ctrl_wb_sel      = WB_FPU;
            end
            OP_FP_NMSUB: begin
                ctrl_fp_en       = 1'b1;
                ctrl_fp_op       = FP_FNMSUB;
                ctrl_fp_rm       = (funct3 == 3'b111) ? fcsr_frm : funct3;
                ctrl_fp_rs1_used = 1'b1;
                ctrl_fp_rs2_used = 1'b1;
                ctrl_fp_rs3_used = 1'b1;
                ctrl_fp_reg_we   = 1'b1;
                ctrl_wb_sel      = WB_FPU;
            end
            OP_FP_NMADD: begin
                ctrl_fp_en       = 1'b1;
                ctrl_fp_op       = FP_FNMADD;
                ctrl_fp_rm       = (funct3 == 3'b111) ? fcsr_frm : funct3;
                ctrl_fp_rs1_used = 1'b1;
                ctrl_fp_rs2_used = 1'b1;
                ctrl_fp_rs3_used = 1'b1;
                ctrl_fp_reg_we   = 1'b1;
                ctrl_wb_sel      = WB_FPU;
            end

            default: begin
                // Unknown opcode: NOP (all defaults)
            end
        endcase
    end

    // ========================================================================
    // Hazard unit source address outputs
    // ========================================================================
    assign id_rs1_addr    = rs1;
    assign id_rs2_addr    = rs2;
    assign id_rs1_used    = ctrl_rs1_used & ifid_valid;
    assign id_rs2_used    = ctrl_rs2_used & ifid_valid;
    assign id_fp_rs1_addr = rs1;
    assign id_fp_rs2_addr = rs2;
    assign id_fp_rs3_addr = rs3;
    assign id_fp_rs1_used = ctrl_fp_rs1_used & ifid_valid;
    assign id_fp_rs2_used = ctrl_fp_rs2_used & ifid_valid;
    assign id_fp_rs3_used = ctrl_fp_rs3_used & ifid_valid;

    // ========================================================================
    // Forwarding Muxes (integer)
    // 00=regfile, 01=EX(comb), 10=EX/MEM, 11=MEM/WB
    // ========================================================================
    reg [63:0] rs1_fwd, rs2_fwd;

    always @(*) begin
        case (fwd_rs1_sel)
            2'd0:    rs1_fwd = rs1_raw;
            2'd1:    rs1_fwd = ex_result;
            2'd2:    rs1_fwd = exmem_result;
            2'd3:    rs1_fwd = memwb_result;
            default: rs1_fwd = rs1_raw;
        endcase
    end

    always @(*) begin
        case (fwd_rs2_sel)
            2'd0:    rs2_fwd = rs2_raw;
            2'd1:    rs2_fwd = ex_result;
            2'd2:    rs2_fwd = exmem_result;
            2'd3:    rs2_fwd = memwb_result;
            default: rs2_fwd = rs2_raw;
        endcase
    end

    // ========================================================================
    // Forwarding Muxes (FP)
    // 00=regfile, 01=EX(comb), 10=EX/MEM, 11=MEM/WB
    // ========================================================================
    reg [63:0] fp_rs1_fwd, fp_rs2_fwd, fp_rs3_fwd;

    always @(*) begin
        case (fwd_fp_rs1_sel)
            2'd0:    fp_rs1_fwd = fp_rs1_raw;
            2'd1:    fp_rs1_fwd = ex_fp_result;
            2'd2:    fp_rs1_fwd = exmem_fp_result;
            2'd3:    fp_rs1_fwd = memwb_fp_result;
            default: fp_rs1_fwd = fp_rs1_raw;
        endcase
    end

    always @(*) begin
        case (fwd_fp_rs2_sel)
            2'd0:    fp_rs2_fwd = fp_rs2_raw;
            2'd1:    fp_rs2_fwd = ex_fp_result;
            2'd2:    fp_rs2_fwd = exmem_fp_result;
            2'd3:    fp_rs2_fwd = memwb_fp_result;
            default: fp_rs2_fwd = fp_rs2_raw;
        endcase
    end

    always @(*) begin
        case (fwd_fp_rs3_sel)
            2'd0:    fp_rs3_fwd = fp_rs3_raw;
            2'd1:    fp_rs3_fwd = ex_fp_result;
            2'd2:    fp_rs3_fwd = exmem_fp_result;
            2'd3:    fp_rs3_fwd = memwb_fp_result;
            default: fp_rs3_fwd = fp_rs3_raw;
        endcase
    end

    // ========================================================================
    // ID/EX Pipeline Register
    // ========================================================================
    always @(posedge clk) begin
        if (rst || flush_id) begin
            idex_rs1_data    <= 64'd0;
            idex_rs2_data    <= 64'd0;
            idex_imm         <= 64'd0;
            idex_pc          <= 64'd0;
            idex_fp_rs1_data <= 64'd0;
            idex_fp_rs2_data <= 64'd0;
            idex_fp_rs3_data <= 64'd0;
            idex_rd          <= 5'd0;
            idex_alu_op      <= 5'd0;
            idex_alu_src     <= 1'b0;
            idex_alu_a_sel   <= 1'b0;
            idex_reg_we      <= 1'b0;
            idex_fp_reg_we   <= 1'b0;
            idex_mem_we      <= 1'b0;
            idex_mem_re      <= 1'b0;
            idex_branch_op   <= 4'd0;
            idex_wb_sel      <= 3'd0;
            idex_mem_size    <= 2'd0;
            idex_mem_unsigned <= 1'b0;
            idex_valid       <= 1'b0;
            idex_fp_en       <= 1'b0;
            idex_fp_op       <= 5'd0;
            idex_fp_rm       <= 3'd0;
            idex_is_fp_load  <= 1'b0;
            idex_is_fp_store <= 1'b0;
        end else if (!stall_id) begin
            if (ifid_valid) begin
                idex_rs1_data    <= rs1_fwd;
                idex_rs2_data    <= rs2_fwd;
                idex_imm         <= imm_val;
                idex_pc          <= ifid_pc;
                idex_fp_rs1_data <= fp_rs1_fwd;
                idex_fp_rs2_data <= fp_rs2_fwd;
                idex_fp_rs3_data <= fp_rs3_fwd;
                idex_rd          <= rd;
                idex_alu_op      <= ctrl_alu_op;
                idex_alu_src     <= ctrl_alu_src;
                idex_alu_a_sel   <= ctrl_alu_a_sel;
                idex_reg_we      <= ctrl_reg_we;
                idex_fp_reg_we   <= ctrl_fp_reg_we;
                idex_mem_we      <= ctrl_mem_we;
                idex_mem_re      <= ctrl_mem_re;
                idex_branch_op   <= ctrl_branch_op;
                idex_wb_sel      <= ctrl_wb_sel;
                idex_mem_size    <= ctrl_mem_size;
                idex_mem_unsigned <= ctrl_mem_unsigned;
                idex_valid       <= 1'b1;
                idex_fp_en       <= ctrl_fp_en;
                idex_fp_op       <= ctrl_fp_op;
                idex_fp_rm       <= ctrl_fp_rm;
                idex_is_fp_load  <= ctrl_is_fp_load;
                idex_is_fp_store <= ctrl_is_fp_store;
            end else begin
                // Insert bubble
                idex_reg_we      <= 1'b0;
                idex_fp_reg_we   <= 1'b0;
                idex_mem_we      <= 1'b0;
                idex_mem_re      <= 1'b0;
                idex_branch_op   <= BR_NONE;
                idex_valid       <= 1'b0;
                idex_fp_en       <= 1'b0;
                idex_is_fp_load  <= 1'b0;
                idex_is_fp_store <= 1'b0;
            end
        end
        // stall_id: hold current values
    end

endmodule
