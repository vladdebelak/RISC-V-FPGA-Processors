# program.tcl — flash the rv16 bitstream onto the connected FPGA board (Nexys A7-100T)
# Usage (from verilog/rv16):  vivado -mode batch -source scripts/program.tcl
# Requires: board connected via USB and powered on; Vivado cable drivers installed.
# Auto-selects the first device on the JTAG chain, so it works for any board.

set bit_file [file normalize ./rv16_mcu/rv16_mcu.runs/impl_1/rv16_top.bit]

if {![file exists $bit_file]} {
    error "Bitstream not found: $bit_file  (run scripts/build_nexys_a7.tcl first)"
}
puts "Bitstream: $bit_file"

open_hw_manager
connect_hw_server
open_hw_target

# Auto-select the first (only) device on the JTAG chain — the Nexys A7 xc7a100t
set dev [lindex [get_hw_devices] 0]
puts "Target device: $dev"
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $bit_file $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "===== Board programmed: $dev ====="

close_hw_target
disconnect_hw_server
close_hw_manager
