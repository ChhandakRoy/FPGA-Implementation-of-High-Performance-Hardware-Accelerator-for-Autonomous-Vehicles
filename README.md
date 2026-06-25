# ALU Functional Verification — SystemVerilog Layered Testbench

![Language](https://img.shields.io/badge/Language-SystemVerilog-blue)
![Simulator](https://img.shields.io/badge/Simulator-Vivado%20XSim%202024.2-orange)
![Status](https://img.shields.io/badge/Status-Complete-brightgreen)

## Overview
Functional verification of a parameterized synchronous 8-bit ALU using a 
SystemVerilog layered testbench with constrained-random stimulus, functional 
coverage collection, and a self-checking scoreboard.

---

## DUT Specification

| Parameter | Value |
|-----------|-------|
| Width | 8-bit (parametric) |
| Output | 16-bit (2×width) |
| Clock | Synchronous |
| Reset | Active-high |

| Mode | Operation |
|------|-----------|
| 2'b00 (ADD) | result = a + b |
| 2'b01 (SUB) | result = a − b |
| 2'b10 (MUL) | result = a × b |
| 2'b11 (CMP) | result = (a > b) ? 1 : 0 |

---

## Testbench Architecture

![TB Architecture](testbench environment/ALU_testbench_environemnt.png)

| Component | Role |
|-----------|------|
| Transaction | Randomized data object with constraints |
| Generator | Creates 20 transactions; feeds Driver and Monitor via mailboxes |
| Driver | Drives DUT inputs via virtual interface |
| Monitor | Samples DUT output after clock edge; sends to Scoreboard |
| Scoreboard | Computes expected output; compares with actual; prints PASS/FAIL |
| Coverage | Covergroup on mode, a, b, result with cross coverage |

---

## Simulation Results

![Waveform](results/sim_waveform.png)

**Scoreboard Summary:**
- ADD transactions: X
- SUB transactions: X
- MUL transactions: X
- CMP transactions: X
- All results: MATCHED ✅

---

## How to Reproduce

1. Open Vivado 2024.2
2. Create new project → add `rtl/ALU.sv` as Design Source
3. Add `tb/ALU_testbench.sv` as Simulation Source
4. In TCL Console: `source sim/run_sim.tcl`

---

## Skills Demonstrated
- SystemVerilog OOP (classes, mailboxes, virtual interfaces)
- Constrained-random verification (CRV)
- Functional coverage (covergroup, coverpoint, cross)
- Self-checking scoreboard
- Layered testbench architecture (UVM-preparatory)

---

## Author
**Chhandak Roy**  
M.Tech VLSI & Nanoelectronics, IIT Guwahati (2024–2026)  
[LinkedIn](www.linkedin.com/in/chhandak-roy-profile)