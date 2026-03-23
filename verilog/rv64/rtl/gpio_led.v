// gpio_led.v — Memory-mapped 16-bit LED output register
// Active-high synchronous reset

module gpio_led (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [15:0] wdata,
    output wire [15:0] rdata,
    output wire [15:0] led_out
);

    reg [15:0] led_reg;

    always @(posedge clk) begin
        if (rst)
            led_reg <= 16'h0000;
        else if (we)
            led_reg <= wdata;
    end

    assign rdata   = led_reg;
    assign led_out = led_reg;

endmodule
