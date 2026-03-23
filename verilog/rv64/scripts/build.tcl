# build.tcl — Vivado 2020.2 batch build for RV64I MCU on Basys 3
# Usage: vivado -mode batch -source scripts/build.tcl

set proj_name  rv64_mcu
set part       xc7a35tcpg236-1
set top        rv64_top
set src_dir    ./rtl
set hex_file   ./sw/program.hex
set xdc_file   ./constraints/basys3.xdc

# Create project
create_project $proj_name ./$proj_name -part $part -force

# Add RTL sources
add_files [glob $src_dir/*.v]
set_property top $top [current_fileset]

# Add hex file as data
add_files -norecurse $hex_file
set_property file_type {Memory File} [get_files $hex_file]

# Add constraints
add_files -fileset constrs_1 -norecurse $xdc_file

# Update compile order
update_compile_order -fileset sources_1

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed."
}

# Run implementation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation/bitstream failed."
}

puts "===== Build complete ====="
puts "Bitstream: [pwd]/$proj_name/$proj_name.runs/impl_1/${top}.bit"

# Program the board
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {C:/rv64_build/rv64_mcu/rv64_mcu.runs/impl_1/rv64_top.bit} [get_hw_devices xc7a35t_0]
program_hw_devices [get_hw_devices xc7a35t_0]
close_hw_target
disconnect_hw_server
close_hw_manager

puts "===== Board programmed ====="
