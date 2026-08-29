module register_file
#(
  parameter
  DATA_WIDTH = 32, 
  ADDR_WIDTH = 5
)
(
  input clk, n_reset, 
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

  //sequential write. x0 is hardwired, so writes to it are dropped.
  //write is on negedge 
  integer i; 
  always@(negedge clk, negedge n_reset)
  begin 
    if(~n_reset)
    begin 
      for(i = 0; i < N_REGS; i = i+1)
      begin 
        file[i] <= 0; 
      end 
    end
    else
    begin 
      if(write_en && write_addr != {ADDR_WIDTH{1'b0}})
        file[write_addr] <= write_data; 
    end 
  end 
  
  //combinational read. x0 always reads zero.
  always@(*)
  begin 
    read_data_1 = (read_addr_1 == {ADDR_WIDTH{1'b0}})? {DATA_WIDTH{1'b0}} : file[read_addr_1]; 
    read_data_2 = (read_addr_2 == {ADDR_WIDTH{1'b0}})? {DATA_WIDTH{1'b0}} : file[read_addr_2]; 
  end
  


endmodule 
