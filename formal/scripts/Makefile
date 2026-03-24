# ===========================================================================
# Makefile — Formal verification runner for RISC-V processors
#
# Targets:
#   formal-rv16, formal-rv64, formal-rv64fp  — SymbiYosys BMC
#   formal-all                                — All SymbiYosys targets
#   vivado-rv16, vivado-rv64, vivado-rv64fp   — Vivado xsim SVA
#   vivado-all                                — All Vivado targets
#   clean                                     — Remove generated output
# ===========================================================================

SBY    = sby -f
VIVADO = vivado -mode batch -source run_formal_vivado.tcl -tclargs

.PHONY: formal-all formal-rv16 formal-rv64 formal-rv64fp \
        vivado-all vivado-rv16 vivado-rv64 vivado-rv64fp \
        clean

# ---- SymbiYosys targets ----

formal-all: formal-rv16 formal-rv64 formal-rv64fp

formal-rv16:
	$(SBY) sby/rv16_alu.sby
	$(SBY) sby/rv16_reset.sby

formal-rv64:
	$(SBY) sby/rv64_alu.sby

formal-rv64fp:
	$(SBY) sby/rv64fp_alu.sby
	$(SBY) sby/rv64fp_fpu.sby
	$(SBY) sby/rv64fp_hazard.sby
	$(SBY) sby/rv64fp_reset.sby
	$(SBY) sby/rv64fp_mem_bus.sby

# ---- Vivado xsim targets ----

vivado-all: vivado-rv16 vivado-rv64 vivado-rv64fp

vivado-rv16:
	$(VIVADO) rv16

vivado-rv64:
	$(VIVADO) rv64

vivado-rv64fp:
	$(VIVADO) rv64fp

# ---- Clean ----

clean:
	rm -rf sby/rv16_alu
	rm -rf sby/rv16_reset
	rm -rf sby/rv64_alu
	rm -rf sby/rv64fp_alu
	rm -rf sby/rv64fp_fpu
	rm -rf sby/rv64fp_hazard
	rm -rf sby/rv64fp_reset
	rm -rf sby/rv64fp_mem_bus
	rm -rf xsim_rv16 xsim_rv64 xsim_rv64fp
