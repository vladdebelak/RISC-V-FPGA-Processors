# Lab Setup on Your Personal Windows Machine

This is how you can work on programming FPGA Boards from your personal windows machine

1. Install Vivado
   - Use these instructions:
     
2. Install Git Bash
   - Download the Git for Windows/x64 Setup from: https://git-scm.com/install/windows
   - Open the downloaded file, follow the prompts and accept the default options
   - Now you have to add it to your path:
     - Search for "Edit the System Environment Variables" in the start menu
     - Click the "Environment Variable" button
     - Under the "User Variables" section edit the "Path"
     - Create a new path and put: `C:\Program Files\Git\bin`
    
3. Install Python
   - Download Python from https://www.python.org/downloads and dowload the latest installer
   - Open the downloaded installer
   - Follow the prompts and make sure you check the box that says "Add Python to Path" 
       
5. Install Claude
   - Open Windows Powershell as an Adminisrtator
   - Run this command: `irm https://claude.ai/install.ps1 | iex`
   - Now you have to add it to your path:
     - Search for "Edit the System Environment Variables" in the start menu
     - Click the "Environment Variable" button
     - Under the "User Variables" section edit the "Path"
     - Creat a new path and put: 'C:\Users\USERPROFRILE\.local\bin'
        - Note the USERPROFILE is what shows up after `C:\Users\` in Windows Powershell

6. Now you can follow [Lab_Computer_Setup.md](https://github.com/vladdebelak/RISC-V-FPGA-Processors/blob/main/Lab_Computer_Setup.md) to finish the setup and get started.
