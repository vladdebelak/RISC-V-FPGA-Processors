// mem_bus.v — Address decoder / memory bus
// Routes CPU data bus to data_mem or gpio_led based on address

module mem_bus (
    input  wire        clk,
    input  wire        rst,

    // From CPU
    input  wire [15:0] addr,
    input  wire [15:0] wdata,
    input  wire        we,
    input  wire        re,

    // To data memory
    output wire [7:0]  dm_addr,
    output wire [15:0] dm_wdata,
    input  wire [15:0] dm_rdata,
    output wire        dm_we,
    output wire        dm_re,

    // To GPIO
    output wire        gpio_we,
    output wire [15:0] gpio_wdata,
    input  wire [15:0] gpio_rdata,

    // Back to CPU
    output reg  [15:0] rdata
);

    // Address decode signals
    wire sel_gpio = (addr[15:12] == 4'hF);
    wire sel_dmem = (addr[15:12] == 4'h1);

    // Latched select for read-data mux (data returns one cycle after re)
    reg sel_gpio_r;
    reg sel_dmem_r;

    always @(posedge clk) begin
        if (rst) begin
            sel_gpio_r <= 1'b0;
            sel_dmem_r <= 1'b0;
        end else if (re) begin
            sel_gpio_r <= sel_gpio;
            sel_dmem_r <= sel_dmem;
        end
    end

    // Data memory connections
    assign dm_addr  = addr[8:1]; // byte to word index
    assign dm_wdata = wdata;
    assign dm_we    = we & sel_dmem;
    assign dm_re    = re & sel_dmem;

    // GPIO connections
    assign gpio_wdata = wdata;
    assign gpio_we    = we & sel_gpio;

    // Read data mux — uses latched select
    always @(*) begin
        rdata = 16'h0000; // default to prevent latch
        if (sel_gpio_r)
            rdata = gpio_rdata;
        else if (sel_dmem_r)
            rdata = dm_rdata;
    end

endmodule
