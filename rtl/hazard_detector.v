module hazard_detector
#(
  parameter
  REG_ADDR_WIDTH = 5
)
(
  //control 
  input prediction_miss, 

  //load-use 
  input ex_jump, 
  input [REG_ADDR_WIDTH-1:0] ex_rd, 
  input ex_mem_read, 
  input [REG_ADDR_WIDTH-1:0] id_rs1, 
  input [REG_ADDR_WIDTH-1:0] id_rs2, 
  
  //cache port 
  input req_stall, 
  output reg mem_advance, 
  
  //control unit port 
  input sys_busy, 
  
  //stall and flush lines 
  output reg pc_stall,
  output reg if_id_stall, 
  output reg id_ex_stall,
  output reg ex_mem_stall, 
  output reg mem_wb_stall, 

  output reg if_id_flush, 
  output reg id_ex_flush, 
  output reg ex_mem_flush, 
  output reg mem_wb_flush
); 

  reg lu_hazard;
                              
  always@(*)
  begin 
    lu_hazard = 0; 
    if(ex_mem_read && (ex_rd != 0) && ((ex_rd == id_rs1) || (ex_rd == id_rs2)))
      lu_hazard = 1; 
  end


  always@(*)
  begin
    pc_stall = 0; 
    if_id_stall = 0; 
    id_ex_stall = 0; 
    ex_mem_stall = 0;  
    mem_wb_stall = 0; 

    if_id_flush = 0;  
    id_ex_flush = 0; 
    ex_mem_flush = 0;  
    mem_wb_flush = 0;

    mem_advance = !req_stall; 

    if(req_stall) //stall IF/ID/EX, bubble MEM
    begin 
      pc_stall = 1; 
      if_id_stall = 1; 
      id_ex_stall = 1; 
      ex_mem_stall = 1; 
      mem_wb_flush = 1; 
    end
  
    else if(prediction_miss || ex_jump)
    begin 
      if_id_flush = 1;
      id_ex_flush = 1;  
    end
    

    else if(lu_hazard || sys_busy) 
    begin 
      pc_stall = 1;
      if_id_stall = 1;
      id_ex_flush = 1; 
    end
  end
endmodule
