# Research material (not part of the chip)

This folder is not used by the Tiny Tapeout workflows. Nothing here is listed in `info.yaml`.

| Path | Content |
|---|---|
| `reference_rtl/` | Original SV-PBS V2.1 RTL, with modules renamed `ref_*` |
| `testbench/tb_equiv.v` | Equivalence test: original V2.1 core (inputs clipped to full scale) vs taped-out core |
| `testbench/tb_compare.v` | Dataset evaluation: taped-out core (proposed) and original core (baseline) |
| `model/` | Synthetic dataset generator, metrics and noise sweep |
| `run_equivalence.sh` | Runs the equivalence test with five random seeds |
| `run_dataset_eval.sh` | Generates the dataset, simulates it and prints the metrics |

`python3 model/noise_sweep.py` repeats the evaluation at noise levels 0, 2, 5 and 10.

The original `tb_compare.v` printed the outputs one clock after each sample. At that point the controllers still showed the previous sample's decision. The new testbench waits until BUSY is low, so each row's filtered values and decisions belong to the same sample. Metrics from the old script may therefore differ slightly.
