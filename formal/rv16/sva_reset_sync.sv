`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for reset_sync module (RV16)
// Verifies async-assert, sync-release reset synchronizer behavior.
//////////////////////////////////////////////////////////////////////////////

module sva_reset_sync_props (
    input logic clk,
    input logic rst_btn,
    input logic rst_sync,
    input logic sync_ff0,
    input logic sync_ff1
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // P_ASYNC_ASSERT: When rst_btn asserts, rst_sync goes high within 0-1 cycles
    // -----------------------------------------------------------------------
    P_ASYNC_ASSERT: assert property (
        @(posedge clk) $rose(rst_btn) |-> ##[0:1] rst_sync
    ) else $error("P_ASYNC_ASSERT: rst_sync did not assert after rst_btn rose");

    // -----------------------------------------------------------------------
    // P_SYNC_RELEASE: When rst_btn deasserts, rst_sync clears after 2 cycles
    // -----------------------------------------------------------------------
    P_SYNC_RELEASE: assert property (
        @(posedge clk) $fell(rst_btn) |-> ##2 !rst_sync
    ) else $error("P_SYNC_RELEASE: rst_sync did not deassert 2 cycles after rst_btn fell");

    // -----------------------------------------------------------------------
    // P_FF0_CLEARS_FIRST: At the cycle rst_btn deasserts, sync_ff0 clears
    // while sync_ff1 remains asserted (sync_ff0 leads sync_ff1 by one stage)
    // -----------------------------------------------------------------------
    P_FF0_CLEARS_FIRST: assert property (
        @(posedge clk) $fell(rst_btn) |-> !sync_ff0 && sync_ff1
    ) else $error("P_FF0_CLEARS_FIRST: sync_ff0 did not clear before sync_ff1");

    // -----------------------------------------------------------------------
    // C_RESET_EXERCISED: Cover reset assert and release
    // -----------------------------------------------------------------------
    C_RESET_EXERCISED: cover property (
        @(posedge clk) $rose(rst_btn) ##[1:10] $fell(rst_btn)
    );

endmodule
