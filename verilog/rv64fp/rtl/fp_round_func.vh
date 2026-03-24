// fp_round_func.vh — IEEE 754 rounding decision as a Verilog function
// Include this file inside any module that needs rounding.
// Usage: if (fp_do_round(sign, guard, round_bit, sticky, lsb, rm)) ...

function fp_do_round;
    input        f_sign;
    input        f_guard;
    input        f_round_bit;
    input        f_sticky;
    input        f_lsb;
    input  [2:0] f_rm;
    begin
        case (f_rm)
            3'b000:  fp_do_round = f_guard & (f_round_bit | f_sticky | f_lsb); // RNE
            3'b001:  fp_do_round = 1'b0;                                        // RTZ
            3'b010:  fp_do_round = f_sign & (f_guard | f_round_bit | f_sticky); // RDN
            3'b011:  fp_do_round = !f_sign & (f_guard | f_round_bit | f_sticky);// RUP
            3'b100:  fp_do_round = f_guard;                                     // RMM
            default: fp_do_round = 1'b0;
        endcase
    end
endfunction
