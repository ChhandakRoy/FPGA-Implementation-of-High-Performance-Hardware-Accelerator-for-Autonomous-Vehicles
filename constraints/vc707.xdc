# ==============================================================================
# File        : vc707_ctp.xdc
# Project     : CTP Module FPGA Hardware Accelerator
# Board       : Xilinx Virtex-7 VC707 (xc7vx485tffg1761-2)
# Top Module  : CTP (width=8, M=128, N=64, C=64, FW=8)
# Target Freq : 166 MHz  (Period = 6.024 ns)
# Tool        : Vivado 2024.2
# Author      : Chhandak Roy — IIT Guwahati, M.Tech VLSI (2024-2026)
# ==============================================================================
# NOTE: The CTP module takes a single-ended 'clk' input. The VC707 provides
#       a 200 MHz differential system clock. A Clock Wizard (MMCM) wrapper
#       must be instantiated at the top level to generate 166.667 MHz from
#       the 200 MHz source.
#
#       MMCM Settings to generate ~166 MHz:
#         CLKIN1_PERIOD   = 5.000 (200 MHz input)
#         CLKFBOUT_MULT_F = 5.0
#         DIVCLK_DIVIDE   = 1
#         CLKOUT0_DIVIDE_F= 6.0   → Output = 1000/6 = 166.667 MHz
# ==============================================================================


# ==============================================================================
# SECTION 1 — PRIMARY CLOCK
# VC707 onboard 200 MHz LVDS differential system clock
# Bank 33 — Pins AD12 (P), AD11 (N)
# ==============================================================================

set_property -dict {PACKAGE_PIN AD12  IOSTANDARD LVDS} [get_ports sysclk_p]
set_property -dict {PACKAGE_PIN AD11  IOSTANDARD LVDS} [get_ports sysclk_n]

create_clock \
    -period 5.000 \
    -name   sysclk_200 \
    -waveform {0.000 2.500} \
    [get_ports sysclk_p]


# ==============================================================================
# SECTION 2 — GENERATED CLOCK (MMCM Output → CTP clk)
# Source   : sysclk_200 via MMCM CLKOUT0
# Frequency: 166.667 MHz (Period = 6.000 ns)
# ==============================================================================

create_generated_clock \
    -name       clk_166 \
    -source     [get_ports sysclk_p] \
    -multiply_by 5 \
    -divide_by   6 \
    [get_pins mmcm_clk_wiz/CLKOUT0]

# Report expected period for clarity
# clk_166 period = 5.000 * (6/5) = 6.000 ns → 166.667 MHz


# ==============================================================================
# SECTION 3 — RESET
# VC707 CPU Reset Button SW7 — Active High, LVCMOS18
# Bank 10 — Pin AR40
# ==============================================================================

set_property -dict {PACKAGE_PIN AR40  IOSTANDARD LVCMOS18} [get_ports reset]

# Reset is asynchronous — declare as false path to avoid timing analysis errors
set_false_path -from [get_ports reset]


# ==============================================================================
# SECTION 4 — STAGE COMPLETION FLAGS → GPIO LEDs DS9–DS12
# Bank 10 — Active High, LVCMOS18
# STAGE1 lights when Stage 1 (PW Conv 1/4) completes
# STAGE2 lights when Stage 2 (DwDConv parallel blocks) completes
# STAGE3 lights when Stage 3 (DwDConv r=18, r=36) completes
# STAGE4 lights when Stage 4 (PW Conv 1/2) completes
# ==============================================================================

set_property -dict {PACKAGE_PIN AM39  IOSTANDARD LVCMOS18} [get_ports STAGE1]
set_property -dict {PACKAGE_PIN AN39  IOSTANDARD LVCMOS18} [get_ports STAGE2]
set_property -dict {PACKAGE_PIN AR37  IOSTANDARD LVCMOS18} [get_ports STAGE3]
set_property -dict {PACKAGE_PIN AV40  IOSTANDARD LVCMOS18} [get_ports STAGE4]

# Stage flags are slow status signals — false path (not timing critical)
set_false_path -to [get_ports {STAGE1 STAGE2 STAGE3 STAGE4}]


# ==============================================================================
# SECTION 5 — S4_CHANNEL_STATUS[7:0] → GPIO LEDs DS13–DS16 + GPIO Header J58
# S4_CHANNEL_STATUS[3:0] → remaining onboard LEDs DS13–DS16
# S4_CHANNEL_STATUS[7:4] → GPIO Header J58 expansion pins
# ==============================================================================

