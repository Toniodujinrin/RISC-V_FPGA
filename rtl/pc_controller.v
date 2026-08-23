module pc_controller
#(
  parameter
  DATA_WIDTH = 32
)
(
  input [DATA_WIDTH-1:0] if_pc, //current pc
  input pc_stall, 
  input ex_jump,
  input [DATA_WIDTH-1:0] jump_target,
  input bp_miss, 
  input [DATA_WIDTH-1:0] branch_target,
  input bp_taken, 
  input [DATA_WIDTH-1:0] branch_target_actual,
  input [DATA_WIDTH-1:0] t_target, 
  input trap, 
  output reg [DATA_WIDTH-1:0] pc_next
  
); 


  always@(*)
  begin 
    if(trap)
      pc_next = t_target; 
    else if(bp_miss)
      pc_next = branch_target_actual; 
    else if(ex_jump)
      pc_next = jump_target; 
    else if(pc_stall)
      pc_next = if_pc; 
    else if(bp_taken)
      pc_next = branch_target; 
    else 
      pc_next = if_pc + 4; 
  end

endmodule
