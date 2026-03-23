# RISC-V FPGA Processors

AI-powered RISC-V processor designs in Verilog and VHDL, targeting the Basys 3 board (Xilinx Artix-7 XC7A35T).

Built with [Claude Code](https://claude.ai/claude-code) (Anthropic, Claude Opus 4).

## Projects

| Project | Language | Datapath | Pipeline | ISA | Instructions | LUTs | FPU |
|---------|----------|----------|----------|-----|-------------|------|-----|
| rv16 | Verilog | 16-bit | 3-stage | RV32I subset | 12 | ~400 | No |
| rv64 | Verilog | 64-bit | 3-stage | RV64I | 40 | 3,273 | No |
| rv64fp | Verilog | 64-bit | 5-stage | RV64IFD | 68 | 17,236 | IEEE 754 Double |
| rv16 | VHDL | 16-bit | 3-stage | RV32I subset | 12 | ~400 | No |
| rv64 | VHDL | 64-bit | 3-stage | RV64I | 40 | 3,273 | No |
| rv64fp | VHDL | 64-bit | 5-stage | RV64IFD | 68 | 17,236 | IEEE 754 Double |

## Architecture Highlights

- **5-stage pipeline** (IF/ID/EX/MEM/WB) with full data forwarding
- **IEEE 754 double-precision FPU**: FADD, FSUB, FMUL, FDIV, FSQRT, FMADD/FMSUB, comparisons, conversions
- **18 DSP48E1 slices** for 53x53-bit mantissa multiplication
- **82.9% FPGA utilization** on XC7A35T
- **Harvard architecture** with separate instruction and data BRAM
- **Memory-mapped GPIO** for LED output

## Directory Structure

```
verilog/
  rv16/       # 16-bit, 3-stage, 13 files, 994 lines
  rv64/       # 64-bit, 3-stage, 10 files, 1,208 lines
  rv64fp/     # 64-bit, 5-stage + FPU, 26 files, 5,755 lines
vhdl/
  rv16/       # VHDL equivalent of rv16
  rv64/       # VHDL equivalent of rv64
  rv64fp/     # VHDL equivalent of rv64fp
```

Each project contains: `rtl/` (source), `constraints/` (XDC), `sw/` (assembler + hex), `sim/` (testbenches), `scripts/` (Vivado TCL).

## Target Board

- **Basys 3** (Digilent)
- **FPGA**: Xilinx Artix-7 XC7A35T-1CPG236C
- **Resources**: 20,800 LUTs, 41,600 FFs, 50 BRAMs, 90 DSPs
- **Clock**: 100 MHz
- **Vivado**: 2020.2

## Building

```bash
cd verilog/rv64fp
vivado -mode batch -source scripts/build.tcl
```

## Author

George Teifel — ECE-238L Computer Logic Design, Spring 2026, University of New Mexico
