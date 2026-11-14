/*
 * Copyright (c) 2026 Pavan G, Manali Kulkarni, Shylashree N, RV College of Engineering
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// 8-sample windowed temperature rise predictor; units 0.1 degC.
module thermal_predictor #(parameter WINDOW=8,RISE_LIMIT=12)(
 input wire clk,rst_n,valid_in,input wire [11:0] temperature,
 output reg predicted_risk,output reg [11:0] rise_delta
);
reg [11:0] start_temp;reg [3:0] count;
always @(posedge clk or negedge rst_n)
 if(!rst_n)begin start_temp<=0;count<=0;predicted_risk<=0;rise_delta<=0;end
 else if(valid_in)begin
  if(count==0)begin start_temp<=temperature;count<=1;end
  else if(count==WINDOW-1)begin
   if(temperature>=start_temp)begin
    rise_delta<=temperature-start_temp;
    if((temperature-start_temp)>=RISE_LIMIT && temperature<500)predicted_risk<=1;
   end else rise_delta<=0;
   count<=0;
  end else count<=count+1'b1;
  if(temperature<380)predicted_risk<=0;
 end
endmodule
