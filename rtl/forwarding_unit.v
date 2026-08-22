module forwarding_unit
#(
  ADDR_WIDTH = 3
)
(
  input [ADDR_WIDTH-1:0] ID_EX_RS1, 
  input [ADDR_WIDTH-1:0] ID_EX_RS2, 
  input [ADDR_WIDTH-1:0] EX_MEM_RD, 
  input [ADDR_WIDTH-1:0] MEM_WB_RD, 
  input EX_MEM_RegWrite, //A write operation is being carried out on the destination register  
  input MEM_WB_RegWrite, 
  output reg [1:0] forward_a,forward_b
); 

  wire EX_MEM_valid = EX_MEM_RegWrite && (EX_MEM_RD != {ADDR_WIDTH{1'b0}}); 
  wire MEM_WB_valid = MEM_WB_RegWrite && (MEM_WB_RD != {ADDR_WIDTH{1'b0}});

  wire EX_MEM_match_b = EX_MEM_valid && (EX_MEM_RD == ID_EX_RS2); 
  wire EX_MEM_match_a = EX_MEM_valid && (EX_MEM_RD == ID_EX_RS1);  


  always@(*)
  begin 
    if(EX_MEM_match_a)
      forward_a = 2'b10; 
    else if(MEM_WB_valid && MEM_WB_RD == ID_EX_RS1)
      forward_a = 2'b01; 
    else 
      forward_a = 2'b00; 

    if(EX_MEM_match_b)
      forward_b = 2'b10; 
    else if(MEM_WB_valid && MEM_WB_RD == ID_EX_RS2)
      forward_b = 2'b01; 
    else 
      forward_b = 2'b00; 
  end 

endmodule 
