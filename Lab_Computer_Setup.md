# Lab Computer Setup for FPGA Programming with Claude

Target board: **Digilent Nexys A7-100T** (Xilinx Artix-7 `XC7A100T-1CSG324C`)
Design: **rv16** (16-bit RISC-V MCU)

> **Note:** If you do not use the same lab computer each week, repeat these steps
> each session. The OSS CAD Suite *install* is one-time per machine, but its
> `environment.bat` must be run every session (Step 1), and Step 3 (Claude login)
> may need repeating on shared machines.

---

## Before you start — prerequisites

Vivado, Git, Python, and Claude are already installed on the lab machines, and
**Vivado is already on the PATH**, so its simulator (`xvlog` / `xelab` / `xsim`)
just works. A quick sanity check in **Windows PowerShell** (all three should print
a version):

```powershell
git --version         # Git
python --version      # Python 3
xvlog --version       # Vivado simulator (runs the simulation-first workflow)
```

The only tool you still need to install is the OSS CAD Suite — see Step 1.

---

## Step 1: Install SymbiYosys + Z3 (required for formal verification)

The only extra tool beyond the lab image is the OSS CAD Suite (SymbiYosys + Yosys
+ Z3).

**One-time install (per machine):**

1. Download the latest Windows build:
   https://github.com/YosysHQ/oss-cad-suite-build/releases
2. Extract it, e.g. to `C:\oss-cad-suite`. The extracted files stay on disk — you
   do not reinstall each session.

**Every session** (this is how you make the tools available — no PATH editing):

3. Open **Windows PowerShell** and run the environment script:
   ```powershell
   C:\oss-cad-suite\environment.bat
   ```
4. Verify in that **same** window:
   ```powershell
   sby --version
   yosys --version
   ```

> The environment script only affects the window you run it in, and its effect is
> gone when you close that window. So each session: run `environment.bat`, then
> start `claude` in the same window. If you land on a different machine (or the lab
> wipes files between sessions), redo the one-time install too.

---

## Step 2: Get the project + skill

Clone the repository. It contains **both** the project (RTL, testbenches,
constraints) **and** the Claude FPGA skill under `.claude/skills/fpga`.

```powershell
cd $env:USERPROFILE
git clone https://github.com/vladdebelak/RISC-V-FPGA-Processors.git
```

Install the skill into your Claude account so it is available in every project:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills" | Out-Null
Copy-Item -Recurse -Force `
  "$env:USERPROFILE\RISC-V-FPGA-Processors\.claude\skills\fpga" `
  "$env:USERPROFILE\.claude\skills\fpga"
```

You should now have `C:\Users\<you>\.claude\skills\fpga\SKILL.md`.

---

## Step 3: Set up your Claude account

1. In the **same PowerShell window** where you ran `environment.bat` (Step 1),
   run: `claude`
2. Pick your color theme; it opens a browser to create/log into your account.
3. After creating your account and choosing a plan, return to PowerShell — you
   are now in Claude Code.
4. **Restart Claude Code once** (exit and run `claude` again) so it loads the
   `fpga` skill you installed in Step 2.

Confirm the skill loaded by asking Claude: `what skills do you have?` — you should
see **fpga** listed.

---

## Step 4: Run the simulation-first workflow

From inside the repo, tell Claude what you want, e.g.:

> "Work in `RISC-V-FPGA-Processors/verilog/rv16`. Follow the simulation-first
> workflow in the fpga skill: write/extend self-checking testbenches, run them
> with xsim, and make all tests pass before any synthesis."

Simulation and formal verification are **board-independent** — they work the same
no matter which board you target.

---

## Step 5: Build a bitstream for the Nexys A7-100T (hardware only)

The repo ships a ready-made Nexys A7-100T build script,
`verilog/rv16/scripts/build_nexys_a7.tcl` (already set to part
`xc7a100tcsg324-1` and `constraints/nexys_a7.xdc`) — nothing to edit. Just ask
Claude to build and program:

> "Build the rv16 bitstream for the Nexys A7-100T using build_nexys_a7.tcl, then
> program the connected board with program.tcl."

(The original `build_bitstream.tcl` still targets the Basys 3 if you ever need it.)

`program.tcl` auto-selects the board on the JTAG chain, so no device name needs
editing. The board must be connected via USB, powered on, and have Vivado cable
drivers installed.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `sby`/`yosys` not recognized | Run `C:\oss-cad-suite\environment.bat` in this window (and launch `claude` from it) — see Step 1. |
| Claude doesn't list the `fpga` skill | Skill not copied, or Claude Code not restarted — see Steps 2–3. |
| Board not detected by `program.tcl` | Cable drivers missing, board off, or a power-only USB cable. |
| Wrong LEDs / clock on hardware | Verify `nexys_a7.xdc` pins against the official Digilent Nexys A7-100T Master XDC. |
