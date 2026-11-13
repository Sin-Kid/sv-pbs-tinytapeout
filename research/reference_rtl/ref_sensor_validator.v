// Sensor-degraded flag is separate from battery-critical protection.
// Range checks are immediate. Stuck checks require channel activity context.
module ref_sensor_validator #(parameter STUCK_LIMIT=10)(
 input wire clk,rst_n,valid_in,
 input wire [15:0] voltage,current,input wire [11:0] temperature,
 output reg sensor_degraded,output reg [2:0] sensor_fault_code
);
reg [15:0] pv,pi; reg [11:0] pt;
reg [7:0] sv,si,st;
wire va=(voltage>pv+16'd5)||(pv>voltage+16'd5);
wire ia=(current>pi+16'd5)||(pi>current+16'd5);
wire ta=(temperature>pt+12'd2)||(pt>temperature+12'd2);
always @(posedge clk or negedge rst_n)
 if(!rst_n) begin
  pv<=0;pi<=0;pt<=0;sv<=0;si<=0;st<=0;sensor_degraded<=0;sensor_fault_code<=0;
 end else if(valid_in) begin
  if(voltage<2500 || voltage>5000) begin sensor_degraded<=1;sensor_fault_code<=1;end
  else if(current>1000) begin sensor_degraded<=1;sensor_fault_code<=2;end
  else if(temperature>800) begin sensor_degraded<=1;sensor_fault_code<=3;end
  else if(sv>=STUCK_LIMIT-1 && (ia||ta)) begin sensor_degraded<=1;sensor_fault_code<=4;end
  else if(si>=STUCK_LIMIT-1 && (va||ta)) begin sensor_degraded<=1;sensor_fault_code<=5;end
  else if(st>=STUCK_LIMIT-1 && (va||ia)) begin sensor_degraded<=1;sensor_fault_code<=6;end
  else begin sensor_degraded<=0;sensor_fault_code<=0;end

  if(voltage==pv) begin if(sv<STUCK_LIMIT)sv<=sv+1'b1;end else sv<=0;
  if(current==pi) begin if(si<STUCK_LIMIT)si<=si+1'b1;end else si<=0;
  if(temperature==pt) begin if(st<STUCK_LIMIT)st<=st+1'b1;end else st<=0;
  pv<=voltage;pi<=current;pt<=temperature;
 end
endmodule
