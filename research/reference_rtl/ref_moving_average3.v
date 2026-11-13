module ref_moving_average3 #(parameter WIDTH=16)(
 input wire clk,rst_n,valid_in,input wire [WIDTH-1:0] din,
 output reg [WIDTH-1:0] dout
);
reg [WIDTH-1:0] d1,d2; reg [1:0] count;
wire [WIDTH+1:0] sum3=din+d1+d2;
always @(posedge clk or negedge rst_n)
 if(!rst_n) begin d1<=0;d2<=0;count<=0;dout<=0;end
 else if(valid_in) begin
  if(count<2) begin dout<=din;count<=count+1'b1;end
  else dout<=sum3/3;
  d2<=d1;d1<=din;
 end
endmodule
