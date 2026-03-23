open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {C:/rv64fp_vhdl/build/rv64fp_vhdl_mcu.runs/impl_1/rv64fp_top.bit} [get_hw_devices xc7a35t_0]
program_hw_devices [get_hw_devices xc7a35t_0]
close_hw_target
disconnect_hw_server
close_hw_manager
puts "VHDL board programmed successfully."
