# program.tcl — Quick reprogram for RV64I MCU on Basys 3
# Usage: vivado -mode batch -source scripts/program.tcl

open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {C:/rv64_build/rv64_mcu/rv64_mcu.runs/impl_1/rv64_top.bit} [get_hw_devices xc7a35t_0]
program_hw_devices [get_hw_devices xc7a35t_0]
close_hw_target
disconnect_hw_server
close_hw_manager

puts "===== Board programmed ====="
