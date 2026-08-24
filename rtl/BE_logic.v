module BE_logic //Sign extend cache data
#(
  parameter
  DATA_WIDTH = 32, 
  FUNCT_3_WIDTH = 3
)
(
  input [FUNCT_3_WIDTH-1:0] funct_3, 
  input [DATA_WIDTH-1:0] cache_in, 
  output reg [DATA_WIDTH-1:0] r_out
); 
  localparam HALF_WORD = DATA_WIDTH/2; 

  always@(*)
  begin 
    case(funct_3)
      3'b000:  r_out = {{(DATA_WIDTH-8){cache_in[7]}}, cache_in[7:0]};                 //LB
      3'b001:  r_out = {{HALF_WORD{cache_in[HALF_WORD-1]}}, cache_in[HALF_WORD-1:0]};  //LH
      default: r_out = cache_in;                                        //LW, LBU, LHU
    endcase
  end
endmodule 
