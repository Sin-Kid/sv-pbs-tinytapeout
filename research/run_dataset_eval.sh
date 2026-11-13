#!/bin/sh
# Synthetic dataset evaluation of the taped-out RTL (baseline vs proposed).
set -e
cd "$(dirname "$0")"
mkdir -p results
python3 model/generate_dataset.py
iverilog -g2012 -o sim_compare.out $(ls ../src/*.v | grep -v project.v) reference_rtl/*.v testbench/tb_compare.v
vvp -n sim_compare.out
python3 model/evaluate.py
