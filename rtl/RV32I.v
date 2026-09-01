//Synthesis top level.
//
//Both memories now live inside data_path: inst_mem.v and data_mem.v were
//instantiated there on 28 Aug, so neither instruction fetch nor the cache's
//BLOCK_BITS-wide backing port crosses this boundary any more. mmio.v followed,
//taking the io bus with it, so the boundary is now just the uart pins and
//sim_exit's observation port.
//
//Those ports are declared VIRTUAL_PIN in syn/virtual_pins.tcl so the fitter
//does not have to place them; only clk and reset stay real. Keep that file in
//step with this port list. Set SIM_EXIT_PRESENT to 0 for a fitter build --
//sim_exit is a simulation block with no business in the fitted design.
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
  IMEM_DEPTH = 8192,
  PROGRAM_FILE = "build/test.mem",
  DATA_FILE = "build/data.mem",
  CACHE_SET_N = 128,
  DATA_MEM_DEPTH = 1024,
  SIM_EXIT_PRESENT = 1,
  SIM_EXIT_FINISH = 1
)
(
  input clk, reset,


  //the mmio subsystem now lives inside data_path, so the io bus no longer
  //crosses this boundary -- only the uart pins and sim_exit's observation port
  input uart_rx, 
  output uart_tx, 
  output exit_valid, 
  output [DATA_WIDTH-1:0] exit_code, 
  output io_slv_err
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
    .DATA_FILE(DATA_FILE),
    .CACHE_SET_N(CACHE_SET_N),
    .DATA_MEM_DEPTH(DATA_MEM_DEPTH),
    .SIM_EXIT_PRESENT(SIM_EXIT_PRESENT),
    .SIM_EXIT_FINISH(SIM_EXIT_FINISH)
  )
  core
  (
    .clk(clk),
    .reset(reset),


    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .exit_valid(exit_valid),
    .exit_code(exit_code),
    .io_slv_err(io_slv_err)
  );

endmodule
