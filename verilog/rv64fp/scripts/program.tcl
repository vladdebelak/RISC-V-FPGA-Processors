# ==============================================================================
# Quick reprogram script for rv64fp_mcu
# Usage: vivado -mode batch -source scripts/program.tcl
# ==============================================================================

set base_dir     C:/rv64fp_build
set project_name rv64fp_mcu
set top_module   rv64fp_top
set bitstream    "$base_dir/vivado_project/$project_name.runs/impl_1/${top_module}.bit"

if {![file exists $bitstream]} {
    error "Bitstream not found: $bitstream\nRun build.tcl first."
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set hw_device [get_hw_devices xc7a35t_0]
current_hw_device $hw_device
set_property PROGRAM.FILE $bitstream $hw_device
program_hw_devices $hw_device

puts "Programming complete: $bitstream"

close_hw_manager
