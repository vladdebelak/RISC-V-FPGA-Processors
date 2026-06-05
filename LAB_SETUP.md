# Deploying the Framework on Lab Machines

This guide is for equipping lab computers (e.g. ~20 machines, ~60 students per
class) so future students can do **AI-assisted HDL work** of the kind this
repository demonstrates. The goal is not to copy this paper's processors onto
each machine — it is to install the **reusable framework** that produced them,
so students can generate, simulate, and verify *new* designs.

If you only want to reproduce this paper's exact numbers on one machine, see
[REPRODUCE.md](REPRODUCE.md) instead.

---

## 1. What "the Framework" Is

The framework is three things working together — **not** the HDL in this repo:

1. **The FPGA skill** — `.claude/skills/fpga/`. A self-contained knowledge
   pack that teaches Claude Code how to do FPGA work correctly:
   - `SKILL.md` — the master instructions (Vivado version awareness,
     Context7 documentation retrieval, the simulation-first TDD mandate,
     formal-verification workflow).
   - `references/patterns.md` — *how to build* (CDC synchronizers, FSM
     templates, BRAM inference, pipeline + forwarding, DSP48E1 usage).
   - `references/sharp_edges.md` — *known failure modes* and why they happen
     (e.g. `$readmemh` absolute-path requirement, Windows long-path issues).
   - `references/validations.md` — *strict review rules* the model checks
     designs against.
   - `references/formal_verification.md` — SVA bind templates and pitfalls.

2. **The simulation-first TDD workflow** — the methodology the skill enforces:
   write self-checking testbenches first, run them in `xsim` batch mode, and
   never synthesize or program a board until simulation passes. This is what
   caught 10 FPU bugs and drove a 48% LUT reduction in the paper.

3. **Claude Code** — the Anthropic CLI agent that loads the skill and does the
   work. Without it the skill is just documentation.

A student gets the framework's benefit by running Claude Code, with the FPGA
skill available, in a project that has Vivado and the verification tools
installed.

---

## 2. Per-Machine Install Checklist

Install on every lab machine:

| Tool | How | Notes |
|------|-----|-------|
| **Vivado 2020.2** | AMD/Xilinx installer | WebPACK edition covers the Basys 3 XC7A35T (free). Use a **campus floating license** if one exists. Install cable drivers for board programming. |
| **SymbiYosys + Z3** | OSS CAD Suite (YosysHQ) | Prebuilt bundle, includes `sby`, Yosys, Z3. Source its `environment` script. |
| **Python 3** | OS package / python.org | Runs the `asm2hex.py` assembler. |
| **Git** | OS package / git-scm.com | Cloning student/project repos. |
| **Node.js 18+** | nodejs.org / `nvm` | Required by Claude Code (and the optional `gen_article.js`). |
| **Claude Code (CLI)** | `npm install -g @anthropic-ai/claude-code` or the native installer | The AI agent. See §2.1. |

### 2.1 Installing Claude Code — IT / admin dependency

Claude Code is the Anthropic command-line agent. Install options:

```bash
# Option A — npm (requires Node.js 18+)
npm install -g @anthropic-ai/claude-code

# Option B — native installer (no Node needed for the runtime, but Node is
# still required for the FPGA tooling above)
# Linux/macOS/WSL2:
curl -fsSL https://claude.ai/install.sh | bash
```

Verify:
```bash
claude --version
```

> **IT dependency — flag this clearly.** All of the above are *global*
> installs (Vivado, OSS CAD Suite, a global npm package or the native Claude
> Code binary on `PATH`). On locked-down lab machines this requires **local
> administrator rights**. Plan to do this **with your IT/lab administrator**:
> they will need to (a) install Vivado 2020.2 and cable drivers, (b) place the
> OSS CAD Suite where students can source it, (c) allow the global
> `npm install -g` / native installer, and (d) ensure Node.js is on `PATH`.
> Students typically will *not* have rights to do these themselves.

A first run of `claude` will prompt the student to authenticate (see §5 on
licensing). Once authenticated, the session persists per user profile.

---

## 3. Making the FPGA Skill Available

The skill is a directory you copy. Two placements:

### Option A — per project (scoped to one repo)

Copy the skill into the project's `.claude/skills/`:

```bash
mkdir -p <project>/.claude/skills
cp -r .claude/skills/fpga <project>/.claude/skills/
```

The skill is then available to Claude Code sessions started inside
`<project>`. This is how it lives in *this* repo.

### Option B — user/global (available in every project)

Copy it to the per-user Claude config so it loads everywhere on that account:

```bash
mkdir -p ~/.claude/skills
cp -r .claude/skills/fpga ~/.claude/skills/
```

Recommended for lab machines: place it at the global level so any student
project picks it up without per-repo setup. The directory structure to
preserve is exactly:

```
fpga/
  SKILL.md
  references/
    patterns.md
    sharp_edges.md
    validations.md
    formal_verification.md
```

> If lab user profiles are wiped between sessions, either bake
> `~/.claude/skills/fpga/` into the machine image, or have students clone a
> starter repo that already contains `.claude/skills/fpga/` (Option A).

---

## 4. How a Student Uses It

1. Open a project directory (new or cloned) in a terminal where Vivado and the
   OSS CAD Suite environment are available.
2. Start Claude Code: `claude`.
3. Invoke the skill — say what you want, or trigger it explicitly:
   ```
   /fpga build a 32-bit RV32I core with a 5-stage pipeline targeting the Basys 3
   ```
   The skill auto-triggers on FPGA/Verilog/VHDL/RTL/synthesis keywords; the
   `/fpga` form forces it.
4. Describe the target design (ISA, datapath, board/part, clock).
5. **Let the simulation-first loop run.** The skill will write testbenches,
   run `xsim` in batch, fix RTL until tests pass, and only then move to
   synthesis and (optionally) formal verification with SymbiYosys. Students
   review the pass/fail output at each level.

This mirrors exactly the flow that produced the six processors in this repo.

---

## 5. Claude Code Licensing / Cost

Claude Code requires a Claude account. For sustained classroom use, consider
an individual **Claude Max** plan, which raises usage limits enough for
agentic HDL workloads; pay-as-you-go API billing is an alternative. The
accompanying email covers specific plan tiers, per-seat costs, and how to
provision accounts for a lab — refer to it for the cost decision.

---

## 6. Extending the Framework

The framework is meant to grow. To adapt it for new device families, boards,
or design classes, **edit the reference files** in `.claude/skills/fpga/`:

- **New FPGA family / board** (e.g. a Zynq or UltraScale lab board):
  - Add device-specific guidance to `references/patterns.md` (resource
    primitives — URAM/HBM availability, DSP variants) and update the
    version/device notes in `SKILL.md`.
  - Add the part's pitfalls to `references/sharp_edges.md`.
- **New Vivado version:** update the "Version Awareness" section of `SKILL.md`
  (TCL syntax, IP catalog, language support) so the skill tailors codegen to
  the version installed on the lab machines.
- **New design patterns** (e.g. AXI peripherals, cache hierarchies): add
  reusable templates to `references/patterns.md` and validation rules to
  `references/validations.md`.
- **New formal properties:** extend `references/formal_verification.md` with
  SVA bind templates; the per-variant `formal/` directories show the working
  pattern (separate `sva_*.sv` modules bound via `sva_binds.sv`, with a `.sby`
  config per property).

Because the skill is plain Markdown, edits are version-controlled like any
other source. Keep a single canonical copy in a starter repo and redistribute
to `~/.claude/skills/fpga/` on each machine when it changes.
