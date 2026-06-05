# Reproducing the Paper's Results

This guide takes you from a bare machine to the numbers reported in
*"Building VHDL Processors with Claude Code: From 16-Bit to 64-Bit FPU"*
(`latex/main_tcad_9pg.tex`). It covers the full flow for all six processor
variants: assembling test programs, simulation, synthesis/implementation,
programming the Basys 3 board, and formal verification.

The headline result — the `rv64fp` variant consuming **12,969 LUTs (82.9% of
the XC7A35T) and 18 DSP48E1 slices**, with **10 floating-point bugs caught in
simulation** and a **48% LUT reduction** from the initial generation — is
reproduced by the commands in the [claim → command map](#claim--command-map)
below.

---

## 1. Bill of Materials

### Hardware

| Item | Detail |
|------|--------|
| FPGA board | Digilent **Basys 3** (Xilinx Artix-7 **XC7A35T-1CPG236C**) |
| Resources | 20,800 LUTs, 41,600 FFs, 90 DSP48E1, 50 × 36 Kb BRAM, 100 MHz |
| USB cable | Micro-USB (board JTAG/UART programming + power) |
| Host PC | x86-64, ≥ 16 GB RAM recommended (Vivado synthesis is memory-hungry), ≥ 30 GB free disk for Vivado |

The board is only needed for the hardware-validation step (programming). All
simulation, synthesis, and formal-verification numbers can be reproduced
without a board.

### Software

| Component | Version | Purpose |
|-----------|---------|---------|
| Xilinx **Vivado** | **2020.2** | Synthesis, implementation, bitstream, `xsim` simulation, board programming |
| **SymbiYosys** (`sby`) + **Z3** | OSS CAD Suite (any recent) | Formal verification (BMC) |
| **Python** | 3.6+ | `asm2hex.py` assembler |
| **GNU Make** | any | Driving the formal targets |
| **Node.js** | 18+ (optional) | `gen_article.js` document generation only — not required to reproduce HDL results |

> **Why Vivado 2020.2 specifically?** The TCL scripts and the FPGA skill are
> written against 2020.2 syntax and the 7-series IP catalog of that release.
> Other versions may work but the project status strings checked in
> `build.tcl` (e.g. `"write_bitstream Complete!"`) and exact LUT counts can
> differ between releases. To match the paper's numbers exactly, use 2020.2.

---

## 2. Toolchain Install

### 2.1 Vivado 2020.2

1. Create a free **AMD/Xilinx account** (the former Xilinx download portal).
2. Download the **Vivado 2020.2** installer (Web Installer or full image).
   The free **WebPACK** edition covers the Artix-7 XC7A35T — no paid license
   is required for this part. If your campus runs a **floating license
   server**, point Vivado at it (Help → Manage License → set
   `XILINXD_LICENSE_FILE=<port>@<server>`); otherwise WebPACK is sufficient.
3. During install, select **Artix-7** device support and the **Vitis/Vivado**
   tools. Install the **cable drivers** when prompted (needed for board
   programming).
4. Add Vivado to `PATH` so `vivado`, `xvlog`, `xelab`, `xsim` are callable:
   - **Windows**: `C:\Xilinx\Vivado\2020.2\bin`
   - **Linux**: `source /tools/Xilinx/Vivado/2020.2/settings64.sh`

### 2.2 SymbiYosys + Z3 (formal)

The easiest install is the prebuilt **OSS CAD Suite** from YosysHQ, which
bundles Yosys, SymbiYosys (`sby`), and the Z3 SMT solver:

- Download: <https://github.com/YosysHQ/oss-cad-suite-build/releases>
- Extract and source its environment:
  ```bash
  source <oss-cad-suite>/environment   # Linux/WSL2
  ```
  (Windows: run `<oss-cad-suite>\environment.bat`.)
- Verify:
  ```bash
  sby --version
  z3 --version
  ```

### 2.3 Python, Make, Node (optional)

- **Linux/WSL2**: `sudo apt install python3 make` (Node optional:
  `nodejs npm`).
- **Windows**: install Python 3 from python.org; Make comes with the OSS CAD
  Suite shell or via MSYS2/Git-Bash. Node from nodejs.org.

### 2.4 Windows-native vs WSL2 / Linux notes

The Vivado TCL scripts use **Windows-style paths** (`set base_dir
C:/rv64fp_build`) and the shell helpers look for Vivado under `/c/Xilinx/...`.
Two supported setups:

- **Windows-native (matches the scripts as written):** Run Vivado from a
  Windows shell. Copy a variant's source tree into `C:\rv64fp_build` (see
  §4). `asm2hex.py` and `make` run from Git-Bash or the OSS CAD Suite shell.
- **WSL2 / Linux:** Vivado runs natively on Linux too. Either (a) edit the
  `set base_dir ...` line in each `scripts/*.tcl` and the `proj_dir` in
  `sim/run_tests.tcl` to a Linux path, or (b) keep the manual
  `xvlog`/`xelab`/`xsim` flow (§4.2) which takes plain relative paths and
  needs no base-dir edit. Formal verification (SymbiYosys) is Linux/WSL2
  native and needs no path changes.

