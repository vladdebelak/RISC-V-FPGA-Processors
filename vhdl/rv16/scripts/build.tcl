# build.tcl — Vivado non-project-mode build script for rv16_vhdl_mcu
# Usage: vivado -mode batch -source build.tcl

# --- Configuration --------------------------------------------------------
set proj_name   rv16_vhdl_mcu
set part        xc7a35tcpg236-1
set top         rv16_top
set rtl_dir     [file normalize [file join [file dirname [info script]] ../rtl]]
set out_dir     [file normalize [file join [file dirname [info script]] ../build]]
set xdc_file    [file normalize [file join [file dirname [info script]] ../constraints/basys3.xdc]]

# --- Create output directory ----------------------------------------------
file mkdir $out_dir

# --- Create in-memory project ---------------------------------------------
create_project -in_memory -part $part

# --- Read RTL sources -----------------------------------------------------
foreach f [glob $rtl_dir/*.vhd] {
    read_vhdl -vhdl2008 $f
}

# --- Read constraints -----------------------------------------------------
if {[file exists $xdc_file]} {
    read_xdc $xdc_file
}

# --- Synthesis ------------------------------------------------------------
synth_design -top $top -part $part
write_checkpoint -force $out_dir/${proj_name}_synth.dcp
report_timing_summary -file $out_dir/${proj_name}_timing_synth.rpt
report_utilization     -file $out_dir/${proj_name}_util_synth.rpt

# --- Placement ------------------------------------------------------------
opt_design
place_design
write_checkpoint -force $out_dir/${proj_name}_placed.dcp
report_timing_summary -file $out_dir/${proj_name}_timing_placed.rpt

# --- Routing --------------------------------------------------------------
route_design
write_checkpoint -force $out_dir/${proj_name}_routed.dcp
report_timing_summary -file $out_dir/${proj_name}_timing_routed.rpt
report_utilization     -file $out_dir/${proj_name}_util_routed.rpt

# --- Bitstream generation -------------------------------------------------
write_bitstream -force $out_dir/${proj_name}.bit

# --- Programming ----------------------------------------------------------
# Uncomment below to auto-program the Basys 3 after build:
# open_hw_manager
# connect_hw_server -allow_non_jtag
# open_hw_target
# set_property PROGRAM.FILE $out_dir/${proj_name}.bit [current_hw_device]
# program_hw_devices [current_hw_device]
# close_hw_manager

puts "=== Build complete: $out_dir/${proj_name}.bit ==="
