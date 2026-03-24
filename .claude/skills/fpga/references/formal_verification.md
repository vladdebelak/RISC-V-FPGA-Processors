# FPGA Design - Formal Verification Reference

## SVA Property Patterns

### Protocol Verification (Handshake)
```systemverilog
// Busy/done handshake for multicycle units
// start pulse → busy asserts → done pulse → busy deasserts
module sva_handshake_props (
    input wire clk, rst, start, done, busy
);
    P_BUSY_ON_START: assert property (
        @(posedge clk) disable iff (rst)
        !busy && start |=> busy
    );
    P_DONE_ENDS_BUSY: assert property (
        @(posedge clk) disable iff (rst)
        done |=> !busy
    );
    P_DONE_PULSE: assert property (
        @(posedge clk) disable iff (rst)
        done |=> !done
    );
    P_EVENTUAL_DONE: assert property (
        @(posedge clk) disable iff (rst)
        start |-> ##[1:100] done
    );
endmodule
```

### Combinational Correctness
```systemverilog
// ALU operation verification pattern
// Note: needs clock for concurrent assertions even though ALU is combinational
P_ADD: assert property (
    @(posedge clk) alu_op == OP_ADD |-> result == a + b
);
```

### Pipeline Invariants
```systemverilog
// Forwarding priority: EX (01) > MEM (10) > WB (11)
P_FWD_PRIORITY: assert property (
    @(posedge clk)
    (ex_match && mem_match) |-> fwd_sel == 2'b01
);

// x0 hardwire: integer forwarding must never activate for x0
P_NO_FWD_X0: assert property (
    @(posedge clk)
    fwd_sel != 2'b00 |-> rs_addr != 5'd0
);

// FP register f0 IS a real register (unlike integer x0)
// FP forwarding CAN activate for f0
```

### IEEE 754 Special Values
```systemverilog
// Latch inputs at start for multicycle comparison
always @(posedge clk) begin
    if (start) begin
        latched_a  <= fp_a;
        latched_b  <= fp_b;
        latched_op <= fp_op;
    end
end

// Check special value handling at done
P_INF_MINUS_INF: assert property (
    @(posedge clk) disable iff (rst)
    done && latched_op == FP_SUB &&
    is_pos_inf(latched_a) && is_pos_inf(latched_b)
    |-> is_nan(fp_result) && fp_flags[4]  // NV flag
);
```

## Bind Statement Patterns

### Direct bind (clocked modules)
```systemverilog
// Module has clk port — bind directly
bind fpu_top sva_fpu_protocol_props fpu_proto_i (.*);
```

### Parent-level bind (combinational modules)
```systemverilog
// ALU has no clock — bind at parent level with hierarchical refs
bind execute sva_alu_props alu_props_i (
    .clk(clk),
    .a(u_alu.a),
    .b(u_alu.b),
    .alu_op(u_alu.alu_op),
    .result(u_alu.result),
    .zero(u_alu.zero)
);
```

### Internal signal access
```systemverilog
// Access internal FFs in reset synchronizer
bind reset_sync sva_reset_sync_props rst_props_i (
    .clk(clk), .rst_btn(rst_btn), .rst_sync(rst_sync),
    .sync_ff0(sync_ff0), .sync_ff1(sync_ff1)
);
```

## SymbiYosys Configuration
```
[tasks]
bmc

[options]
bmc: mode bmc
bmc: depth 10        # Adjust per module complexity

[engines]
smtbmc z3            # Or: smtbmc yices, boolector

[script]
read_verilog -formal rtl/module.v
read -sv formal/sva_module.sv
read -sv formal/sva_binds.sv
prep -top module_name

[files]
rtl/module.v
formal/sva_module.sv
formal/sva_binds.sv
```

## Common Pitfalls

### 1. Combinational module clock
**Problem**: SVA concurrent assertions need a clock, but combinational modules (ALU, hazard unit) have no clock port.
**Solution**: Add `input wire clk` to the SVA module and bind at the parent level where a clock is available.

### 2. SymbiYosys SVA subset
**Problem**: SymbiYosys supports limited SVA — no `s_eventually`, no complex sequences with `throughout`.
**Solution**: Use bounded liveness (`##[1:N] done`) instead of `s_eventually`. Stick to `|->`, `|=>`, `##N`.

### 3. Multicycle input latching
**Problem**: FPU inputs change after `start`; properties at `done` time see wrong inputs.
**Solution**: Add auxiliary registers in the SVA module to capture inputs when `start` fires.

### 4. Vivado 2020.2 limitations
**Problem**: Older xelab may not support all SVA constructs.
**Solution**: Use `module` not `checker`. Avoid `let` declarations. Test with simple properties first.

### 5. State space explosion
**Problem**: 64-bit datapath makes BMC very slow for deep depths.
**Solution**: For combinational modules, depth=1 suffices. For multicycle FPU, limit depth to 120. Consider constraining inputs with `assume` statements for targeted verification.
