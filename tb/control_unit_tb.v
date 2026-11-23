//=============================================================================
// control_unit_tb.v — Self-checking testbench for the RV32I control unit
// RV32I single-cycle CPU.
//
// Every case sets opcode/funct3/funct7 and checks ALL thirteen control
// outputs against the table in rtl/control_unit.v. Any mismatch prints
// FAIL and is counted; the summary exits non-zero ($fatal) on failure.
//
// Covers: every R-type and I-type ALU operation (including the funct7[5]
// rule — SUB/SRA only for R-type, never for I-type), all five loads,
// all three stores, all six branches, JAL, JALR, LUI, AUIPC, and an
// illegal opcode (must be a harmless all-zero no-op).
//
// Run with Icarus Verilog:
//   iverilog -o sim/control_unit_tb.vvp rtl/control_unit.v tb/control_unit_tb.v
//   vvp sim/control_unit_tb.vvp
//=============================================================================

`timescale 1ns / 1ps

module control_unit_tb;

    reg  [6:0] opcode;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    wire       reg_write, mem_write, mem_read;
    wire       alu_src, alu_a_pc, branch, jump;
    wire [1:0] result_src, alu_op;
    wire [2:0] imm_src;
    wire [3:0] alu_ctrl;

    integer errors = 0;
    integer total  = 0;

    control_unit dut (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .mem_write(mem_write), .mem_read(mem_read),
        .alu_src(alu_src), .alu_a_pc(alu_a_pc), .result_src(result_src),
        .branch(branch), .jump(jump), .alu_op(alu_op), .imm_src(imm_src),
        .alu_ctrl(alu_ctrl)
    );

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

    // Opcodes.
    localparam OP_R      = 7'b0110011;
    localparam OP_I      = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;

    // Check one case: set the instruction fields, wait for the
    // combinational decoders to settle, compare every output.
    task check;
        input        exp_rw, exp_mw, exp_mr, exp_as, exp_apc;
        input [1:0]  exp_rs;
        input        exp_br, exp_j;
        input [1:0]  exp_ao;
        input [2:0]  exp_is;
        input [3:0]  exp_ac;
        input [8*20-1:0] tname;
        begin
            total = total + 1;
            #1;
            if (reg_write  !== exp_rw  || mem_write !== exp_mw ||
                mem_read   !== exp_mr  || alu_src   !== exp_as ||
                alu_a_pc   !== exp_apc || result_src !== exp_rs ||
                branch     !== exp_br  || jump      !== exp_j  ||
                alu_op     !== exp_ao  || imm_src   !== exp_is ||
                alu_ctrl   !== exp_ac) begin
                errors = errors + 1;
                $display("FAIL %-20s : rw=%b mw=%b mr=%b as=%b apc=%b rs=%b br=%b j=%b ao=%b is=%b ac=%b",
                         tname, reg_write, mem_write, mem_read, alu_src,
                         alu_a_pc, result_src, branch, jump, alu_op,
                         imm_src, alu_ctrl);
                $display("     expected          : rw=%b mw=%b mr=%b as=%b apc=%b rs=%b br=%b j=%b ao=%b is=%b ac=%b",
                         exp_rw, exp_mw, exp_mr, exp_as, exp_apc, exp_rs,
                         exp_br, exp_j, exp_ao, exp_is, exp_ac);
            end else begin
                $display("PASS %-20s : ac=%b ao=%b is=%b rs=%b",
                         tname, alu_ctrl, alu_op, imm_src, result_src);
            end
        end
    endtask

    // Shorter form: the common case for R/I-type ALU ops
    // (rw=1, everything else 0 except alu_op=10, imm_src=000).
    task check_alu_op;
        input [3:0] exp_ac;
        input [8*20-1:0] tname;
        begin
            check(1'b1, 1'b0, 1'b0, (opcode == OP_I), 1'b0,
                  2'b00, 1'b0, 1'b0, 2'b10, 3'b000, exp_ac, tname);
        end
    endtask

    initial begin
        $display("=== RV32I control unit testbench ===");

        // ---- R-type (opcode 0110011) -------------------------------------
        opcode = OP_R; funct7 = 7'b0000000;
        funct3 = 3'b000; check_alu_op(ALU_ADD,  "R ADD");
        funct7 = 7'b0100000;
        funct3 = 3'b000; check_alu_op(ALU_SUB,  "R SUB");
        funct7 = 7'b0000000;
        funct3 = 3'b001; check_alu_op(ALU_SLL,  "R SLL");
        funct3 = 3'b010; check_alu_op(ALU_SLT,  "R SLT");
        funct3 = 3'b011; check_alu_op(ALU_SLTU, "R SLTU");
        funct3 = 3'b100; check_alu_op(ALU_XOR,  "R XOR");
        funct3 = 3'b101; check_alu_op(ALU_SRL,  "R SRL");
        funct7 = 7'b0100000;
        funct3 = 3'b101; check_alu_op(ALU_SRA,  "R SRA");
        funct7 = 7'b0000000;
        funct3 = 3'b110; check_alu_op(ALU_OR,   "R OR");
        funct3 = 3'b111; check_alu_op(ALU_AND,  "R AND");

        // ---- I-type ALU (opcode 0010011) ----------------------------------
        opcode = OP_I; funct7 = 7'b0000000;
        funct3 = 3'b000; check_alu_op(ALU_ADD,  "I ADDI");
        funct3 = 3'b010; check_alu_op(ALU_SLT,  "I SLTI");
        funct3 = 3'b011; check_alu_op(ALU_SLTU, "I SLTIU");
        funct3 = 3'b100; check_alu_op(ALU_XOR,  "I XORI");
        funct3 = 3'b110; check_alu_op(ALU_OR,   "I ORI");
        funct3 = 3'b111; check_alu_op(ALU_AND,  "I ANDI");
        funct3 = 3'b001; check_alu_op(ALU_SLL,  "I SLLI");
        funct3 = 3'b101; check_alu_op(ALU_SRL,  "I SRLI");
        funct7 = 7'b0100000;
        funct3 = 3'b101; check_alu_op(ALU_SRA,  "I SRAI");
        // funct7[5] set on an I-type ADD must NOT mean SUB: for I-type
        // that bit is part of the immediate, not the funct7 field.
        funct7 = 7'b0100000;
        funct3 = 3'b000; check_alu_op(ALU_ADD,  "I ADDI f7[5]=1->ADD");

        // ---- Loads (opcode 0000011): rw=1 mr=1 as=1 rs=01 ao=00 is=000 --
        opcode = OP_LOAD; funct7 = 7'b0000000;
        funct3 = 3'b000;
        check(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 2'b01, 1'b0, 1'b0,
              2'b00, 3'b000, ALU_ADD, "LOAD LB");
        funct3 = 3'b001;
        check(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 2'b01, 1'b0, 1'b0,
              2'b00, 3'b000, ALU_ADD, "LOAD LH");
        funct3 = 3'b010;
        check(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 2'b01, 1'b0, 1'b0,
              2'b00, 3'b000, ALU_ADD, "LOAD LW");
        funct3 = 3'b100;
        check(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 2'b01, 1'b0, 1'b0,
              2'b00, 3'b000, ALU_ADD, "LOAD LBU");
        funct3 = 3'b101;
        check(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 2'b01, 1'b0, 1'b0,
              2'b00, 3'b000, ALU_ADD, "LOAD LHU");

        // ---- Stores (opcode 0100011): mw=1 as=1 ao=00 is=001 -------------
        opcode = OP_STORE; funct7 = 7'b0000000;
        funct3 = 3'b000;
        check(1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 2'b00, 1'b0, 1'b0,
              2'b00, 3'b001, ALU_ADD, "STORE SB");
        funct3 = 3'b001;
        check(1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 2'b00, 1'b0, 1'b0,
              2'b00, 3'b001, ALU_ADD, "STORE SH");
        funct3 = 3'b010;
        check(1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 2'b00, 1'b0, 1'b0,
              2'b00, 3'b001, ALU_ADD, "STORE SW");

        // ---- Branches (opcode 1100011): br=1 ao=01 is=010 ----------------
        opcode = OP_BRANCH; funct7 = 7'b0000000;
        funct3 = 3'b000;
        check(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1, 1'b0,
              2'b01, 3'b010, ALU_SUB, "BRANCH BEQ->SUB");
        funct3 = 3'b001;
        check(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1, 1'b0,
              2'b01, 3'b010, ALU_SUB, "BRANCH BNE->SUB");
        funct3 = 3'b100;
        check(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1, 1'b0,
              2'b01, 3'b010, ALU_SLT, "BRANCH BLT->SLT");
        funct3 = 3'b101;
        check(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1, 1'b0,
              2'b01, 3'b010, ALU_SLT, "BRANCH BGE->SLT");
        funct3 = 3'b110;
        check(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1, 1'b0,
              2'b01, 3'b010, ALU_SLTU, "BRANCH BLTU->SLTU");
        funct3 = 3'b111;
        check(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1, 1'b0,
              2'b01, 3'b010, ALU_SLTU, "BRANCH BGEU->SLTU");

        // ---- JAL (1101111): rw=1 jump=1 rs=10 is=100 ----------------------
        opcode = OP_JAL; funct3 = 3'b000; funct7 = 7'b0000000;
        check(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'b10, 1'b0, 1'b1,
              2'b00, 3'b100, ALU_ADD, "JAL");

        // ---- JALR (1100111): rw=1 jump=1 as=1 rs=10 is=000 ---------------
        opcode = OP_JALR; funct3 = 3'b000; funct7 = 7'b0000000;
        check(1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 2'b10, 1'b0, 1'b1,
              2'b00, 3'b000, ALU_ADD, "JALR");

        // ---- LUI (0110111): rw=1 as=1 rs=11 is=011 ------------------------
        opcode = OP_LUI; funct3 = 3'b000; funct7 = 7'b0000000;
        check(1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 2'b11, 1'b0, 1'b0,
              2'b00, 3'b011, ALU_ADD, "LUI");

        // ---- AUIPC (0010111): rw=1 as=1 apc=1 rs=00 is=011 ----------------
        opcode = OP_AUIPC; funct3 = 3'b000; funct7 = 7'b0000000;
        check(1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 2'b00, 1'b0, 1'b0,
              2'b00, 3'b011, ALU_ADD, "AUIPC");

        // ---- Illegal opcode: everything zero (harmless no-op) -------------
        opcode = 7'b0000000; funct3 = 3'b111; funct7 = 7'b1111111;
        check(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0,
              2'b00, 3'b000, ALU_ADD, "ILLEGAL -> NOP");

        // ---- summary -------------------------------------------------------
        $display("--------------------------------------------------");
        $display("CONTROL UNIT TEST SUMMARY: %0d/%0d passed",
                 total - errors, total);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1, "Control unit testbench failed");
        end
    end

endmodule
