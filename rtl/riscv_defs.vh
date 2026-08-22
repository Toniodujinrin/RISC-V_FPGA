`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

//=============================================================================
// Shared constants for the RV32I core.
//
// These are `define macros rather than localparams so a single copy can be
// shared across modules. Macros live in one global namespace for the whole
// compilation, so every name here is expected to be unique project-wide.
//=============================================================================


//-----------------------------------------------------------------------------
// ALU operation codes -- 4 bits, the alu_op port between alu_controller and alu
//-----------------------------------------------------------------------------
`define NON   4'd0
`define ADD   4'd1
`define SUB   4'd2
`define AND   4'd3
`define OR    4'd4
`define XOR   4'd5
`define SLL   4'd6
`define SRL   4'd7
`define SRA   4'd8
`define LT    4'd9
`define LTU   4'd10
`define PC    4'd11
`define GTE   4'd12
`define GTEU  4'd13
`define NEQ   4'd14
`define EQ    4'd15


//-----------------------------------------------------------------------------
// Instruction classes -- op_code[6:2].
// The low two bits of a 32-bit RV32I instruction are always 2'b11 and carry no
// information, so they are dropped and the class is matched on 5 bits.
//-----------------------------------------------------------------------------
`define R_TYPE     5'b01100  // OP      -- register-register arithmetic
`define I_TYPE_1   5'b11100  // SYSTEM  -- CSR access, ECALL, EBREAK
`define I_TYPE_2   5'b11001  // JALR
`define I_TYPE_3   5'b00000  // LOAD    -- address is rs1 + imm, so it wants ADD
`define I_TYPE_4   5'b00100  // OP-IMM  -- register-immediate arithmetic
`define S_TYPE     5'b01000  // STORE
`define B_TYPE     5'b11000  // BRANCH
`define J_TYPE     5'b11011  // JAL
`define U_TYPE_1   5'b01101  // LUI
`define U_TYPE_2   5'b00101  // AUIPC 
`endif
