//=============================================================================
// riscv_cpu.v — RV32I Single-Cycle CPU (top level)
// RV32I single-cycle CPU (Vedas Rasmal, GHRCEM Pune)
//
// One instruction per clock cycle: fetch, decode, execute, memory access
// and write-back all happen in the same cycle. The PC is the only
// sequential state in the CPU itself (the register file and the data
// memory write on the clock edge, as their own modules define).
//
// Datapath (Harris & Harris single-cycle structure):
//
//   PC -> instr_mem -> control_unit, regfile, imm_gen
//   regfile rs1/rs2 -> ALU (A = rs1 or PC for AUIPC, B = rs2 or imm)
//   ALU -> data_mem address, branch compare
//   data_mem -> write-back mux (ALU result / loaded data / PC+4 / imm)
//   write-back mux -> regfile rd
//
//   Next PC:
//     JALR  : (rs1 + imm) with bit 0 cleared
//     JAL or taken branch : PC + imm
//     otherwise           : PC + 4
//
// Branch decision (from funct3, the ALU zero flag, and the ALU result):
//   BEQ  taken when zero = 1          BNE  taken when zero = 0
//   BLT  taken when SLT result = 1    BGE  taken when SLT result = 0
//   BLTU taken when SLTU result = 1   BGEU taken when SLTU result = 0
// The control unit already selects SUB for BEQ/BNE, SLT for BLT/BGE and
// SLTU for BLTU/BGEU, so the CPU only reads zero and result[0].
//
// Reset: synchronous, active high — the PC returns to 0 (the reset
// vector). The register file and data memory start cleared to zero by
// their own initial blocks; instruction memory is loaded from HEX_FILE.
//
// Program loading: HEX_FILE is the path (relative to the directory the
// simulation is run from) of a text file with one 32-bit hex word per
// line, loaded by $readmemh inside instr_mem. Testbenches override it
// per program, e.g. riscv_cpu #(.HEX_FILE("tb/prog_arith.hex")).
//
// Observability: the testbenches read the register file and data memory
// through hierarchical references (dut.u_regfile.regs[i],
// dut.u_dmem.mem[i]) — the standard way to inspect CPU state in
// simulation without adding debug ports to the synthesizable design.
//=============================================================================

`timescale 1ns / 1ps

module riscv_cpu #(
    parameter HEX_FILE = "tb/prog_arith.hex" // program to run
) (
    input  wire clk, // clock: one instruction per rising edge
    input  wire rst  // synchronous reset, active high (PC -> 0)
);

    // ---- program counter ---------------------------------------------------
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;

    // ---- instruction fetch -------------------------------------------------
    wire [31:0] instr;
    instr_mem #(.HEX_FILE(HEX_FILE)) u_imem (
        .addr(pc),
        .instr(instr)
    );

    // Instruction fields.
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] funct7 = instr[31:25];

    // ---- control -----------------------------------------------------------
    wire        reg_write, mem_write, mem_read;
    wire        alu_src, alu_a_pc, branch, jump;
    wire [1:0]  result_src, alu_op;
    wire [2:0]  imm_src;
    wire [3:0]  alu_ctrl;

    control_unit u_control (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .reg_write(reg_write),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .alu_src(alu_src),
        .alu_a_pc(alu_a_pc),
        .result_src(result_src),
        .branch(branch),
        .jump(jump),
        .alu_op(alu_op),
        .imm_src(imm_src),
        .alu_ctrl(alu_ctrl)
    );

    // ---- register file -----------------------------------------------------
    wire [31:0] rd1, rd2;      // register-file read data
    wire [31:0] write_data;    // write-back value (mux below)

    regfile u_regfile (
        .clk(clk),
        .reg_write(reg_write),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .write_data(write_data),
        .read_data1(rd1),
        .read_data2(rd2)
    );

    // ---- immediate ---------------------------------------------------------
    wire [31:0] imm;
    imm_gen u_immgen (
        .instr(instr),
        .imm_src(imm_src),
        .imm(imm)
    );

    // ---- ALU ---------------------------------------------------------------
    // A input: rs1, or the PC for AUIPC. B input: rs2, or the immediate.
    wire [31:0] alu_a = alu_a_pc ? pc : rd1;
    wire [31:0] alu_b = alu_src  ? imm : rd2;
    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .a(alu_a),
        .b(alu_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .zero(alu_zero)
    );

    // ---- data memory -------------------------------------------------------
    wire [31:0] read_data;
    data_mem u_dmem (
        .clk(clk),
        .addr(alu_result),
        .write_data(rd2),
        .funct3(funct3),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .read_data(read_data)
    );

    // ---- write-back mux ----------------------------------------------------
    // 00 = ALU result, 01 = loaded data, 10 = PC+4, 11 = immediate (LUI).
    assign write_data = (result_src == 2'b01) ? read_data  :
                        (result_src == 2'b10) ? pc_plus4  :
                        (result_src == 2'b11) ? imm        :
                                                alu_result;

    // ---- branch decision ---------------------------------------------------
    // BEQ/BNE use the zero flag; BLT/BGE use the SLT result bit;
    // BLTU/BGEU use the SLTU result bit (see header note).
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000:  branch_taken = alu_zero;         // BEQ
            3'b001:  branch_taken = ~alu_zero;        // BNE
            3'b100:  branch_taken = alu_result[0];   // BLT  (SLT = 1)
            3'b101:  branch_taken = ~alu_result[0];  // BGE  (SLT = 0)
            3'b110:  branch_taken = alu_result[0];   // BLTU (SLTU = 1)
            3'b111:  branch_taken = ~alu_result[0];  // BGEU (SLTU = 0)
            default: branch_taken = 1'b0;
        endcase
    end

    // ---- next PC -----------------------------------------------------------
    wire is_jalr = (opcode == 7'b1100111);
    // JALR target: rs1 + imm, bit 0 forced to 0 (ISA rule).
    wire [31:0] jalr_target = (rd1 + imm) & 32'hFFFFFFFE;
    wire [31:0] pc_next = jump ? (is_jalr ? jalr_target : pc + imm) :
                          (branch && branch_taken) ? pc + imm :
                                                     pc_plus4;

    // ---- PC register (the CPU's only sequential state) ---------------------
    always @(posedge clk) begin
        if (rst)
            pc <= 32'd0;
        else
            pc <= pc_next;
    end

endmodule
