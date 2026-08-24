module program_counter
#(
  parameter
  DATA_WIDTH = 32
)
(
  input clk, reset,
  input [DATA_WIDTH-1:0] next_pc, 
  output reg [DATA_WIDTH-1:0] pc
); 


  always@(posedge clk, posedge reset)
  begin 
    if(reset)
      pc <= 0; 
    else 
      pc <= next_pc; 
  end


endmodule
