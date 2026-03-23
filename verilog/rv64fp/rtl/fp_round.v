`timescale 1ns / 1ps
//
// fp_round.v — IEEE 754 rounding logic (combinational)
// Shared by all FPU subunits.
//

module fp_round (
    input        sign,
    input        guard,
    input        round_bit,
    input        sticky,
    input        lsb,       // LSB of mantissa result
    input  [2:0] rm,        // rounding mode
    output reg   round_up
);

    // Rounding mode encodings (RISC-V fcsr.frm)
    localparam [2:0] RNE = 3'b000;  // Round to Nearest, ties to Even
    localparam [2:0] RTZ = 3'b001;  // Round toward Zero
    localparam [2:0] RDN = 3'b010;  // Round Down (toward -inf)
    localparam [2:0] RUP = 3'b011;  // Round Up   (toward +inf)
    localparam [2:0] RMM = 3'b100;  // Round to Nearest, ties to Max Magnitude

    always @(*) begin
        round_up = 1'b0;
        case (rm)
            RNE:     round_up = guard & (round_bit | sticky | lsb);
            RTZ:     round_up = 1'b0;
            RDN:     round_up = sign & (guard | round_bit | sticky);
            RUP:     round_up = !sign & (guard | round_bit | sticky);
            RMM:     round_up = guard;
            default: round_up = 1'b0;
        endcase
    end

endmodule
