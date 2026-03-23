# program.tcl — Program Basys3 FPGA with rv64fp_vhdl bitstream
# Usage: vivado -mode batch -source program.tcl

set bitstream C:/rv64fp_vhdl/build/rv64fp_vhdl_mcu.runs/impl_1/rv64fp_top.bit

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE $bitstream $device

program_hw_devices $device
refresh_hw_device $device

puts "=========================================="
puts " Programming complete!"
puts " Bitstream: $bitstream"
puts "=========================================="

close_hw_target
disconnect_hw_server
close_hw_manager
