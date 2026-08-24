module EX_MEM_reg
#(
  parameter
  DATA_WIDTH = 32, 
  OP_CODE_WIDTH = 7, 
  FUNCT_3_WIDTH = 3, 
  REG_ADDR_WIDTH = 5
)
(
  input clk, reset, 

  //control consumed in MEM. these cross here because the access happens in the
  //stage after this register, and they stop at MEM/WB because by then it is done.
  input mem_read, 
  input mem_write, 

  //control consumed in WB 
  input [2:0] mem_to_reg, 
  input reg_write, 
  input csr_write, 

  //datapath.
  input [DATA_WIDTH-1:0] alu_result, 
  input [DATA_WIDTH-1:0] rd_2, 
  input [DATA_WIDTH-1:0] imm, 
  input [DATA_WIDTH-1:0] r_imm, 
  input [DATA_WIDTH-1:0] pc, 
  input [DATA_WIDTH-1:0] pc_4, 
  input [DATA_WIDTH-1:0] csr_read_data, 
  input [DATA_WIDTH-1:0] instr, 

  //decode fields still read from MEM onward: funct_3 sizes and signs the
  //sub-word access in MEM, rd is the writeback target and the forwarding tag.
  input [FUNCT_3_WIDTH-1:0] funct_3, 
  input [OP_CODE_WIDTH-1:0] op_code, 
  input [REG_ADDR_WIDTH-1:0] rd, 

  input flush, 
  input stall, 

  output reg em_mem_read, 
  output reg em_mem_write, 
  output reg [2:0] em_mem_to_reg, 
  output reg em_reg_write, 
  output reg em_csr_write, 
  output reg [DATA_WIDTH-1:0] em_alu_result, 
  output reg [DATA_WIDTH-1:0] em_rd_2, 
  output reg [DATA_WIDTH-1:0] em_imm, 
  output reg [DATA_WIDTH-1:0] em_r_imm, 
  output reg [DATA_WIDTH-1:0] em_pc, 
  output reg [DATA_WIDTH-1:0] em_pc_4, 
  output reg [DATA_WIDTH-1:0] em_csr_read_data, 
  output reg [DATA_WIDTH-1:0] em_instr, 
  output reg [FUNCT_3_WIDTH-1:0] em_funct_3, 
  output reg [OP_CODE_WIDTH-1:0] em_op_code, 
  output reg [REG_ADDR_WIDTH-1:0] em_rd
); 


  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      em_mem_read <= 0; 
      em_mem_write <= 0; 
      em_mem_to_reg <= 0; 
      em_reg_write <= 0; 
      em_csr_write <= 0; 
      em_alu_result <= 0; 
      em_rd_2 <= 0; 
      em_imm <= 0; 
      em_r_imm <= 0; 
      em_pc <= 0; 
      em_pc_4 <= 0; 
      em_csr_read_data <= 0; 
      em_instr <= 0; 
      em_funct_3 <= 0; 
      em_op_code <= 0; 
      em_rd <= 0; 
    end
    else if(flush)
    begin 
      em_mem_read <= 0; 
      em_mem_write <= 0; 
      em_mem_to_reg <= 0; 
      em_reg_write <= 0; 
      em_csr_write <= 0; 
      em_alu_result <= 0; 
      em_rd_2 <= 0; 
      em_imm <= 0; 
      em_r_imm <= 0; 
      em_pc <= 0; 
      em_pc_4 <= 0; 
      em_csr_read_data <= 0; 
      em_instr <= 0; 
      em_funct_3 <= 0; 
      em_op_code <= 0; 
      em_rd <= 0; 
    end
    else if(!stall)
    begin 
      em_mem_read <= mem_read; 
      em_mem_write <= mem_write; 
      em_mem_to_reg <= mem_to_reg; 
      em_reg_write <= reg_write; 
      em_csr_write <= csr_write; 
      em_alu_result <= alu_result; 
      em_rd_2 <= rd_2; 
      em_imm <= imm; 
      em_r_imm <= r_imm; 
      em_pc <= pc; 
      em_pc_4 <= pc_4; 
      em_csr_read_data <= csr_read_data; 
      em_instr <= instr; 
      em_funct_3 <= funct_3; 
      em_op_code <= op_code; 
      em_rd <= rd; 
    end
  end 
endmodule 
