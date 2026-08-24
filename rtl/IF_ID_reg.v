module IF_ID_reg
#(
  parameter
  DATA_WIDTH = 32, 
  HIST_BITS = 7, 
  BHR_SNAPS = 4
)
(
  input clk, reset, 
  input [DATA_WIDTH-1:0] instr, 
  input [DATA_WIDTH-1:0] pc, 
  input [DATA_WIDTH-1:0] pc_4, 
  //prediction payload, latched at fetch alongside the instruction it belongs to.
  //branch_predictor's update port needs all of this back at resolve time, so it
  //has to ride the pipeline with the branch rather than be re-read later: the
  //bhr has already shifted by then and current_index would train the wrong entry.
  input branch_prediction, //prediction_out[1], the taken/not-taken decision
  input [1:0] prediction, //the counter value read, returned on predicted_in
  input [HIST_BITS-1:0] prediction_index, //returned on predicted_index
  input [$clog2(BHR_SNAPS)-1:0] bhr_snap_index, //returned on predicted_snap_index
  input prediction_valid, //returned on predicted_valid
  input flush, 
  input stall,
  output reg [DATA_WIDTH-1:0] if_pc, 
  output reg [DATA_WIDTH-1:0] if_pc_4, 
  output reg [DATA_WIDTH-1:0] if_instr, 
  output reg if_branch_prediction, 
  output reg [1:0] if_prediction, 
  output reg [HIST_BITS-1:0] if_prediction_index, 
  output reg [$clog2(BHR_SNAPS)-1:0] if_bhr_snap_index, 
  output reg if_prediction_valid
); 

  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      if_pc <= 0;  
      if_pc_4 <= 0;  
      if_instr <= 0;  
      if_branch_prediction <= 0;
      if_prediction <= 0; 
      if_prediction_index <= 0; 
      if_bhr_snap_index <= 0; 
      if_prediction_valid <= 0; 
    end
    //bubble. if_instr = 0 decodes to no control signals, and the whole prediction
    //payload is dropped with it: if_prediction_valid is what gates the update, so
    //a killed branch can never train the pht. pc/pc_4 are left alone, a bubble has
    //no meaningful pc.
    else if(flush)
    begin 
      if_instr <= 0; 
      if_branch_prediction <= 0; 
      if_prediction <= 0; 
      if_prediction_index <= 0; 
      if_bhr_snap_index <= 0; 
      if_prediction_valid <= 0; 
    end
    else if(!stall)
    begin 
      if_pc <= pc;  
      if_pc_4 <= pc_4;  
      if_instr <= instr;  
      if_branch_prediction <= branch_prediction;
      if_prediction <= prediction; 
      if_prediction_index <= prediction_index; 
      if_bhr_snap_index <= bhr_snap_index; 
      if_prediction_valid <= prediction_valid; 
    end
  end


endmodule 
