// alu.v — 16-bit ALU for RISC-V microcontroller
// Operations: ADD, SUB, AND, OR, XOR, PASS_B

module alu (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [3:0]  alu_op,
    output reg  [15:0] result,
    output wire        zero
);

    localparam ALU_ADD    = 4'b0000;
    localparam ALU_SUB    = 4'b0001;
    localparam ALU_AND    = 4'b0010;
    localparam ALU_OR     = 4'b0011;
    localparam ALU_XOR    = 4'b0100;
    localparam ALU_PASS_B = 4'b0101;

    assign zero = (result == 16'h0000);

    always @(*) begin
        result = 16'h0000; // default to prevent latch
        case (alu_op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_AND:    result = a & b;
            ALU_OR:     result = a | b;
            ALU_XOR:    result = a ^ b;
            ALU_PASS_B: result = b;
            default:    result = 16'h0000;
        endcase
    end

endmodule
