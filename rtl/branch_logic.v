module branch_logic
#(
  parameter
  DATA_WIDTH = 32
)
(
 input branch, //branch assert from control unit  
 input [DATA_WIDTH-1:0] EX_pc, //the branch's own PC, not the fetch PC
 input [DATA_WIDTH-1:0] EX_imm, 
 input alu_cond, 
 input branch_prediction, 
 output reg prediction_miss, 
 output reg [DATA_WIDTH-1:0] branch_target_actual, 
 output reg branch_taken 
);
  
  always@(*)
  begin 
    branch_taken = 0; 
    prediction_miss = 0; 
    branch_target_actual = EX_pc + 4;

    if(branch)
    begin
     prediction_miss = (alu_cond != branch_prediction); 
     if(alu_cond)
     begin 
       branch_taken = 1'b1; 
       branch_target_actual = EX_pc + EX_imm; 
     end
    end 
  end
endmodule
