// imm_gen.v — Immediate generator for 16-bit RISC-V microcontroller
// Extracts and sign-extends immediates from 32-bit instruction word

module imm_gen (
    input  wire [31:0] instr,
    input  wire [2:0]  imm_type,
    output reg  [15:0] imm_out
);

    localparam IMM_I = 3'd0;
    localparam IMM_S = 3'd1;
    localparam IMM_B = 3'd2;
    localparam IMM_U = 3'd3;
    localparam IMM_J = 3'd4;

    wire sign = instr[31];

    always @(*) begin
        imm_out = 16'h0000; // default to prevent latch
        case (imm_type)
            // I-type: imm[11:0] = {instr[31:20]}
            IMM_I: begin
                imm_out = {{5{sign}}, instr[30:20]};
            end

            // S-type: imm[11:0] = {instr[31:25], instr[11:7]}
            IMM_S: begin
                imm_out = {{5{sign}}, instr[30:25], instr[11:7]};
            end

            // B-type: imm[12:1|0] = {sign, instr[7], instr[30:25], instr[11:8], 1'b0}
            IMM_B: begin
                imm_out = {{4{sign}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            end

            // U-type: LUI value = {instr[31:12], 12'b0} truncated to 16 bits
            //         = {instr[15:12], 12'b0}
            IMM_U: begin
                imm_out = {instr[15:12], 12'b0};
            end

            // J-type: imm[20:1|0] — truncated to 16 bits
            //         full = {sign, instr[19:12], instr[20], instr[30:21], 1'b0}
            //         low 16 = {sign-ext[15:12], instr[20], instr[30:21], 1'b0}
            IMM_J: begin
                imm_out = {{4{sign}}, instr[20], instr[30:21], 1'b0};
            end

            default: begin
                imm_out = 16'h0000;
            end
        endcase
    end

endmodule
