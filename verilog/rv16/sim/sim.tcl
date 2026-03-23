# sim.tcl - xsim automation for Vivado 2017.2
# Run from the sim/ directory:
#   vivado -mode batch -source sim.tcl
# Or use xvlog/xelab/xsim directly.

# ----------------------------------------------------------
# Compile all RTL sources
# ----------------------------------------------------------
xvlog ../rtl/alu.v
xvlog ../rtl/regfile.v
xvlog ../rtl/imm_gen.v
xvlog ../rtl/instr_mem.v
xvlog ../rtl/data_mem.v
xvlog ../rtl/gpio_led.v
xvlog ../rtl/mem_bus.v
xvlog ../rtl/reset_sync.v
xvlog ../rtl/fetch.v
xvlog ../rtl/decode.v
xvlog ../rtl/execute.v
xvlog ../rtl/rv16_core.v
xvlog ../rtl/rv16_top.v

# ----------------------------------------------------------
# Compile testbenches
# ----------------------------------------------------------
xvlog tb_alu.v
xvlog tb_rv16_core.v
xvlog tb_rv16_top.v

# ----------------------------------------------------------
# Elaborate and run ALU test
# ----------------------------------------------------------
xelab tb_alu -s tb_alu_sim
xsim tb_alu_sim -runall

# ----------------------------------------------------------
# Elaborate and run core test
# ----------------------------------------------------------
xelab tb_rv16_core -s tb_core_sim
xsim tb_core_sim -runall

# ----------------------------------------------------------
# Elaborate and run top test
# ----------------------------------------------------------
xelab tb_rv16_top -s tb_top_sim
xsim tb_top_sim -runall
