`include "riscv_defs.vh"

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






always@(*)
begin 
  alu_op = `NON; 
  casez({op_code[OP_CODE_WIDTH-1:2],funct_7[5],funct_3})
    {`S_TYPE, 1'b?, 3'b???},{`I_TYPE_3, 1'b?, 3'b???}, {`U_TYPE_1, 1'b?, 3'b???}, {`U_TYPE_2, 1'b?, 3'b???}, {`R_TYPE, 1'b0, 3'b000}, {`I_TYPE_4, 1'b?, 3'b000}: 
      alu_op = `ADD; 
    {`R_TYPE, 1'b1,3'b000}: //Subtract
      alu_op = `SUB; 
    {`R_TYPE, 1'b0,3'b001}, {`I_TYPE_4,1'b0,3'b001}: // Shift left logical (+Immediate)
      alu_op = `SLL;  
    {`R_TYPE, 1'b0,3'b010}, {`I_TYPE_4,1'b?,3'b010},{`B_TYPE,1'b?,3'b100}: //Set less than signed (+Immediate), BLT
      alu_op = `LT; 
    {`R_TYPE, 1'b0,3'b011}, {`I_TYPE_4,1'b?,3'b011}, {`B_TYPE,1'b?,3'b110}: //Set less than unsigned (+Immediate), BLTU
      alu_op = `LTU; 
    {`R_TYPE, 1'b0,3'b100}, {`I_TYPE_4,1'b?,3'b100}: //XOR, XORI 
      alu_op = `XOR; 
    {`R_TYPE, 1'b1,3'b101}, {`I_TYPE_4,1'b1,3'b101}: //Shift Right Arithmetic (+Immediate)
      alu_op = `SRA; 
    {`R_TYPE, 1'b0,3'b101}, {`I_TYPE_4,1'b0,3'b101}: //Shift Right Logical (+Immediat)
      alu_op = `SRL; 
    {`R_TYPE, 1'b0,3'b110}, {`I_TYPE_4,1'b?,3'b110}: //OR, ORI 
      alu_op = `OR; 
    {`R_TYPE, 1'b0,3'b111}, {`I_TYPE_4,1'b?,3'b111}: //AND, ANDI 
      alu_op = `AND; 
    {`B_TYPE, 1'b?,3'b000}: //BEQ
      alu_op = `EQ;    
    {`B_TYPE, 1'b?, 3'b001}: // BNE
      alu_op = `NEQ;  
    {`J_TYPE, 1'b?, 3'b???}, {`I_TYPE_2, 1'b?, 3'b???}:  // JAL and JALR 
      alu_op = `PC; 
    {`B_TYPE, 1'b?, 3'b101}: // BGE
      alu_op = `GTE;
    {`B_TYPE, 1'b?, 3'b111}: // BGEU
      alu_op = `GTEU;  
    default:
      alu_op = `NON;
  endcase
end 

endmodule


// RESOLVED 22 Aug: NOP_TYPE is gone. It held 5'b00000, which is the LOAD
// opcode and was a duplicate of I_TYPE_3; both collapsed onto `I_TYPE_3 when
// the constants moved to riscv_defs.vh. Mapping it to `ADD stays correct --
// loads need ADD for address calculation.
