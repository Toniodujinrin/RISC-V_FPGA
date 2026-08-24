`include "riscv_defs.vh"
module control
(
  input [6:0] op_code, 
  input [2:0] funct3,
  input trap_done, 
  input csr_ready, 
  output reg pc_stall,
  output reg pc_src, 
  output reg jump, 
  output reg branch, 
  output reg [1:0] alu_src_1, //00 RD1 | 01 PC | 10 rs1-as-zimm (Day 3, CSR imm)
  output reg [1:0] alu_src_2, //00 RD2 | 01 imm | 10 csrRD (Day 3)
  output reg mem_read, 
  output reg mem_write, 
  output reg [2:0] mem_to_reg, //000 ALU | 001 memory | 010 PC+4| 011 lui| 100 CSR
  output reg reg_write, 
  output reg csr_write 
); 


  always@(*)
  begin 
    alu_src_1 = 2'd0; 
    alu_src_2 = 2'd0; 
    mem_read = 0; //memory read request 
    mem_write = 0; // memory write request 
    branch = 0; 
    jump = 0; 
    reg_write = 0; // register file write enable 
    mem_to_reg = 3'd0; //writeback source, see encoding above 
    pc_src = 0; 
    pc_stall = 0; 
    csr_write = 0; 
    

    case(op_code[6:2])
     `R_TYPE: 
     begin
      reg_write = 1; 
     end

     `I_TYPE_4: //Immediate Arithmetic  
     begin 
      reg_write = 1; 
      alu_src_2 = 2'd1; 
     end

     `B_TYPE: //Branch 
     begin
      branch = 1; 
     end


     `S_TYPE: //Store instruction
     begin 
      mem_write = 1; 
      alu_src_2 = 2'd1; 
     end

     `I_TYPE_3: //Load instruction
     begin 
      alu_src_2 = 2'd1; 
      mem_to_reg = 3'd1; //from memory
      mem_read = 1; 
      reg_write = 1; 
     end  

     `J_TYPE, `I_TYPE_2: //JAL , JALR 
     begin
        reg_write = 1; 
        jump = 1; 
        alu_src_1 = (op_code[6:2] == `J_TYPE) ? 2'd1 : 2'd0; //JAL: PC, JALR: rs1 
        alu_src_2 = 2'd1; 
        mem_to_reg = 3'd2; 
      end 

     `U_TYPE_1, `U_TYPE_2: //LUI, AUPIC  
     begin 
        reg_write = 1; 
        alu_src_2 = 2'd1; 
        mem_to_reg = (op_code[6:2] == `U_TYPE_1) ? 3'd4 : 3'd0;
        alu_src_1 = (op_code[6:2] == `U_TYPE_2) ? 2'd1 : 2'd0; 
     end 
    endcase
  end 
  
endmodule 
