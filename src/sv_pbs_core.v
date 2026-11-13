/*
 * Copyright (c) 2026 Pavan G
 * SPDX-License-Identifier: Apache-2.0
 *
 * SV-PBS core: filtering -> sensor validation + thermal trend prediction
 * -> baseline and proposed (adaptive) protection controllers.
 */

`default_nettype none

module sv_pbs_core (
    input  wire        clk,
    input  wire        rst_n,
    // Byte write port for the next sample (see project.v for byte order)
    input  wire        wr_en,
    input  wire [2:0]  wr_idx,
    input  wire [7:0]  wr_data,
    input  wire        sample_valid,   // pulse after all six bytes are written

    output wire [15:0] filtered_voltage,
    output wire [15:0] filtered_current,
    output wire [11:0] filtered_temperature,

    output wire [1:0]  baseline_state,
    output wire [1:0]  proposed_state,

    output wire        baseline_derate,
    output wire        baseline_isolate,
    output wire        proposed_derate,
    output wire        proposed_isolate,

    output wire        sensor_degraded,
    output wire        predicted_risk,
    output wire [2:0]  sensor_fault_code,

    output wire        busy
);

    wire [15:0] fv;
    wire [15:0] fi;
    wire [11:0] ft;
    wire        filtered_valid;
    wire        filter_busy;
    reg         stage2_pending;
    wire        va, ia, ta, v_same, i_same, t_same;

    moving_average3 filt (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_idx(wr_idx), .wr_data(wr_data),
        .start(sample_valid),
        .v_out(fv), .i_out(fi), .t_out(ft),
        .done(filtered_valid), .busy(filter_busy),
        .v_act(va), .i_act(ia), .t_act(ta),
        .v_same(v_same), .i_same(i_same), .t_same(t_same)
    );

    // Downstream blocks update on the cycle after filtered_valid.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) stage2_pending <= 1'b0;
        else        stage2_pending <= filtered_valid;
    end
    assign busy = filter_busy | filtered_valid | stage2_pending;

    wire [11:0] delta;

    sensor_validator sv (
        .clk(clk), .rst_n(rst_n), .valid_in(filtered_valid),
        .voltage(fv), .current(fi), .temperature(ft),
        .va(va), .ia(ia), .ta(ta),
        .v_same(v_same), .i_same(i_same), .t_same(t_same),
        .sensor_degraded(sensor_degraded), .sensor_fault_code(sensor_fault_code)
    );

    thermal_predictor tp (
        .clk(clk), .rst_n(rst_n), .valid_in(filtered_valid),
        .temperature(ft), .predicted_risk(predicted_risk), .rise_delta(delta)
    );

    baseline_controller bc (
        .clk(clk), .rst_n(rst_n), .valid_in(filtered_valid),
        .voltage(fv), .current(fi), .temperature(ft),
        .state(baseline_state), .derate(baseline_derate), .isolate(baseline_isolate)
    );

    proposed_controller pc (
        .clk(clk), .rst_n(rst_n), .valid_in(filtered_valid),
        .voltage(fv), .current(fi), .temperature(ft),
        .predicted_risk(predicted_risk), .sensor_degraded(sensor_degraded),
        .state(proposed_state), .derate(proposed_derate), .isolate(proposed_isolate)
    );

    assign filtered_voltage     = fv;
    assign filtered_current     = fi;
    assign filtered_temperature = ft;

    wire _unused = &{1'b0, delta};

endmodule
