module lsu //load store unit
#(
  parameter
  DATA_WIDTH = 32, 
  FUNCT_3_WIDTH = 3, 
  IO_PAGE = 4'hF //addr[31:28] == IO_PAGE goes to the io bus
)
(
  input clk, reset, 

  //processor port
  input em_mem_read, 
  input em_mem_write,
  input [FUNCT_3_WIDTH-1:0] em_funct_3, 
  input [DATA_WIDTH-1:0] em_r_data_2, 
  input [DATA_WIDTH-1:0] em_alu_result, 
  output [DATA_WIDTH-1:0] be_cache_in, 
  

  //cache port 
  input cpu_data_out_valid,
  input [DATA_WIDTH-1:0] cpu_data_out, 
  input cpu_ready_out, 

  output reg cpu_data_in_valid, 
  output reg cpu_write_read, 
  output reg [DATA_WIDTH-1:0] cpu_data_in, 
  output reg [1:0] cpu_size,
  output reg [DATA_WIDTH-1:0] cpu_addr_in, 

  //io port. uncached, unbuffered, single request pulse. a trivial slave ties
  //io_ack to io_req delayed by one cycle
  input [DATA_WIDTH-1:0] io_data_out, 
  input io_ack, 

  output reg io_req, 
  output reg io_write_read, 
  output reg [DATA_WIDTH-1:0] io_data_in, 
  output reg [1:0] io_size, 
  output reg [DATA_WIDTH-1:0] io_addr_in, 

  //hazard port 
  output req_stall, 
  input mem_advance


); 

  localparam IDLE = 2'b00; 
  localparam RESP_WAITING = 2'b10; 
  localparam DONE = 2'b11; //cache has responded but cpu is still stalling for another reason 
  reg [1:0] current_state; 

  //decoded off the address before the request is routed, so the cache never
  //sees an io access
  wire is_io; 
  assign is_io = (em_alu_result[DATA_WIDTH-1 -: 4] == IO_PAGE); 

  //which port the outstanding access went to. the response side is a mux on it
  reg io_access_r; 

  wire resp_valid; 
  wire [DATA_WIDTH-1:0] resp_data; 
  assign resp_valid = io_access_r? io_ack : cpu_data_out_valid; 
  assign resp_data  = io_access_r? io_data_out : cpu_data_out; 

  wire cache_responded; 
  assign cache_responded = (current_state == RESP_WAITING) && resp_valid; 

  //req_stall drops combinationally on cache_responded, so MEM/WB latches at the
  //end of the response cycle. a registered be_cache_in is still holding the
  //previous value at that point, so the load would write back stale data -- the
  //pipeline released one cycle before the data it waited for was observable.
  //bypass the register on the response cycle; resp_data_r only has to hold the
  //value for DONE, when MEM could not advance yet.
  reg [DATA_WIDTH-1:0] resp_data_r; 
  assign be_cache_in = cache_responded? resp_data : resp_data_r; 
  assign req_stall = (em_mem_read | em_mem_write)
                      && ~cache_responded && ~(current_state == DONE); 

  

  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      current_state <= IDLE;
      cpu_data_in_valid <= 0;  
      cpu_write_read <= 0;  
      cpu_data_in <= 0;  
      cpu_size <= 0; 
      cpu_addr_in <= 0;
      io_req <= 0; 
      io_write_read <= 0; 
      io_data_in <= 0; 
      io_size <= 0; 
      io_addr_in <= 0; 
      io_access_r <= 0; 
      resp_data_r <= 0; 
    end
    else 
    begin 
      case(current_state) 
        IDLE:
        begin 
        if((em_mem_read | em_mem_write))
        begin 
            current_state <= RESP_WAITING; 
            io_access_r <= is_io; 
            if(is_io)
            begin 
              io_req <= 1; 
              io_write_read <= em_mem_write; 
              io_data_in <= em_r_data_2; 
              io_size <= em_funct_3[1:0]; 
              io_addr_in <= em_alu_result; 
            end
            else
            begin 
              cpu_write_read <= em_mem_write; 
              cpu_data_in_valid <= 1;
              cpu_data_in <= em_r_data_2; 
              cpu_size <= em_funct_3[1:0]; 
              cpu_addr_in <= em_alu_result; 
            end
        end 
        end
        RESP_WAITING:
        begin
          io_req <= 0; //one cycle pulse, so a store can never be issued twice
          if(!cpu_ready_out)
            cpu_data_in_valid <= 0; 
          if(resp_valid)
          begin 
            resp_data_r <= resp_data; 
            current_state <= mem_advance? IDLE : DONE; 
          end 
        end
        DONE: 
        begin 
          if(mem_advance)
            current_state <= IDLE; 
        end
        default: 
          current_state <= IDLE; 
      endcase
    end
  end


endmodule
