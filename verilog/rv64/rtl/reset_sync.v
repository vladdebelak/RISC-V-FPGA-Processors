// reset_sync.v — 2-FF async-assert, sync-release reset synchronizer
// Input: rst_btn (active-high from Basys3 button)
// Output: rst_sync (active-high synchronized reset)

module reset_sync (
    input  wire clk,
    input  wire rst_btn,
    output wire rst_sync
);

    (* ASYNC_REG = "TRUE" *)
    reg sync_ff0;

    (* ASYNC_REG = "TRUE" *)
    reg sync_ff1;

    // Async assert (rst_btn high), sync release
    always @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            sync_ff0 <= 1'b1;
            sync_ff1 <= 1'b1;
        end else begin
            sync_ff0 <= 1'b0;
            sync_ff1 <= sync_ff0;
        end
    end

    assign rst_sync = sync_ff1;

endmodule