> **`$readmemh` path caveat (from the skill's sharp-edges notes):** in Vivado
> batch mode `$readmemh` needs an absolute path to the `.hex` file. The
> `build.tcl`/`run_tests.tcl` scripts resolve this by copying the variant
> tree to `$base_dir` so the testbench's hard-coded paths line up. If you
> change `base_dir`, keep `rtl/`, `sim/`, and `sw/` consistent underneath it.

---

## 3. Clone & Repo Layout

```bash
git clone https://github.com/george11642/RISC-V-FPGA-Processors.git
cd RISC-V-FPGA-Processors
```

```
verilog/                 vhdl/                  # six variants, two languages
  rv16/    rv64/   rv64fp/   (mirrored under vhdl/)
    rtl/         # HDL source (.v / .vhd)
    constraints/ # basys3.xdc pin + clock constraints
    sw/          # asm2hex.py assembler + .s programs + .hex outputs
    sim/         # testbenches + run_tests.tcl + run_sim.sh
    scripts/     # build.tcl (synth+impl+bitstream), program.tcl
formal/
  scripts/       # Makefile, run_formal_vivado.tcl, sby/*.sby configs
  <variant>/     # SVA modules (sva_*.sv) + sva_binds.sv per variant
.claude/skills/fpga/   # the reusable framework (see LAB_SETUP.md)
latex/                 # the manuscript sources (main_tcad_9pg.tex)
```

Variant summary:

| Variant | Datapath | Pipeline | ISA | Instr. | LUTs (paper) |
|---------|----------|----------|-----|--------|--------------|
| rv16    | 16-bit | 3-stage | RV32I subset | 12 | ~400 |
| rv64    | 64-bit | 3-stage | RV64I | 40 | 3,273 |
| rv64fp  | 64-bit | 5-stage + IEEE-754 FPU | RV64IFD | 68 | **12,969** |

(Verilog and VHDL builds report identical LUT counts.)

---

## 4. Per-Variant Workflow

The examples below use `verilog/rv64fp` (the most complex variant). The same
steps apply to every variant directory — substitute the path. The build/sim
TCL scripts expect the variant's `rtl/`, `sim/`, `sw/`, and `constraints/`
to live under `base_dir` (default `C:/rv64fp_build`), so the first step on
Windows is to stage the tree:

```bash
# Windows: stage the variant where the scripts expect it
cp -r verilog/rv64fp/* /c/rv64fp_build/      # or copy in Explorer
```

(On Linux/WSL2, edit `base_dir`/`proj_dir` in the scripts to your path, or
use the manual flow in §4.2.)

### 4.1 Assemble a test program

The assembler turns RV64I(FD) assembly into a `$readmemh`-loadable hex image:

```bash
cd verilog/rv64fp/sw
python asm2hex.py demo_all_ops.s demo_all_ops.hex   # usage: asm2hex.py in.s out.hex
```

Prebuilt `.hex` files ship in `sw/` (`demo_all_ops`, `demo_fma`,
`demo_golden`, `demo_knight`, `demo_pi`, `demo_sqrt`, plus `program.hex` which
is the image the top-level testbench/bitstream loads). To select a demo as the
active program:

```bash
./load_demo.sh fma     # copies sw/demo_fma.hex -> sw/program.hex, then rebuild
```

### 4.2 Simulation (xsim)

**Scripted (recommended)** — compiles RTL + testbench, elaborates, runs, and
exits 0 on pass / 1 on fail:

```bash
cd verilog/rv64fp/sim
vivado -mode batch -source run_tests.tcl                 # default tb: tb_rv64fp_full
vivado -mode batch -source run_tests.tcl -tclargs tb_alu # pick a testbench
```

Available testbenches in `sim/`: `tb_alu.v` (ALU unit tests),
`tb_fpu_ops.v` (per-operation FPU regression — this is where the 10 FPU bugs
were caught), `tb_rv64fp_full.v` (full-system, runs a program for 2,000+
cycles and maps FPU results to LED bits). A `run_sim.sh` wrapper is also
provided (`./run_sim.sh all`).

**Manual flow** (no base-dir staging needed — runs from the variant dir):

```bash
cd verilog/rv64fp
xvlog rtl/*.v                                  # compile RTL
xvlog sim/tb_fpu_ops.v                         # compile testbench
xelab tb_fpu_ops -s snap -timescale 1ns/1ps    # elaborate
xsim snap -R                                   # run to completion
```

A passing run prints an `ALL ... PASSED` banner; the scripted path keys its
exit code off that string.

### 4.3 Synthesis + Implementation (build.tcl)

```bash
# (Windows) after staging into C:/rv64fp_build:
vivado -mode batch -source verilog/rv64fp/scripts/build.tcl
```

`build.tcl` creates the Vivado project, adds `rtl/*.v` and
`constraints/*.xdc`, sets the top module (`rv64fp_top`), then runs synthesis
and implementation through `write_bitstream`. It errors out if either stage
does not reach `Complete!`.

**Where the `.bit` lands:**

```
C:/rv64fp_build/vivado_project/rv64fp_mcu.runs/impl_1/rv64fp_top.bit
```

LUT/DSP utilization is reported by Vivado at the end of implementation
(`report_utilization`); this is the number to compare against the paper's
12,969 LUTs / 18 DSPs / 82.9%.

### 4.4 Program the board (program.tcl)

Connect the Basys 3 via micro-USB, power it on, then:

```bash
vivado -mode batch -source verilog/rv64fp/scripts/program.tcl
```

`program.tcl` opens the hardware manager, targets `xc7a35t_0`, and pushes the
bitstream produced by `build.tcl`. (`build.tcl` also auto-programs at the end;
comment out its programming block if no board is attached.) The 16 Basys 3
LEDs display the program's GPIO output.

### 4.5 Formal verification

Formal runs use the Makefile in `formal/scripts`. Source the OSS CAD Suite
environment first so `sby` and `z3` are on `PATH`.

```bash
cd formal/scripts

# --- SymbiYosys BMC (true formal) ---
make formal-rv16        # rv16_alu + rv16_reset
make formal-rv64        # rv64_alu
make formal-rv64fp      # rv64fp_alu, rv64fp_fpu, rv64fp_hazard, rv64fp_reset, rv64fp_mem_bus
make formal-all         # all of the above

# --- Vivado xsim assertion checking (SVA in simulation) ---
make vivado-rv16
make vivado-rv64
make vivado-rv64fp
make vivado-all

make clean              # remove generated sby/ and xsim_* output
```

These targets prove the property categories in the paper's Table II:
ALU correctness (depth 1, combinational), FPU protocol + IEEE-754 special
values (depth 120), hazard detection (depth 10), reset synchronizer
(depth 10), and memory-bus protocol (depth 10) — all reported PASS.

---

## 5. Claim → Command Map

| Paper claim | Where reported | Command that regenerates / verifies it |
|-------------|----------------|----------------------------------------|
| rv64fp = **12,969 LUTs, 18 DSP48E1, 82.9% of XC7A35T** | §V, Table I | `vivado -mode batch -source scripts/build.tcl` → read `report_utilization` after `impl_1` |
| rv64 = 3,273 LUTs; rv16 ≈ 400 LUTs | Table I | same `build.tcl` in `verilog/rv64`, `verilog/rv16` |
| Identical Verilog/VHDL LUT counts | Table I | run `build.tcl` under `vhdl/<variant>` and compare |
| **10 FPU bugs caught in simulation** | §IV-A | `vivado -mode batch -source run_tests.tcl -tclargs tb_fpu_ops` (per-op FPU regression) |
| Full-system program runs 2,000+ cycles | §IV-A | `run_tests.tcl -tclargs tb_rv64fp_full` |
| **48% LUT reduction (~25,000 → 12,969)**; fp_fma 13,932 → 1,942 (86%) | §V | the optimized RTL in `rtl/` builds to 12,969 via `build.tcl`; the figure is the before/after of the design history (Fig. 4) |
| FPU protocol + IEEE-754 proved at **BMC depth 120** | §IV-B, Table II | `make formal-rv64fp` (runs `rv64fp_fpu.sby`) |
| ALU proved at depth 1; hazard/reset/mem-bus at depth 10 | Table II | `make formal-rv64fp`, `make formal-rv64`, `make formal-rv16` |
| 16 SVA modules / ~1,500 lines, bind-based (no RTL edits) | §IV-B | inspect `formal/<variant>/sva_*.sv` and `sva_binds.sv` |
| Hardware validation on Basys 3 @ 100 MHz | §III, §V | `program.tcl` → observe 16 LEDs |

---

## 6. Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| LUT count differs from 12,969 | **Vivado version mismatch.** Use 2020.2; later releases pack logic differently. Confirm `vivado -version`. |
| `glob` finds no files / `base_dir` errors | TCL path issue. The scripts expect the variant tree under `base_dir` (`C:/rv64fp_build`). Either stage it there (§4) or edit `set base_dir`/`set proj_dir` to your path. |
| `$readmemh` cannot open hex | Needs an **absolute** path in batch mode. Ensure `sw/program.hex` exists under `base_dir/sw/`. |
| `sby: command not found` / `z3` missing | OSS CAD Suite environment not sourced. `source <oss-cad-suite>/environment`, then `sby --version`. |
| Formal target says solver unavailable | Z3 not on `PATH`; the `.sby` configs use the SMT/Z3 engine — re-source the OSS CAD Suite. |
| Board not detected by `program.tcl` | Cable drivers not installed, board off, or USB cable is power-only. Reinstall Vivado cable drivers; check `connect_hw_server` sees `xc7a35t_0`. |
| `write_bitstream Complete!` check fails | Implementation hit a timing or DRC error — open the project GUI to inspect the impl report; the design closes timing at 100 MHz but custom edits can break it. |
| Vivado out-of-memory during synthesis | rv64fp is large (82.9% util). Use ≥ 16 GB RAM or reduce `-jobs` in `build.tcl`. |

---

For deploying the reusable framework (the FPGA skill + Claude Code) on lab
machines so students can do similar AI-assisted HDL work, see
[LAB_SETUP.md](LAB_SETUP.md).
