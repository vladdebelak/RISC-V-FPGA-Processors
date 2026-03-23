`timescale 1ns / 1ps
//
// alu.v — 64-bit Integer ALU (combinational, standalone)
// RV64I / RV64W operations
//

module alu (
    input      [63:0] a,
    input      [63:0] b,
    input      [4:0]  alu_op,
    output reg [63:0] result,
    output            zero,
    output            lt_signed,
    output            lt_unsigned
);

    // ALU operation encodings
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

    // Comparison flags — always computed from a, b directly
    assign zero        = (a == b);
    assign lt_signed   = $signed(a) < $signed(b);
    assign lt_unsigned = a < b;

    // Intermediate 32-bit result for W-variants
    reg [31:0] r32;

    always @(*) begin
        result = 64'd0;
        r32    = 32'd0;

        case (alu_op)
            // --- RV64I operations ---
            OP_ADD:   result = a + b;
            OP_SUB:   result = a - b;
            OP_AND:   result = a & b;
            OP_OR:    result = a | b;
            OP_XOR:   result = a ^ b;
            OP_SLL:   result = a << b[5:0];
            OP_SRL:   result = a >> b[5:0];
            OP_SRA:   result = $signed(a) >>> b[5:0];
            OP_SLT:   result = {63'd0, lt_signed};
            OP_SLTU:  result = {63'd0, lt_unsigned};
            OP_PASSB: result = b;

            // --- RV64 W-variant operations (32-bit, sign-extended) ---
            OP_ADDW: begin
                r32    = a[31:0] + b[31:0];
                result = {{32{r32[31]}}, r32};
            end
            OP_SUBW: begin
                r32    = a[31:0] - b[31:0];
                result = {{32{r32[31]}}, r32};
            end
            OP_SLLW: begin
                r32    = a[31:0] << b[4:0];
                result = {{32{r32[31]}}, r32};
            end
            OP_SRLW: begin
                r32    = a[31:0] >> b[4:0];
                result = {{32{r32[31]}}, r32};
            end
            OP_SRAW: begin
                r32    = $signed(a[31:0]) >>> b[4:0];
                result = {{32{r32[31]}}, r32};
            end

            default: result = 64'd0;
        endcase
    end

endmodule
