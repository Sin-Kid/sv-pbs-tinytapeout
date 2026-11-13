#!/bin/sh
# Proves the taped-out RTL (src/) gives bit-identical results to the original
# SV-PBS V2.1 RTL (research/reference_rtl/) for every sample.
set -e
cd "$(dirname "$0")"
SRC=../src
iverilog -g2012 -o equiv.out reference_rtl/*.v \
  $SRC/sv_pbs_core.v $SRC/moving_average3.v $SRC/sensor_validator.v \
  $SRC/thermal_predictor.v $SRC/proposed_controller.v \
  testbench/tb_equiv.v
for seed in 1 7 42 1234 99; do vvp -n equiv.out +seed=$seed | grep -E "Samples|EQUIVALENT|MISMATCH"; done
