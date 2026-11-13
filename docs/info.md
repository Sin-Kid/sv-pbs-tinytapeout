<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

SV-PBS (Sensor-Validated Predictive Battery Safety) is a digital battery-protection controller. It receives voltage, current and temperature samples of a battery cell and decides whether the battery should run normally, be derated, or be disconnected. The **ISOLATE** output is meant to drive the gate driver of an external protection MOSFET that disconnects the cell.

Each sample passes through four stages:

1. **Moving-average filter.** Each channel is averaged over the last three samples to suppress noise. Samples are stored in a 3-slot ring buffer per channel, at the sensors' full-scale widths: voltage 13 bit (up to 8191 mV), current 11 bit (up to 2047 mA) and temperature 11 bit (up to 204.7 °C). Larger readings are clipped to those maxima. One shared, exact, bit-serial divide-by-3 unit processes the three channels one after another, which takes about 47 clock cycles. While a sample is being processed, the BUSY output is high.
2. **Sensor validator.** This stage checks plausibility:
   - voltage outside 2.5–5.0 V, current above 1.0 A or temperature above 80.0 °C counts as a sensor fault;
   - a reading stuck at the same value for 9 samples while another channel is clearly moving counts as a stuck sensor.

   A fault raises **SENSOR_DEGRADED** and gives a fault code. A sensor fault alone never disconnects the battery.
3. **Thermal trend predictor.** This stage compares the temperature at the start and end of an 8-sample window. A rise of at least 1.2 °C raises **THERMAL_RISK** before the hard temperature limit is reached.
4. **Controllers.**
   - The **proposed adaptive controller** isolates the battery only for validated hard limits: T ≥ 50.0 °C, V > 4.6 V, V < 2.6 V or I > 1.0 A. A sensor fault gives the separate SENSOR_DEGRADED state with derating, and T ≥ 43.0 °C, I > 0.3 A or a predicted thermal risk gives WARNING with derating. It returns to NORMAL only after 4 consecutive safe samples (T < 39.0 °C, I < 0.25 A, 2.8 V ≤ V ≤ 4.4 V).

| Proposed state (uo[1:0]) | Meaning |
|---|---|
| 0 | Normal |
| 1 | Warning (derate) |
| 2 | Critical (derate + isolate) |
| 3 | Sensor degraded (derate, battery kept connected) |

| Fault code (uio[4:2]) | Meaning |
|---|---|
| 0 | No fault |
| 1 | Voltage out of sensor range |
| 2 | Current out of sensor range |
| 3 | Temperature out of sensor range |
| 4 | Voltage sensor stuck |
| 5 | Current sensor stuck |
| 6 | Temperature sensor stuck |

Units: voltage in mV, current in mA and temperature in 0.1 °C. All thresholds are illustrative values for a Li-ion cell. For comparison, a fixed-threshold baseline controller was evaluated in simulation (see the `research` folder in the repository); it is not part of the chip.

## How to test

A sample is sent as six bytes on `ui_in[7:0]`:

| Byte | Content |
|---|---|
| 0 | voltage[15:8] |
| 1 | voltage[7:0] |
| 2 | current[15:8] |
| 3 | current[7:0] |
| 4 | temperature[11:4] |
| 5 | temperature[3:0] on ui_in[3:0] |

1. Reset the design and keep `ena` high. The clock is 10 MHz.
2. For each byte, put it on `ui_in` and pulse **BYTE_STROBE** (`uio[0]`) high for exactly one clock.
3. After byte 5, pulse **SAMPLE_COMMIT** (`uio[1]`) high for one clock.
4. Wait until **BUSY** (`uio[7]`) goes low, which takes about 50 clocks. Then read the outputs. Inputs are ignored while BUSY is high.

Outputs: `uo[1:0]` state, `uo[2]` DERATE, `uo[3]` ISOLATE, `uo[4]` SENSOR_DEGRADED, `uo[5]` THERMAL_RISK, `uo[6]` WARNING and `uo[7]` CRITICAL (state decoded for LEDs), `uio[4:2]` fault code, `uio[7]` BUSY.

For example, the sample V = 3700 mV, I = 200 mA, T = 30.0 °C is sent as bytes `0E 74 00 C8 12 0C`. Repeating it gives state 0 with all flags low. Sending T = 55.0 °C (`22 06` as bytes 4–5) a few times gives state 2 with ISOLATE high.

The first two samples after reset pass through unfiltered (filter warm-up).

## External hardware

- A microcontroller or the RP2040 on the Tiny Tapeout demo board, to send sensor samples (for example from an ADC or INA219/INA226 current/voltage monitor and a thermistor).
- Optional: a gate driver and N-channel protection MOSFET driven by ISOLATE (uo[3]), and LEDs on WARNING, CRITICAL, SENSOR_DEGRADED and THERMAL_RISK.

## Credits

We gratefully acknowledge the Center of Excellence (CoE) in Integrated Circuits and Systems (ICAS) and the Department of Electronics and Communication Engineering (ECE) for providing the necessary resources and guidance.

Special thanks to Dr. H V Ravish Aradhya (HoD - ECE), Dr. K R Usha Rani (Associate Dean - PG), Dr. K. S. Geetha (Vice Principal) and Dr. K. N. Subramanya (Principal) for their constant encouragement and support in facilitating this Tiny Tapeout SKY26D submission.
