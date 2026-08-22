module register_file
#(
  DATA_WIDTH = 32, 
  ADDR_WIDTH = 5
)
(
  input clk, reset, 
  input write_en, 
  input [ADDR_WIDTH-1:0] read_addr_1, 
  input [ADDR_WIDTH-1:0] read_addr_2, 
  input [ADDR_WIDTH-1:0] write_addr,
  input [DATA_WIDTH-1:0] write_data, 
  output reg [DATA_WIDTH-1:0] read_data_1, 
  output reg [DATA_WIDTH-1:0] read_data_2
); 
  localparam N_REGS = 1 << ADDR_WIDTH; 
  (* ramstyle = "logic" *) reg [DATA_WIDTH-1:0] file [0:N_REGS-1];

  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      read_data_1 <= 0; 
      read_data_2 <= 0; 
    end 
    else 
    begin 
      if(write_en)
      begin 
        file[write_addr] <= write_data; 
      end 

      read_data_1 <= file[read_addr_1]; 
      read_data_2 <= file[read_addr_2]; 
    end 
  end 

  //set all initial values to 0 
  integer i; 
  initial
  begin 
    for(i = 0; i < N_REGS; i = i+1)
      file[i] = 0; 
  end 


  initial 
  begin 
    $dumpfile("register_file_dump.vcd"); 
    $dumpvars(0,register_file); 
  end
endmodule 
