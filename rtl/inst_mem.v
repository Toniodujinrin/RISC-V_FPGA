module inst_mem
#(
  parameter 
  DATA_WIDTH = 32, 
  IMEM_DEPTH = 128, 
  PROGRAM_FILE = "build/test.mem"
)
(
  input clk, 
  input [DATA_WIDTH-1:0] imem_addr, 
  output reg [DATA_WIDTH-1:0] imem_data, 
  output reg output_valid 
); 

  reg [DATA_WIDTH-1:0] mem [0:IMEM_DEPTH-1]; 
  localparam ADDR_WIDTH = $clog2(IMEM_DEPTH); 
  initial 
  begin 
    $readmemb(PROGRAM_FILE,mem); 
  end

  wire  [ADDR_WIDTH-1:0] trunc_addr; 
  assign trunc_addr = imem_addr[ADDR_WIDTH+1:2] ; 


  always@(posedge clk)
  begin 
      imem_data <= mem[trunc_addr]; 
      output_valid <= (imem_addr[DATA_WIDTH-1:2] < IMEM_DEPTH); 
  end


endmodule 

