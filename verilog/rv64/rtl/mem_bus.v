//============================================================================
// mem_bus.v — Address Decoder, Byte Alignment, and Load Sign-Extension
// Routes CPU memory accesses to data memory or GPIO peripherals.
//============================================================================

module mem_bus (
    input         clk,
    input         rst,

    // From CPU
    input  [63:0] addr,
    input  [63:0] wdata,
    input         we,
    input         re,
    input  [1:0]  size,
    input         is_unsigned,

    // To/from data memory
    output [8:0]  dm_addr,
    output [63:0] dm_wdata,
    input  [63:0] dm_rdata,
    output        dm_we,
    output [7:0]  dm_byte_en,

    // To/from GPIO
    output        gpio_we,
    output [15:0] gpio_wdata,
    input  [15:0] gpio_rdata,

    // To CPU
    output reg [63:0] rdata
);

    // --- Address decode ---
    wire sel_gpio = (addr[15:8] == 8'hFF);
    wire sel_dmem = (addr[15:12] == 4'h1);

    // --- Data memory address (doubleword index) ---
    assign dm_addr = addr[11:3];

    // --- Write enable routing ---
    assign dm_we   = we & sel_dmem;
    assign gpio_we = we & sel_gpio;

    // --- GPIO write data (lower 16 bits) ---
    assign gpio_wdata = wdata[15:0];

    // --- Byte-enable generation ---
    reg [7:0] byte_en_r;
    always @(*) begin
        byte_en_r = 8'h00;
        case (size)
            2'b00: byte_en_r = 8'h01 << addr[2:0];              // byte
            2'b01: byte_en_r = 8'h03 << (addr[2:1] * 2);        // half
            2'b10: byte_en_r = addr[2] ? 8'hF0 : 8'h0F;         // word
            2'b11: byte_en_r = 8'hFF;                            // double
            default: byte_en_r = 8'h00;
        endcase
    end
    assign dm_byte_en = byte_en_r;

    // --- Write data alignment (replicate pattern) ---
    reg [63:0] wdata_aligned;
    always @(*) begin
        wdata_aligned = 64'd0;
        case (size)
            2'b00: wdata_aligned = {8{wdata[7:0]}};              // SB
            2'b01: wdata_aligned = {4{wdata[15:0]}};             // SH
            2'b10: wdata_aligned = {2{wdata[31:0]}};             // SW
            2'b11: wdata_aligned = wdata;                        // SD
            default: wdata_aligned = 64'd0;
        endcase
    end
    assign dm_wdata = wdata_aligned;

    // --- Latched control signals for load extraction ---
    reg [2:0]  latched_addr;
    reg [1:0]  latched_size;
    reg        latched_unsigned;
    reg        latched_sel_gpio;

    always @(posedge clk) begin
        if (rst) begin
            latched_addr     <= 3'd0;
            latched_size     <= 2'd0;
            latched_unsigned <= 1'b0;
            latched_sel_gpio <= 1'b0;
        end else if (re || we) begin
            latched_addr     <= addr[2:0];
            latched_size     <= size;
            latched_unsigned <= is_unsigned;
            latched_sel_gpio <= sel_gpio;
        end
    end

    // --- Load data extraction and sign/zero extension ---
    reg [63:0] shifted_data;
    reg [63:0] extended_data;

    always @(*) begin
        // Shift right by byte offset
        shifted_data = dm_rdata >> (latched_addr * 8);

        extended_data = 64'd0;
        case (latched_size)
            2'b00: begin // byte
                if (latched_unsigned)
                    extended_data = {56'd0, shifted_data[7:0]};
                else
                    extended_data = {{56{shifted_data[7]}}, shifted_data[7:0]};
            end
            2'b01: begin // half
                if (latched_unsigned)
                    extended_data = {48'd0, shifted_data[15:0]};
                else
                    extended_data = {{48{shifted_data[15]}}, shifted_data[15:0]};
            end
            2'b10: begin // word
                if (latched_unsigned)
                    extended_data = {32'd0, shifted_data[31:0]};
                else
                    extended_data = {{32{shifted_data[31]}}, shifted_data[31:0]};
            end
            2'b11: begin // double
                extended_data = shifted_data;
            end
            default: extended_data = 64'd0;
        endcase
    end

    // --- Read data mux ---
    always @(*) begin
        if (latched_sel_gpio)
            rdata = {48'b0, gpio_rdata};
        else
            rdata = extended_data;
    end

endmodule
