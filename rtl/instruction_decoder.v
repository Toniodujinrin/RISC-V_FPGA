module instruction_decoder
#(
  parameter DATA_WIDTH = 32
)
(
  input [DATA_WIDTH-1:0] inst_in, 
  output reg [6:0] op_code,
  output reg [6:0] funct_7, 
  output reg [2:0] funct_3, 
  output reg [31:0] imm, 
  output reg [4:0] rs1, 
  output reg [4:0] rs2, 
  output reg [4:0] rd
); 

  localparam R_TYPE = 5'b01100; 
  localparam I_TYPE_1 = 5'b11100; 
  localparam I_TYPE_2 = 5'b11001; 
  localparam I_TYPE_3 = 5'b00000; 
  localparam I_TYPE_4 = 5'b00100; 
  localparam S_TYPE = 5'b01000; 
  localparam B_TYPE = 5'b11000; 
  localparam J_TYPE = 5'b11011; 
  localparam U_TYPE = 5'b01101; 

  always@(*)
  begin
    op_code = 0; 
    funct_7 = 0; 
    funct_3 = 0; 
    imm = 0; 
    rs1 = 0;  
    rs2 = 0; 
    rd = 0; 

    case(inst_in[6:2])
      R_TYPE: 
      begin 
        op_code = inst_in[6:0]; 
        rd = inst_in[11:7]; 
        funct_3 = inst_in[14:12]; 
        rs1 = inst_in[19:15]; 
        rs2 = inst_in[24:20]; 
        funct_7 = inst_in[31:25]; 
      end 

      I_TYPE_1, I_TYPE_2, I_TYPE_3, I_TYPE_4: 
      begin 
        op_code = inst_in[6:0];
        rd = inst_in[11:7]; 
        funct_3 = inst_in[14:12]; 
        rs1 = inst_in[19:15]; 
        imm = {{20{inst_in[31]}}, inst_in[31:20]}; 
      end 

      S_TYPE:
      begin 
        op_code = inst_in[6:0]; 
        funct_3 = inst_in[14:12];
        rs1 = inst_in[19:15];
        rs2 = inst_in[24:20];
        imm = {{20{inst_in[31]}}, inst_in[31:25], inst_in[11:7]};
      end 

      B_TYPE: 
      begin 
         op_code = inst_in[6:0]; 
         funct_3 = inst_in[14:12];
         rs1 = inst_in[19:15];
         rs2 = inst_in[24:20];
         imm = {{20{inst_in[31]}}, inst_in[7], inst_in[30:25], inst_in[11:8], 1'b0};
      end 

      J_TYPE: 
      begin 
         op_code = inst_in[6:0]; 
         rd = inst_in[11:7]; 
         imm = {{12{inst_in[31]}}, inst_in[19:12], inst_in[20], inst_in[30:21], 1'b0}; 
      end 

      U_TYPE: 
      begin 
         op_code = inst_in[6:0]; 
         rd = inst_in[11:7]; 
         imm = {inst_in[31:12], 12'b0}; 
      end 
    endcase
  end 
endmodule
