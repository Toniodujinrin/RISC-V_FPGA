//the mmio subsystem: the apb bridge and every slave hanging off it. the lsu
//routes any access with addr[31:28] == IO_PAGE here, and the bridge's decoder
//splits that page into 4K windows, one per slave:
//
//  0xF000_0000 - 0xF000_0FFF   SIM_EXIT  (a write to 0xF000_00FC ends the sim)
//  0xF000_1000 - 0xF000_1FFF   UART
//
//N_C is 2, so the windows above the last slave fail the bridge's decode and come
//back as io_slv_err. that matters: the bridge's ACCESS state has no timeout, so
//a window with nothing in it to drive PREADY would hang the core for good
module mmio
#(
  parameter
  DATA_WIDTH = 32,
  //1 keeps sim_exit in the design. drop it to 0 for the fitter build, the block
  //being simulation only -- its window then answers with an error
  SIM_EXIT_PRESENT = 1,
  //cocotb cannot survive an RTL $finish, so a cocotb build wants 0 here and
  //should await exit_valid itself
  SIM_EXIT_FINISH = 1
)
(
  input clk, reset,

  //lsu port
  input io_req,
  input io_write_read,
  input [DATA_WIDTH-1:0] io_data_in,
  input [1:0] io_size,
  input [DATA_WIDTH-1:0] io_addr_in,
  output io_ack,
  output io_slv_err,
  output [DATA_WIDTH-1:0] io_data_out,

  //uart pins
  input uart_rx,
  output uart_tx,

  //sim_exit observation. sticky, so a testbench can sample it on any edge
  output exit_valid,
  output [DATA_WIDTH-1:0] exit_code
);

  localparam N_C = 2;
  localparam SIM_EXIT_SLV = 0;
  localparam UART_SLV = 1;

  wire [N_C-1:0] PSEL;
  wire PWRITE, PENABLE;
  wire [DATA_WIDTH-1:0] PWDATA, PADDR;
  wire [3:0] PSTRB;

  wire exit_ready, exit_slverr;
  wire [DATA_WIDTH-1:0] exit_prdata;
  wire uart_ready, uart_slverr;
  wire [DATA_WIDTH-1:0] uart_prdata;

  //slave 1 takes the upper slice of each vector, the bridge indexing them as
  //[(i*DATA_WIDTH) +: DATA_WIDTH]
  io_apb_bridge
  #(
    .DATA_WIDTH(DATA_WIDTH),
    .N_C(N_C)
  )
  BRIDGE
  (
    .clk(clk),
    .reset(reset),

    .io_write_read(io_write_read),
    .io_req(io_req),
    .io_data_in(io_data_in),
    .io_size(io_size),
    .io_addr_in(io_addr_in),
    .io_ack(io_ack),
    .io_slv_err(io_slv_err),
    .io_data_out(io_data_out),

    .PSEL(PSEL),
    .PWRITE(PWRITE),
    .PENABLE(PENABLE),
    .PWDATA(PWDATA),
    .PADDR(PADDR),
    .PSTRB(PSTRB),
    .PREADY({uart_ready, exit_ready}),
    .PSLVERR({uart_slverr, exit_slverr}),
    .PRDATA({uart_prdata, exit_prdata})
  );

  generate
  if(SIM_EXIT_PRESENT)
  begin: SIM_EXIT_BLOCK
    //zero wait state and it answers for every offset in its window, so a stray
    //access to an unimplemented one returns instead of hanging
    sim_exit
    #(
      .APB_DATA_WIDTH(DATA_WIDTH),
      .FINISH(SIM_EXIT_FINISH)
    )
    EXIT
    (
      .clk(clk),
      .reset(reset),
      .PSEL(PSEL[SIM_EXIT_SLV]),
      .PWRITE(PWRITE),
      .PENABLE(PENABLE),
      .PWDATA(PWDATA),
      .PADDR(PADDR),
      .PSTRB(PSTRB),
      .PREADY(exit_ready),
      .PRDATA(exit_prdata),
      .exit_valid(exit_valid),
      .exit_code(exit_code)
    );
    assign exit_slverr = 1'b0; //it has no way to fail a transfer
  end
  else
  begin: NO_SIM_EXIT
    //left out of the build, so the window answers rather than hanging
    assign exit_ready = 1'b1;
    assign exit_slverr = 1'b1;
    assign exit_prdata = 0;
    assign exit_valid = 1'b0;
    assign exit_code = 0;
  end
  endgenerate

  uart
  #(
    .APB_DATA_WIDTH(DATA_WIDTH)
  )
  UART
  (
    .clk(clk),
    .reset(reset),
    .rx(uart_rx),
    .tx(uart_tx),
    .PSEL(PSEL[UART_SLV]),
    .PWRITE(PWRITE),
    .PENABLE(PENABLE),
    .PWDATA(PWDATA),
    .PADDR(PADDR),
    .PSTRB(PSTRB),
    .PREADY(uart_ready),
    .PSLVERR(uart_slverr),
    .PRDATA(uart_prdata)
  );

endmodule
