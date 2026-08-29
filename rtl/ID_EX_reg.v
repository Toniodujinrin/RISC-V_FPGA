module ID_EX_reg
#(
  parameter
  DATA_WIDTH = 32, 
  OP_CODE_WIDTH = 7, 
  FUNCT_3_WIDTH = 3, 
  REG_ADDR_WIDTH = 5, 
  HIST_BITS = 7, 
  BHR_SNAPS = 4
)
(
  input clk, reset, 

  //control, all decoded once in ID and consumed from EX onward 
  input jump, 
  input branch, 
  input [1:0] alu_src_1,
  input [1:0] alu_src_2, 
  input mem_write, 
  input mem_read, 
  input [2:0] mem_to_reg, 
  input reg_write,
  input csr_write, 

  //alu_op is computed in ID by alu_controller
  input [3:0] alu_op, 

  //decode fields still read after ID: forwarding_unit needs rs1/rs2, the
  //writeback path needs rd, branch_logic needs funct_3, the btb needs op_code.
  input [OP_CODE_WIDTH-1:0] op_code,
  input [FUNCT_3_WIDTH-1:0] funct_3, 
  input [REG_ADDR_WIDTH-1:0] rs1, 
  input [REG_ADDR_WIDTH-1:0] rs2, 
  input [REG_ADDR_WIDTH-1:0] rd, 

  //datapath values 
  input [DATA_WIDTH-1:0] rd_1, 
  input [DATA_WIDTH-1:0] rd_2, 
  input [DATA_WIDTH-1:0] imm, 
  input [DATA_WIDTH-1:0] r_imm, 
  input [DATA_WIDTH-1:0] pc, 
  input [DATA_WIDTH-1:0] pc_4, 
  input [DATA_WIDTH-1:0] csr_read_data, 
  input [DATA_WIDTH-1:0] instr, 
  input instr_valid, 

  //prediction payload, handed over from IF_ID_reg. 
  input [1:0] branch_prediction, 
  input [HIST_BITS-1:0] prediction_index, 
  input [$clog2(BHR_SNAPS)-1:0] bhr_snap_index, 
  input prediction_valid, 

  //the forwarded operands, fed back from the datapath's forwarding muxes. only
  //read while stalled -- see the stall branch below
  input [DATA_WIDTH-1:0] fwd_rd_1, 
  input [DATA_WIDTH-1:0] fwd_rd_2, 
  input flush, 
  input stall, 

  output reg ex_jump, 
  output reg ex_branch, 
  output reg [1:0] ex_alu_src_1, 
  output reg [1:0] ex_alu_src_2, 
  output reg ex_mem_write, 
  output reg ex_mem_read, 
  output reg [2:0] ex_mem_to_reg,
  output reg ex_reg_write, 
  output reg ex_csr_write,
  output reg [3:0] ex_alu_op,
  output reg [OP_CODE_WIDTH-1:0] ex_op_code, 
  output reg [FUNCT_3_WIDTH-1:0] ex_funct_3, 
  output reg [REG_ADDR_WIDTH-1:0] ex_rs1, 
  output reg [REG_ADDR_WIDTH-1:0] ex_rs2, 
  output reg [REG_ADDR_WIDTH-1:0] ex_rd, 
  output reg [DATA_WIDTH-1:0] ex_rd_1, 
  output reg [DATA_WIDTH-1:0] ex_rd_2, 
  output reg [DATA_WIDTH-1:0] ex_imm, 
  output reg [DATA_WIDTH-1:0] ex_r_imm, 
  output reg [DATA_WIDTH-1:0] ex_pc, 
  output reg [DATA_WIDTH-1:0] ex_pc_4, 
  output reg [DATA_WIDTH-1:0] ex_csr_read_data, 
  output reg [DATA_WIDTH-1:0] ex_instr, 
  output reg ex_instr_valid, 
  output reg [1:0] ex_branch_prediction, 
  output reg [HIST_BITS-1:0] ex_prediction_index, 
  output reg [$clog2(BHR_SNAPS)-1:0] ex_bhr_snap_index, 
  output reg ex_prediction_valid
); 


  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      ex_jump <= 0; 
      ex_branch <= 0; 
      ex_alu_src_1 <= 0; 
      ex_alu_src_2 <= 0; 
      ex_mem_write <= 0; 
      ex_mem_read <= 0; 
      ex_mem_to_reg <= 0; 
      ex_reg_write <= 0; 
      ex_csr_write <= 0; 
      ex_alu_op <= 0; 
      ex_op_code <= 0; 
      ex_funct_3 <= 0; 
      ex_rs1 <= 0; 
      ex_rs2 <= 0; 
      ex_rd <= 0; 
      ex_rd_1 <= 0; 
      ex_rd_2 <= 0; 
      ex_imm <= 0; 
      ex_r_imm <= 0; 
      ex_pc <= 0; 
      ex_pc_4 <= 0; 
      ex_csr_read_data <= 0; 
      ex_instr <= 0; 
      ex_instr_valid <= 0; 
      ex_branch_prediction <= 0; 
      ex_prediction_index <= 0; 
      ex_bhr_snap_index <= 0; 
      ex_prediction_valid <= 0; 
    end
    else if(flush)
    begin 
      ex_jump <= 0; 
      ex_branch <= 0; 
      ex_alu_src_1 <= 0; 
      ex_alu_src_2 <= 0; 
      ex_mem_write <= 0; 
      ex_mem_read <= 0; 
      ex_mem_to_reg <= 0; 
      ex_reg_write <= 0; 
      ex_csr_write <= 0; 
      ex_alu_op <= 0; 
      ex_op_code <= 0; 
      ex_funct_3 <= 0; 
      ex_rs1 <= 0; 
      ex_rs2 <= 0; 
      ex_rd <= 0; 
      ex_rd_1 <= 0; 
      ex_rd_2 <= 0; 
      ex_imm <= 0; 
      ex_r_imm <= 0; 
      ex_pc <= 0; 
      ex_pc_4 <= 0; 
      ex_csr_read_data <= 0; 
      ex_instr <= 0; 
      ex_instr_valid <= 0; 
      ex_branch_prediction <= 0; 
      ex_prediction_index <= 0; 
      ex_bhr_snap_index <= 0; 
      ex_prediction_valid <= 0; 
    end
    else if(!stall)
    begin 
      ex_jump <= jump; 
      ex_branch <= branch; 
      ex_alu_src_1 <= alu_src_1; 
      ex_alu_src_2 <= alu_src_2; 
      ex_mem_write <= mem_write; 
      ex_mem_read <= mem_read; 
      ex_mem_to_reg <= mem_to_reg; 
      ex_reg_write <= reg_write; 
      ex_csr_write <= csr_write; 
      ex_alu_op <= alu_op; 
      ex_op_code <= op_code; 
      ex_funct_3 <= funct_3; 
      ex_rs1 <= rs1; 
      ex_rs2 <= rs2; 
      ex_rd <= rd; 
      ex_rd_1 <= rd_1; 
      ex_rd_2 <= rd_2; 
      ex_imm <= imm; 
      ex_r_imm <= r_imm; 
      ex_pc <= pc; 
      ex_pc_4 <= pc_4; 
      ex_csr_read_data <= csr_read_data; 
      ex_instr <= instr; 
      ex_instr_valid <= instr_valid; 
      ex_branch_prediction <= branch_prediction; 
      ex_prediction_index <= prediction_index; 
      ex_bhr_snap_index <= bhr_snap_index; 
      ex_prediction_valid <= prediction_valid; 
    end
    else
    begin 
      //stalled: hold everything, but re-capture the forwarded operands.
      //a memory stall bubbles MEM/WB, so a producer in writeback is a forwarding
      //source for exactly one cycle. an instruction parked in EX re-derives its
      //operand combinationally every cycle, so once that source is bubbled away
      //it falls back to the stale value it read in ID and the correct one is
      //lost. capturing is a no-op when no forward is active, since the mux
      //selects ex_rd_1/ex_rd_2 in that case.
      ex_rd_1 <= fwd_rd_1; 
      ex_rd_2 <= fwd_rd_2; 
    end
  end 
endmodule 
