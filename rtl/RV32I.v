//Synthesis top level.
//
//data_path brings the instruction fetch port and the whole backing-memory
//interface out to its boundary (inst_mem.v/data_mem.v are still empty), which
//is ~1130 signals once the two BLOCK_BITS-wide block ports are counted. No
//Cyclone V part has that many user I/O, so this wrapper exists to give the
//fitter a top level whose ports can be declared VIRTUAL_PIN -- see
//syn/virtual_pins.tcl. Only clk and reset stay real.
//
//This is a timing/area probe, not the SoC top. When real memories land they
//get instantiated here and these ports go away.
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
  BLOCK_BITS = 8*8,
  WB_FIFO_DEPTH = 8
)
(
  input clk, reset,

  //instruction fetch port
  output [DATA_WIDTH-1:0] imem_addr,
  input [DATA_WIDTH-1:0] imem_data,

  //backing memory behind the data cache
  input mem_ready,
  input mem_data_in_valid,
  input [BLOCK_BITS-1:0] mem_data_in,
  output mem_write_read,
  output [DATA_WIDTH-1:0] mem_addr_in,
  output mem_addr_in_valid,
  output [BLOCK_BITS-1:0] mem_data_out,
  output mem_data_out_valid
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
    .WB_FIFO_DEPTH(WB_FIFO_DEPTH)
  )
  core
  (
    .clk(clk),
    .reset(reset),

    .imem_addr(imem_addr),
    .imem_data(imem_data),

    .mem_ready(mem_ready),
    .mem_data_in_valid(mem_data_in_valid),
    .mem_data_in(mem_data_in),
    .mem_write_read(mem_write_read),
    .mem_addr_in(mem_addr_in),
    .mem_addr_in_valid(mem_addr_in_valid),
    .mem_data_out(mem_data_out),
    .mem_data_out_valid(mem_data_out_valid)
  );

endmodule
