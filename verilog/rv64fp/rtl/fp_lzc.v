`timescale 1ns / 1ps
//
// fp_lzc.v — 64-bit Leading Zero Counter (combinational, tree-based)
//

module fp_lzc (
    input  [63:0] data,
    output reg [6:0] count,
    output zero
);

    assign zero = (data == 64'b0);

    // Per-byte leading-zero counts
    reg [3:0] lzc_byte [0:7];  // 0..8 fits in 4 bits
    reg [7:0] byte_nonzero;     // 1 if byte has any set bit

    integer i;

    always @(*) begin
        // --- Stage 1: compute LZC within each 8-bit group ---
        for (i = 0; i < 8; i = i + 1) begin
            byte_nonzero[i] = |data[(7-i)*8 +: 8];   // MSB group = index 0
            lzc_byte[i]     = 4'd0;
        end

        // Byte 0 — bits [63:56]
        casez (data[63:56])
            8'b1???????: lzc_byte[0] = 4'd0;
            8'b01??????: lzc_byte[0] = 4'd1;
            8'b001?????: lzc_byte[0] = 4'd2;
            8'b0001????: lzc_byte[0] = 4'd3;
            8'b00001???: lzc_byte[0] = 4'd4;
            8'b000001??: lzc_byte[0] = 4'd5;
            8'b0000001?: lzc_byte[0] = 4'd6;
            8'b00000001: lzc_byte[0] = 4'd7;
            default:     lzc_byte[0] = 4'd8;
        endcase

        // Byte 1 — bits [55:48]
        casez (data[55:48])
            8'b1???????: lzc_byte[1] = 4'd0;
            8'b01??????: lzc_byte[1] = 4'd1;
            8'b001?????: lzc_byte[1] = 4'd2;
            8'b0001????: lzc_byte[1] = 4'd3;
            8'b00001???: lzc_byte[1] = 4'd4;
            8'b000001??: lzc_byte[1] = 4'd5;
            8'b0000001?: lzc_byte[1] = 4'd6;
            8'b00000001: lzc_byte[1] = 4'd7;
            default:     lzc_byte[1] = 4'd8;
        endcase

        // Byte 2 — bits [47:40]
        casez (data[47:40])
            8'b1???????: lzc_byte[2] = 4'd0;
            8'b01??????: lzc_byte[2] = 4'd1;
            8'b001?????: lzc_byte[2] = 4'd2;
            8'b0001????: lzc_byte[2] = 4'd3;
            8'b00001???: lzc_byte[2] = 4'd4;
            8'b000001??: lzc_byte[2] = 4'd5;
            8'b0000001?: lzc_byte[2] = 4'd6;
            8'b00000001: lzc_byte[2] = 4'd7;
            default:     lzc_byte[2] = 4'd8;
        endcase

        // Byte 3 — bits [39:32]
        casez (data[39:32])
            8'b1???????: lzc_byte[3] = 4'd0;
            8'b01??????: lzc_byte[3] = 4'd1;
            8'b001?????: lzc_byte[3] = 4'd2;
            8'b0001????: lzc_byte[3] = 4'd3;
            8'b00001???: lzc_byte[3] = 4'd4;
            8'b000001??: lzc_byte[3] = 4'd5;
            8'b0000001?: lzc_byte[3] = 4'd6;
            8'b00000001: lzc_byte[3] = 4'd7;
            default:     lzc_byte[3] = 4'd8;
        endcase

        // Byte 4 — bits [31:24]
        casez (data[31:24])
            8'b1???????: lzc_byte[4] = 4'd0;
            8'b01??????: lzc_byte[4] = 4'd1;
            8'b001?????: lzc_byte[4] = 4'd2;
            8'b0001????: lzc_byte[4] = 4'd3;
            8'b00001???: lzc_byte[4] = 4'd4;
            8'b000001??: lzc_byte[4] = 4'd5;
            8'b0000001?: lzc_byte[4] = 4'd6;
            8'b00000001: lzc_byte[4] = 4'd7;
            default:     lzc_byte[4] = 4'd8;
        endcase

        // Byte 5 — bits [23:16]
        casez (data[23:16])
            8'b1???????: lzc_byte[5] = 4'd0;
            8'b01??????: lzc_byte[5] = 4'd1;
            8'b001?????: lzc_byte[5] = 4'd2;
            8'b0001????: lzc_byte[5] = 4'd3;
            8'b00001???: lzc_byte[5] = 4'd4;
            8'b000001??: lzc_byte[5] = 4'd5;
            8'b0000001?: lzc_byte[5] = 4'd6;
            8'b00000001: lzc_byte[5] = 4'd7;
            default:     lzc_byte[5] = 4'd8;
        endcase

        // Byte 6 — bits [15:8]
        casez (data[15:8])
            8'b1???????: lzc_byte[6] = 4'd0;
            8'b01??????: lzc_byte[6] = 4'd1;
            8'b001?????: lzc_byte[6] = 4'd2;
            8'b0001????: lzc_byte[6] = 4'd3;
            8'b00001???: lzc_byte[6] = 4'd4;
            8'b000001??: lzc_byte[6] = 4'd5;
            8'b0000001?: lzc_byte[6] = 4'd6;
            8'b00000001: lzc_byte[6] = 4'd7;
            default:     lzc_byte[6] = 4'd8;
        endcase

        // Byte 7 — bits [7:0]
        casez (data[7:0])
            8'b1???????: lzc_byte[7] = 4'd0;
            8'b01??????: lzc_byte[7] = 4'd1;
            8'b001?????: lzc_byte[7] = 4'd2;
            8'b0001????: lzc_byte[7] = 4'd3;
            8'b00001???: lzc_byte[7] = 4'd4;
            8'b000001??: lzc_byte[7] = 4'd5;
            8'b0000001?: lzc_byte[7] = 4'd6;
            8'b00000001: lzc_byte[7] = 4'd7;
            default:     lzc_byte[7] = 4'd8;
        endcase

        // --- Stage 2: select first non-zero byte, compose final count ---
        // count = (byte_index * 8) + lzc within that byte
        // If all bytes are zero, count = 64
        count = 7'd64;
        if (byte_nonzero[0])
            count = 7'd0  + {3'd0, lzc_byte[0]};
        else if (byte_nonzero[1])
            count = 7'd8  + {3'd0, lzc_byte[1]};
        else if (byte_nonzero[2])
            count = 7'd16 + {3'd0, lzc_byte[2]};
        else if (byte_nonzero[3])
            count = 7'd24 + {3'd0, lzc_byte[3]};
        else if (byte_nonzero[4])
            count = 7'd32 + {3'd0, lzc_byte[4]};
        else if (byte_nonzero[5])
            count = 7'd40 + {3'd0, lzc_byte[5]};
        else if (byte_nonzero[6])
            count = 7'd48 + {3'd0, lzc_byte[6]};
        else if (byte_nonzero[7])
            count = 7'd56 + {3'd0, lzc_byte[7]};
    end

endmodule
