//=============================================================================
// imm_gen_tb.v — Self-checking testbench for the RV32I immediate generator
// RV32I single-cycle CPU.
//
// Every case feeds a real instruction encoding (hand-built from the
// instruction fields, checked below) and compares the sign-extended
// immediate against the expected value. Any mismatch prints FAIL and is
// counted; at the end a summary is printed and the simulation exits
// non-zero ($fatal) if anything failed.
//
// Run with Icarus Verilog:
//   iverilog -o sim/imm_gen_tb.vvp rtl/imm_gen.v tb/imm_gen_tb.v
//   vvp sim/imm_gen_tb.vvp
//
// Encodings used (opcode / fields), all hand-computed:
//   ADDI x1, x0, 5      = 0x00500093   (I, imm 5)
//   ADDI x1, x0, -1     = 0xFFF00093   (I, imm -1)
//   LW   x2, 16(x3)     = 0x0101A103   (I, imm 16)
//   SW   x2, 8(x3)      = 0x0021A423   (S, imm 8)
//   SW   x2, -4(x3)     = 0xFE21AE23   (S, imm -4)
//   SW   x2, 1020(x3)   = 0x3E21AE23   (S, imm 1020)
//   BEQ  x1, x2, 12     = 0x00208663   (B, imm 12)
//   BEQ  x1, x2, -8     = 0xFE208CE3   (B, imm -8)
//   LUI  x1, 0x12345    = 0x123450B7   (U, imm 0x12345000)
//   AUIPC x2, 0xFFFFF   = 0xFFFFF117   (U, imm 0xFFFFF000)
//   JAL  x1, 20         = 0x014000EF   (J, imm 20)
//   JAL  x1, -4         = 0xFFDFF0EF   (J, imm -4)
//=============================================================================

`timescale 1ns / 1ps

module imm_gen_tb;

    reg  [31:0] instr;
    reg  [2:0]  imm_src;
    wire [31:0] imm;

    integer errors = 0;
    integer total  = 0;

    imm_gen dut (
        .instr(instr),
        .imm_src(imm_src),
        .imm(imm)
    );

    // Format selects — must match rtl/imm_gen.v
    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;

    // Check one case: set the inputs, wait for the combinational logic to
    // settle, then compare the immediate against the expected value.
    task check;
        input [31:0] exp_imm;
        input [8*28-1:0] tname;
        begin
            total = total + 1;
            #1;
            if (imm !== exp_imm) begin
                errors = errors + 1;
                $display("FAIL %-28s : instr=%h src=%b -> imm=%h (expected %h)",
                         tname, instr, imm_src, imm, exp_imm);
            end else begin
                $display("PASS %-28s : imm=%h", tname, imm);
            end
        end
    endtask

    initial begin
        $display("=== RV32I immediate generator testbench ===");

        // ---- I-type ------------------------------------------------------
        instr = 32'h00500093; imm_src = IMM_I;
        check(32'd5, "I: ADDI 5");
        instr = 32'hFFF00093; imm_src = IMM_I;
        check(32'hFFFFFFFF, "I: ADDI -1 sign-extended");
        instr = 32'h0101A103; imm_src = IMM_I;
        check(32'd16, "I: LW offset 16");
        instr = 32'h80000093; imm_src = IMM_I;
        check(32'hFFFFF800, "I: imm -2048 (0x800)");
        instr = 32'h7FF00093; imm_src = IMM_I;
        check(32'd2047, "I: imm +2047 (0x7FF)");

        // ---- S-type ------------------------------------------------------
        instr = 32'h0021A423; imm_src = IMM_S;
        check(32'd8, "S: SW offset 8");
        instr = 32'hFE21AE23; imm_src = IMM_S;
        check(32'hFFFFFFFC, "S: SW offset -4");
        instr = 32'h3E21AE23; imm_src = IMM_S;
        check(32'd1020, "S: SW offset 1020 (split)");

        // ---- B-type ------------------------------------------------------
        instr = 32'h00208663; imm_src = IMM_B;
        check(32'd12, "B: BEQ +12");
        instr = 32'hFE208CE3; imm_src = IMM_B;
        check(32'hFFFFFFF8, "B: BEQ -8");
        instr = 32'h00208063; imm_src = IMM_B;
        check(32'd0, "B: BEQ 0");

        // ---- U-type ------------------------------------------------------
        instr = 32'h123450B7; imm_src = IMM_U;
        check(32'h12345000, "U: LUI 0x12345");
        instr = 32'hFFFFF117; imm_src = IMM_U;
        check(32'hFFFFF000, "U: AUIPC 0xFFFFF");
        instr = 32'h000000B7; imm_src = IMM_U;
        check(32'd0, "U: LUI 0");

        // ---- J-type ------------------------------------------------------
        instr = 32'h014000EF; imm_src = IMM_J;
        check(32'd20, "J: JAL +20");
        instr = 32'hFFDFF0EF; imm_src = IMM_J;
        check(32'hFFFFFFFC, "J: JAL -4");
        instr = 32'h000000EF; imm_src = IMM_J;
        check(32'd0, "J: JAL 0");

        // ---- default (undefined imm_src) --------------------------------
        instr = 32'hDEADBEEF; imm_src = 3'b111;
        check(32'd0, "DEFAULT src -> 0");
        instr = 32'h00500093; imm_src = 3'b101;
        check(32'd0, "DEFAULT src 101 -> 0");

        // ---- summary -----------------------------------------------------
        $display("--------------------------------------------------");
        $display("IMM_GEN TEST SUMMARY: %0d/%0d passed", total - errors, total);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1, "imm_gen testbench failed");
        end
    end

endmodule
