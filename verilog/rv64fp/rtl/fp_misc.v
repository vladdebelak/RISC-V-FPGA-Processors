`timescale 1ns / 1ps
//
// fp_misc.v — Sign injection (FSGNJ, FSGNJN, FSGNJX) and FCLASS.D
// All combinational, single-cycle. No flags generated.
//

module fp_misc (
    input  [63:0] a,
    input  [63:0] b,
    input  [2:0]  op,      // 0=FSGNJ, 1=FSGNJN, 2=FSGNJX, 3=FCLASS
    output reg [63:0] result,
    output        result_is_int  // 1 for FCLASS (result goes to integer rd)
);

    // -----------------------------------------------------------------
    // Unpack fields of 'a' for FCLASS
    // -----------------------------------------------------------------
    wire        a_sign = a[63];
    wire [10:0] a_exp  = a[62:52];
    wire [51:0] a_mant = a[51:0];

    wire a_exp_zero  = (a_exp == 11'h000);
    wire a_exp_max   = (a_exp == 11'h7FF);
    wire a_mant_zero = (a_mant == 52'b0);

    // NaN sub-classification
    wire a_is_snan = a_exp_max && !a_mant_zero && (a_mant[51] == 1'b0);
    wire a_is_qnan = a_exp_max && (a_mant[51] == 1'b1);

    // -----------------------------------------------------------------
    // FCLASS bit-mask (only one bit set at a time)
    // -----------------------------------------------------------------
    reg [9:0] fclass_mask;

    always @(*) begin
        fclass_mask = 10'b0;
        if (a_sign && a_exp_max && a_mant_zero)         fclass_mask[0] = 1'b1; // -Inf
        else if (a_sign && !a_exp_zero && !a_exp_max)    fclass_mask[1] = 1'b1; // -normal
        else if (a_sign && a_exp_zero && !a_mant_zero)   fclass_mask[2] = 1'b1; // -subnormal
        else if (a_sign && a_exp_zero && a_mant_zero)    fclass_mask[3] = 1'b1; // -0
        else if (!a_sign && a_exp_zero && a_mant_zero)   fclass_mask[4] = 1'b1; // +0
        else if (!a_sign && a_exp_zero && !a_mant_zero)  fclass_mask[5] = 1'b1; // +subnormal
        else if (!a_sign && !a_exp_zero && !a_exp_max)   fclass_mask[6] = 1'b1; // +normal
        else if (!a_sign && a_exp_max && a_mant_zero)    fclass_mask[7] = 1'b1; // +Inf
        else if (a_is_snan)                              fclass_mask[8] = 1'b1; // sNaN
        else if (a_is_qnan)                              fclass_mask[9] = 1'b1; // qNaN
    end

    // -----------------------------------------------------------------
    // Output mux
    // -----------------------------------------------------------------
    always @(*) begin
        result = 64'b0;
        case (op)
            3'd0:    result = {b[63],         a[62:0]};          // FSGNJ.D
            3'd1:    result = {~b[63],        a[62:0]};          // FSGNJN.D
            3'd2:    result = {a[63] ^ b[63], a[62:0]};          // FSGNJX.D
            3'd3:    result = {54'b0, fclass_mask};               // FCLASS.D
            default: result = 64'b0;
        endcase
    end

    // FCLASS result goes to integer register file
    assign result_is_int = (op == 3'd3);

endmodule
