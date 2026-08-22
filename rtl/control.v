`include "riscv_defs.vh"

module control
#(
  DATA_WIDTH = 32, 
  REG_WIDTH = 5
)
(
  input [7:0] op_code, 
  input [3:0] funct3,
  input trap_done, 
  input csr_ready
  output reg pc_stall,
  output reg pc_src, 
  output reg jump, 
  output reg branch, 
  output reg alu_src_1, 
  output reg alu_src_2, 
  output reg mem_read, 
  output reg mem_write, 
  output reg [REG_WIDTH-1:0] mem_to_reg,  
  output reg reg_write, 
  output reg csr_write, 
  output reg lui, 
  output reg pc_src
); 


  always@(*)
  begin 
    alu_src_1 = 0; 
    alu_src_2 = 0; 
    mem_read = 0; //memory read request 
    mem_write = 0; // memory write request 
    branch = 0; 
    jump = 0; 
    reg_write = 0; // register file write enable 
    mem_to_reg = 0; //write back from memory 
    lui = 0; 
    pc_src = 0; 
    

    case(op_code)
     `R_TYPE: 
     begin
      reg_write = 1; 
     end

     `I_TYPE_4: //Immediate Arithmetic  
     begin 
      reg_write = 1; 
      alu_src_2 = 1; 
     end

     `B_TYPE: //Branch 
     begin
      branch = 1; 
     end


     `S_TYPE: //Store instruction
     begin 
      mem_write = 1; 
      alu_src_2 = 1; 
     end

     `I_TYPE_3: //Load instruction
     begin 
      alu_src_2 = 1; 
      mem_to_reg = 1; 
      mem_read = 1; 
      reg_write = 1; 
     end  

     `J_TYPE, `I_TYPE_2: //JAL , JALR 
     begin
        reg_write = 1; 
        jump = 1; 
        alu_src_1 = 1; //take pc bits 
        pc_src = (op_code == I_TYPE_2) ? 1 : 0; 
     end 

     `U_TYPE_1, `U_TYPE_2: //LUI, AUPIC  
     begin 
        reg_write = 1; 
        alu_src_2 = 1; 
        lui = (op_code == `U_TYPE_1) ? 1 : 0;
        alu_src_1 = (op_code == `U_TYPE_2) ? 1 : 0; 
     end 
    endcase
  end 
  
endmodule 
