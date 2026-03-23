`timescale 1ns / 1ps
//
// fcsr.v — RISC-V Floating-Point Control and Status Register
//

module fcsr (
    input        clk,
    input        rst,
    input        we,           // CSR write enable (from CSR instructions)
    input  [2:0] wr_frm,      // rounding mode to write
    input  [4:0] wr_fflags,   // exception flags to write
    input        we_flags,     // accumulate flags from FPU result
    input  [4:0] fpu_flags,   // flags from FPU ({NV, DZ, OF, UF, NX})
    output [2:0] frm,
    output [4:0] fflags
);

    reg [2:0] frm_reg;
    reg [4:0] fflags_reg;

    assign frm    = frm_reg;
    assign fflags = fflags_reg;

    always @(posedge clk) begin
        if (rst) begin
            frm_reg    <= 3'b000;   // RNE
            fflags_reg <= 5'b00000;
        end else begin
            if (we) begin
                frm_reg    <= wr_frm;
                fflags_reg <= wr_fflags;
            end
            if (we_flags) begin
                fflags_reg <= fflags_reg | fpu_flags;
            end
        end
    end

endmodule
