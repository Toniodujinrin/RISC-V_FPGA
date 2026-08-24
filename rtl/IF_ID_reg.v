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
  input [1:0] branch_prediction, // return from branch predictor [1] contains actual prediction  
  input [HIST_BITS-1:0] prediction_index, //returned on predicted_index
  input [$clog2(BHR_SNAPS)-1:0] bhr_snap_index, //returned on predicted_snap_index
  input prediction_valid, //returned on predicted_valid
  input flush, 
  input stall,
  output reg [DATA_WIDTH-1:0] id_pc, 
  output reg [DATA_WIDTH-1:0] id_pc_4, 
  output reg [DATA_WIDTH-1:0] id_instr, 
  output reg [1:0] id_branch_prediction, 
  output reg [HIST_BITS-1:0] id_prediction_index, 
  output reg [$clog2(BHR_SNAPS)-1:0] id_bhr_snap_index, 
  output reg id_prediction_valid
); 

  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      id_pc <= 0;  
      id_pc_4 <= 0;  
      id_instr <= 0;  
      id_branch_prediction <= 0;
      id_prediction_index <= 0; 
      id_bhr_snap_index <= 0; 
      id_prediction_valid <= 0; 
    end
    else if(flush)
    begin 
      id_instr <= 0; 
      id_branch_prediction <= 0; 
      id_prediction_index <= 0; 
      id_bhr_snap_index <= 0; 
      id_prediction_valid <= 0; 
    end
    else if(!stall)
    begin 
      id_pc <= pc;  
      id_pc_4 <= pc_4;  
      id_instr <= instr;  
      id_branch_prediction <= branch_prediction;
      id_prediction_index <= prediction_index; 
      id_bhr_snap_index <= bhr_snap_index; 
      id_prediction_valid <= prediction_valid; 
    end
  end


endmodule 
