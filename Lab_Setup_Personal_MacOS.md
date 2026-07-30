# Lab Setup on Your Personal MacOS Machine

This is how you can work on programming FPGA Boards from your personal MacOS machine

1. Install Vivado
   - Use these instructions: [Vivado Installation Instructions](https://github.com/vladdebelak/RISC-V-FPGA-Processors/blob/main/VivadoInstallation2020_1.pdf)
   - Note: To install Vivado on Mac you will need a windows emulator 

2. Install Git Bash
   - Opent the terminal
   - Run the following command to install Homebrew: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
   - After Homebrew has been installed, run: `brew install git` (You may have to cloase and then reopen the terminal first)

3. Install Python
   - Run the command in the terminal to install python: `brew install python`
   - Now you need to add python to your path
     - In the terminal run: `nano ~/.profile`
     - Add the following line: `export PATH="/usr/local/opt/python/libexec/bin:$PATH"`
     - To save press `CTRL + X`, then `Y` and then press `ENTER`
     - Now run: `source ~/.profile`
    
4. Install Claude-Code
   - Run this command in the terminal to instal Node.js: `brew install node`
   - Now run: `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash`
   - Now to install Claude-Code run: `npm install -g @anthropic-ai/claude-code`
   - Now you need to add Cluade to your path 
     - In the terminal run: `nano ~/.profile`
     - Add the following line: `export PATH=~/.npm-global/bin:$PATH`
     - To save press `CTRL + X`, then `Y` and then press `ENTER`
     - Now run: `source ~/.profile`

5. Install SymbiYosys + Z3
   - Run these commands to install Yosys and Z3: `brew install yosys`, and `brew install z3`,
   - Now run these commands to install SymbiYosys: `git clone https://github.com/YosysHQ/sby.git`, `cd sby`, and `sudo make install`
   - Now you need to add SymbiYosys + Z3 to your path 
     - In the terminal run: `nano ~/.profile`
     - Add the following line: `export PATH="$HOME/oss-cad-suite/bin:$PATH"`
     - To save press `CTRL + X`, then `Y` and then press `ENTER`
     - Now run: `source ~/.profile`

6. Now you can follow [Lab_Computer_Setup.md](https://github.com/vladdebelak/RISC-V-FPGA-Processors/blob/main/Lab_Computer_Setup.md) to finish the setup and get started.

   - Note: Since you already have installed SymbiYosys + Z3 and put it in the path, ignore Step 1 from [Lab_Computer_Setup.md](https://github.com/vladdebelak/RISC-V-FPGA-Processors/blob/main/Lab_Computer_Setup.md)
   - Note: Step 2 will be different on MacOS, instead use the following commands:
     - `cd ~`
     - `git clone https://github.com/vladdebelak/RISC-V-FPGA-Processors.git`
     - `mkdir -p ~/.claude/skills`
     - `cp -R ~/RISC-V-FPGA-Processors/.claude/skills/fpga ~/.claude/skills/fpga`


