`timescale 1ns/1ps
module tb_alu;

    reg  [15:0] a, b;
    reg  [3:0]  alu_op;
    wire [15:0] result;
    wire        zero;

    alu uut (
        .a(a),
        .b(b),
        .alu_op(alu_op),
        .result(result),
        .zero(zero)
    );

    integer failures = 0;
    integer test_num = 0;

    task check;
        input [15:0] expected_result;
        input        expected_zero;
        input [8*32-1:0] name;
        begin
            test_num = test_num + 1;
            #1; // allow combinational settle
            if (result !== expected_result || zero !== expected_zero) begin
                $display("FAIL test %0d [%0s]: a=%h b=%h op=%b => result=%h zero=%b (expected result=%h zero=%b)",
                         test_num, name, a, b, alu_op, result, zero, expected_result, expected_zero);
                failures = failures + 1;
            end else begin
                $display("PASS test %0d [%0s]: a=%h b=%h op=%b => result=%h zero=%b",
                         test_num, name, a, b, alu_op, result, zero);
            end
        end
    endtask

    initial begin
        // ----------------------------------------------------------------
        // ALU_ADD (4'b0000)
        // ----------------------------------------------------------------
        a = 16'h0005; b = 16'h0003; alu_op = 4'b0000;
        check(16'h0008, 1'b0, "ADD 5+3=8");

        a = 16'hFFFF; b = 16'h0001; alu_op = 4'b0000;
        check(16'h0000, 1'b1, "ADD FFFF+1=0 overflow");

        a = 16'h0000; b = 16'h0000; alu_op = 4'b0000;
        check(16'h0000, 1'b1, "ADD 0+0=0");

        // ----------------------------------------------------------------
        // ALU_SUB (4'b0001)
        // ----------------------------------------------------------------
        a = 16'h0008; b = 16'h0003; alu_op = 4'b0001;
        check(16'h0005, 1'b0, "SUB 8-3=5");

        a = 16'h0000; b = 16'h0001; alu_op = 4'b0001;
        check(16'hFFFF, 1'b0, "SUB 0-1=FFFF");

        a = 16'h0005; b = 16'h0005; alu_op = 4'b0001;
        check(16'h0000, 1'b1, "SUB 5-5=0 zero");

        // ----------------------------------------------------------------
        // ALU_AND (4'b0010)
        // ----------------------------------------------------------------
        a = 16'hFF0F; b = 16'h0FF0; alu_op = 4'b0010;
        check(16'h0F00, 1'b0, "AND FF0F&0FF0=0F00");

        // ----------------------------------------------------------------
        // ALU_OR (4'b0011)
        // ----------------------------------------------------------------
        a = 16'hFF00; b = 16'h00FF; alu_op = 4'b0011;
        check(16'hFFFF, 1'b0, "OR FF00|00FF=FFFF");

        // ----------------------------------------------------------------
        // ALU_XOR (4'b0100)
        // ----------------------------------------------------------------
        a = 16'hAAAA; b = 16'h5555; alu_op = 4'b0100;
        check(16'hFFFF, 1'b0, "XOR AAAA^5555=FFFF");

        a = 16'h1234; b = 16'h1234; alu_op = 4'b0100;
        check(16'h0000, 1'b1, "XOR same^same=0");

        // ----------------------------------------------------------------
        // ALU_PASS_B (4'b0101)
        // ----------------------------------------------------------------
        a = 16'h1234; b = 16'hABCD; alu_op = 4'b0101;
        check(16'hABCD, 1'b0, "PASS_B a=1234 b=ABCD => ABCD");

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("");
        $display("==========================================");
        if (failures == 0)
            $display("ALL %0d TESTS PASSED", test_num);
        else
            $display("FAILED: %0d / %0d tests failed", failures, test_num);
        $display("==========================================");
        $finish;
    end

endmodule
