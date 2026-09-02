//SoC top level -- the board build.
//
//This file used to be a virtual-pin timing/area probe. That probe is gone: the
//port list is now just the real board pins (clk, reset_n, uart_rx, uart_tx)
//plus io_slv_err as a bring-up LED driver, and syn/virtual_pins.tcl has been
//deleted with it.
//
//reset_n is active low, matching a KEY button on the DE10-Standard
//(5CSXFC6D6F31C6). The reset synchroniser below asserts asynchronously and
//deasserts synchronously, so every internal block that uses async reset keeps
//working and the whole core leaves reset on one clean, met, clock edge.
//
//SIM_EXIT_PRESENT is 0: sim_exit is a simulation block and is not instantiated
//in a fitted design. A store to its window then answers with io_slv_err rather
//than hanging (see rtl/mmio.v). Flip it back to 1 and re-add the exit ports if
//the exit code is wanted on hardware LEDs during bring-up.
//
//Memory init: inst_mem/data_mem take $readmemb on Verilog .mem files, which
//Quartus does not honour -- PROGRAM_FILE/DATA_FILE must be converted to
//.mif/.hex and attached via ram_init_file / quartus_cdb --update_mif before
//programming the board.
//
//Clock: the board oscillator is fed straight through, so the design runs at
//50 MHz, matching uart.v's hardwired CLOCK_SPEED. The 100 MHz SDC in syn/ is a
//timing-closure target only -- the aim is to prove 100 MHz closes, not to run
//there. A PLL goes here if 100 MHz ever becomes the run clock (AND its locked
//into the reset release).
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
  PROGRAM_FILE = "programs/test.mem",
  DATA_FILE = "programs/data.mem",
  CACHE_SET_N = 128,
  DATA_MEM_DEPTH = 1024,
  SIM_EXIT_PRESENT = 0,
  SIM_EXIT_FINISH = 0
)
(
  input clk,
  //board reset button, active low
  input reset_n,
  input uart_rx,
  output uart_tx,
  //flagged by the bridge on a decode error or a slave error. worth an LED on
  //bring-up: a stray MMIO access is exactly the failure that looks like a hang
  output io_slv_err
);

  //async assert, sync deassert: the chain is set asynchronously while the
  //button is down, and cleared only on clock edges after it comes back up.
  reg [1:0] rst_chain;
  always @(posedge clk or negedge reset_n)
  begin
    if (!reset_n) rst_chain <= 2'b11;
    else          rst_chain <= {rst_chain[0], 1'b0};
  end
  wire core_reset = rst_chain[1];

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
    .reset(core_reset),

    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .io_slv_err(io_slv_err)
  );

endmodule
