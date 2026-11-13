// Fixed threshold baseline. Consumes the same filtered samples as proposed controller.
module ref_baseline_controller(
 input wire clk,rst_n,valid_in,input wire [15:0] voltage,current,
 input wire [11:0] temperature,
 output reg [1:0] state,output reg derate,isolate
);
always @(posedge clk or negedge rst_n)
 if(!rst_n)begin state<=0;derate<=0;isolate<=0;end
 else if(valid_in)begin
  if(temperature>=500 || voltage>4400 || voltage<2800 || current>1000)begin state<=2;derate<=1;isolate<=1;end
  else if(temperature>=430 || current>300)begin state<=1;derate<=1;isolate<=0;end
  else begin state<=0;derate<=0;isolate<=0;end
 end
endmodule
