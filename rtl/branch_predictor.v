module branch_predictor
#(
  parameter HIST_BITS = 7, 
  parameter BHR_SNAPS = 4,
  parameter DATA_WIDTH = 32
)
(
  input clk, reset,
  input stall, 
  //predicted port (update)
  input history_write,
  input [HIST_BITS-1:0] predicted_index, //the index this branch was predicted with, carried back through the pipeline 
  input [1:0] predicted_in, 
  input actually_taken, 
  input predicted_valid,
  input[$clog2(BHR_SNAPS)-1:0] predicted_snap_index,
 
   
  //prediction port
  input [DATA_WIDTH-1:0] pc_bits,
  input history_read,
  output [1:0] prediction_out,
  output [HIST_BITS-1:0] prediction_index,
  output prediction_valid, 
  output reg [$clog2(BHR_SNAPS)-1:0] bhr_snap_index
); 

  localparam LOCATIONS = 1 << HIST_BITS; 

  //logic, not block: an M10K has no combinational read port, and 128x2 bits does
  //not justify one anyway
  (*ramstyle = "logic"*) reg [1:0] pht [0:LOCATIONS-1]; 
  (*ramstyle = "logic"*) reg [HIST_BITS-1:0] bhr_snaps [0:BHR_SNAPS-1]; 


  reg [HIST_BITS-1:0] bhr; 
  wire [HIST_BITS-1:0] current_index = bhr ^ pc_bits[2 +: HIST_BITS]; 
  
  reg actually_taken_r; 
  reg [HIST_BITS-1:0] predicted_index_r;
  reg [1:0] predicted_in_r;
  reg history_write_r;
  reg predicted_valid_r;


  assign prediction_out   = history_read ? pht[current_index] : 2'b00;
  assign prediction_index = current_index;
  assign prediction_valid = history_read;

  

  
  //history shifter and snapshot  
  always@(posedge clk or posedge reset)
  begin
    if(reset)
    begin 
      bhr <= 0; 
      bhr_snap_index <= 0; 
    end
    else if(!stall)
    begin 
      if(prediction_valid)
      begin 
        bhr <= {bhr[HIST_BITS-2:0],prediction_out[1]};
        bhr_snaps[bhr_snap_index] <= {bhr[HIST_BITS-2:0],prediction_out[1]};
        bhr_snap_index <= bhr_snap_index + 1; //wraps and overwrites 
      end 

      else if(history_write && predicted_valid)
      begin 
        bhr <= {bhr_snaps[predicted_snap_index][HIST_BITS-1:1], actually_taken}; 
      end
    end 
  end
  

  
  //pht search 
  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      predicted_index_r <= 0; 
      predicted_in_r <= 0; 
      history_write_r <= 0;
      predicted_valid_r <= 0; 
      actually_taken_r <= 0; 
    end
    else 
    begin 
      predicted_index_r <= predicted_index; 
      predicted_in_r <= predicted_in; 
      history_write_r <= history_write; 
      predicted_valid_r <= predicted_valid; 
      actually_taken_r <= actually_taken; 
      

      if(history_write_r && predicted_valid_r)
      begin 
        if(!actually_taken_r) //miss 
        begin 
          pht[predicted_index_r] <= (predicted_in_r == 2'd0)? 2'd0:
            predicted_in_r - 2'd1; 
        end 
        else 
           pht[predicted_index_r] <= (predicted_in_r == 2'd3) ? 2'd3:
            predicted_in_r + 2'd1; 
      end
    end 
  end




  //weakly not-taken on startup.    
  integer i; 
  initial 
  begin 
    for(i = 0; i < LOCATIONS; i = i+1)
    begin 
      pht[i] = 2'b01; 
    end
  end 

endmodule 
