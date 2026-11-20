//=============================================================================
// alu.v — RV32I Arithmetic Logic Unit
// RV32I single-cycle CPU (Vedas Rasmal, GHRCEM Pune)
//
// A pure combinational 32-bit ALU. It takes two 32-bit operands and a 4-bit
// control code, and produces a 32-bit result plus a zero flag (used later by
// the branch logic: BEQ/BNE compare against zero).
//
// ALU control encoding (Harris & Harris, Digital Design and Computer
// Architecture, RISC-V edition):
//
//   alu_ctrl | operation | notes
//   ---------|-----------|----------------------------------------------
//   4'b0000  | ADD       | a + b (wraps mod 2^32, no trap on overflow)
//   4'b0001  | SUB       | a - b (wraps mod 2^32)
//   4'b0010  | AND       | bitwise AND
//   4'b0011  | OR        | bitwise OR
//   4'b0100  | XOR       | bitwise XOR
//   4'b0101  | SLL       | logical left shift by b[4:0]
//   4'b0110  | SRL       | logical right shift by b[4:0] (zero fill)
//   4'b0111  | SRA       | arithmetic right shift by b[4:0] (sign fill)
//   4'b1000  | SLT       | 1 if a < b (SIGNED), else 0
//   4'b1001  | SLTU      | 1 if a < b (UNSIGNED), else 0
//   default  | 0         | undefined control -> 0 (safe, never X)
//
// Shift amount is always b[4:0] (RV32I shifts are modulo 32), so a shift
// by 32 behaves as a shift by 0, a shift by 33 as a shift by 1, and so on.
//=============================================================================

`timescale 1ns / 1ps

module alu (
    input  wire [31:0] a,         // first operand (usually rs1 / PC)
    input  wire [31:0] b,         // second operand (rs2 or immediate)
    input  wire [3:0]  alu_ctrl,  // operation select (see table above)
    output reg  [31:0] result,    // ALU result
    output wire        zero       // 1 when result == 0
);

    // Shift amount: RV32I uses only the low 5 bits.
    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a + b;                                   // ADD
            4'b0001: result = a - b;                                   // SUB
            4'b0010: result = a & b;                                   // AND
            4'b0011: result = a | b;                                   // OR
            4'b0100: result = a ^ b;                                   // XOR
            4'b0101: result = a << shamt;                              // SLL
            4'b0110: result = a >> shamt;                              // SRL
            4'b0111: result = $signed(a) >>> shamt;                    // SRA
            4'b1000: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            4'b1001: result = (a < b) ? 32'd1 : 32'd0;                 // SLTU
            default: result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);

endmodule
