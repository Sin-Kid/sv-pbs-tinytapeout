![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Design and Implementation of a MOSFET-Based Adaptive Battery Safety Monitoring and Protection ASIC Using CMOS Technology

**SV-PBS: Sensor-Validated Predictive Battery Safety.** A Tiny Tapeout (SKY130) project from RV College of Engineering.

Author: Pavan G

- [Project datasheet / documentation](docs/info.md)

## Overview

SV-PBS is a digital battery-protection controller implemented as a SKY130 CMOS ASIC tile. It receives battery voltage, current and temperature samples and decides whether the cell should run normally, be derated, or be disconnected. Disconnection is requested on the ISOLATE pin, which drives an external protection MOSFET through a gate driver.

Conventional fixed-threshold protection reacts only after a limit is crossed, and it cannot tell a real battery fault from a faulty sensor. SV-PBS adds three things:

- **Sensor validation:** range and stuck-sensor checks. A sensor fault derates the battery but does not disconnect it on its own.
- **Thermal trend prediction:** an 8-sample temperature-rise detector that warns before the hard limit is reached.
- **Adaptive recovery:** the battery is reconnected only after several consecutive safe samples.

A fixed-threshold **baseline controller** is integrated alongside it, so both strategies can be compared on the same silicon.

## Architecture

```
ui_in (bytes) ──► sample ring buffer ──► 3-sample moving average ──┬─► sensor validator ──┐
                  (3 slots/channel)      (shared bit-serial ÷3)    ├─► thermal predictor ─┤
                                                                   ├─► baseline controller│──► uo_out / uio_out
                                                                   └─► proposed controller ◄┘
```

| File | Function |
|---|---|
| `src/project.v` | Tiny Tapeout wrapper `tt_um_rvce_sv_pbs`: byte protocol, pin mapping |
| `src/sv_pbs_core.v` | Core integration |
| `src/moving_average3.v` | Sample buffer, moving-average filter, change detection |
| `src/sensor_validator.v` | Range and stuck-sensor checks, fault codes |
| `src/thermal_predictor.v` | 8-sample temperature-rise predictor |
| `src/baseline_controller.v` | Fixed-threshold reference controller |
| `src/proposed_controller.v` | Adaptive controller: normal / warning / critical / sensor-degraded |

## Pinout

| Pin | Direction | Function |
|---|---|---|
| ui[7:0] | in | Sample data byte |
| uio[0] | in | BYTE_STROBE |
| uio[1] | in | SAMPLE_COMMIT |
| uo[1:0] | out | Proposed state (0 normal, 1 warning, 2 critical, 3 sensor degraded) |
| uo[2] | out | DERATE |
| uo[3] | out | ISOLATE (MOSFET gate request) |
| uo[4] | out | SENSOR_DEGRADED |
| uo[5] | out | THERMAL_RISK |
| uo[6] | out | Baseline isolate |
| uo[7] | out | Baseline derate |
| uio[4:2] | out | Sensor fault code |
| uio[6:5] | out | Baseline state |
| uio[7] | out | BUSY |

See [docs/info.md](docs/info.md) for the byte protocol and a worked example.

## Implementation for one tile

The original V2.1 RTL synthesized to about 18,500 µm² of SKY130 standard cells, which is larger than a whole 1x1 tile (about 160 × 110 µm). The taped-out RTL keeps exactly the same behaviour in about 11,500 µm², roughly 70% of the tile, by:

- replacing three combinational divide-by-3 circuits with one shared, exact, bit-serial divider (about 56 clock cycles per sample, 5.6 µs at 10 MHz);
- storing samples in a 3-slot ring buffer per channel that bytes are written into directly;
- computing the stuck-sensor change flags while the new filtered value is shifted in, with a 4-bit saturating difference instead of separate 16-bit registers and subtractors;
- removing resets from registers that are always written before they are read.

`src/config.json` sets `CLOCK_PERIOD` to 100 ns (10 MHz) and `PL_TARGET_DENSITY_PCT` to 80, within the range the template recommends, because the design fills about 70% of the tile.

## Verification

- `test/`: a cocotb test suite with 9 tests. It covers reset and pin directions, nominal operation, over-temperature, over-voltage and over-current, a stuck sensor that degrades without isolating, thermal prediction before the hard limit, recovery hysteresis, and the BUSY handshake. The same tests run on the gate-level netlist in the GDS workflow.
- `research/run_equivalence.sh`: compares the taped-out core with the original V2.1 RTL (`research/reference_rtl/`) on more than 27,000 directed, boundary and random samples. Every output matches bit for bit. The test was checked by injecting deliberate bugs, and all of them were detected.
- `research/run_dataset_eval.sh`: synthetic-dataset comparison of the baseline and proposed controllers (`research/model/`).

Run the tests locally:

```sh
cd test && make            # cocotb, needs iverilog + cocotb
cd research && ./run_equivalence.sh && ./run_dataset_eval.sh
```

## Limitations

The evaluation uses synthetic sensor data and illustrative Li-ion thresholds, not measured cell data. The thermal predictor is a fixed-window trend rule, not a trained machine-learning model. The chip produces protection decisions; the MOSFET switch, gate driver and analog sensing front end are external. This is an academic research design, not a certified battery management system.

## Credits

We gratefully acknowledge the Center of Excellence (CoE) in Integrated Circuits and Systems (ICAS) and the Department of Electronics and Communication Engineering (ECE) for providing the necessary resources and guidance.

Special thanks to Dr. H V Ravish Aradhya (HoD - ECE), Dr. K R Usha Rani (Associate Dean - PG), Dr. K. S. Geetha (Vice Principal) and Dr. K. N. Subramanya (Principal) for their constant encouragement and support in facilitating this Tiny Tapeout SKY26D submission.

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that makes it easier and cheaper than ever to get digital and analog designs manufactured on a real chip. Visit https://tinytapeout.com to learn more.
