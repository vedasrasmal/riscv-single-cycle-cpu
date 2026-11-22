//=============================================================================
// imm_gen.v — RV32I Immediate Generator
// RV32I single-cycle CPU (Vedas Rasmal, GHRCEM Pune)
//
// The immediate is scattered across the instruction in different places for
// each format, so this module gathers the right bits and sign-extends them
// to 32 bits. imm_src selects the format (set by the control unit):
//
//   imm_src | format | instructions        | immediate layout
//   --------|--------|---------------------|----------------------------------
//   3'b000  | I-type | ADDI, LW, JALR, ... | {instr[31:20]} (sign-extended)
//   3'b001  | S-type | SW, SB, SH          | {instr[31:25], instr[11:7]}
//   3'b010  | B-type | BEQ, BNE, ...       | {instr[31], instr[7], instr[30:25],
//           |        |                     |  instr[11:8], 1'b0}
//   3'b011  | U-type | LUI, AUIPC          | {instr[31:12], 12'b0}
//   3'b100  | J-type | JAL                 | {instr[31], instr[19:12],
//           |        |                     |  instr[20], instr[30:21], 1'b0}
//   other   | —      | —                   | 0 (safe default)
//
// Branch and jump immediates are already shifted: their lowest bit is
// always 0 (instructions are 2-byte aligned), so the 1'b0 at the bottom is
// part of the value, not a shift the CPU has to do later.
//=============================================================================

`timescale 1ns / 1ps

module imm_gen (
    input  wire [31:0] instr,   // full 32-bit instruction
    input  wire [2:0]  imm_src, // format select (see table above)
    output reg  [31:0] imm      // sign-extended immediate
);

    always @(*) begin
        case (imm_src)
            // I-type: imm[11:0] = instr[31:20], sign-extended.
            3'b000: imm = {{20{instr[31]}}, instr[31:20]};
            // S-type: imm[11:0] = {instr[31:25], instr[11:7]}.
            3'b001: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            // B-type: imm[12|10:5|4:1|11], low bit 0.
            3'b010: imm = {{19{instr[31]}}, instr[31], instr[7],
                           instr[30:25], instr[11:8], 1'b0};
            // U-type: imm[31:12] = instr[31:12], low 12 bits 0.
            3'b011: imm = {instr[31:12], 12'b0};
            // J-type: imm[20|10:1|11|19:12], low bit 0.
            3'b100: imm = {{11{instr[31]}}, instr[31], instr[19:12],
                           instr[20], instr[30:21], 1'b0};
            default: imm = 32'd0;
        endcase
    end

endmodule