# LEDs DS13–DS16 (Bank 10)
set_property -dict {PACKAGE_PIN AW40  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[0]}]
set_property -dict {PACKAGE_PIN AY39  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[1]}]
set_property -dict {PACKAGE_PIN AZ39  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[2]}]
set_property -dict {PACKAGE_PIN BA39  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[3]}]

# GPIO Header J58 expansion — upper nibble (Bank 10)
set_property -dict {PACKAGE_PIN AN40  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[4]}]
set_property -dict {PACKAGE_PIN AP40  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[5]}]
set_property -dict {PACKAGE_PIN AR39  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[6]}]
set_property -dict {PACKAGE_PIN AT39  IOSTANDARD LVCMOS18} [get_ports {S4_CHANNEL_STATUS[7]}]

# Channel status is a slow diagnostic signal — false path
set_false_path -to [get_ports {S4_CHANNEL_STATUS[*]}]


# ==============================================================================
# SECTION 6 — TIMING CONSTRAINTS
# ==============================================================================

# --- Input delay (from external stimulus / BRAM interface) ---
# Assuming inputs are synchronous to clk_166
set_input_delay  -clock clk_166 -max 2.000 [get_ports reset]
set_input_delay  -clock clk_166 -min 0.500 [get_ports reset]

# --- Output delay (to LEDs / external observer) ---
# LEDs have no strict timing requirement; set loose constraint
set_output_delay -clock clk_166 -max 2.000 [get_ports {STAGE1 STAGE2 STAGE3 STAGE4}]
set_output_delay -clock clk_166 -max 2.000 [get_ports {S4_CHANNEL_STATUS[*]}]

# --- Clock uncertainty ---
# Accounts for MMCM jitter + board trace skew
set_clock_uncertainty -setup 0.200 [get_clocks clk_166]
set_clock_uncertainty -hold  0.100 [get_clocks clk_166]

# --- Clock groups ---
# sysclk_200 and clk_166 are related (MMCM derived) — mark as such
# No asynchronous crossing between them
set_clock_groups \
    -physically_exclusive \
    -group [get_clocks sysclk_200] \
    -group [get_clocks clk_166]


# ==============================================================================
# SECTION 7 — MULTICYCLE PATHS
# ==============================================================================

# Stage completion flags (STAGE1–4) are asserted and held for multiple cycles
# Relax timing to 2 cycles — safe since these are status registers
set_multicycle_path -setup 2 -to [get_ports {STAGE1 STAGE2 STAGE3 STAGE4}]
set_multicycle_path -hold  1 -to [get_ports {STAGE1 STAGE2 STAGE3 STAGE4}]

set_multicycle_path -setup 2 -to [get_ports {S4_CHANNEL_STATUS[*]}]
set_multicycle_path -hold  1 -to [get_ports {S4_CHANNEL_STATUS[*]}]


# ==============================================================================
# SECTION 8 — FLOORPLANNING (Pblock)
# Constrains CTP datapath logic to center-right slice of Virtex-7 fabric
# Ensures DSPs and BRAMs are co-located — minimizes routing congestion
# Uncomment after first implementation pass if timing is not met
# ==============================================================================

# create_pblock pblock_ctp
# add_cells_to_pblock [get_pblocks pblock_ctp] \
#     [get_cells -hierarchical -filter {NAME =~ *CTP*}]
#
# # Slice region (adjust after reviewing floorplan)
# resize_pblock [get_pblocks pblock_ctp] -add {SLICE_X60Y100:SLICE_X180Y300}
#
# # DSP columns for Hybrid MAC and PW Conv Engine
# resize_pblock [get_pblocks pblock_ctp] -add {DSP48_X4Y40:DSP48_X10Y120}
#
# # BRAM columns for pixel/kernel storage
# resize_pblock [get_pblocks pblock_ctp] -add {RAMB36_X4Y40:RAMB36_X10Y120}


# ==============================================================================
# SECTION 9 — BITSTREAM & CONFIGURATION
# ==============================================================================

set_property CFGBVS          VCCO    [current_design]
set_property CONFIG_VOLTAGE  1.8     [current_design]

# Quad SPI for fast configuration
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH   4     [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE     33    [current_design]

# Enable bitstream compression — reduces .bit file size
set_property BITSTREAM.GENERAL.COMPRESS      TRUE  [current_design]

# CRC check on configuration readback
set_property BITSTREAM.CONFIG.UNUSEDPIN      Pulldown [current_design]


# ==============================================================================
# END OF CONSTRAINTS
# ==============================================================================
