//=============================================================================
// alu_tb.v — Self-checking testbench for the RV32I ALU (rtl/alu.v)
// RV32I single-cycle CPU.
//
// Every case checks the result AND the zero flag against expected values.
// Any mismatch prints FAIL and is counted; at the end a summary is printed
// and the simulation exits non-zero ($fatal) if anything failed, so a CI
// script or a plain shell command can tell pass from fail by the exit code.
//
// Run with Icarus Verilog:
//   iverilog -o sim/alu_tb.vvp rtl/alu.v tb/alu_tb.v && vvp sim/alu_tb.vvp
//=============================================================================

`timescale 1ns / 1ps

module alu_tb;

    reg  [31:0] a, b;
    reg  [3:0]  alu_ctrl;
    wire [31:0] result;
    wire        zero;

    integer errors = 0;
    integer total  = 0;

    alu dut (
        .a(a),
        .b(b),
        .alu_ctrl(alu_ctrl),
        .result(result),
        .zero(zero)
    );

    // ALU control codes — must match rtl/alu.v
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

    // Check one case: set the inputs, wait for the combinational logic to
    // settle, then compare result and zero against the expected values.
    task check;
        input [31:0] exp_r;
        input        exp_z;
        input [8*28-1:0] tname;
        begin
            total = total + 1;
            #1;
            if (result !== exp_r || zero !== exp_z) begin
                errors = errors + 1;
                $display("FAIL %-28s : a=%h b=%h ctrl=%b -> result=%h (expected %h), zero=%b (expected %b)",
                         tname, a, b, alu_ctrl, result, exp_r, zero, exp_z);
            end else begin
                $display("PASS %-28s : result=%h zero=%b", tname, result, zero);
            end
        end
    endtask

    initial begin
        $display("=== RV32I ALU testbench ===");

        // ---- ADD ---------------------------------------------------------
        a = 32'd5;          b = 32'd3;          alu_ctrl = ALU_ADD;
        check(32'd8, 1'b0, "ADD 5+3");
        a = 32'hFFFFFFFF;   b = 32'd1;          alu_ctrl = ALU_ADD;
        check(32'd0, 1'b1, "ADD -1+1 = 0, zero");
        a = 32'h7FFFFFFF;   b = 32'd1;          alu_ctrl = ALU_ADD;
        check(32'h80000000, 1'b0, "ADD overflow wrap");
        a = 32'hFFFFFFFF;   b = 32'hFFFFFFFF;   alu_ctrl = ALU_ADD;
        check(32'hFFFFFFFE, 1'b0, "ADD -1 + -1 = -2");
        a = 32'd0;          b = 32'd0;          alu_ctrl = ALU_ADD;
        check(32'd0, 1'b1, "ADD 0+0 = 0, zero");

        // ---- SUB ---------------------------------------------------------
        a = 32'd10;         b = 32'd3;          alu_ctrl = ALU_SUB;
        check(32'd7, 1'b0, "SUB 10-3");
        a = 32'd3;          b = 32'd10;         alu_ctrl = ALU_SUB;
        check(32'hFFFFFFF9, 1'b0, "SUB 3-10 = -7");
        a = 32'd5;          b = 32'd5;          alu_ctrl = ALU_SUB;
        check(32'd0, 1'b1, "SUB 5-5 = 0, zero");
        a = 32'h80000000;   b = 32'd1;          alu_ctrl = ALU_SUB;
        check(32'h7FFFFFFF, 1'b0, "SUB minint-1 wrap");
        a = 32'd0;          b = 32'd1;          alu_ctrl = ALU_SUB;
        check(32'hFFFFFFFF, 1'b0, "SUB 0-1 = -1");

        // ---- AND / OR / XOR ----------------------------------------------
        a = 32'hFF0F00FF;   b = 32'h0FF0FF00;   alu_ctrl = ALU_AND;
        check(32'h0F000000, 1'b0, "AND mask");
        a = 32'hFF;         b = 32'd0;          alu_ctrl = ALU_AND;
        check(32'd0, 1'b1, "AND with 0, zero");
        a = 32'hF0F0F0F0;   b = 32'h0F0F0F0F;   alu_ctrl = ALU_OR;
        check(32'hFFFFFFFF, 1'b0, "OR fill");
        a = 32'd0;          b = 32'd0;          alu_ctrl = ALU_OR;
        check(32'd0, 1'b1, "OR 0|0 = 0, zero");
        a = 32'hFF00FF00;   b = 32'h0F0F0F0F;   alu_ctrl = ALU_XOR;
        check(32'hF00FF00F, 1'b0, "XOR pattern");
        a = 32'hDEADBEEF;   b = 32'hDEADBEEF;   alu_ctrl = ALU_XOR;
        check(32'd0, 1'b1, "XOR x^x = 0, zero");

        // ---- SLL ---------------------------------------------------------
        a = 32'd1;          b = 32'd0;          alu_ctrl = ALU_SLL;
        check(32'd1, 1'b0, "SLL by 0");
        a = 32'd1;          b = 32'd31;         alu_ctrl = ALU_SLL;
        check(32'h80000000, 1'b0, "SLL by 31");
        a = 32'h12345678;   b = 32'd4;          alu_ctrl = ALU_SLL;
        check(32'h23456780, 1'b0, "SLL by 4");
        a = 32'd1;          b = 32'd32;         alu_ctrl = ALU_SLL;
        check(32'd1, 1'b0, "SLL by 32 -> shamt 0");
        a = 32'hFFFFFFFF;   b = 32'd1;          alu_ctrl = ALU_SLL;
        check(32'hFFFFFFFE, 1'b0, "SLL all-ones by 1");

        // ---- SRL ---------------------------------------------------------
        a = 32'h80000000;   b = 32'd1;          alu_ctrl = ALU_SRL;
        check(32'h40000000, 1'b0, "SRL 0x80000000>>1");
        a = 32'h80000000;   b = 32'd31;         alu_ctrl = ALU_SRL;
        check(32'd1, 1'b0, "SRL by 31");
        a = 32'hFFFFFFFF;   b = 32'd16;         alu_ctrl = ALU_SRL;
        check(32'h0000FFFF, 1'b0, "SRL zero fill");
        a = 32'd1;          b = 32'd0;          alu_ctrl = ALU_SRL;
        check(32'd1, 1'b0, "SRL by 0");
        a = 32'h80000000;   b = 32'd32;         alu_ctrl = ALU_SRL;
        check(32'h80000000, 1'b0, "SRL by 32 -> shamt 0");

        // ---- SRA ---------------------------------------------------------
        a = 32'h80000000;   b = 32'd1;          alu_ctrl = ALU_SRA;
        check(32'hC0000000, 1'b0, "SRA sign extend >>1");
        a = 32'h80000000;   b = 32'd31;         alu_ctrl = ALU_SRA;
        check(32'hFFFFFFFF, 1'b0, "SRA by 31 -> -1");
        a = 32'h40000000;   b = 32'd1;          alu_ctrl = ALU_SRA;
        check(32'h20000000, 1'b0, "SRA positive >>1");
        a = 32'hFFFFFFFF;   b = 32'd31;         alu_ctrl = ALU_SRA;
        check(32'hFFFFFFFF, 1'b0, "SRA -1 >>31 = -1");
        a = 32'h80000000;   b = 32'd0;          alu_ctrl = ALU_SRA;
        check(32'h80000000, 1'b0, "SRA by 0");
        // SRA vs SRL on the same value: sign fill vs zero fill
        a = 32'hF0000000;   b = 32'd4;          alu_ctrl = ALU_SRA;
        check(32'hFF000000, 1'b0, "SRA 0xF0000000>>4");
        a = 32'hF0000000;   b = 32'd4;          alu_ctrl = ALU_SRL;
        check(32'h0F000000, 1'b0, "SRL 0xF0000000>>4");

        // ---- SLT (signed) ------------------------------------------------
        a = 32'hFFFFFFFF;   b = 32'd1;          alu_ctrl = ALU_SLT;
        check(32'd1, 1'b0, "SLT -1 < 1 (signed)");
        a = 32'd1;          b = 32'hFFFFFFFF;   alu_ctrl = ALU_SLT;
        check(32'd0, 1'b1, "SLT 1 < -1 false, zero");
        a = 32'hFFFFFFFB;   b = 32'hFFFFFFFD;   alu_ctrl = ALU_SLT;
        check(32'd1, 1'b0, "SLT -5 < -3");
        a = 32'd5;          b = 32'd5;          alu_ctrl = ALU_SLT;
        check(32'd0, 1'b1, "SLT 5 < 5 false, zero");
        a = 32'h80000000;   b = 32'h7FFFFFFF;   alu_ctrl = ALU_SLT;
        check(32'd1, 1'b0, "SLT minint < maxint");
        a = 32'h7FFFFFFF;   b = 32'h80000000;   alu_ctrl = ALU_SLT;
        check(32'd0, 1'b1, "SLT maxint < minint false");

        // ---- SLTU (unsigned) ---------------------------------------------
        a = 32'd1;          b = 32'hFFFFFFFF;   alu_ctrl = ALU_SLTU;
        check(32'd1, 1'b0, "SLTU 1 < 0xFFFFFFFF");
        a = 32'hFFFFFFFF;   b = 32'd1;          alu_ctrl = ALU_SLTU;
        check(32'd0, 1'b1, "SLTU 0xFFFFFFFF < 1 false");
        a = 32'd0;          b = 32'd0;          alu_ctrl = ALU_SLTU;
        check(32'd0, 1'b1, "SLTU 0 < 0 false, zero");
        a = 32'h80000000;   b = 32'h7FFFFFFF;   alu_ctrl = ALU_SLTU;
        check(32'd0, 1'b1, "SLTU 0x80000000 > 0x7FFFFFFF");
        // Same pair, opposite answers: signed says -1 < 1, unsigned says not.
        a = 32'hFFFFFFFF;   b = 32'd1;          alu_ctrl = ALU_SLT;
        check(32'd1, 1'b0, "SLT -1 < 1 (repeat, signed)");
        a = 32'hFFFFFFFF;   b = 32'd1;          alu_ctrl = ALU_SLTU;
        check(32'd0, 1'b1, "SLTU -1 < 1 false (unsigned)");

        // ---- default (undefined control) ---------------------------------
        a = 32'hDEADBEEF;   b = 32'h12345678;   alu_ctrl = 4'b1111;
        check(32'd0, 1'b1, "DEFAULT ctrl -> 0, zero");
        a = 32'd1;          b = 32'd1;          alu_ctrl = 4'b1010;
        check(32'd0, 1'b1, "DEFAULT ctrl 1010 -> 0");

        // ---- summary -----------------------------------------------------
        $display("--------------------------------------------------");
        $display("ALU TEST SUMMARY: %0d/%0d passed", total - errors, total);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1, "ALU testbench failed");
        end
    end

endmodule
