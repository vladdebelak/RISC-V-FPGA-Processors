# build.tcl — Vivado build script for rv64fp_vhdl_mcu
# Usage: vivado -mode batch -source build.tcl

set project_name rv64fp_vhdl_mcu
set top_module   rv64fp_top
set part         xc7a35tcpg236-1
set rtl_dir      C:/rv64fp_vhdl/rtl
set hex_path     C:/rv64fp_vhdl/sw/program.hex
set build_dir    C:/rv64fp_vhdl/build

# Create project
create_project $project_name $build_dir -part $part -force

# Add all VHDL source files
foreach f [glob -directory $rtl_dir *.vhd] {
    add_files $f
}

# Set VHDL 2008 for all files (needed for process(all))
set_property file_type {VHDL 2008} [get_files *.vhd]

# Set top module
set_property top $top_module [current_fileset]

# Add hex file path as generic or file reference
add_files -norecurse $hex_path -fileset [current_fileset]
set_property is_global_include true [get_files $hex_path]

# Add constraints (Basys3)
set xdc_content {
## Clock
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK100MHZ]

## LEDs
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN V3  IOSTANDARD LVCMOS33} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN W3  IOSTANDARD LVCMOS33} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN U3  IOSTANDARD LVCMOS33} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN P3  IOSTANDARD LVCMOS33} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN N3  IOSTANDARD LVCMOS33} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN P1  IOSTANDARD LVCMOS33} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN L1  IOSTANDARD LVCMOS33} [get_ports {LED[15]}]

## Center Button (active-high reset)
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports BTNC]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
}

set xdc_file $build_dir/basys3.xdc
set fp [open $xdc_file w]
puts $fp $xdc_content
close $fp
add_files -fileset constrs_1 $xdc_file

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run implementation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "=========================================="
puts " Build complete!"
puts " Bitstream: $build_dir/${project_name}.runs/impl_1/${top_module}.bit"
puts "=========================================="
