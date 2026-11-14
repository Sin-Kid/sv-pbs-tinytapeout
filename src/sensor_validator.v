/*
 * Copyright (c) 2026 Pavan G, Manali Kulkarni, Shylashree N, RV College of Engineering
 * SPDX-License-Identifier: Apache-2.0
 *
 * Sensor validator: range checks and stuck-sensor detection.
 * The sensor-degraded flag is separate from battery-critical protection.
 *
 * A channel is "active" when it moved by more than its tolerance since the
 * previous sample (|x - x_prev| > tol). A channel is "stuck" when it has
 * repeated the same value STUCK_LIMIT-1 times while another channel is active.
 * The change flags are computed by moving_average3 with one shared
 * subtractor while it writes each new filtered value (area-optimised).
 */

`default_nettype none

module sensor_validator #(
    parameter STUCK_LIMIT = 10
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [15:0] voltage,
    input  wire [15:0] current,
    input  wire [11:0] temperature,
    // Change flags vs. previous filtered sample (from moving_average3)
    input  wire        va, ia, ta,               // channel active
    input  wire        v_same, i_same, t_same,   // channel unchanged
    output reg         sensor_degraded,
    output reg  [2:0]  sensor_fault_code
);

    localparam CW = 4;   // counter width, enough for STUCK_LIMIT <= 15
    localparam [CW-1:0] LIMIT   = STUCK_LIMIT;
    localparam [CW-1:0] LIMIT_1 = STUCK_LIMIT - 1;

    reg [CW-1:0] cnt_v, cnt_i, cnt_t;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_v <= {CW{1'b0}}; cnt_i <= {CW{1'b0}}; cnt_t <= {CW{1'b0}};
            sensor_degraded   <= 1'b0;
            sensor_fault_code <= 3'd0;
        end else if (valid_in) begin
            if (voltage < 16'd2500 || voltage > 16'd5000) begin
                sensor_degraded <= 1'b1; sensor_fault_code <= 3'd1;
            end else if (current > 16'd1000) begin
                sensor_degraded <= 1'b1; sensor_fault_code <= 3'd2;
            end else if (temperature > 12'd800) begin
                sensor_degraded <= 1'b1; sensor_fault_code <= 3'd3;
            end else if (cnt_v >= LIMIT_1 && (ia || ta)) begin
                sensor_degraded <= 1'b1; sensor_fault_code <= 3'd4;
            end else if (cnt_i >= LIMIT_1 && (va || ta)) begin
                sensor_degraded <= 1'b1; sensor_fault_code <= 3'd5;
            end else if (cnt_t >= LIMIT_1 && (va || ia)) begin
                sensor_degraded <= 1'b1; sensor_fault_code <= 3'd6;
            end else begin
                sensor_degraded <= 1'b0; sensor_fault_code <= 3'd0;
            end

            if (v_same) begin if (cnt_v < LIMIT) cnt_v <= cnt_v + 1'b1; end else cnt_v <= {CW{1'b0}};
            if (i_same) begin if (cnt_i < LIMIT) cnt_i <= cnt_i + 1'b1; end else cnt_i <= {CW{1'b0}};
            if (t_same) begin if (cnt_t < LIMIT) cnt_t <= cnt_t + 1'b1; end else cnt_t <= {CW{1'b0}};
        end
    end

endmodule
