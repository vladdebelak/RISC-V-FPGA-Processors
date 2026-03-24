#!/bin/bash
cp "sw/demo_${1}.hex" sw/program.hex
echo "Loaded demo_${1}. Rebuild to flash."
