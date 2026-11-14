/*
 * Copyright (c) 2026 Pavan G, Manali Kulkarni, Shylashree N, RV College of Engineering
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Proposed controller: same filtered inputs as baseline plus trend predictor
// and sensor-degraded output. Sensor fault alone does NOT assert battery isolate.
module proposed_controller(
 input wire clk,rst_n,valid_in,input wire [15:0] voltage,current,
 input wire [11:0] temperature,input wire predicted_risk,input wire sensor_degraded,
 output reg [1:0] state,output reg derate,isolate
);
localparam NORMAL=0,WARNING=1,CRITICAL=2,SENSOR_DEGRADED=3;
reg [3:0] safe_count;
always @(posedge clk or negedge rst_n)
 if(!rst_n)begin state<=NORMAL;derate<=0;isolate<=0;safe_count<=0;end
 else if(valid_in)begin
  // Only direct, validated battery-limit violations cause isolation.
  if(temperature>=500 || voltage>4600 || voltage<2600 || current>1000)begin
   state<=CRITICAL;derate<=1;isolate<=1;safe_count<=0;
  end else if(sensor_degraded)begin
   state<=SENSOR_DEGRADED;derate<=1;isolate<=0;safe_count<=0;
  end else if(temperature>=430 || current>300 || predicted_risk)begin
   state<=WARNING;derate<=1;isolate<=0;safe_count<=0;
  end else if(state==CRITICAL || state==SENSOR_DEGRADED || state==WARNING)begin
   if(temperature<390 && current<250 && voltage>=2800 && voltage<=4400)begin
    if(safe_count<4)safe_count<=safe_count+1'b1;
    if(safe_count>=3)begin state<=NORMAL;derate<=0;isolate<=0;safe_count<=0;end
   end else safe_count<=0;
  end else begin state<=NORMAL;derate<=0;isolate<=0;end
 end
endmodule
