module alu
#(
  parameter DATA_WIDTH = 32 
)
(
  input [3:0] alu_op, 
  input [DATA_WIDTH-1:0] x, 
  input [DATA_WIDTH-1:0] y, 
  output reg [DATA_WIDTH-1:0] r
);
  
  //ALU_OPS
  localparam ADD = 4'd1; 
  localparam SUB = 4'd2; 
  localparam AND = 4'd3; 
  localparam OR = 4'd4; 
  localparam XOR = 4'd5; 
  localparam SLL = 4'd6; 
  localparam SRL = 4'd7; 
  localparam SRA = 4'd8; 
  localparam LT = 4'd9; 
  localparam LTU = 4'd10; 
  localparam PC = 4'd11; 
  localparam GTE = 4'd12; 
  localparam GTEU = 4'd13; 
  localparam NEQ = 4'd14; 
  localparam EQ = 4'd15; 
  localparam NON = 4'd0; 

  always@(*)
  begin 
    r = 0; 
    case(alu_op)
    ADD: r = $signed(x)+$signed(y); 
    SUB: r = $signed(x)-$signed(y);  
    AND: r = x&y; 
    OR: r = x|y; 
    XOR: r = x^y; 
    SLL: r = x << y[4:0]; 
    SRL: r = x >> y[4:0]; 
    SRA: r = $signed(x) >>> y[4:0]; 
    LT: r = ($signed(x) < $signed(y))? 1:0; 
    LTU: r = x < y ? 1:0; 
    PC: r = x + 4;
    GTE: r = ($signed(x) >= $signed(y))? 1:0; 
    GTEU: r = x >= y ? 1 : 0; 
    NEQ: r = x == y ? 0 : 1; 
    EQ: r = x == y? 1 : 0; 
    NON: r = 0;
    default: r = 0; 
    endcase
  end




endmodule 
