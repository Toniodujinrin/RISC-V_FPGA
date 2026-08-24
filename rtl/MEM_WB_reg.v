module MEM_WB_reg
#(
  parameter 
  DATA_WIDTH = 32, 
  REG_ADDR_WIDTH = 5, 
  OP_CODE_WIDTH = 7
)
(
  input clk, reset, 

  input [DATA_WIDTH-1:0] alu_result,  //mem_to_reg 000
  input [DATA_WIDTH-1:0] read_data,   //mem_to_reg 001, load data out of the memory stage
  input [DATA_WIDTH-1:0] pc_4,        //mem_to_reg 010, link value for jal/jalr
  input [DATA_WIDTH-1:0] liu_imm,     //mem_to_reg 011
  input [DATA_WIDTH-1:0] csr_rd,      //mem_to_reg 100

  //control whose effect lands in wb 
  input [2:0] mem_to_reg, 
  input reg_write, 

  //destination 
  input [REG_ADDR_WIDTH-1:0] rd, 

  //forwarding and hazard use rd/reg_write, traps use pc, csr uses r_imm/op_code/instr.
  input [DATA_WIDTH-1:0] pc, 
  input [DATA_WIDTH-1:0] r_imm, 
  input [OP_CODE_WIDTH-1:0] op_code, 
  input [DATA_WIDTH-1:0] instr, 

  input stall, 
  input flush,

  output reg [DATA_WIDTH-1:0] mem_alu_result, 
  output reg [DATA_WIDTH-1:0] mem_read_data, 
  output reg [DATA_WIDTH-1:0] mem_pc_4, 
  output reg [DATA_WIDTH-1:0] mem_liu_imm, 
  output reg [DATA_WIDTH-1:0] mem_csr_rd, 
  output reg [2:0] mem_mem_to_reg, 
  output reg mem_reg_write, 
  output reg [REG_ADDR_WIDTH-1:0] mem_rd, 
  output reg [DATA_WIDTH-1:0] mem_pc, 
  output reg [DATA_WIDTH-1:0] mem_r_imm, 
  output reg [OP_CODE_WIDTH-1:0] mem_op_code,  
  output reg [DATA_WIDTH-1:0] mem_instr 
); 

  
  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      mem_alu_result <= 0; 
      mem_read_data <= 0; 
      mem_pc_4 <= 0; 
      mem_liu_imm <= 0; 
      mem_csr_rd <= 0; 
      mem_mem_to_reg <= 0; 
      mem_reg_write <= 0; 
      mem_rd <= 0; 
      mem_pc <= 0; 
      mem_r_imm <= 0; 
      mem_op_code <= 0; 
      mem_instr <= 0; 
    end   
    else if(flush)
    begin 
      mem_alu_result <= 0; 
      mem_read_data <= 0; 
      mem_pc_4 <= 0; 
      mem_liu_imm <= 0; 
      mem_csr_rd <= 0; 
      mem_mem_to_reg <= 0; 
      mem_reg_write <= 0; 
      mem_rd <= 0; 
      mem_pc <= 0; 
      mem_r_imm <= 0; 
      mem_op_code <= 0; 
      mem_instr <= 0; 
    end 
    else if(!stall)
    begin 
      mem_alu_result <= alu_result; 
      mem_read_data <= read_data; 
      mem_pc_4 <= pc_4; 
      mem_liu_imm <= liu_imm; 
      mem_csr_rd <= csr_rd; 
      mem_mem_to_reg <= mem_to_reg; 
      mem_reg_write <= reg_write; 
      mem_rd <= rd; 
      mem_pc <= pc; 
      mem_r_imm <= r_imm; 
      mem_op_code <= op_code; 
      mem_instr <= instr; 
    end 
  end 

endmodule 
