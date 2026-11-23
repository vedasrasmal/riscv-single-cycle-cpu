//=============================================================================
// control_unit.v — RV32I Control Unit (main decoder + ALU decoder)
// RV32I single-cycle CPU (Vedas Rasmal, GHRCEM Pune)
//
// The control unit looks at the opcode, funct3 and funct7 fields of the
// instruction and produces every control signal the datapath needs. It is
// two decoders in one module:
//
//   - Main decoder: opcode -> reg_write, mem_write, mem_read, alu_src,
//     alu_a_pc, result_src, branch, jump, alu_op, imm_src.
//   - ALU decoder: alu_op + funct3 + funct7[5] + opcode[5] -> alu_ctrl
//     (the 4-bit code of rtl/alu.v, Harris & Harris encoding).
//
// Control-signal table (x = don't care):
//
//   instr  | reg_ | mem_ | mem_ | alu_ | alu_ | result_ | br-  | jump | alu_ | imm_
//          | write| write| read | src  | a_pc | src     | anch |      | op   | src
//   --------|------|------|------|------|------|---------|------|------|------|------
//   R-type |  1   |  0   |  0   |  0   |  0   |  00     |  0   |  0   | 10   | 000
//   I ALU  |  1   |  0   |  0   |  1   |  0   |  00     |  0   |  0   | 10   | 000
//   Load   |  1   |  0   |  1   |  1   |  0   |  01     |  0   |  0   | 00   | 000
//   Store  |  0   |  1   |  0   |  1   |  0   |  xx     |  0   |  0   | 00   | 001
//   Branch |  0   |  0   |  0   |  0   |  0   |  xx     |  1   |  0   | 01   | 010
//   JAL    |  1   |  0   |  0   |  0   |  0   |  10     |  0   |  1   | 00   | 100
//   JALR   |  1   |  0   |  0   |  1   |  0   |  10     |  0   |  1   | 00   | 000
//   LUI    |  1   |  0   |  0   |  1   |  0   |  11     |  0   |  0   | 00   | 011
//   AUIPC  |  1   |  0   |  0   |  1   |  1   |  00     |  0   |  0   | 00   | 011
//
//   result_src: 00 = ALU result, 01 = data-memory read data,
//               10 = PC+4 (JAL/JALR return address), 11 = immediate (LUI).
//   alu_a_pc: 0 = ALU input A is rs1, 1 = ALU input A is the PC (AUIPC).
//   alu_op: 00 = ADD (address / JALR target / AUIPC), 01 = branch compare,
//           10 = decode funct3/funct7 (R/I-type ALU).
//
//   ALU decoder (alu_op = 10): funct3 selects the operation; funct7[5]
//   picks SUB over ADD and SRA over SRL. For ADD/SUB the funct7 bit
//   only counts for R-type: for I-type ADD (ADDI) the same bit is part
//   of the immediate, so opcode[5] (1 for R-type 0110011, 0 for I-type
//   0010011) gates it. For shifts the rule is different: SLLI/SRLI/SRAI
//   carry their funct7 in the immediate itself, so funct7[5] always
//   distinguishes SRA/SRAI from SRL/SRLI, for R-type and I-type alike.
//   (This is the Harris & Harris rule.)
//
//   Branch compare (alu_op = 01): BEQ/BNE use SUB (the ALU zero flag),
//   BLT/BGE use SLT, BLTU/BGEU use SLTU — the CPU reads the comparison
//   from the ALU result bit 0 (SLT/SLTU produce 0 or 1).
//
//   Unknown opcodes produce all-zero control signals (no write, no
//   memory access, no branch, no jump) — an illegal instruction is a
//   harmless no-op instead of a wild write. FENCE/ECALL/EBREAK are
//   therefore treated as NOPs.
//=============================================================================

