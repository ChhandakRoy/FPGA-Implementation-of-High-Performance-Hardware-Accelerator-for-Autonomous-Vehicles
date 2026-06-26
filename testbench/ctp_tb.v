`timescale 1ns / 1ps
// ==============================================================================
// File        : ctp_tb.v
// Description : Functional simulation testbench for the CTP Module
//               FPGA Hardware Accelerator.
//               Drives clock and reset; monitors all 4 stage completion
//               flags; measures per-stage and total cycle counts;
//               computes achieved FPS and validates against design targets.
// DUT         : CTP (M=128, N=64, C=64, width=8, FW=8)
// Board       : Xilinx Virtex-7 VC707
// Clock       : 166.667 MHz  (Period = 6.000 ns)
// Tool        : Vivado XSim 2024.2
// Author      : Chhandak Roy — IIT Guwahati, M.Tech VLSI (2024-2026)
// ==============================================================================


module ctp_tb;


    // =========================================================================
    // SECTION 1 — PARAMETERS
    // =========================================================================

    // DUT parameters — must match CTP module instantiation
    parameter WIDTH             = 8;
    parameter M                 = 128;
    parameter N                 = 64;
    parameter C                 = 64;
    parameter FW                = 8;

    // Clock: 166.667 MHz → period = 6.000 ns
    parameter real CLK_PERIOD   = 6.000;
    parameter real CLK_HALF     = CLK_PERIOD / 2.0;

    // Design targets (from hardware characterization)
    parameter EXP_TOTAL_CYCLES  = 215605;   // Expected cycles per full frame
    parameter EXP_FPS           = 774;      // Expected frames per second
    parameter real EXP_FRAME_MS = 1.290;    // Expected latency in ms

    // Timeout watchdog — 3x expected cycles; catches infinite loops / hangs
    parameter TIMEOUT_LIMIT     = EXP_TOTAL_CYCLES * 3;

    // Reset duration — hold for 10 clock cycles
    parameter RESET_CYCLES      = 10;


    // =========================================================================
    // SECTION 2 — DUT SIGNAL DECLARATIONS
    // =========================================================================

    reg         clk;
    reg         reset;

    wire        STAGE1;              // High when Stage 1 (PW Conv 1/4) completes
    wire        STAGE2;              // High when Stage 2 (parallel DwDConv) completes
    wire        STAGE3;              // High when Stage 3 (DwDConv r=18, r=36) completes
    wire        STAGE4;              // High when Stage 4 (PW Conv 1/2) completes
    wire [7:0]  S4_CHANNEL_STATUS;   // Tracks Stage 4 channel progress (0 → C/2)


    // =========================================================================
    // SECTION 3 — MEASUREMENT REGISTERS
    // =========================================================================

    integer     cycle_count;         // Free-running cycle counter (clears on reset)
    integer     stage1_cycle;        // Cycle at which STAGE1 first asserted
    integer     stage2_cycle;        // Cycle at which STAGE2 first asserted
    integer     stage3_cycle;        // Cycle at which STAGE3 first asserted
    integer     stage4_cycle;        // Cycle at which STAGE4 first asserted
    integer     timeout_count;       // Watchdog counter

    reg         stage1_captured;     // Prevents re-capture on multi-cycle assertion
    reg         stage2_captured;
    reg         stage3_captured;
    reg         stage4_captured;

    reg  [7:0]  prev_status;         // Tracks S4_CHANNEL_STATUS transitions
    real        frame_time_us;       // Computed frame latency in microseconds
    real        achieved_fps;        // Computed frames per second


    // =========================================================================
    // SECTION 4 — DUT INSTANTIATION
    // =========================================================================

    CTP #(
        .width  (WIDTH),
        .M      (M),
        .N      (N),
        .C      (C),
        .FW     (FW)
    ) DUT (
        .clk                (clk              ),
        .reset              (reset            ),
        .STAGE1             (STAGE1           ),
        .STAGE2             (STAGE2           ),
        .STAGE3             (STAGE3           ),
        .STAGE4             (STAGE4           ),
        .S4_CHANNEL_STATUS  (S4_CHANNEL_STATUS)
    );


    // =========================================================================
    // SECTION 5 — CLOCK GENERATION
    // 166.667 MHz — 6.000 ns period
    // =========================================================================

    initial clk = 1'b0;
    always  #(CLK_HALF) clk = ~clk;


    // =========================================================================
    // SECTION 6 — FREE-RUNNING CYCLE COUNTER
    // Resets synchronously with the DUT; counts from 0 after reset release
    // =========================================================================

    always @(posedge clk) begin
        if (reset)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end


    // =========================================================================
    // SECTION 7 — STAGE COMPLETION MONITORS
    // Each block watches for the rising edge of its flag and records
    // the cycle count exactly once (guard flag prevents re-capture)
    // =========================================================================

    // --- Stage 1 : Pointwise Conv (channel squeeze Cin → Cin/4) ---
    always @(posedge clk) begin
        if (reset) begin
            stage1_captured <= 1'b0;
            stage1_cycle    <= 0;
        end else if (STAGE1 && !stage1_captured) begin
            stage1_captured <= 1'b1;
            stage1_cycle    <= cycle_count;
            $display("[STAGE 1] COMPLETE | Cycle = %7d | Time = %8.3f us | PW Conv (1/4) — Cin=%0d → Cin/4=%0d",
                      cycle_count,
                      (cycle_count * CLK_PERIOD) / 1000.0,
                      C, C/4);
        end
    end

    // --- Stage 2 : Parallel DwDConv r=6 + r=12 with AP+BI ---
    always @(posedge clk) begin
        if (reset) begin
            stage2_captured <= 1'b0;
            stage2_cycle    <= 0;
        end else if (STAGE2 && !stage2_captured) begin
            stage2_captured <= 1'b1;
            stage2_cycle    <= cycle_count;
            $display("[STAGE 2] COMPLETE | Cycle = %7d | Time = %8.3f us | DwDConv r=6 || DwDConv r=12 + AP16x16 + BI",
                      cycle_count,
                      (cycle_count * CLK_PERIOD) / 1000.0);
        end
    end

    // --- Stage 3 : DwDConv r=18 + r=36 with AP+BI ---
    always @(posedge clk) begin
        if (reset) begin
            stage3_captured <= 1'b0;
            stage3_cycle    <= 0;
        end else if (STAGE3 && !stage3_captured) begin
            stage3_captured <= 1'b1;
            stage3_cycle    <= cycle_count;
            $display("[STAGE 3] COMPLETE | Cycle = %7d | Time = %8.3f us | DwDConv r=18 || DwDConv r=36 + AP4x4 + BI",
                      cycle_count,
                      (cycle_count * CLK_PERIOD) / 1000.0);
        end
    end

    // --- Stage 4 : Pointwise Conv (channel project Cin/4 → Cin/2) ---
    always @(posedge clk) begin
        if (reset) begin
            stage4_captured <= 1'b0;
            stage4_cycle    <= 0;
        end else if (STAGE4 && !stage4_captured) begin
            stage4_captured <= 1'b1;
            stage4_cycle    <= cycle_count;
            $display("[STAGE 4] COMPLETE | Cycle = %7d | Time = %8.3f us | PW Conv (1/2) — 4-channel parallel",
                      cycle_count,
                      (cycle_count * CLK_PERIOD) / 1000.0);
        end
    end


    // =========================================================================
    // SECTION 8 — S4 CHANNEL STATUS MONITOR
    // Prints every time the Stage 4 channel counter increments
    // Shows progress through the C/2 output channels
    // =========================================================================

    always @(posedge clk) begin
        if (reset) begin
            prev_status <= 8'h00;
        end else if (S4_CHANNEL_STATUS != prev_status) begin
            prev_status <= S4_CHANNEL_STATUS;
            $display("[S4 STATUS]         Channel %3d / %3d complete | Cycle = %7d",
                      S4_CHANNEL_STATUS, C/2, cycle_count);
        end
    end


    // =========================================================================
    // SECTION 9 — TIMEOUT WATCHDOG
    // Terminates simulation if STAGE4 never asserts within TIMEOUT_LIMIT cycles
    // Prevents infinite hang on BRAM init errors or RTL deadlocks
    // =========================================================================

    always @(posedge clk) begin
        if (reset) begin
            timeout_count <= 0;
        end else begin
            timeout_count <= timeout_count + 1;
            if (timeout_count >= TIMEOUT_LIMIT) begin
                $display(" ");
                $display("================================================================");
                $display("[WATCHDOG] TIMEOUT — Simulation killed at cycle %0d", cycle_count);
                $display("[WATCHDOG] STAGE flags at timeout:");
                $display("[WATCHDOG]   STAGE1 = %b | STAGE2 = %b | STAGE3 = %b | STAGE4 = %b",
                          STAGE1, STAGE2, STAGE3, STAGE4);
                $display("[WATCHDOG] Possible causes:");
                $display("[WATCHDOG]   1. BRAM .coe file not loaded correctly");
                $display("[WATCHDOG]   2. RTL state machine stuck — check reset polarity");
                $display("[WATCHDOG]   3. Stage handshaking (latency_tracker) misconfigured");
                $display("================================================================");
                $finish;
            end
        end
    end


    // =========================================================================
    // SECTION 10 — MAIN STIMULUS & REPORT
    // =========================================================================

    initial begin

        //----------------------------------------------------------------------
        // Initialize all signals
        //----------------------------------------------------------------------
        clk             = 1'b0;
        reset           = 1'b1;
        stage1_captured = 1'b0;
        stage2_captured = 1'b0;
        stage3_captured = 1'b0;
        stage4_captured = 1'b0;
        stage1_cycle    = 0;
        stage2_cycle    = 0;
        stage3_cycle    = 0;
        stage4_cycle    = 0;
        timeout_count   = 0;
        prev_status     = 8'h00;

        //----------------------------------------------------------------------
        // Simulation header
        //----------------------------------------------------------------------
        $display(" ");
        $display("================================================================");
        $display("[TB] CTP Module FPGA Accelerator — Simulation Started");
        $display("================================================================");
        $display("[TB] DUT Parameters:");
        $display("[TB]   Image Size  : %0d x %0d (M x N)",  M, N);
        $display("[TB]   Channels    : Cin=%0d | Cout=%0d",  C, C/2);
        $display("[TB]   Pixel Width : %0d bits",            WIDTH);
        $display("[TB]   Frac Width  : %0d bits",            FW);
        $display("[TB] Clock         : 166.667 MHz (%.3f ns period)", CLK_PERIOD);
        $display("[TB] Design Target : %0d cycles | %.3f ms | %0d FPS",
                  EXP_TOTAL_CYCLES, EXP_FRAME_MS, EXP_FPS);
        $display("================================================================");

        //----------------------------------------------------------------------
        // Reset sequence — hold for RESET_CYCLES clock cycles
        //----------------------------------------------------------------------
        repeat(RESET_CYCLES) @(posedge clk);
        reset = 1'b0;
        $display("[TB] Reset de-asserted | Simulation clock running");
        $display("[TB] Waiting for stage completion flags...");
        $display(" ");

        //----------------------------------------------------------------------
        // Wait for full frame — STAGE4 asserts when final PW Conv completes
        //----------------------------------------------------------------------
        wait(stage4_captured == 1'b1);

        // Allow pipeline drain — a few extra cycles before capturing final state
        repeat(50) @(posedge clk);

        //----------------------------------------------------------------------
        // Compute performance metrics
        //----------------------------------------------------------------------
        frame_time_us = (stage4_cycle * CLK_PERIOD) / 1000.0;
        achieved_fps  = 1.0e6 / frame_time_us;

        //----------------------------------------------------------------------
        // Final simulation report
        //----------------------------------------------------------------------
        $display(" ");
        $display("================================================================");
        $display("[REPORT] =========== CTP SIMULATION SUMMARY ============");
        $display("================================================================");
        $display("  Configuration : M=%0d | N=%0d | C=%0d | width=%0d | FW=%0d",
                  M, N, C, WIDTH, FW);
        $display("  Clock         : 166.667 MHz | %.3f ns period", CLK_PERIOD);
        $display("----------------------------------------------------------------");
        $display("  STAGE 1  PW Conv (1/4)          : %7d cycles | %8.3f us",
                  stage1_cycle,
                  (stage1_cycle * CLK_PERIOD) / 1000.0);
        $display("  STAGE 2  DwDConv r=6 || r=12    : %7d cycles | %8.3f us",
                  stage2_cycle,
                  (stage2_cycle * CLK_PERIOD) / 1000.0);
        $display("  STAGE 3  DwDConv r=18 || r=36   : %7d cycles | %8.3f us",
                  stage3_cycle,
                  (stage3_cycle * CLK_PERIOD) / 1000.0);
        $display("  STAGE 4  PW Conv (1/2)          : %7d cycles | %8.3f us",
                  stage4_cycle,
                  (stage4_cycle * CLK_PERIOD) / 1000.0);
        $display("----------------------------------------------------------------");
        $display("  Stage 1 share of total          : %5.1f %%",
                  (100.0 * stage1_cycle) / stage4_cycle);
        $display("  Stage 2 delta                   : %5.1f %%",
                  (100.0 * (stage2_cycle - stage1_cycle)) / stage4_cycle);
        $display("  Stage 3 delta                   : %5.1f %%",
                  (100.0 * (stage3_cycle - stage2_cycle)) / stage4_cycle);
        $display("  Stage 4 delta                   : %5.1f %%",
                  (100.0 * (stage4_cycle - stage3_cycle)) / stage4_cycle);
        $display("----------------------------------------------------------------");
        $display("  Total Cycles per Frame          : %7d", stage4_cycle);
        $display("  Expected Cycles                 : %7d", EXP_TOTAL_CYCLES);

        if (stage4_cycle <= EXP_TOTAL_CYCLES)
            $display("  Cycle Budget Check              : PASS ✓  (%0d cycles under)",
                      EXP_TOTAL_CYCLES - stage4_cycle);
        else
            $display("  Cycle Budget Check              : FAIL ✗  (%0d cycles over)",
                      stage4_cycle - EXP_TOTAL_CYCLES);

        $display("----------------------------------------------------------------");
        $display("  Frame Latency (achieved)        : %8.3f us", frame_time_us);
        $display("  Frame Latency (expected)        : %8.3f us", EXP_FRAME_MS * 1000.0);
        $display("  Achieved FPS                    : %8.2f FPS", achieved_fps);
        $display("  Expected FPS                    : %8.2f FPS", 1.0 * EXP_FPS);

        if (achieved_fps >= EXP_FPS)
            $display("  FPS Check                       : PASS ✓");
        else
            $display("  FPS Check                       : FAIL ✗");

        $display("================================================================");
        $display("[TB] Simulation Complete");
        $display("================================================================");
        $display(" ");

        $finish;
    end


endmodule
// ==============================================================================
// END OF TESTBENCH
// ==============================================================================