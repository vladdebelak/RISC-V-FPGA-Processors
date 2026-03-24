`timescale 1ns / 1ps

module tb_formal_wrapper;

    // Clock and reset
    reg CLK100MHZ;
    reg BTNC;
    wire [15:0] LED;

    // 100 MHz clock generation (10ns period)
    initial CLK100MHZ = 0;
    always #5 CLK100MHZ = ~CLK100MHZ;

    // Reset sequence: assert for 10 cycles, then release
    initial begin
        BTNC = 1;
        repeat (10) @(posedge CLK100MHZ);
        BTNC = 0;
    end

    // Instantiate top-level module
    rv64fp_top dut (
        .CLK100MHZ (CLK100MHZ),
        .BTNC      (BTNC),
        .LED       (LED)
    );

    // Run for 10000 cycles then finish
    initial begin
        repeat (10000) @(posedge CLK100MHZ);
        $display("FORMAL: Simulation completed after 10000 cycles.");
        $finish;
    end

endmodule