`timescale 1ns / 1ps

module control_unit (
    input  wire [6:0] opcode,    // instr[6:0]
    input  wire [2:0] funct3,    // instr[14:12]
    input  wire [6:0] funct7,    // instr[31:25]
    output reg        reg_write, // write the register file this cycle
    output reg        mem_write, // write data memory this cycle
    output reg        mem_read,  // read data memory this cycle (loads)
    output reg        alu_src,   // ALU input B: 0 = rs2, 1 = immediate
    output reg        alu_a_pc,  // ALU input A: 0 = rs1, 1 = PC (AUIPC)
    output reg  [1:0] result_src,// write-back mux: 00 ALU, 01 mem,
                                 //                 10 PC+4, 11 imm (LUI)
    output reg        branch,    // this is a branch instruction
    output reg        jump,      // this is JAL or JALR
    output reg  [1:0] alu_op,    // to the ALU decoder (see table above)
    output reg  [2:0] imm_src,   // to the immediate generator
    output reg  [3:0] alu_ctrl   // to the ALU (Harris & Harris encoding)
);

    // Opcodes (RV32I base ISA).
    localparam OP_RTYPE = 7'b0110011; // ADD, SUB, SLL, SLT, SLTU, XOR,
                                      // SRL, SRA, OR, AND
    localparam OP_ITYPE = 7'b0010011; // ADDI, SLTI, ..., SLLI, SRLI, SRAI
    localparam OP_LOAD  = 7'b0000011; // LB, LH, LW, LBU, LHU
    localparam OP_STORE = 7'b0100011; // SB, SH, SW
    localparam OP_BRANCH= 7'b1100011; // BEQ, BNE, BLT, BGE, BLTU, BGEU
    localparam OP_JAL   = 7'b1101111;
    localparam OP_JALR  = 7'b1100111;
    localparam OP_LUI   = 7'b0110111;
    localparam OP_AUIPC = 7'b0010111;

    // ALU control codes — must match rtl/alu.v.
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    // ---- main decoder ----------------------------------------------------
    always @(*) begin
        // Safe defaults: do nothing (illegal opcode = NOP).
        reg_write  = 1'b0;
        mem_write  = 1'b0;
        mem_read   = 1'b0;
        alu_src    = 1'b0;
        alu_a_pc   = 1'b0;
        result_src = 2'b00;
        branch     = 1'b0;
        jump       = 1'b0;
        alu_op     = 2'b00;
        imm_src    = 3'b000;

        case (opcode)
            OP_RTYPE: begin
                reg_write = 1'b1;
                alu_op    = 2'b10;
            end
            OP_ITYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b10;
                imm_src   = 3'b000; // I-type immediate
            end
            OP_LOAD: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                alu_src    = 1'b1;
                result_src = 2'b01; // write back the loaded data
                alu_op     = 2'b00; // ADD: address = rs1 + imm
                imm_src    = 3'b000;
            end
            OP_STORE: begin
                mem_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b00; // ADD: address = rs1 + imm
                imm_src   = 3'b001; // S-type immediate
            end
            OP_BRANCH: begin
                branch  = 1'b1;
                alu_op  = 2'b01;    // branch compare
                imm_src = 3'b010;   // B-type immediate
            end
            OP_JAL: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                result_src = 2'b10; // write back PC+4
                imm_src    = 3'b100; // J-type immediate
            end
            OP_JALR: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                alu_src    = 1'b1;
                result_src = 2'b10; // write back PC+4
                alu_op     = 2'b00; // ADD: target = rs1 + imm
                imm_src    = 3'b000;
            end
            OP_LUI: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                result_src = 2'b11; // write back the immediate itself
                imm_src    = 3'b011; // U-type immediate
            end
            OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_a_pc  = 1'b1;    // ALU input A is the PC
                alu_op    = 2'b00;   // ADD: PC + imm
                imm_src   = 3'b011;  // U-type immediate
            end
            default: begin
                // All defaults above: a harmless no-op.
            end
        endcase
    end

    // ---- ALU decoder -----------------------------------------------------
    always @(*) begin
        case (alu_op)
            2'b00:   alu_ctrl = ALU_ADD; // address / JALR target / AUIPC
            2'b01: begin                 // branch compare
                case (funct3)
                    3'b100,             // BLT
                    3'b101: alu_ctrl = ALU_SLT;  // BGE
                    3'b110,             // BLTU
                    3'b111: alu_ctrl = ALU_SLTU; // BGEU
                    default: alu_ctrl = ALU_SUB; // BEQ, BNE
                endcase
            end
            2'b10: begin                 // R/I-type ALU operation
                case (funct3)
                    // ADD/SUB: funct7[5] only counts for R-type,
                    // where opcode[5] = 1. For I-type it is an
                    // immediate bit, so ADDI always means ADD.
                    3'b000: alu_ctrl = (opcode[5] && funct7[5])
                                        ? ALU_SUB : ALU_ADD;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
            end
            default: alu_ctrl = ALU_ADD;
        endcase
    end

endmodule
