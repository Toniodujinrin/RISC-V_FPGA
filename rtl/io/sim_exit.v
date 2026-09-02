//SIM_EXIT -- 0xF000_00FC. A write ends the simulation, the value is the exit
//code. This is the whole point of the block: it turns every program from
//"stare at a waveform" into "pass or fail".
//
//Simulation only.
module sim_exit
#(
  parameter
  APB_DATA_WIDTH = 32,
  //offset inside this peripheral's 4K window. 0xF000_00FC -> 12'h0FC
  EXIT_OFFSET = 12'h0FC,
  //1: $finish inside the RTL, the way the roadmap describes it.
  //0: raise exit_valid and leave stopping to the testbench. cocotb cannot
  //survive an RTL $finish -- the scoreboard never gets to run its checks and
  //the test is reported as a crash rather than a failure -- so a cocotb TB
  //wants FINISH=0 and should await exit_valid itself.
  FINISH = 1
)
(
  input clk, reset,

  //apb port
  input PSEL,
  input PWRITE,
  input PENABLE,
  input [APB_DATA_WIDTH-1:0] PWDATA,
  input [APB_DATA_WIDTH-1:0] PADDR,
  input [3:0] PSTRB,
  output PREADY,
  output [APB_DATA_WIDTH-1:0] PRDATA,

  //observation port. sticky, so a testbench that samples on any edge after the
  //store still sees the result
  output reg exit_valid,
  output reg [APB_DATA_WIDTH-1:0] exit_code
);

  //zero wait state, and asserted for every address in the window rather than
  //only the matching one -- a stray access to an unimplemented offset must
  //return, not hang the core in the bridge's ACCESS state forever
  assign PREADY = 1'b1;

  //readable back for a testbench that would rather poll than watch exit_valid
  assign PRDATA = exit_code;

  //the write is the whole register: SIM_EXIT is word-only, so PSTRB is ignored
  wire exit_write;
  assign exit_write = PSEL && PENABLE && PWRITE && (PADDR[11:0] == EXIT_OFFSET);

  always@(posedge clk, posedge reset)
  begin
    if(reset)
    begin
      exit_valid <= 1'b0;
      exit_code <= 0;
    end
    else if(exit_write && !exit_valid) //first write wins, a second one is noise
    begin
      exit_valid <= 1'b1;
      exit_code <= PWDATA;
      if(PWDATA == 0)
        $display("[%0t] SIM_EXIT: PASS (code 0)", $time);
      else
        $display("[%0t] SIM_EXIT: FAIL (code %0d / 0x%08h)", $time, PWDATA, PWDATA);
      //$finish does not carry a process exit status in iverilog, so the code
      //lives in the line above and on exit_code -- do not expect $? to hold it
      if(FINISH)
        $finish;
    end
  end

endmodule
