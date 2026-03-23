// =============================================================================
// decode.v — DE stage for 3-stage RV64I pipeline
// Full RV64I control decode, register file, immediate generation
// Vivado 2020.2 compatible
// =============================================================================

module decode (
    input        clk,
    input        rst,
    input        stall,
    input        flush,
    input [31:0] instr,
    input [63:0] ifde_pc,
    input        ifde_valid,
    // Writeback port
    input  [4:0]  wb_rd,
    input  [63:0] wb_data,
    input         wb_we,
    // DE/EX pipeline outputs
    output reg [63:0] deex_rs1_data,
    output reg [63:0] deex_rs2_data,
    output reg [63:0] deex_imm,
    output reg [63:0] deex_pc,
    output reg  [4:0] deex_rd,
    output reg  [4:0] deex_alu_op,
    output reg        deex_alu_src,      // 0=rs2, 1=imm
    output reg        deex_alu_a_sel,    // 0=rs1, 1=PC (AUIPC)
    output reg        deex_reg_we,
    output reg        deex_mem_we,
    output reg        deex_mem_re,
    output reg  [3:0] deex_branch_op,
    output reg  [1:0] deex_wb_sel,
    output reg  [1:0] deex_mem_size,
    output reg        deex_mem_unsigned,
    output reg        deex_valid
);

    // =========================================================================
    // Local parameters
    // =========================================================================

    // ALU ops (5-bit)
    localparam ALU_ADD   = 5'b00000;
    localparam ALU_SUB   = 5'b00001;
    localparam ALU_AND   = 5'b00010;
    localparam ALU_OR    = 5'b00011;
    localparam ALU_XOR   = 5'b00100;
    localparam ALU_SLL   = 5'b00101;
    localparam ALU_SRL   = 5'b00110;
    localparam ALU_SRA   = 5'b00111;
    localparam ALU_SLT   = 5'b01000;
    localparam ALU_SLTU  = 5'b01001;
    localparam ALU_PASS_B = 5'b01010;
    localparam ALU_ADDW  = 5'b10000;
    localparam ALU_SUBW  = 5'b10001;
    localparam ALU_SLLW  = 5'b10101;
    localparam ALU_SRLW  = 5'b10110;
    localparam ALU_SRAW  = 5'b10111;

    // Immediate types (3-bit)
    localparam IMM_I = 3'd0;
    localparam IMM_S = 3'd1;
    localparam IMM_B = 3'd2;
    localparam IMM_U = 3'd3;
    localparam IMM_J = 3'd4;

    // Branch ops (4-bit)
    localparam BR_NONE = 4'd0;
    localparam BR_BEQ  = 4'd1;
    localparam BR_BNE  = 4'd2;
    localparam BR_JAL  = 4'd3;
    localparam BR_JALR = 4'd4;
    localparam BR_BLT  = 4'd5;
    localparam BR_BGE  = 4'd6;
    localparam BR_BLTU = 4'd7;
    localparam BR_BGEU = 4'd8;

    // WB select (2-bit)
    localparam WB_ALU = 2'd0;
    localparam WB_MEM = 2'd1;
    localparam WB_PC4 = 2'd2;

    // Opcodes (7-bit)
    localparam OP_RTYPE  = 7'b0110011;
    localparam OP_ITYPE  = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_RW     = 7'b0111011;
    localparam OP_IW     = 7'b0011011;

    // =========================================================================
    // Instruction field extraction
    // =========================================================================
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rs1_addr = instr[19:15];
    wire [4:0] rs2_addr = instr[24:20];
    wire [4:0] rd_addr  = instr[11:7];

    // =========================================================================
    // Register file (32 x 64-bit, x0 hardwired to 0)
    // =========================================================================
    reg [63:0] regfile [0:31];

    wire [63:0] rs1_data = (rs1_addr == 5'd0) ? 64'd0 : regfile[rs1_addr];
    wire [63:0] rs2_data = (rs2_addr == 5'd0) ? 64'd0 : regfile[rs2_addr];

    // Register write
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regfile[i] <= 64'd0;
        end else if (wb_we && (wb_rd != 5'd0)) begin
            regfile[wb_rd] <= wb_data;
        end
    end

    // =========================================================================
    // Immediate generator (combinational)
    // =========================================================================
    reg [2:0] imm_type;
    reg [63:0] imm_out;

    always @(*) begin
        imm_out = 64'd0; // default
        case (imm_type)
            IMM_I: imm_out = {{52{instr[31]}}, instr[31:20]};
            IMM_S: imm_out = {{52{instr[31]}}, instr[31:25], instr[11:7]};
            IMM_B: imm_out = {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            IMM_U: imm_out = {{32{instr[31]}}, instr[31:12], 12'd0};
            IMM_J: imm_out = {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default: imm_out = 64'd0;
        endcase
    end

    // =========================================================================
    // Control decode (combinational)
    // =========================================================================
    reg [4:0] ctrl_alu_op;
    reg       ctrl_alu_src;
    reg       ctrl_alu_a_sel;
    reg       ctrl_reg_we;
    reg       ctrl_mem_we;
    reg       ctrl_mem_re;
    reg [3:0] ctrl_branch_op;
    reg [1:0] ctrl_wb_sel;
    reg [1:0] ctrl_mem_size;
    reg       ctrl_mem_unsigned;

    always @(*) begin
        // Defaults (NOP)
        ctrl_alu_op      = ALU_ADD;
        ctrl_alu_src     = 1'b0;
        ctrl_alu_a_sel   = 1'b0;
        ctrl_reg_we      = 1'b0;
        ctrl_mem_we      = 1'b0;
        ctrl_mem_re      = 1'b0;
        ctrl_branch_op   = BR_NONE;
        ctrl_wb_sel      = WB_ALU;
        ctrl_mem_size    = 2'b00;
        ctrl_mem_unsigned = 1'b0;
        imm_type         = IMM_I;

        case (opcode)
            // -----------------------------------------------------------------
            // R-type (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
            // -----------------------------------------------------------------
            OP_RTYPE: begin
                ctrl_alu_src = 1'b0;
                ctrl_reg_we  = 1'b1;
                ctrl_wb_sel  = WB_ALU;
                case (funct3)
                    3'b000: ctrl_alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b001: ctrl_alu_op = ALU_SLL;
                    3'b010: ctrl_alu_op = ALU_SLT;
                    3'b011: ctrl_alu_op = ALU_SLTU;
                    3'b100: ctrl_alu_op = ALU_XOR;
                    3'b101: ctrl_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: ctrl_alu_op = ALU_OR;
                    3'b111: ctrl_alu_op = ALU_AND;
                    default: ctrl_alu_op = ALU_ADD;
                endcase
            end

            // -----------------------------------------------------------------
            // I-type ALU (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
            // -----------------------------------------------------------------
            OP_ITYPE: begin
                ctrl_alu_src = 1'b1;
                ctrl_reg_we  = 1'b1;
                ctrl_wb_sel  = WB_ALU;
                imm_type     = IMM_I;
                case (funct3)
                    3'b000: ctrl_alu_op = ALU_ADD;
                    3'b010: ctrl_alu_op = ALU_SLT;
                    3'b011: ctrl_alu_op = ALU_SLTU;
                    3'b100: ctrl_alu_op = ALU_XOR;
                    3'b110: ctrl_alu_op = ALU_OR;
                    3'b111: ctrl_alu_op = ALU_AND;
                    3'b001: ctrl_alu_op = ALU_SLL;   // SLLI (shamt=instr[25:20])
                    3'b101: ctrl_alu_op = instr[30] ? ALU_SRA : ALU_SRL;
                    default: ctrl_alu_op = ALU_ADD;
                endcase
            end

            // -----------------------------------------------------------------
            // R-type word (ADDW, SUBW, SLLW, SRLW, SRAW)
            // -----------------------------------------------------------------
            OP_RW: begin
                ctrl_alu_src = 1'b0;
                ctrl_reg_we  = 1'b1;
                ctrl_wb_sel  = WB_ALU;
                case (funct3)
                    3'b000: ctrl_alu_op = funct7[5] ? ALU_SUBW : ALU_ADDW;
                    3'b001: ctrl_alu_op = ALU_SLLW;
                    3'b101: ctrl_alu_op = funct7[5] ? ALU_SRAW : ALU_SRLW;
                    default: ctrl_alu_op = ALU_ADDW;
                endcase
            end

            // -----------------------------------------------------------------
            // I-type word (ADDIW, SLLIW, SRLIW, SRAIW)
            // -----------------------------------------------------------------
            OP_IW: begin
                ctrl_alu_src = 1'b1;
                ctrl_reg_we  = 1'b1;
                ctrl_wb_sel  = WB_ALU;
                imm_type     = IMM_I;
                case (funct3)
                    3'b000: ctrl_alu_op = ALU_ADDW;
                    3'b001: ctrl_alu_op = ALU_SLLW;
                    3'b101: ctrl_alu_op = instr[30] ? ALU_SRAW : ALU_SRLW;
                    default: ctrl_alu_op = ALU_ADDW;
                endcase
            end

            // -----------------------------------------------------------------
            // Load (LB, LH, LW, LD, LBU, LHU, LWU)
            // -----------------------------------------------------------------
            OP_LOAD: begin
                ctrl_alu_op  = ALU_ADD;
                ctrl_alu_src = 1'b1;
                ctrl_reg_we  = 1'b1;
                ctrl_mem_re  = 1'b1;
                ctrl_wb_sel  = WB_MEM;
                imm_type     = IMM_I;
                case (funct3)
                    3'b000: begin ctrl_mem_size = 2'b00; ctrl_mem_unsigned = 1'b0; end // LB
                    3'b001: begin ctrl_mem_size = 2'b01; ctrl_mem_unsigned = 1'b0; end // LH
                    3'b010: begin ctrl_mem_size = 2'b10; ctrl_mem_unsigned = 1'b0; end // LW
                    3'b011: begin ctrl_mem_size = 2'b11; ctrl_mem_unsigned = 1'b0; end // LD
                    3'b100: begin ctrl_mem_size = 2'b00; ctrl_mem_unsigned = 1'b1; end // LBU
                    3'b101: begin ctrl_mem_size = 2'b01; ctrl_mem_unsigned = 1'b1; end // LHU
                    3'b110: begin ctrl_mem_size = 2'b10; ctrl_mem_unsigned = 1'b1; end // LWU
                    default: begin ctrl_mem_size = 2'b00; ctrl_mem_unsigned = 1'b0; end
                endcase
            end

            // -----------------------------------------------------------------
            // Store (SB, SH, SW, SD)
            // -----------------------------------------------------------------
            OP_STORE: begin
                ctrl_alu_op  = ALU_ADD;
                ctrl_alu_src = 1'b1;
                ctrl_reg_we  = 1'b0;
                ctrl_mem_we  = 1'b1;
                imm_type     = IMM_S;
                case (funct3)
                    3'b000: ctrl_mem_size = 2'b00; // SB
                    3'b001: ctrl_mem_size = 2'b01; // SH
                    3'b010: ctrl_mem_size = 2'b10; // SW
                    3'b011: ctrl_mem_size = 2'b11; // SD
                    default: ctrl_mem_size = 2'b00;
                endcase
            end

            // -----------------------------------------------------------------
            // LUI
            // -----------------------------------------------------------------
            OP_LUI: begin
                ctrl_alu_op  = ALU_PASS_B;
                ctrl_alu_src = 1'b1;
                ctrl_reg_we  = 1'b1;
                ctrl_wb_sel  = WB_ALU;
                imm_type     = IMM_U;
            end

            // -----------------------------------------------------------------
            // AUIPC
            // -----------------------------------------------------------------
            OP_AUIPC: begin
                ctrl_alu_op    = ALU_ADD;
                ctrl_alu_a_sel = 1'b1;   // PC as ALU input A
                ctrl_alu_src   = 1'b1;   // imm as ALU input B
                ctrl_reg_we    = 1'b1;
                ctrl_wb_sel    = WB_ALU;
                imm_type       = IMM_U;
            end

            // -----------------------------------------------------------------
            // JAL
            // -----------------------------------------------------------------
            OP_JAL: begin
                ctrl_reg_we    = 1'b1;
                ctrl_branch_op = BR_JAL;
                ctrl_wb_sel    = WB_PC4;
                imm_type       = IMM_J;
            end

            // -----------------------------------------------------------------
            // JALR
            // -----------------------------------------------------------------
            OP_JALR: begin
                ctrl_alu_op    = ALU_ADD;
                ctrl_alu_src   = 1'b1;
                ctrl_reg_we    = 1'b1;
                ctrl_branch_op = BR_JALR;
                ctrl_wb_sel    = WB_PC4;
                imm_type       = IMM_I;
            end

            // -----------------------------------------------------------------
            // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // -----------------------------------------------------------------
            OP_BRANCH: begin
                ctrl_alu_src = 1'b0;
                ctrl_reg_we  = 1'b0;
                imm_type     = IMM_B;
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

            // -----------------------------------------------------------------
            // Default: NOP
            // -----------------------------------------------------------------
            default: begin
                ctrl_alu_op      = ALU_ADD;
                ctrl_alu_src     = 1'b0;
                ctrl_alu_a_sel   = 1'b0;
                ctrl_reg_we      = 1'b0;
                ctrl_mem_we      = 1'b0;
                ctrl_mem_re      = 1'b0;
                ctrl_branch_op   = BR_NONE;
                ctrl_wb_sel      = WB_ALU;
                ctrl_mem_size    = 2'b00;
                ctrl_mem_unsigned = 1'b0;
                imm_type         = IMM_I;
            end
        endcase
    end

    // =========================================================================
    // DE/EX pipeline register — sequential
    // =========================================================================
    always @(posedge clk) begin
        if (rst || flush) begin
            deex_rs1_data    <= 64'd0;
            deex_rs2_data    <= 64'd0;
            deex_imm         <= 64'd0;
            deex_pc          <= 64'd0;
            deex_rd          <= 5'd0;
            deex_alu_op      <= 5'd0;
            deex_alu_src     <= 1'b0;
            deex_alu_a_sel   <= 1'b0;
            deex_reg_we      <= 1'b0;
            deex_mem_we      <= 1'b0;
            deex_mem_re      <= 1'b0;
            deex_branch_op   <= 4'd0;
            deex_wb_sel      <= 2'd0;
            deex_mem_size    <= 2'd0;
            deex_mem_unsigned <= 1'b0;
            deex_valid       <= 1'b0;
        end else if (!stall) begin
            if (ifde_valid) begin
                deex_rs1_data    <= rs1_data;
                deex_rs2_data    <= rs2_data;
                deex_imm         <= imm_out;
                deex_pc          <= ifde_pc;
                deex_rd          <= rd_addr;
                deex_alu_op      <= ctrl_alu_op;
                deex_alu_src     <= ctrl_alu_src;
                deex_alu_a_sel   <= ctrl_alu_a_sel;
                deex_reg_we      <= ctrl_reg_we;
                deex_mem_we      <= ctrl_mem_we;
                deex_mem_re      <= ctrl_mem_re;
                deex_branch_op   <= ctrl_branch_op;
                deex_wb_sel      <= ctrl_wb_sel;
                deex_mem_size    <= ctrl_mem_size;
                deex_mem_unsigned <= ctrl_mem_unsigned;
                deex_valid       <= 1'b1;
            end else begin
                // Bubble: invalidate pipeline stage
                deex_rs1_data    <= 64'd0;
                deex_rs2_data    <= 64'd0;
                deex_imm         <= 64'd0;
                deex_pc          <= 64'd0;
                deex_rd          <= 5'd0;
                deex_alu_op      <= 5'd0;
                deex_alu_src     <= 1'b0;
                deex_alu_a_sel   <= 1'b0;
                deex_reg_we      <= 1'b0;
                deex_mem_we      <= 1'b0;
                deex_mem_re      <= 1'b0;
                deex_branch_op   <= 4'd0;
                deex_wb_sel      <= 2'd0;
                deex_mem_size    <= 2'd0;
                deex_mem_unsigned <= 1'b0;
                deex_valid       <= 1'b0;
            end
        end
    end

endmodule
