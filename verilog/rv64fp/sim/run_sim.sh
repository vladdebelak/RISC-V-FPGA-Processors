#!/bin/bash
# ===========================================================================
# run_sim.sh — Shell script to run rv64fp simulation with Vivado xsim
#
# Usage:
#   ./run_sim.sh                  # runs tb_rv64fp_full (default)
#   ./run_sim.sh tb_alu           # runs ALU unit test
#   ./run_sim.sh tb_fpu_ops       # runs FPU unit tests
#   ./run_sim.sh all              # runs all three testbenches
#
# Prerequisites:
#   - Vivado 2020.2 installed
#   - program.hex in C:/rv64fp_build/sw/ (for full system test)
# ===========================================================================

set -e

# Vivado installation path — adjust if different
VIVADO_BIN="/c/Xilinx/Vivado/2020.2/bin"

# If Vivado isn't at the default path, try to find it
if [ ! -d "$VIVADO_BIN" ]; then
    # Try Windows-style path
    if [ -d "/c/Xilinx/Vivado/2024.1/bin" ]; then
        VIVADO_BIN="/c/Xilinx/Vivado/2024.1/bin"
    elif [ -d "/c/Xilinx/Vivado/2023.2/bin" ]; then
        VIVADO_BIN="/c/Xilinx/Vivado/2023.2/bin"
    elif [ -d "/c/Xilinx/Vivado/2022.2/bin" ]; then
        VIVADO_BIN="/c/Xilinx/Vivado/2022.2/bin"
    elif command -v xvlog &> /dev/null; then
        VIVADO_BIN=""  # Already in PATH
    else
        echo "ERROR: Cannot find Vivado installation."
        echo "Edit VIVADO_BIN in this script to point to your Vivado bin directory."
        exit 1
    fi
fi

# Prefix commands with path if needed
if [ -n "$VIVADO_BIN" ]; then
    XVLOG="$VIVADO_BIN/xvlog"
    XELAB="$VIVADO_BIN/xelab"
    XSIM="$VIVADO_BIN/xsim"
else
    XVLOG="xvlog"
    XELAB="xelab"
    XSIM="xsim"
fi

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"
RTL_DIR="$PROJ_DIR/rtl"
SIM_DIR="$SCRIPT_DIR"
SW_DIR="$PROJ_DIR/sw"

# Work from sim directory
cd "$SIM_DIR"

# Testbench selection
TB="${1:-tb_rv64fp_full}"

# ===========================================================================
# Function: run one testbench
# ===========================================================================
run_testbench() {
    local tb_name="$1"
    local snapshot="sim_${tb_name}"

    echo ""
    echo "================================================================"
    echo " Running: $tb_name"
    echo "================================================================"
    echo ""

    # Ensure program.hex is available for full system test
    if [ "$tb_name" = "tb_rv64fp_full" ]; then
        if [ -f "$SW_DIR/demo_all_ops.hex" ]; then
            cp "$SW_DIR/demo_all_ops.hex" "$SW_DIR/program.hex"
            echo "Copied demo_all_ops.hex -> program.hex"
        elif [ ! -f "$SW_DIR/program.hex" ]; then
            echo "WARNING: No program.hex found in $SW_DIR"
            echo "Full system test may fail."
        fi
    fi

    # Clean previous artifacts
    rm -rf xsim.dir xvlog.log xelab.log xsim.log webtalk* .Xil 2>/dev/null || true

    # Step 1: Compile all RTL sources
    echo "=== Compiling RTL ==="
    $XVLOG "$RTL_DIR"/*.v 2>&1 | tail -5
    echo ""

    # Step 2: Compile testbench
    echo "=== Compiling Testbench: $tb_name ==="
    $XVLOG "$SIM_DIR/${tb_name}.v" 2>&1 | tail -5
    echo ""

    # Step 3: Elaborate
    echo "=== Elaborating ==="
    $XELAB "$tb_name" -s "$snapshot" -timescale 1ns/1ps 2>&1 | tail -5
    echo ""

    # Step 4: Run simulation
    echo "=== Running Simulation ==="
    local sim_output
    sim_output=$($XSIM "$snapshot" -R 2>&1)
    echo "$sim_output"
    echo ""

    # Check result
    if echo "$sim_output" | grep -qi "ALL.*PASSED"; then
        echo ">>> $tb_name: PASS <<<"
        return 0
    else
        echo ">>> $tb_name: FAIL (or inconclusive) <<<"
        return 1
    fi
}

# ===========================================================================
# Main
# ===========================================================================

overall_result=0

if [ "$TB" = "all" ]; then
    echo "Running ALL testbenches..."

    for tb in tb_alu tb_fpu_ops tb_rv64fp_full; do
        if run_testbench "$tb"; then
            echo "  $tb -> PASS"
        else
            echo "  $tb -> FAIL"
            overall_result=1
        fi
    done

    echo ""
    echo "================================================================"
    if [ $overall_result -eq 0 ]; then
        echo " ALL TESTBENCHES PASSED"
    else
        echo " SOME TESTBENCHES FAILED"
    fi
    echo "================================================================"
else
    run_testbench "$TB" || overall_result=1
fi

exit $overall_result
