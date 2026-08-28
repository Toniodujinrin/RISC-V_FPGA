module data_path
#(
  parameter
  DATA_WIDTH = 32, 
  OP_CODE_WIDTH = 7, 
  FUNCT_3_WIDTH = 3, 
  REG_ADDR_WIDTH = 5, 
  HIST_BITS = 7, 
  BHR_SNAPS = 4, 
  BTB_DEPTH = 8, 
  BLOCK_BITS = 32*8, //8 words of DATA_WIDTH per block
  WB_FIFO_DEPTH = 8, 
  IMEM_DEPTH = 1024, 
  PROGRAM_FILE = "build/test.mem",
  CACHE_SET_N = 128, 
  DATA_MEM_DEPTH = 1024
)
(
  input clk, reset, 
  //io bus behind the lsu's mmio bypass. no slave exists yet, so this is the
  //only interface still brought out: inst_mem and data_mem are both
  //instantiated below, so fetch and the cache's backing port stay internal
  input [DATA_WIDTH-1:0] io_data_out, 
  input io_ack, 
  output io_req, 
  output io_write_read, 
  output [DATA_WIDTH-1:0] io_data_in, 
  output [1:0] io_size, 
  output [DATA_WIDTH-1:0] io_addr_in
); 

  //////////////////////////////////////////////////////////////
  // stall and flush lines. all driven by HAZARD, instantiated in MEM below
  // where every one of its inputs has been declared.
  // TODO CSR: csr_read_data, trap, t_target, trap_done, csr_ready are tied off.
  //////////////////////////////////////////////////////////////
  wire pc_stall; 
  wire if_id_stall, id_ex_stall, ex_mem_stall, mem_wb_stall; 
  wire if_id_flush, id_ex_flush, ex_mem_flush, mem_wb_flush; 
  wire req_stall, mem_advance; 

  //////////////////////////////////////////////////////////////
  // FETCH
  //////////////////////////////////////////////////////////////
  wire [DATA_WIDTH-1:0] if_pc; 
  wire [DATA_WIDTH-1:0] if_pc_next; 
  wire [DATA_WIDTH-1:0] if_pc_4 = if_pc + 32'd4; 

  wire [DATA_WIDTH-1:0] btb_target; 
  wire btb_hit; 
  wire [1:0] prediction_out; 
  wire [HIST_BITS-1:0] prediction_index; 
  wire prediction_valid; 
  wire [$clog2(BHR_SNAPS)-1:0] bhr_snap_index; 

  wire ex_jump, ex_branch, ex_prediction_miss, ex_branch_taken; 
  wire ex_instr_valid; 
  wire [DATA_WIDTH-1:0] ex_branch_target_actual, ex_alu_result, ex_pc; 
  wire [OP_CODE_WIDTH-1:0] ex_op_code; 
  wire [1:0] ex_branch_prediction; 
  wire [HIST_BITS-1:0] ex_prediction_index; 
  wire [$clog2(BHR_SNAPS)-1:0] ex_bhr_snap_index; 
  wire ex_prediction_valid; 
  wire id_sys_busy; 


  //TODO the prediction is registered one cycle behind btb_target, which is
  //combinational off if_pc. resolve this skew with the hazard unit.
  wire bp_taken = prediction_valid & prediction_out[1]; 


  program_counter
  #(.DATA_WIDTH(DATA_WIDTH))
  PC
  (
    .clk(clk), 
    .reset(reset), 
    .next_pc(if_pc_next), 
    .pc(if_pc)
  ); 

  pc_controller
  #(.DATA_WIDTH(DATA_WIDTH))
  PC_CONTROLLER
  (
    .if_pc(if_pc), 
    .pc_stall(pc_stall), 
    .ex_jump(ex_jump), 
    .jump_target(ex_alu_result), 
    .bp_miss(ex_prediction_miss), 
    .branch_target(btb_target), 
    .bp_taken(bp_taken), 
    .branch_target_actual(ex_branch_target_actual), 
    .t_target({DATA_WIDTH{1'b0}}), 
    .trap(1'b0), 
    .pc_next(if_pc_next)
  ); 
  
  wire [DATA_WIDTH-1:0] imem_araddr = reset?32'd0:if_pc_next; 
  wire [DATA_WIDTH-1:0] imem_data; 
  wire imem_out_valid; 
  inst_mem
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .IMEM_DEPTH(IMEM_DEPTH), 
    .PROGRAM_FILE(PROGRAM_FILE)
  )
  IMEM
  (
    .clk(clk),
    .imem_addr(imem_araddr), 
    .imem_data(imem_data), 
    .output_valid(imem_out_valid) 
  );

  btb
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .OP_CODE_WIDTH(OP_CODE_WIDTH), 
    .BUFFER_DEPTH(BTB_DEPTH)
  )
  BTB
  (
    .clk(clk), 
    .reset(reset), 
    .if_pc(if_pc), 
    .write_en(ex_branch), 
    .ex_target(ex_branch_target_actual), 
    .ex_pc(ex_pc), 
    .ex_op_code(ex_op_code), 
    .hit_miss(btb_hit), 
    .target(btb_target)
  ); 

  branch_predictor
  #(
    .HIST_BITS(HIST_BITS), 
    .BHR_SNAPS(BHR_SNAPS), 
    .DATA_WIDTH(DATA_WIDTH)
  )
  BRANCH_PREDICTOR
  (
    .clk(clk), 
    .reset(reset), 
    .history_write(ex_branch), 
    .predicted_index(ex_prediction_index), 
    .predicted_in(ex_branch_prediction), 
    .actually_taken(ex_branch_taken), 
    .predicted_valid(ex_prediction_valid), 
    .predicted_snap_index(ex_bhr_snap_index), 
    .pc_bits(if_pc), 
    .history_read(btb_hit), 
    .prediction_out(prediction_out), 
    .prediction_index(prediction_index), 
    .prediction_valid(prediction_valid), 
    .bhr_snap_index(bhr_snap_index)
  ); 

  //////////////////////////////////////////////////////////////
  // DECODE
  //////////////////////////////////////////////////////////////
  wire [DATA_WIDTH-1:0] id_pc, id_pc_4, id_instr; 
  wire id_instr_valid; 
  wire [1:0] id_branch_prediction; 
  wire [HIST_BITS-1:0] id_prediction_index; 
  wire [$clog2(BHR_SNAPS)-1:0] id_bhr_snap_index; 
  wire id_prediction_valid; 

  wire [OP_CODE_WIDTH-1:0] id_op_code; 
  wire [6:0] id_funct_7; 
  wire [FUNCT_3_WIDTH-1:0] id_funct_3; 
  wire [REG_ADDR_WIDTH-1:0] id_rs1, id_rs2, id_rd; 
  wire [DATA_WIDTH-1:0] id_imm, id_r_imm; 
  wire [DATA_WIDTH-1:0] id_read_data_1, id_read_data_2; 
  wire [3:0] id_alu_op; 

  wire id_jump, id_branch, id_mem_read, id_mem_write, id_reg_write, id_csr_write; 
  wire [1:0] id_alu_src_1, id_alu_src_2; 
  wire [2:0] id_mem_to_reg; 

  wire wb_reg_write, wb_instr_valid; 
  wire [REG_ADDR_WIDTH-1:0] wb_rd; 
  reg [DATA_WIDTH-1:0] wb_src; 

  IF_ID_reg
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .HIST_BITS(HIST_BITS), 
    .BHR_SNAPS(BHR_SNAPS)
  )
  IF_ID
  (
    .clk(clk), 
    .reset(reset), 
    .instr(imem_data), 
    .instr_valid(imem_out_valid), 
    .pc(if_pc), 
    .pc_4(if_pc_4), 
    .branch_prediction(prediction_out), 
    .prediction_index(prediction_index), 
    .bhr_snap_index(bhr_snap_index), 
    .prediction_valid(prediction_valid), 
    .flush(if_id_flush), 
    .stall(if_id_stall), 
    .id_pc(id_pc), 
    .id_pc_4(id_pc_4), 
    .id_instr(id_instr), 
    .id_instr_valid(id_instr_valid), 
    .id_branch_prediction(id_branch_prediction), 
    .id_prediction_index(id_prediction_index), 
    .id_bhr_snap_index(id_bhr_snap_index), 
    .id_prediction_valid(id_prediction_valid)
  ); 

  instruction_decoder
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH)
  )
  INSTRUCTION_DECODER
  (
    .inst_in(id_instr), 
    .op_code(id_op_code), 
    .funct_7(id_funct_7), 
    .funct_3(id_funct_3), 
    .r_imm(id_r_imm), 
    .imm(id_imm), 
    .rs1(id_rs1), 
    .rs2(id_rs2), 
    .rd(id_rd)
  ); 

  control
  CONTROL_UNIT
  (
    .op_code(id_op_code), 
    .funct3(id_funct_3), 
    .trap_done(1'b0), 
    .csr_ready(1'b1), 
    .pc_stall(id_sys_busy), //multi cycle SYSTEM instruction. goes to HAZARD, not the PC
    .jump(id_jump), 
    .branch(id_branch), 
    .alu_src_1(id_alu_src_1), 
    .alu_src_2(id_alu_src_2), 
    .mem_read(id_mem_read), 
    .mem_write(id_mem_write), 
    .mem_to_reg(id_mem_to_reg),
    .reg_write(id_reg_write),
    .csr_write(id_csr_write)
  );

  // instr_valid is authoritative and gates all control bits 
  wire id_jump_q      = id_jump      & id_instr_valid;
  wire id_branch_q    = id_branch    & id_instr_valid;
  wire id_mem_read_q  = id_mem_read  & id_instr_valid;
  wire id_mem_write_q = id_mem_write & id_instr_valid;
  wire id_reg_write_q = id_reg_write & id_instr_valid;
  wire id_csr_write_q = id_csr_write & id_instr_valid; 

  alu_controller
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .OP_CODE_WIDTH(OP_CODE_WIDTH), 
    .FUNCT_7_WIDTH(7), 
    .FUNCT_3_WIDTH(FUNCT_3_WIDTH)
  )
  ALU_CONTROLLER
  (
    .funct_7(id_funct_7), 
    .funct_3(id_funct_3), 
    .op_code(id_op_code), 
    .alu_op(id_alu_op)
  ); 

  register_file
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .ADDR_WIDTH(REG_ADDR_WIDTH)
  )
  REG_FILE
  (
    .clk(clk), 
    .write_en(wb_reg_write), 
    .read_addr_1(id_rs1), 
    .read_addr_2(id_rs2), 
    .write_addr(wb_rd), 
    .write_data(wb_src), 
    .read_data_1(id_read_data_1), 
    .read_data_2(id_read_data_2)
  ); 

  //////////////////////////////////////////////////////////////
  // EXECUTE
  //////////////////////////////////////////////////////////////
  wire [1:0] ex_alu_src_1, ex_alu_src_2; 
  wire ex_mem_write, ex_mem_read, ex_reg_write, ex_csr_write; 
  wire [2:0] ex_mem_to_reg; 
  wire [3:0] ex_alu_op; 
  wire [FUNCT_3_WIDTH-1:0] ex_funct_3; 
  wire [REG_ADDR_WIDTH-1:0] ex_rs1, ex_rs2, ex_rd; 
  wire [DATA_WIDTH-1:0] ex_rd_1, ex_rd_2, ex_imm, ex_r_imm; 
  wire [DATA_WIDTH-1:0] ex_pc_4, ex_csr_read_data, ex_instr; 

  wire [1:0] forward_a, forward_b; 
  reg [DATA_WIDTH-1:0] rd_1_fwd, rd_2_fwd, alu_in_1, alu_in_2; 
  reg [DATA_WIDTH-1:0] em_src; 

  ID_EX_reg
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .OP_CODE_WIDTH(OP_CODE_WIDTH), 
    .FUNCT_3_WIDTH(FUNCT_3_WIDTH), 
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH), 
    .HIST_BITS(HIST_BITS), 
    .BHR_SNAPS(BHR_SNAPS)
  )
  ID_EX
  (
    .clk(clk), 
    .reset(reset), 
    .jump(id_jump_q), 
    .branch(id_branch_q), 
    .alu_src_1(id_alu_src_1), 
    .alu_src_2(id_alu_src_2), 
    .mem_write(id_mem_write_q), 
    .mem_read(id_mem_read_q), 
    .mem_to_reg(id_mem_to_reg), 
    .reg_write(id_reg_write_q), 
    .csr_write(id_csr_write_q), 
    .alu_op(id_alu_op), 
    .op_code(id_op_code), 
    .funct_3(id_funct_3), 
    .rs1(id_rs1), 
    .rs2(id_rs2), 
    .rd(id_rd), 
    .rd_1(id_read_data_1), 
    .rd_2(id_read_data_2), 
    .imm(id_imm), 
    .r_imm(id_r_imm), 
    .pc(id_pc), 
    .pc_4(id_pc_4), 
    .csr_read_data({DATA_WIDTH{1'b0}}), 
    .instr(id_instr), 
    .instr_valid(id_instr_valid), 
    .branch_prediction(id_branch_prediction), 
    .prediction_index(id_prediction_index), 
    .bhr_snap_index(id_bhr_snap_index), 
    .prediction_valid(id_prediction_valid), 
    .flush(id_ex_flush), 
    .stall(id_ex_stall), 
    .ex_jump(ex_jump), 
    .ex_branch(ex_branch), 
    .ex_alu_src_1(ex_alu_src_1), 
    .ex_alu_src_2(ex_alu_src_2), 
    .ex_mem_write(ex_mem_write), 
    .ex_mem_read(ex_mem_read), 
    .ex_mem_to_reg(ex_mem_to_reg), 
    .ex_reg_write(ex_reg_write), 
    .ex_csr_write(ex_csr_write), 
    .ex_alu_op(ex_alu_op), 
    .ex_op_code(ex_op_code), 
    .ex_funct_3(ex_funct_3), 
    .ex_rs1(ex_rs1), 
    .ex_rs2(ex_rs2), 
    .ex_rd(ex_rd), 
    .ex_rd_1(ex_rd_1), 
    .ex_rd_2(ex_rd_2), 
    .ex_imm(ex_imm), 
    .ex_r_imm(ex_r_imm), 
    .ex_pc(ex_pc), 
    .ex_pc_4(ex_pc_4), 
    .ex_csr_read_data(ex_csr_read_data), 
    .ex_instr(ex_instr), 
    .ex_instr_valid(ex_instr_valid), 
    .ex_branch_prediction(ex_branch_prediction), 
    .ex_prediction_index(ex_prediction_index), 
    .ex_bhr_snap_index(ex_bhr_snap_index), 
    .ex_prediction_valid(ex_prediction_valid)
  ); 

  //forward the register reads first, then pick the alu source. doing it the
  //other way round lets a forward overwrite PC or the csr immediate.
  always@(*)
  begin 
    case(forward_a)
      2'b10:   rd_1_fwd = em_src; 
      2'b01:   rd_1_fwd = wb_src; 
      default: rd_1_fwd = ex_rd_1; 
    endcase
  end

  always@(*)
  begin 
    case(forward_b)
      2'b10:   rd_2_fwd = em_src; 
      2'b01:   rd_2_fwd = wb_src; 
      default: rd_2_fwd = ex_rd_2; 
    endcase
  end

  always@(*)
  begin 
    case(ex_alu_src_1)
      2'b01:   alu_in_1 = ex_pc; 
      2'b10:   alu_in_1 = {{(DATA_WIDTH-REG_ADDR_WIDTH){1'b0}}, ex_rs1}; 
      default: alu_in_1 = rd_1_fwd; 
    endcase
  end

  always@(*)
  begin 
    case(ex_alu_src_2)
      2'b01:   alu_in_2 = ex_imm; 
      2'b10:   alu_in_2 = ex_csr_read_data; 
      default: alu_in_2 = rd_2_fwd; 
    endcase
  end

  alu
  #(.DATA_WIDTH(DATA_WIDTH))
  ALU
  (
    .alu_op(ex_alu_op), 
    .x(alu_in_1), 
    .y(alu_in_2), 
    .r(ex_alu_result)
  ); 

  branch_logic
  #(.DATA_WIDTH(DATA_WIDTH))
  BRANCH_LOGIC
  (
    .branch(ex_branch), 
    .EX_pc(ex_pc), 
    .EX_imm(ex_imm), 
    .alu_cond(ex_alu_result[0]), 
    .branch_prediction(ex_branch_prediction[1]), 
    .prediction_miss(ex_prediction_miss), 
    .branch_target_actual(ex_branch_target_actual), 
    .branch_taken(ex_branch_taken)
  ); 

  //////////////////////////////////////////////////////////////
  // MEMORY
  //////////////////////////////////////////////////////////////
  wire em_mem_read, em_mem_write, em_reg_write, em_csr_write; 
  wire em_instr_valid; 
  wire [2:0] em_mem_to_reg; 
  wire [DATA_WIDTH-1:0] em_alu_result, em_r_data_2, em_imm, em_r_imm; 
  wire [DATA_WIDTH-1:0] em_pc, em_pc_4, em_csr_read_data, em_instr; 
  wire [FUNCT_3_WIDTH-1:0] em_funct_3; 
  wire [OP_CODE_WIDTH-1:0] em_op_code; 
  wire [REG_ADDR_WIDTH-1:0] em_rd; 

  wire [DATA_WIDTH-1:0] cache_data_out, be_data_out, lsu_data_out; 
  wire cpu_ready_out, cpu_data_out_valid; 
  wire cpu_data_in_valid, cpu_write_read; 
  wire [DATA_WIDTH-1:0] cpu_data_in, cpu_addr_in; 
  wire [1:0] cpu_size; 

  //backing memory behind the data cache
  wire mem_ready; 
  wire mem_data_in_valid; 
  wire [BLOCK_BITS-1:0] mem_data_in;  
  wire mem_write_read; 
  wire [DATA_WIDTH-1:0] mem_addr_in;  
  wire mem_addr_in_valid; 
  wire [BLOCK_BITS-1:0] mem_data_out;  
  wire mem_data_out_valid; 

  EX_MEM_reg
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .OP_CODE_WIDTH(OP_CODE_WIDTH), 
    .FUNCT_3_WIDTH(FUNCT_3_WIDTH), 
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH)
  )
  EX_MEM
  (
    .clk(clk), 
    .reset(reset), 
    .mem_read(ex_mem_read), 
    .mem_write(ex_mem_write), 
    .mem_to_reg(ex_mem_to_reg), 
    .reg_write(ex_reg_write), 
    .csr_write(ex_csr_write), 
    .alu_result(ex_alu_result), 
    .r_data_2(rd_2_fwd), 
    .imm(ex_imm), 
    .r_imm(ex_r_imm), 
    .pc(ex_pc), 
    .pc_4(ex_pc_4), 
    .csr_read_data(ex_csr_read_data), 
    .instr(ex_instr), 
    .instr_valid(ex_instr_valid), 
    .funct_3(ex_funct_3), 
    .op_code(ex_op_code), 
    .rd(ex_rd), 
    .flush(ex_mem_flush), 
    .stall(ex_mem_stall), 
    .em_mem_read(em_mem_read), 
    .em_mem_write(em_mem_write), 
    .em_mem_to_reg(em_mem_to_reg), 
    .em_reg_write(em_reg_write), 
    .em_csr_write(em_csr_write), 
    .em_alu_result(em_alu_result), 
    .em_r_data_2(em_r_data_2), 
    .em_imm(em_imm), 
    .em_r_imm(em_r_imm), 
    .em_pc(em_pc), 
    .em_pc_4(em_pc_4), 
    .em_csr_read_data(em_csr_read_data), 
    .em_instr(em_instr), 
    .em_instr_valid(em_instr_valid), 
    .em_funct_3(em_funct_3), 
    .em_op_code(em_op_code), 
    .em_rd(em_rd)
  ); 

  //the lsu owns the whole memory-stage handshake: it issues each access once,
  //holds req_stall until the response, and routes mmio away from the cache
  lsu
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .FUNCT_3_WIDTH(FUNCT_3_WIDTH)
  )
  LSU
  (
    .clk(clk), 
    .reset(reset), 

    .em_mem_read(em_mem_read), 
    .em_mem_write(em_mem_write), 
    .em_funct_3(em_funct_3), 
    .em_r_data_2(em_r_data_2), 
    .em_alu_result(em_alu_result), 
    .be_cache_in(lsu_data_out), 

    .cpu_data_out_valid(cpu_data_out_valid), 
    .cpu_data_out(cache_data_out), 
    .cpu_ready_out(cpu_ready_out), 
    .cpu_data_in_valid(cpu_data_in_valid), 
    .cpu_write_read(cpu_write_read), 
    .cpu_data_in(cpu_data_in), 
    .cpu_size(cpu_size), 
    .cpu_addr_in(cpu_addr_in), 

    .io_data_out(io_data_out), 
    .io_ack(io_ack), 
    .io_req(io_req), 
    .io_write_read(io_write_read), 
    .io_data_in(io_data_in), 
    .io_size(io_size), 
    .io_addr_in(io_addr_in), 

    .req_stall(req_stall), 
    .mem_advance(mem_advance)
  ); 

  hazard_detector
  #(.REG_ADDR_WIDTH(REG_ADDR_WIDTH))
  HAZARD
  (
    .prediction_miss(ex_prediction_miss), 
    .ex_jump(ex_jump), 
    .ex_rd(ex_rd), 
    .ex_mem_read(ex_mem_read), 
    .id_rs1(id_rs1), 
    .id_rs2(id_rs2), 
    .req_stall(req_stall), 
    .mem_advance(mem_advance), 
    .sys_busy(id_sys_busy & id_instr_valid), 
    .pc_stall(pc_stall), 
    .if_id_stall(if_id_stall), 
    .id_ex_stall(id_ex_stall), 
    .ex_mem_stall(ex_mem_stall), 
    .mem_wb_stall(mem_wb_stall), 
    .if_id_flush(if_id_flush), 
    .id_ex_flush(id_ex_flush), 
    .ex_mem_flush(ex_mem_flush), 
    .mem_wb_flush(mem_wb_flush)
  ); 

  cache_controller
  #(
    .ADDR_BITS(DATA_WIDTH), 
    .DATA_WIDTH(DATA_WIDTH), 
    .BLOCK_BITS(BLOCK_BITS), 
    .WB_FIFO_DEPTH(WB_FIFO_DEPTH),
    .WORD_OFF_BITS($clog2(BLOCK_BITS/DATA_WIDTH)), 
    .SET_N(CACHE_SET_N)
  )
  D_CACHE
  (
    .clk(clk), 
    .reset(reset), 
    .cpu_data_in_valid(cpu_data_in_valid), 
    .cpu_write_read(cpu_write_read), 
    .cpu_data_in(cpu_data_in), 
    .cpu_size(cpu_size), 
    .cpu_addr_in(cpu_addr_in), 
    .cpu_data_out(cache_data_out), 
    .cpu_ready_out(cpu_ready_out), 
    .cpu_data_out_valid(cpu_data_out_valid), 
    .mem_ready(mem_ready), 
    .mem_data_in_valid(mem_data_in_valid), 
    .mem_data_in(mem_data_in), 
    .mem_write_read(mem_write_read), 
    .mem_addr_in(mem_addr_in), 
    .mem_addr_in_valid(mem_addr_in_valid), 
    .mem_data_out(mem_data_out), 
    .mem_data_out_valid(mem_data_out_valid)
  ); 

  data_mem //simulate byte addressed memory
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .BLOCK_BITS(BLOCK_BITS), //32 bytes or 8 words 
    .D_MEM_DEPTH(DATA_MEM_DEPTH), 
    .WORD_OFF_BITS($clog2(BLOCK_BITS/DATA_WIDTH))
  )
  D_MEM
  (
    .clk(clk),
    .reset(reset), 
    .mem_ready(mem_ready), 
    .data_out_valid(mem_data_in_valid), 
    .data_out(mem_data_in), 
    .addr_in(mem_addr_in), 
    .addr_in_valid(mem_addr_in_valid), 
    .data_in(mem_data_out), 
    .data_in_valid(mem_data_out_valid), 
    .write_read(mem_write_read)
  ); 

  BE_logic
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .FUNCT_3_WIDTH(FUNCT_3_WIDTH)
  )
  BE_LOGIC
  (
    .funct_3(em_funct_3), 
    .cache_in(lsu_data_out), 
    .r_out(be_data_out)
  ); 

  always@(*)
  begin 
    case(em_mem_to_reg)
      3'd1:    em_src = be_data_out; 
      3'd2:    em_src = em_pc_4; 
      3'd3:    em_src = em_imm; 
      3'd4:    em_src = em_csr_read_data; 
      default: em_src = em_alu_result; 
    endcase
  end

  forwarding_unit
  #(
    .ADDR_WIDTH(REG_ADDR_WIDTH), 
    .DATA_WIDTH(DATA_WIDTH)
  )
  FORWARDING_UNIT
  (
    .ID_EX_RS1(ex_rs1), 
    .ID_EX_RS2(ex_rs2), 
    .EX_MEM_RD(em_rd), 
    .MEM_WB_RD(wb_rd), 
    .EX_MEM_RegWrite(em_reg_write), 
    .MEM_WB_RegWrite(wb_reg_write), 
    .forward_a(forward_a), 
    .forward_b(forward_b)
  ); 

  //////////////////////////////////////////////////////////////
  // WRITEBACK
  //////////////////////////////////////////////////////////////
  wire [DATA_WIDTH-1:0] wb_alu_result, wb_read_data, wb_pc_4; 
  wire [DATA_WIDTH-1:0] wb_liu_imm, wb_csr_rd, wb_pc, wb_r_imm, wb_instr; 
  wire [2:0] wb_mem_to_reg; 
  wire [OP_CODE_WIDTH-1:0] wb_op_code; 

  MEM_WB_reg
  #(
    .DATA_WIDTH(DATA_WIDTH), 
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH), 
    .OP_CODE_WIDTH(OP_CODE_WIDTH)
  )
  MEM_WB
  (
    .clk(clk), 
    .reset(reset), 
    .alu_result(em_alu_result), 
    .read_data(be_data_out), 
    .pc_4(em_pc_4), 
    .liu_imm(em_imm), 
    .csr_rd(em_csr_read_data), 
    .mem_to_reg(em_mem_to_reg), 
    .reg_write(em_reg_write), 
    .rd(em_rd), 
    .pc(em_pc), 
    .r_imm(em_r_imm), 
    .op_code(em_op_code), 
    .instr(em_instr), 
    .instr_valid(em_instr_valid), 
    .stall(mem_wb_stall), 
    .flush(mem_wb_flush), 
    .mem_alu_result(wb_alu_result), 
    .mem_read_data(wb_read_data), 
    .mem_pc_4(wb_pc_4), 
    .mem_liu_imm(wb_liu_imm), 
    .mem_csr_rd(wb_csr_rd), 
    .mem_mem_to_reg(wb_mem_to_reg), 
    .mem_reg_write(wb_reg_write), 
    .mem_rd(wb_rd), 
    .mem_pc(wb_pc), 
    .mem_r_imm(wb_r_imm), 
    .mem_op_code(wb_op_code), 
    .mem_instr(wb_instr), 
    .mem_instr_valid(wb_instr_valid)
  ); 

  always@(*)
  begin 
    case(wb_mem_to_reg)
      3'd1:    wb_src = wb_read_data; 
      3'd2:    wb_src = wb_pc_4; 
      3'd3:    wb_src = wb_liu_imm; 
      3'd4:    wb_src = wb_csr_rd; 
      default: wb_src = wb_alu_result; 
    endcase
  end

endmodule 
