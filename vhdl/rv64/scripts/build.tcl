# build.tcl — Vivado build script for rv64_vhdl_mcu
# Usage: vivado -mode batch -source build.tcl

set project_name "rv64_vhdl_mcu"
set top_module   "rv64_top"
set rtl_dir      "./rtl"
set hex_path     "C:/rv64_vhdl/sw/program.hex"

# Create project (Basys 3 — xc7a35tcpg236-1)
create_project $project_name ./$project_name -part xc7a35tcpg236-1 -force

# Add all VHDL sources
set vhdl_files [glob $rtl_dir/*.vhd]
add_files -fileset sources_1 $vhdl_files

# Set VHDL-2008 for all files (needed for process(all))
set_property file_type {VHDL 2008} [get_files *.vhd]

# Set top module
set_property top $top_module [current_fileset]

# Add hex file for programming
add_files -norecurse $hex_path

update_compile_order -fileset sources_1

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run implementation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Build complete. Bitstream: ./$project_name/$project_name.runs/impl_1/${top_module}.bit"
