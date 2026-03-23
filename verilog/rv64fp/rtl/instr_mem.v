`timescale 1ns / 1ps

module instr_mem (
    input  wire        clk,
    input  wire [8:0]  addr,
    output reg  [31:0] rdata
);

    (* ram_style = "block" *)
    reg [31:0] mem [0:511];

    initial begin
        $readmemh("C:/rv64fp_build/sw/program.hex", mem);
    end

    always @(posedge clk) begin
        rdata <= mem[addr];
    end

endmodule
