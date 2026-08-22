`include "riscv_defs.vh"

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
  

  always@(*)
  begin 
    r = 0; 
    case(alu_op)
    `ADD: r = $signed(x)+$signed(y); 
    `SUB: r = $signed(x)-$signed(y);  
    `AND: r = x&y; 
    `OR: r = x|y; 
    `XOR: r = x^y; 
    `SLL: r = x << y[4:0]; 
    `SRL: r = x >> y[4:0]; 
    `SRA: r = $signed(x) >>> y[4:0]; 
    `LT: r = ($signed(x) < $signed(y))? 1:0; 
    `LTU: r = x < y ? 1:0; 
    `PC: r = x + 4;
    `GTE: r = ($signed(x) >= $signed(y))? 1:0; 
    `GTEU: r = x >= y ? 1 : 0; 
    `NEQ: r = x == y ? 0 : 1; 
    `EQ: r = x == y? 1 : 0; 
    `NON: r = 0;
    default: r = 0; 
    endcase
  end




endmodule 
