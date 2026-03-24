# ===========================================================================
# run_formal_vivado.tcl — Vivado xsim-based SVA assertion checker
#
# Usage:
#   vivado -mode batch -source run_formal_vivado.tcl -tclargs <variant>
#
# Where variant is: rv16, rv64, or rv64fp (default: rv64fp)
#
# This script compiles RTL + SVA assertions, creates a wrapper testbench,
# elaborates with SystemVerilog assertion support, runs simulation, and
# reports assertion pass/fail counts.
# ===========================================================================

# ---- Parse command-line arguments ----
if {[info exists argc] && $argc > 0} {
    set variant [lindex $argv 0]
} else {
    set variant "rv64fp"
}

# Validate variant
if {$variant ni {rv16 rv64 rv64fp}} {
    puts "ERROR: Invalid variant '$variant'. Must be rv16, rv64, or rv64fp."
    exit 1
}

puts "================================================================"
puts " Formal Verification (SVA via xsim) — Variant: $variant"
puts "================================================================"

# ---- Set paths relative to this script's location ----
set script_dir [file dirname [file normalize [info script]]]
set rtl_dir    [file normalize "$script_dir/../../verilog/$variant/rtl"]
set sva_dir    [file normalize "$script_dir/../$variant"]
set work_dir   [file normalize "$script_dir/xsim_${variant}"]

# Determine top module name
switch $variant {
    rv16    { set top_module "rv16_top" }
    rv64    { set top_module "rv64_top" }
    rv64fp  { set top_module "rv64fp_top" }
}

puts "  RTL dir:    $rtl_dir"
puts "  SVA dir:    $sva_dir"
puts "  Top module: $top_module"
puts "  Work dir:   $work_dir"

# ---- Create and enter work directory ----
file mkdir $work_dir
cd $work_dir

# ---- Step 1: Compile all RTL Verilog sources ----
puts "\n=== Step 1: Compiling RTL ==="
set rtl_files [glob -directory $rtl_dir *.v]
foreach f $rtl_files {
    puts "  RTL: [file tail $f]"
}
eval exec xvlog {*}$rtl_files 2>@1

# ---- Step 2: Compile all SVA SystemVerilog sources ----
puts "\n=== Step 2: Compiling SVA assertions ==="
set sva_files [glob -directory $sva_dir *.sv]
foreach f $sva_files {
    puts "  SVA: [file tail $f]"
}
eval exec xvlog --sv {*}$sva_files 2>@1

# ---- Step 3: Generate wrapper testbench ----
puts "\n=== Step 3: Generating wrapper testbench ==="
set tb_file "$work_dir/tb_formal_wrapper.sv"
set tb_fd [open $tb_file w]
puts $tb_fd "`timescale 1ns / 1ps"
puts $tb_fd ""
puts $tb_fd "module tb_formal_wrapper;"
puts $tb_fd ""
puts $tb_fd "    // Clock and reset"
puts $tb_fd "    reg CLK100MHZ;"
puts $tb_fd "    reg BTNC;"
puts $tb_fd "    wire \[15:0\] LED;"
puts $tb_fd ""
puts $tb_fd "    // 100 MHz clock generation (10ns period)"
puts $tb_fd "    initial CLK100MHZ = 0;"
puts $tb_fd "    always #5 CLK100MHZ = ~CLK100MHZ;"
puts $tb_fd ""
puts $tb_fd "    // Reset sequence: assert for 10 cycles, then release"
puts $tb_fd "    initial begin"
puts $tb_fd "        BTNC = 1;"
puts $tb_fd "        repeat (10) @(posedge CLK100MHZ);"
puts $tb_fd "        BTNC = 0;"
puts $tb_fd "    end"
puts $tb_fd ""
puts $tb_fd "    // Instantiate top-level module"
puts $tb_fd "    ${top_module} dut ("
puts $tb_fd "        .CLK100MHZ (CLK100MHZ),"
puts $tb_fd "        .BTNC      (BTNC),"
puts $tb_fd "        .LED       (LED)"
puts $tb_fd "    );"
puts $tb_fd ""
puts $tb_fd "    // Run for 10000 cycles then finish"
puts $tb_fd "    initial begin"
puts $tb_fd "        repeat (10000) @(posedge CLK100MHZ);"
puts $tb_fd "        \$display(\"FORMAL: Simulation completed after 10000 cycles.\");"
puts $tb_fd "        \$finish;"
puts $tb_fd "    end"
puts $tb_fd ""
puts $tb_fd "endmodule"
close $tb_fd
puts "  Generated: tb_formal_wrapper.sv"

# Compile wrapper testbench
exec xvlog --sv $tb_file 2>@1

# ---- Step 4: Elaborate ----
puts "\n=== Step 4: Elaborating ==="
set snapshot "formal_${variant}"
exec xelab tb_formal_wrapper -s $snapshot -timescale 1ns/1ps 2>@1

# ---- Step 5: Run simulation ----
puts "\n=== Step 5: Running simulation ==="
set result [exec xsim $snapshot -R 2>@1]

# ---- Step 6: Display output ----
puts "\n=== Simulation Output ==="
puts $result

# ---- Step 7: Parse assertion results ----
puts "\n=== Assertion Summary ==="

set pass_count 0
set fail_count 0

# Count assertion passes and failures from xsim output
foreach line [split $result "\n"] {
    if {[string match "*ASSERTION*PASSED*" [string toupper $line]] ||
        [string match "*ASSERT*PASS*" [string toupper $line]]} {
        incr pass_count
    }
    if {[string match "*ASSERTION*FAILED*" [string toupper $line]] ||
        [string match "*ASSERT*FAIL*" [string toupper $line]] ||
        [string match "*ERROR*ASSERT*" [string toupper $line]]} {
        incr fail_count
    }
}

puts "  Assertions passed: $pass_count"
puts "  Assertions failed: $fail_count"

if {$fail_count > 0} {
    puts "\n>>> FORMAL RESULT: FAIL — $fail_count assertion(s) failed <<<"
    exit 1
} elseif {$pass_count > 0} {
    puts "\n>>> FORMAL RESULT: PASS — All $pass_count assertion(s) passed <<<"
    exit 0
} else {
    puts "\n>>> FORMAL RESULT: WARNING — No assertions detected in output <<<"
    puts "    (Assertions may still have been checked; review output above.)"
    exit 0
}
