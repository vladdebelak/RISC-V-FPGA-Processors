# ===========================================================================
# run_tests.tcl — Vivado xsim batch simulation script for rv64fp
#
# Usage:
#   vivado -mode batch -source run_tests.tcl
#   OR
#   tclsh run_tests.tcl   (if Vivado bin is in PATH)
#
# This script compiles all RTL + testbench, elaborates, and runs simulation.
# Supports selecting which testbench to run via the TB variable.
# ===========================================================================

# Default testbench (override with: -tclargs <tb_name>)
if {[info exists argc] && $argc > 0} {
    set tb_name [lindex $argv 0]
} else {
    set tb_name "tb_rv64fp_full"
}

puts "================================================================"
puts " rv64fp Simulation — Testbench: $tb_name"
puts "================================================================"

set proj_dir "C:/rv64fp_build"
set sim_dir  "$proj_dir/sim"
set rtl_dir  "$proj_dir/rtl"

# Change to sim directory for output files
cd $sim_dir

# ---- Step 1: Compile RTL sources ----
puts "\n=== Compiling RTL ==="
set rtl_files [glob -directory $rtl_dir *.v]
foreach f $rtl_files {
    puts "  Compiling: [file tail $f]"
}
eval exec xvlog {*}$rtl_files 2>@1

# ---- Step 2: Compile testbench ----
puts "\n=== Compiling Testbench: $tb_name ==="
exec xvlog "$sim_dir/${tb_name}.v" 2>@1

# ---- Step 3: Elaborate ----
puts "\n=== Elaborating ==="
set snapshot "sim_${tb_name}"
exec xelab $tb_name -s $snapshot -timescale 1ns/1ps 2>@1

# ---- Step 4: Run simulation ----
puts "\n=== Running Simulation ==="
set result [exec xsim $snapshot -R 2>@1]

# ---- Step 5: Print simulation output ----
puts $result

# ---- Step 6: Check for pass/fail in output ----
if {[string match "*ALL*PASSED*" $result]} {
    puts "\n>>> SIMULATION RESULT: PASS <<<"
    exit 0
} else {
    puts "\n>>> SIMULATION RESULT: FAIL <<<"
    exit 1
}
