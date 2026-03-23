`timescale 1ns/1ps
module tb_rv16_top;

    reg         clk;
    reg         btnc;
    wire [15:0] led;

    rv16_top uut (
        .CLK100MHZ(clk),
        .BTNC(btnc),
        .LED(led)
    );

    // Override instruction memory with test program
    initial begin
        $readmemh("program_test.hex", uut.imem.mem);
    end

    // Waveform dump
    initial begin
        $dumpfile("rv16_top.vcd");
        $dumpvars(0, tb_rv16_top);
    end

    // 100 MHz clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Track whether LEDs have been both zero and non-zero
    reg saw_zero    = 0;
    reg saw_nonzero = 0;

    always @(posedge clk) begin
        if (led === 16'h0000)
            saw_zero <= 1;
        else if (led !== 16'hxxxx)
            saw_nonzero <= 1;
    end

    // Periodic display of LED value
    integer cycle_cnt = 0;
    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
        if (cycle_cnt % 50 == 0)
            $display("cycle %0d : LED = %h", cycle_cnt, led);
    end

    initial begin
        // ----------------------------------------------------------
        // 1. Assert reset for 20 cycles
        // ----------------------------------------------------------
        btnc = 1;
        repeat (20) @(posedge clk);

        // ----------------------------------------------------------
        // 2. Release reset
        // ----------------------------------------------------------
        btnc = 0;
        $display("Reset released at cycle %0d", cycle_cnt);

        // ----------------------------------------------------------
        // 3-5. Run for 2000 cycles total (remaining after reset)
        // ----------------------------------------------------------
        repeat (1980) @(posedge clk);

        // ----------------------------------------------------------
        // 6-7. Check toggle
        // ----------------------------------------------------------
        $display("");
        $display("==========================================");
        $display("saw_zero    = %0b", saw_zero);
        $display("saw_nonzero = %0b", saw_nonzero);
        if (saw_zero && saw_nonzero)
            $display("PASS: LED toggled (was both zero and non-zero)");
        else
            $display("FAIL: LED did not toggle (zero=%0b nonzero=%0b)", saw_zero, saw_nonzero);
        $display("==========================================");
        $finish;
    end

endmodule
