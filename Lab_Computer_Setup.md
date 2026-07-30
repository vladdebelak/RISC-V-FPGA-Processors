# Lab Computer Setup for FPGA Programming with Claude

Target board: **Digilent Nexys A7-100T** (Xilinx Artix-7 `XC7A100T-1CSG324C`)
Design: **rv16** (16-bit RISC-V MCU)

> **Note:** If you do not use the same lab computer each week, repeat these steps
> each session. The OSS CAD Suite *install* is one-time per machine but Step 2 (Claude login)
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


> The environment script only affects the window you run it in, and its effect is
> gone when you close that window. So each session: run `environment.bat`, then
> start `claude` in the same window. If you land on a different machine (or the lab
> wipes files between sessions), redo the one-time install too.

---

## Step 1: Get the project + skill

Open up **Windows PowerShell** and run the following commands to give Claude the FPGA skill:


```powershell
cd $env:USERPROFILE
git clone https://github.com/vladdebelak/RISC-V-FPGA-Processors.git
```


```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills" | Out-Null
Copy-Item -Recurse -Force `
  "$env:USERPROFILE\RISC-V-FPGA-Processors\.claude\skills\fpga" `
  "$env:USERPROFILE\.claude\skills\fpga"
```

You should now have `C:\Users\<you>\.claude\skills\fpga\SKILL.md`, where `<you>`
is your Windows user-profile name.

> **What is `$env:USERPROFILE`?** It's PowerShell shorthand for your own user
> folder, `C:\Users\<your-name>`. You do **not** type your name — PowerShell fills
> it in automatically, so the commands above work as-is. 
---

## Step 2: Set up your Claude account

1. In the **same PowerShell window** you used in Step 1,
   run: `claude`
2. Pick your color theme; it opens a browser to create/log into your account.
3. After creating your account and choosing a plan, return to PowerShell — you
   are now in Claude Code.
4. **Restart Claude Code once** (exit and run `claude` again) so it loads the
   `fpga` skill you installed in Step 2.

Confirm the skill loaded by asking Claude: `what skills do you have?` — you should
see **fpga** listed.

---

## Step 3: Install SymbiYosys + Z3 (required for formal verification)

The only extra tool beyond the lab image is the OSS CAD Suite (SymbiYosys + Yosys
+ Z3). To install SymbiYosys + Z3 tell Claude:

>"Install SymbiYosys + Z3 from: https://github.com/YosysHQ/oss-cad-suite-build/releases and put it onto my user path"

Claude will install SymbiYosys + Z3 for you and put it onto your user path so that you can use it in the future as long as you are using the same computer.

---

## Step 4: Use Claude-Code to create code for the FPGA

- Go to your Documents File and create a new folder where you want Claude to put the code
- Go back to the terminal and tell Claude:
  
  > "/fpga In Documents>FolderName for a 16 but Nexys A7 board 
  > create a design and constraint file that programs the board to: (whatever you want the board to do).
  > Write self-checking test benches."

Note: You generally want to tell Claude where you want the code, what kind of board is being used (in this lab it is a 16 but Nexys A7), the kind of files you need (you will always need a design and constraint file, Claude will also include a simulation file as well in your folder), what you want the program to do, and that Claude needs to use self-checking test benches so that it can check that the code works.

---

## Step 5: Put the created code into Vivado 

You should be able to look inside your folder and see the code that Claude has created. 

- Open up Vivado and add the files Claude created
- Generate the Bitstream
- Program the Board

Note: Watch the videos in Step 6 for more detailed instructions. 

 ---

## Step 6: Instruction videos on how to use this framework

Here are two videos that will show you how to use what you have setup with Claude:

### Simple Problem

[![Simple Problem](http://i.ytimg.com/vi/MugMniXK1BQ/hqdefault.jpg)](https://www.youtube.com/watch?v=MugMniXK1BQ)

### Complex Problem

[![Complex Problem](http://i.ytimg.com/vi/kJRBA2rNGUs/hqdefault.jpg)](https://www.youtube.com/watch?v=kJRBA2rNGUs)

