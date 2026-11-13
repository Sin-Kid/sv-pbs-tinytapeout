
module ref_sv_pbs_core(
    input wire clk,
    input wire rst_n,
    input wire sample_valid,

    input wire [15:0] voltage_in,
    input wire [15:0] current_in,
    input wire [11:0] temperature_in,

    output wire [15:0] filtered_voltage,
    output wire [15:0] filtered_current,
    output wire [11:0] filtered_temperature,

    output wire [1:0] baseline_state,
    output wire [1:0] proposed_state,

    output wire baseline_derate,
    output wire baseline_isolate,
    output wire proposed_derate,
    output wire proposed_isolate,

    output wire sensor_degraded,
    output wire predicted_risk,
    output wire [2:0] sensor_fault_code
);

    wire [15:0] fv;
    wire [15:0] fi;
    wire [11:0] ft;

    reg filtered_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            filtered_valid <= 1'b0;
        else
            filtered_valid <= sample_valid;
    end

    ref_moving_average3 #(16) av(
        clk, rst_n, sample_valid, voltage_in, fv
    );

    ref_moving_average3 #(16) ai(
        clk, rst_n, sample_valid, current_in, fi
    );

    ref_moving_average3 #(12) at(
        clk, rst_n, sample_valid, temperature_in, ft
    );

    wire [11:0] delta;

    ref_sensor_validator sv(
        clk, rst_n, filtered_valid,
        fv, fi, ft,
        sensor_degraded, sensor_fault_code
    );

    ref_thermal_predictor tp(
        clk, rst_n, filtered_valid,
        ft, predicted_risk, delta
    );

    ref_baseline_controller bc(
        clk, rst_n, filtered_valid,
        fv, fi, ft,
        baseline_state, baseline_derate, baseline_isolate
    );

    ref_proposed_controller pc(
        clk, rst_n, filtered_valid,
        fv, fi, ft,
        predicted_risk, sensor_degraded,
        proposed_state, proposed_derate, proposed_isolate
    );

    assign filtered_voltage = fv;
    assign filtered_current = fi;
    assign filtered_temperature = ft;

endmodule
