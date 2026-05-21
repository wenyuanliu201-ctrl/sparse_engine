# ============================================================================
# ModelSim GUI仿真脚本 - 交互式调试用
# GUI Simulation Script for Interactive Debugging
# 用法: vsim -do run_gui.tcl
# ============================================================================

# ===== 创建工作库 =====
vlib work
vmap work work

# ===== 编译 =====
vlog -work work ../rtl/sparse_pkg.sv
vlog -work work ../rtl/sparsity_analyzer.sv
vlog -work work ../rtl/granularity_decision.sv
vlog -work work ../rtl/encoder_l2.sv
vlog -work work ../rtl/decoder_l2.sv
vlog -work work ../rtl/sparse_engine_top.sv

vlog -work work ../tb/tb_sparse_engine_top.sv

# ===== 启动GUI仿真 =====
vsim work.tb_sparse_engine_top

# ===== 添加波形 =====
add wave -divider "Clock & Reset"
add wave /tb_sparse_engine_top/clk
add wave /tb_sparse_engine_top/rst_n

add wave -divider "Configuration"
add wave /tb_sparse_engine_top/cfg_addr
add wave /tb_sparse_engine_top/cfg_wdata
add wave /tb_sparse_engine_top/cfg_valid

add wave -divider "Data Input"
add wave /tb_sparse_engine_top/data_in
add wave /tb_sparse_engine_top/valid_mask
add wave /tb_sparse_engine_top/data_valid
add wave /tb_sparse_engine_top/tensor_last

add wave -divider "Analysis Results"
add wave /tb_sparse_engine_top/current_sparsity
add wave /tb_sparse_engine_top/current_cluster
add wave /tb_sparse_engine_top/current_granularity
add wave /tb_sparse_engine_top/decision_reason

add wave -divider "Encode Output"
add wave /tb_sparse_engine_top/out_granularity
add wave /tb_sparse_engine_top/out_nz_count
add wave /tb_sparse_engine_top/out_bitmap
add wave /tb_sparse_engine_top/out_valid

add wave -divider "Decode"
add wave /tb_sparse_engine_top/dec_granularity
add wave /tb_sparse_engine_top/dec_output
add wave /tb_sparse_engine_top/dec_done

# ===== 运行 =====
run 10 us
wave zoom full
