# ==============================================================================
# Vivado batch build script for rv64fp_mcu
# Usage: vivado -mode batch -source scripts/build.tcl
# ==============================================================================

set project_name rv64fp_mcu
set part         xc7a35tcpg236-1
set top_module   rv64fp_top
set base_dir     C:/rv64fp_build

# ------------------------------------------------------------------------------
# Create project
# ------------------------------------------------------------------------------
create_project $project_name $base_dir/vivado_project -part $part -force

# ------------------------------------------------------------------------------
# Add RTL sources
# ------------------------------------------------------------------------------
add_files -norecurse [glob $base_dir/rtl/*.v]

# ------------------------------------------------------------------------------
# Add constraints
# ------------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse [glob $base_dir/constraints/*.xdc]

# ------------------------------------------------------------------------------
# Set top module
# ------------------------------------------------------------------------------
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

# ------------------------------------------------------------------------------
# Synthesis
# ------------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    error "Synthesis failed!"
}

# ------------------------------------------------------------------------------
# Implementation
# ------------------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    error "Implementation failed!"
}

puts "========================================="
puts " Build complete!"
puts " Bitstream: $base_dir/vivado_project/$project_name.runs/impl_1/${top_module}.bit"
puts "========================================="

# ------------------------------------------------------------------------------
# Program FPGA (optional — comment out if not connected)
# ------------------------------------------------------------------------------
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set hw_device [get_hw_devices xc7a35t_0]
current_hw_device $hw_device
set_property PROGRAM.FILE "$base_dir/vivado_project/$project_name.runs/impl_1/${top_module}.bit" $hw_device
program_hw_devices $hw_device

close_hw_manager
