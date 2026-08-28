//Synthesis top level.
//
//Both memories now live inside data_path: inst_mem.v and data_mem.v were
//instantiated there on 28 Aug, so neither instruction fetch nor the cache's
//BLOCK_BITS-wide backing port crosses this boundary any more. Only the io bus
//is still brought out -- ~101 signals -- because no IO slave exists yet.
//
//Those io ports are declared VIRTUAL_PIN in syn/virtual_pins.tcl so the fitter
//does not have to place them; only clk and reset stay real. Keep that file in
//step with this port list.
//
//This is a timing/area probe, not the SoC top. Note the two memories are now
//inside the probe, so fitter area numbers include them -- IMEM_DEPTH and
//DATA_MEM_DEPTH are passed through here for exactly that reason.
module RV32I
#(
  parameter
  DATA_WIDTH = 32,
  OP_CODE_WIDTH = 7,
  FUNCT_3_WIDTH = 3,
  REG_ADDR_WIDTH = 5,
  HIST_BITS = 7,
  BHR_SNAPS = 4,
  BTB_DEPTH = 8,
  BLOCK_BITS = 32*8,
  WB_FIFO_DEPTH = 8,
  IMEM_DEPTH = 1024,
  PROGRAM_FILE = "build/test.mem",
  CACHE_SET_N = 128,
  DATA_MEM_DEPTH = 1024
)
(
  input clk, reset,


  //io bus behind the lsu's mmio bypass
  input [DATA_WIDTH-1:0] io_data_out, 
  input io_ack, 
  output io_req, 
  output io_write_read, 
  output [DATA_WIDTH-1:0] io_data_in, 
  output [1:0] io_size, 
  output [DATA_WIDTH-1:0] io_addr_in
);

  data_path
  #(
    .DATA_WIDTH(DATA_WIDTH),
    .OP_CODE_WIDTH(OP_CODE_WIDTH),
    .FUNCT_3_WIDTH(FUNCT_3_WIDTH),
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
    .HIST_BITS(HIST_BITS),
    .BHR_SNAPS(BHR_SNAPS),
    .BTB_DEPTH(BTB_DEPTH),
    .BLOCK_BITS(BLOCK_BITS),
    .WB_FIFO_DEPTH(WB_FIFO_DEPTH),
    .IMEM_DEPTH(IMEM_DEPTH),
    .PROGRAM_FILE(PROGRAM_FILE),
    .CACHE_SET_N(CACHE_SET_N),
    .DATA_MEM_DEPTH(DATA_MEM_DEPTH)
  )
  core
  (
    .clk(clk),
    .reset(reset),


    .io_data_out(io_data_out),
    .io_ack(io_ack),
    .io_req(io_req),
    .io_write_read(io_write_read),
    .io_data_in(io_data_in),
    .io_size(io_size),
    .io_addr_in(io_addr_in)
  );

endmodule
