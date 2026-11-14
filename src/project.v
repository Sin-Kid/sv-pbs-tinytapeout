/*
 * Copyright (c) 2026 Pavan G, Manali Kulkarni, Shylashree N, RV College of Engineering
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout wrapper for SV-PBS (Sensor-Validated Predictive Battery Safety).
 *
 * Byte-stream input protocol
 *   ui_in[7:0] : one byte of a sensor sample
 *   uio_in[0]  : byte strobe   (byte captured on every clock it is high)
 *   uio_in[1]  : sample commit (pulse once after all six bytes)
 *   Byte order: 0 voltage[15:8], 1 voltage[7:0], 2 current[15:8],
 *               3 current[7:0], 4 temperature[11:4], 5 temperature[3:0]
 *               (in ui_in[3:0]).
 *   Units: mV, mA, 0.1 degC. Values above 8191 mV / 2047 mA / 204.7 degC are
 *   clipped to those maxima.
 *   uio_out[7] (busy) is high for ~50 clocks after a commit; strobes and
 *   commits are ignored while busy.
 *
 * Outputs
 *   uo_out[1:0] proposed state (0 normal, 1 warning, 2 critical, 3 sensor-degraded)
 *   uo_out[2] proposed derate     uo_out[3] proposed isolate (MOSFET gate request)
 *   uo_out[4] sensor degraded     uo_out[5] predicted thermal risk
 *   uo_out[6] warning (state == 1) uo_out[7] critical (state == 2)
 *   uio_out[4:2] sensor fault code, uio_out[7] busy; uio[6:5] unused (inputs)
 */

`default_nettype none

module tt_um_rvce_sv_pbs (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    reg  [2:0]  byte_index;
    reg         sample_valid;

    wire [15:0] filtered_voltage;
    wire [15:0] filtered_current;
    wire [11:0] filtered_temperature;
    wire [1:0]  proposed_state;
    wire        proposed_derate, proposed_isolate;
    wire        sensor_degraded, predicted_risk;
    wire [2:0]  sensor_fault_code;
    wire        core_busy;

    wire busy          = core_busy | sample_valid;
    wire byte_strobe   = ena & uio_in[0] & ~busy;
    wire sample_commit = ena & uio_in[1] & ~busy & ~uio_in[0] & (byte_index == 3'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_index   <= 3'd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= sample_commit;
            if (byte_strobe)
                byte_index <= (byte_index >= 3'd5) ? 3'd0 : byte_index + 3'd1;
        end
    end

    // The bytes are stored directly in the filter's sample buffer.
    sv_pbs_core core (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(byte_strobe),
        .wr_idx(byte_index),
        .wr_data(ui_in),
        .sample_valid(sample_valid),
        .filtered_voltage(filtered_voltage),
        .filtered_current(filtered_current),
        .filtered_temperature(filtered_temperature),
        .proposed_state(proposed_state),
        .proposed_derate(proposed_derate),
        .proposed_isolate(proposed_isolate),
        .sensor_degraded(sensor_degraded),
        .predicted_risk(predicted_risk),
        .sensor_fault_code(sensor_fault_code),
        .busy(core_busy)
    );

    assign uo_out = {
        proposed_state == 2'd2, // [7] critical
        proposed_state == 2'd1, // [6] warning
        predicted_risk,       // [5]
        sensor_degraded,      // [4]
        proposed_isolate,     // [3]
        proposed_derate,      // [2]
        proposed_state        // [1:0]
    };

    // uio[1:0] inputs, uio[4:2] and uio[7] outputs, uio[6:5] unused (inputs)
    assign uio_out = {busy, 2'b00, sensor_fault_code, 2'b00};
    assign uio_oe  = 8'b1001_1100;

    // List all unused inputs to prevent warnings
    wire _unused = &{1'b0, uio_in[7:2],
                     filtered_voltage, filtered_current, filtered_temperature};

endmodule
