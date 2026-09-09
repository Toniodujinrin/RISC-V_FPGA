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
  SDRAM_ADDR_WIDTH = 13,
  SDRAM_DATA_WIDTH = 16,
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
  output io_slv_err,

  output [SDRAM_ADDR_WIDTH-1:0] DRAM_ADDR,
  output [1:0] DRAM_BA,
  output DRAM_CKE,
  output DRAM_CS_N,
  output DRAM_RAS_N,
  output DRAM_CAS_N,
  output DRAM_WE_N,
  output DRAM_LDQM,
  output DRAM_UDQM,
  output DRAM_CLK,
  inout [SDRAM_DATA_WIDTH-1:0] DRAM_DQ
);

  wire [SDRAM_DATA_WIDTH-1:0] dram_dq_out;
  wire dram_dq_oe;

  assign DRAM_DQ  = dram_dq_oe ? dram_dq_out : {SDRAM_DATA_WIDTH{1'bz}};
  assign DRAM_CLK = clk;

  //async assert, sync deassert: the chain is set asynchronously while the
  //button is down, and cleared only on clock edges after it comes back up.
  reg [1:0] rst_chain;
  always @(posedge clk or negedge reset_n)
  begin
    if (!reset_n) rst_chain <= 2'b11;
    else          rst_chain <= {rst_chain[0], 1'b0};
  end
  wire sys_reset  = rst_chain[1];
  wire core_reset = sys_reset | boot_active;

  wire boot_active, boot_tx, core_tx;
  assign uart_tx = boot_active ? boot_tx : core_tx;

  wire boot_imem_we;
  wire [DATA_WIDTH-1:0] boot_imem_waddr, boot_imem_wdata;

  wire boot_dram_valid, boot_dram_write_read;
  wire [DATA_WIDTH-1:0] boot_dram_addr;
  wire [BLOCK_BITS-1:0] boot_dram_wdata;

  wire cache_mem_valid, cache_mem_write_read;
  wire [DATA_WIDTH-1:0] cache_mem_addr;
  wire [BLOCK_BITS-1:0] cache_mem_wdata;

  wire mem_ready, mem_data_out_valid;
  wire [BLOCK_BITS-1:0] mem_data_out;

  //only swap owners while the controller is idle, never mid burst
  reg boot_sel;
  always @(posedge clk, posedge sys_reset)
  begin
    if (sys_reset)      boot_sel <= 1'b1;
    else if (mem_ready) boot_sel <= boot_active;
  end

  SRAM_controller
  #(
    .DATA_WIDTH(DATA_WIDTH),
    .BLOCK_BITS(BLOCK_BITS),
    .MEM_DATA_WIDTH(SDRAM_DATA_WIDTH),
    .MEM_ADDR_WIDTH(SDRAM_ADDR_WIDTH)
  )
  SDRAM
  (
    .clk(clk),
    .reset(sys_reset),
    .mem_addr_in(DRAM_ADDR),
    .mem_data_in(dram_dq_out),
    .mem_data_oe(dram_dq_oe),
    .mem_bank_select(DRAM_BA),
    .mem_clk_en(DRAM_CKE),
    .mem_l_byte_en(DRAM_LDQM),
    .mem_u_byte_en(DRAM_UDQM),
    .mem_we_n(DRAM_WE_N),
    .mem_cas_n(DRAM_CAS_N),
    .mem_ras_n(DRAM_RAS_N),
    .mem_cs_n(DRAM_CS_N),
    .mem_data_out(DRAM_DQ),
    .mem_ready(mem_ready),
    .data_out_valid(mem_data_out_valid),
    .data_out(mem_data_out),
    .cpu_data_in  (boot_sel ? boot_dram_wdata      : cache_mem_wdata),
    .cpu_addr_in  (boot_sel ? boot_dram_addr       : cache_mem_addr),
    .cpu_in_valid (boot_sel ? boot_dram_valid      : cache_mem_valid),
    .cpu_write_read(boot_sel ? boot_dram_write_read : cache_mem_write_read)
  );

  bootloader
  #(
    .DATA_WIDTH(DATA_WIDTH),
    .BLOCK_BITS(BLOCK_BITS)
  )
  BOOT
  (
    .clk(clk),
    .reset(sys_reset),
    .rx(uart_rx),
    .tx(boot_tx),
    .boot_active(boot_active),
    .imem_waddr(boot_imem_waddr),
    .imem_wdata(boot_imem_wdata),
    .imem_we(boot_imem_we),
    .dram_addr(boot_dram_addr),
    .dram_wdata(boot_dram_wdata),
    .dram_valid(boot_dram_valid),
    .dram_write_read(boot_dram_write_read),
    .dram_ready(mem_ready)
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
    .reset(core_reset),

    .uart_rx(uart_rx),
    .uart_tx(core_tx),
    .io_slv_err(io_slv_err),

    .imem_we(boot_imem_we),
    .imem_waddr(boot_imem_waddr),
    .imem_wdata(boot_imem_wdata),

    .mem_ready(mem_ready),
    .mem_data_in_valid(mem_data_out_valid),
    .mem_data_in(mem_data_out),
    .mem_write_read(cache_mem_write_read),
    .mem_addr_in(cache_mem_addr),
    .mem_addr_in_valid(cache_mem_valid),
    .mem_data_out(cache_mem_wdata)
  );

endmodule
