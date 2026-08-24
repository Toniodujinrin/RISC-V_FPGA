`include "riscv_defs.vh"
module btb
#(
  parameter
  DATA_WIDTH = 32, 
  OP_CODE_WIDTH = 7,
  BUFFER_DEPTH = 4
)
(
  input clk, reset, 
  input [DATA_WIDTH-1:0] if_pc,
  input write_en, 
  input [DATA_WIDTH-1:0] ex_target,
  input [DATA_WIDTH-1:0] ex_pc, 
  input [OP_CODE_WIDTH-1:0] ex_op_code, 
  output hit_miss, //high on a hit: if_pc matched a valid entry 
  output [DATA_WIDTH-1:0] target 
); 


  localparam TAG_WIDTH = DATA_WIDTH - 2; 
  localparam BUFFER_WIDTH = TAG_WIDTH + DATA_WIDTH + 1; // {pc_tag[31:2]|target|valid} 
  
  reg [BUFFER_WIDTH-1:0] buff [0:BUFFER_DEPTH-1]; 

  //read logic port 1 
  reg [$clog2(BUFFER_DEPTH)-1:0] buff_index_1; 
  wire [BUFFER_DEPTH-1:0] compares_1;
  assign hit_miss = |compares_1;   
  assign target = buff[buff_index_1][DATA_WIDTH -: DATA_WIDTH]; 

  //read logic port 2
  reg [$clog2(BUFFER_DEPTH)-1:0] buff_index_2; 
  wire [BUFFER_DEPTH-1:0] compares_2;
  wire port_2_hit_miss = |compares_2; //high on a hit: ex_pc is already buffered 

  reg [$clog2(BUFFER_DEPTH)-1:0] wrap_idx; 

  genvar i; 
  generate
    for (i = 0; i < BUFFER_DEPTH; i = i+1)
    begin: COMPARE 
      assign compares_1[i] = (buff[i][BUFFER_WIDTH-1 -: TAG_WIDTH] == if_pc[DATA_WIDTH-1:2]) && buff[i][0];
      assign compares_2[i] = (buff[i][BUFFER_WIDTH-1 -: TAG_WIDTH] == ex_pc[DATA_WIDTH-1:2]); 
    end
  endgenerate 
  
  //priority encoder port 1 
  integer j1; 
  always@(*)
  begin 
    buff_index_1 = 0; 
    for(j1 = 0; j1 < BUFFER_DEPTH; j1 = j1+1)
    begin 
      if(compares_1[j1])
      begin 
        buff_index_1 = j1[$clog2(BUFFER_DEPTH)-1:0]; 
      end 
    end 
  end

  //priority encoder port 2 
  integer j2; 
  always@(*)
  begin 
    buff_index_2 = 0; 
    for(j2 = 0; j2 < BUFFER_DEPTH; j2 = j2+1)
    begin 
      if(compares_2[j2])
      begin 
        buff_index_2 = j2[$clog2(BUFFER_DEPTH)-1:0]; 
      end 
    end 
  end

  integer k; 

  //write logic 
  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      wrap_idx <= 0; 
      for(k = 0; k < BUFFER_DEPTH; k = k+1)
      begin 
        buff[k] <= 0; 
      end 
    end 
    else 
    begin 
      if(write_en && ex_op_code[6:2] == `B_TYPE)
      begin 
        //check if pc already exists in buffer, if not assign it to the wrap_idx location 
        if(~port_2_hit_miss)
        begin 
          buff[wrap_idx] <= {ex_pc[DATA_WIDTH-1:2],ex_target,1'b1}; 
          wrap_idx <= wrap_idx + 1; 
        end 
        else 
          buff[buff_index_2] <= {ex_pc[DATA_WIDTH-1:2],ex_target,1'b1}; 
      end
    end 
  end 
endmodule 
