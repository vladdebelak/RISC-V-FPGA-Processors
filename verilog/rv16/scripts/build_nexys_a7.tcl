# build_nexys_a7.tcl — batch build for RV16 MCU on Nexys A7-100T (bitstream only, no programming)
# Same flow as build_bitstream.tcl, targeting the Digilent Nexys A7-100T (XC7A100T-1CSG324C).
# Usage (run from verilog/rv16):  vivado -mode batch -source scripts/build_nexys_a7.tcl

set proj_name  rv16_mcu_nexys_a7
set part       xc7a100tcsg324-1
set top        rv16_top
set src_dir    ./rtl
set hex_file   ./sw/program.hex
set xdc_file   ./constraints/nexys_a7.xdc

# Create project (fresh each run)
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

# Run implementation through bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation/bitstream failed."
}

puts "===== Build complete ====="
puts "Bitstream: [pwd]/$proj_name/$proj_name.runs/impl_1/${top}.bit"
