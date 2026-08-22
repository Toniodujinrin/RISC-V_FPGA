module alu_controller
#(
  parameter DATA_WIDTH = 32,
  parameter OP_CODE_WIDTH = 7, 
  parameter FUNCT_7_WIDTH = 7, 
  parameter FUNCT_3_WIDTH = 3
)
(
  input [FUNCT_7_WIDTH-1:0] funct_7, 
  input [FUNCT_3_WIDTH-1:0] funct_3, 
  input [OP_CODE_WIDTH-1:0] op_code, 
  output reg [3:0] alu_op
); 

//ALU_OPS
localparam ADD = 4'd1; 
localparam SUB = 4'd2; 
localparam AND = 4'd3; 
localparam OR = 4'd4; 
localparam XOR = 4'd5; 
localparam SLL = 4'd6; 
localparam SRL = 4'd7; 
localparam SRA = 4'd8; 
localparam LT = 4'd9; 
localparam LTU = 4'd10; 
localparam PC = 4'd11; 
localparam GTE = 4'd12; 
localparam GTEU = 4'd13; 
localparam NEQ = 4'd14; 
localparam EQ = 4'd15; 
localparam NON = 4'd0; 


localparam R_TYPE = 5'b01100; 
localparam I_TYPE_1 = 5'b11100; 
localparam I_TYPE_2 = 5'b11001; 
localparam I_TYPE_3 = 5'b00000; 
localparam I_TYPE_4 = 5'b00100; 
localparam S_TYPE = 5'b01000; 
localparam B_TYPE = 5'b11000; 
localparam J_TYPE = 5'b11011; 
localparam U_TYPE = 5'b01101;
localparam NOP_TYPE = 5'b00000; 



always@(*)
begin 
  alu_op = NON; 
  casez({op_code[OP_CODE_WIDTH-1:2],funct_7[5],funct_3})
    {S_TYPE, 1'b?, 3'b???},{NOP_TYPE, 1'b?, 3'b???}, {U_TYPE, 1'b?, 3'b???}, {R_TYPE, 1'b0, 3'b000}, {I_TYPE_4, 1'b?, 3'b000}: 
      alu_op = ADD; 
    {R_TYPE, 1'b1,3'b000}: //Subtract
      alu_op = SUB; 
    {R_TYPE, 1'b0,3'b001}, {I_TYPE_4,1'b0,3'b001}: // Shift left logical (+Immediate)
      alu_op = SLL;  
    {R_TYPE, 1'b0,3'b010}, {I_TYPE_4,1'b?,3'b010},{B_TYPE,1'b?,3'b100}: //Set less than signed (+Immediate), BLT
      alu_op = LT; 
    {R_TYPE, 1'b0,3'b011}, {I_TYPE_4,1'b?,3'b011}, {B_TYPE,1'b?,3'b110}: //Set less than unsigned (+Immediate), BLTU
      alu_op = LTU; 
    {R_TYPE, 1'b0,3'b100}, {I_TYPE_4,1'b?,3'b100}: //XOR, XORI 
      alu_op = XOR; 
    {R_TYPE, 1'b1,3'b101}, {I_TYPE_4,1'b1,3'b101}: //Shift Right Arithmetic (+Immediate)
      alu_op = SRA; 
    {R_TYPE, 1'b0,3'b101}, {I_TYPE_4,1'b0,3'b101}: //Shift Right Logical (+Immediat)
      alu_op = SRL; 
    {R_TYPE, 1'b0,3'b110}, {I_TYPE_4,1'b?,3'b110}: //OR, ORI 
      alu_op = OR; 
    {R_TYPE, 1'b0,3'b111}, {I_TYPE_4,1'b?,3'b111}: //AND, ANDI 
      alu_op = AND; 
    {B_TYPE, 1'b?,3'b000}: //BEQ
      alu_op = EQ;    
    {B_TYPE, 1'b?, 3'b001}: // BNE
      alu_op = NEQ;  
    {J_TYPE, 1'b?, 3'b???}, {I_TYPE_2, 1'b?, 3'b???}:  // JAL and JALR 
      alu_op = PC; 
    {B_TYPE, 1'b?, 3'b101}: // BGE
      alu_op = GTE;
    {B_TYPE, 1'b?, 3'b111}: // BGEU
      alu_op = GTEU;  
    default:
      alu_op = NON;
  endcase
end 

endmodule


// TODO: AUIPC is not decoded. U_TYPE (5'b01101) is LUI only; AUIPC is opcode
// 0010111, i.e. op_code[6:2] == 5'b00101, which has no localparam here. It
// currently falls through to default -> NON, so the ALU returns 0 instead of
// the PC-relative sum. Add a localparam (AUIPC_TYPE = 5'b00101) and put it on
// the ADD arm alongside U_TYPE. Note instruction_decoder.v is missing the same
// opcode, so both need fixing before AUIPC works end to end.

// TODO: NOP_TYPE (5'b00000) is misnamed -- that value is the LOAD opcode
// (0000011), identical to the unused I_TYPE_3 localparam. Mapping it to ADD is
// correct, since loads need ADD for address calculation, but the name says
// otherwise and a real NOP is ADDI (I_TYPE_4). Rename NOP_TYPE to LOAD_TYPE
// and delete the duplicate I_TYPE_3.
