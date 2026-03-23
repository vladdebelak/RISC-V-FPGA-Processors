// decode.v — Stage 2: Instruction decode, register file read,
//            immediate generation, control signal generation
// 16-bit 3-stage RISC-V microcontroller

module decode (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,
    // From IF/DE pipeline register
    input  wire [31:0] instr,
    input  wire [15:0] ifde_pc,
    input  wire        ifde_valid,
    // Writeback from execute stage (regfile write port)
    input  wire [3:0]  wb_rd,
    input  wire [15:0] wb_data,
    input  wire        wb_we,
    // DE/EX pipeline register outputs
    output reg  [15:0] deex_rs1_data,
    output reg  [15:0] deex_rs2_data,
    output reg  [15:0] deex_imm,
    output reg  [15:0] deex_pc,
    output reg  [3:0]  deex_rd,
    output reg  [3:0]  deex_alu_op,
    output reg         deex_alu_src,
    output reg         deex_reg_we,
    output reg         deex_mem_we,
    output reg         deex_mem_re,
    output reg  [1:0]  deex_branch_op,
    output reg  [1:0]  deex_wb_sel,
    output reg         deex_valid
);

    // ---------------------------------------------------------------
    // Localparams
    // ---------------------------------------------------------------
    // ALU operations
    localparam ALU_ADD    = 4'b0000;
    localparam ALU_SUB    = 4'b0001;
    localparam ALU_AND    = 4'b0010;
    localparam ALU_OR     = 4'b0011;
    localparam ALU_XOR    = 4'b0100;
    localparam ALU_PASS_B = 4'b0101;

    // Immediate types
    localparam IMM_I = 3'd0;
    localparam IMM_S = 3'd1;
    localparam IMM_B = 3'd2;
    localparam IMM_U = 3'd3;
    localparam IMM_J = 3'd4;

    // Branch operations
    localparam BR_NONE = 2'd0;
    localparam BR_BEQ  = 2'd1;
    localparam BR_BNE  = 2'd2;
    localparam BR_JAL  = 2'd3;

    // Writeback source
    localparam WB_ALU = 2'd0;
    localparam WB_MEM = 2'd1;
    localparam WB_PC4 = 2'd2;

    // Opcodes
    localparam OP_RTYPE = 7'b0110011;
    localparam OP_ADDI  = 7'b0010011;
    localparam OP_LW    = 7'b0000011;
    localparam OP_SW    = 7'b0100011;
    localparam OP_LUI   = 7'b0110111;
    localparam OP_JAL   = 7'b1101111;
    localparam OP_BXX   = 7'b1100011;

    // ---------------------------------------------------------------
    // Instruction field extraction
    // ---------------------------------------------------------------
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire       funct7_5 = instr[30];
    wire [3:0] rd_addr  = instr[10:7];
    wire [3:0] rs1_addr = instr[18:15];
    wire [3:0] rs2_addr = instr[23:20];

    // ---------------------------------------------------------------
    // Register file instance
    // ---------------------------------------------------------------
    wire [15:0] rs1_data;
    wire [15:0] rs2_data;

    regfile u_regfile (
        .clk      (clk),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .wd_addr  (wb_rd),
        .wd_data  (wb_data),
        .wd_en    (wb_we)
    );

    // ---------------------------------------------------------------
    // Immediate generator instance
    // ---------------------------------------------------------------
    reg  [2:0]  imm_type;
    wire [15:0] imm_out;

    imm_gen u_imm_gen (
        .instr    (instr),
        .imm_type (imm_type),
        .imm_out  (imm_out)
    );

    // ---------------------------------------------------------------
    // Control decode (combinational)
    // ---------------------------------------------------------------
    reg [3:0]  ctrl_alu_op;
    reg        ctrl_alu_src;
    reg        ctrl_reg_we;
    reg        ctrl_mem_we;
    reg        ctrl_mem_re;
    reg [1:0]  ctrl_branch_op;
    reg [1:0]  ctrl_wb_sel;

    always @(*) begin
        // Default assignments — NOP-like
        ctrl_alu_op    = ALU_ADD;
        ctrl_alu_src   = 1'b0;
        ctrl_reg_we    = 1'b0;
        ctrl_mem_we    = 1'b0;
        ctrl_mem_re    = 1'b0;
        ctrl_branch_op = BR_NONE;
        ctrl_wb_sel    = WB_ALU;
        imm_type       = IMM_I;

        case (opcode)
            OP_RTYPE: begin
                ctrl_alu_src   = 1'b0;
                ctrl_reg_we    = 1'b1;
                ctrl_mem_we    = 1'b0;
                ctrl_mem_re    = 1'b0;
                ctrl_branch_op = BR_NONE;
                ctrl_wb_sel    = WB_ALU;
                case (funct3)
                    3'b000:  ctrl_alu_op = funct7_5 ? ALU_SUB : ALU_ADD;
                    3'b111:  ctrl_alu_op = ALU_AND;
                    3'b110:  ctrl_alu_op = ALU_OR;
                    3'b100:  ctrl_alu_op = ALU_XOR;
                    default: ctrl_alu_op = ALU_ADD;
                endcase
            end

            OP_ADDI: begin
                ctrl_alu_op    = ALU_ADD;
                ctrl_alu_src   = 1'b1;
                ctrl_reg_we    = 1'b1;
                ctrl_branch_op = BR_NONE;
                ctrl_wb_sel    = WB_ALU;
                imm_type       = IMM_I;
            end

            OP_LW: begin
                ctrl_alu_op    = ALU_ADD;
                ctrl_alu_src   = 1'b1;
                ctrl_reg_we    = 1'b1;
                ctrl_mem_re    = 1'b1;
                ctrl_branch_op = BR_NONE;
                ctrl_wb_sel    = WB_MEM;
                imm_type       = IMM_I;
            end

            OP_SW: begin
                ctrl_alu_op    = ALU_ADD;
                ctrl_alu_src   = 1'b1;
                ctrl_reg_we    = 1'b0;
                ctrl_mem_we    = 1'b1;
                ctrl_branch_op = BR_NONE;
                imm_type       = IMM_S;
            end

            OP_LUI: begin
                ctrl_alu_op    = ALU_PASS_B;
                ctrl_alu_src   = 1'b1;
                ctrl_reg_we    = 1'b1;
                ctrl_branch_op = BR_NONE;
                ctrl_wb_sel    = WB_ALU;
                imm_type       = IMM_U;
            end

            OP_JAL: begin
                ctrl_alu_op    = ALU_ADD;
                ctrl_alu_src   = 1'b0;
                ctrl_reg_we    = 1'b1;
                ctrl_branch_op = BR_JAL;
                ctrl_wb_sel    = WB_PC4;
                imm_type       = IMM_J;
            end

            OP_BXX: begin
                ctrl_alu_op    = ALU_SUB;
                ctrl_alu_src   = 1'b0;
                ctrl_reg_we    = 1'b0;
                imm_type       = IMM_B;
                case (funct3)
                    3'b000:  ctrl_branch_op = BR_BEQ;
                    3'b001:  ctrl_branch_op = BR_BNE;
                    default: ctrl_branch_op = BR_NONE;
                endcase
            end

            default: begin
                // All signals stay at default (NOP)
            end
        endcase
    end

    // ---------------------------------------------------------------
    // DE/EX pipeline register
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush) begin
            deex_rs1_data  <= 16'h0000;
            deex_rs2_data  <= 16'h0000;
            deex_imm       <= 16'h0000;
            deex_pc        <= 16'h0000;
            deex_rd        <= 4'b0000;
            deex_alu_op    <= ALU_ADD;
            deex_alu_src   <= 1'b0;
            deex_reg_we    <= 1'b0;
            deex_mem_we    <= 1'b0;
            deex_mem_re    <= 1'b0;
            deex_branch_op <= BR_NONE;
            deex_wb_sel    <= WB_ALU;
            deex_valid     <= 1'b0;
        end else if (stall) begin
            deex_rs1_data  <= deex_rs1_data;
            deex_rs2_data  <= deex_rs2_data;
            deex_imm       <= deex_imm;
            deex_pc        <= deex_pc;
            deex_rd        <= deex_rd;
            deex_alu_op    <= deex_alu_op;
            deex_alu_src   <= deex_alu_src;
            deex_reg_we    <= deex_reg_we;
            deex_mem_we    <= deex_mem_we;
            deex_mem_re    <= deex_mem_re;
            deex_branch_op <= deex_branch_op;
            deex_wb_sel    <= deex_wb_sel;
            deex_valid     <= deex_valid;
        end else if (!ifde_valid) begin
            // Insert bubble when incoming instruction is invalid
            deex_rs1_data  <= 16'h0000;
            deex_rs2_data  <= 16'h0000;
            deex_imm       <= 16'h0000;
            deex_pc        <= 16'h0000;
            deex_rd        <= 4'b0000;
            deex_alu_op    <= ALU_ADD;
            deex_alu_src   <= 1'b0;
            deex_reg_we    <= 1'b0;
            deex_mem_we    <= 1'b0;
            deex_mem_re    <= 1'b0;
            deex_branch_op <= BR_NONE;
            deex_wb_sel    <= WB_ALU;
            deex_valid     <= 1'b0;
        end else begin
            deex_rs1_data  <= rs1_data;
            deex_rs2_data  <= rs2_data;
            deex_imm       <= imm_out;
            deex_pc        <= ifde_pc;
            deex_rd        <= rd_addr;
            deex_alu_op    <= ctrl_alu_op;
            deex_alu_src   <= ctrl_alu_src;
            deex_reg_we    <= ctrl_reg_we;
            deex_mem_we    <= ctrl_mem_we;
            deex_mem_re    <= ctrl_mem_re;
            deex_branch_op <= ctrl_branch_op;
            deex_wb_sel    <= ctrl_wb_sel;
            deex_valid     <= 1'b1;
        end
    end

endmodule
