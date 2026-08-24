`include "riscv_defs.vh"

module instruction_decoder
#(
  parameter DATA_WIDTH = 32, 
  parameter REG_ADDR_WIDTH = 5
)
(
  input [DATA_WIDTH-1:0] inst_in, 
  output reg [6:0] op_code,
  output reg [6:0] funct_7, 
  output reg [2:0] funct_3, 
  output reg [DATA_WIDTH-1:0] r_imm, 
  output reg [DATA_WIDTH-1:0] imm, 
  output reg [REG_ADDR_WIDTH-1:0] rs1, 
  output reg [REG_ADDR_WIDTH-1:0] rs2, 
  output reg [REG_ADDR_WIDTH-1:0] rd
); 


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
      `R_TYPE: 
      begin 
        op_code = inst_in[6:0]; 
        rd = inst_in[11:7]; 
        funct_3 = inst_in[14:12]; 
        rs1 = inst_in[19:15]; 
        rs2 = inst_in[24:20]; 
        funct_7 = inst_in[31:25]; 
      end 

      `I_TYPE_1, `I_TYPE_2, `I_TYPE_3, `I_TYPE_4: 
      begin 
        op_code = inst_in[6:0];
        rd = inst_in[11:7]; 
        funct_3 = inst_in[14:12]; 
        rs1 = inst_in[19:15]; 
        
        if(inst_in[6:2] == `I_TYPE_4 && (funct_3 == 3'b001 || funct_3 == 3'b101))
        begin 
          funct_7 = inst_in[31:25]; 
          imm = {27'b0, inst_in[24:20]}; 
        end 
        else
        begin 
          imm = {{20{inst_in[31]}}, inst_in[31:20]};
        end 
      end 

      `S_TYPE:
      begin 
        op_code = inst_in[6:0]; 
        funct_3 = inst_in[14:12];
        rs1 = inst_in[19:15];
        rs2 = inst_in[24:20];
        imm = {{20{inst_in[31]}}, inst_in[31:25], inst_in[11:7]};
      end 

      `B_TYPE: 
      begin 
         op_code = inst_in[6:0]; 
         funct_3 = inst_in[14:12];
         rs1 = inst_in[19:15];
         rs2 = inst_in[24:20];
         imm = {{20{inst_in[31]}}, inst_in[7], inst_in[30:25], inst_in[11:8], 1'b0};
      end 

      `J_TYPE: 
      begin 
         op_code = inst_in[6:0]; 
         rd = inst_in[11:7]; 
         imm = {{12{inst_in[31]}}, inst_in[19:12], inst_in[20], inst_in[30:21], 1'b0}; 
      end 

      `U_TYPE_1: 
      begin 
         op_code = inst_in[6:0]; 
         rd = inst_in[11:7]; 
         imm = {inst_in[31:12], 12'b0}; 
      end 

      `U_TYPE_2: 
      begin 
         op_code = inst_in[6:0]; 
         rd = inst_in[11:7]; 
         imm = {inst_in[31:12], 12'b0}; 
      end
    endcase
  end 
endmodule
