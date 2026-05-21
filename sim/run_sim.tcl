# ============================================================================
# ModelSim 仿真脚本 - 自适应多粒度稀疏编码IP核
# Simulation Script for Adaptive Multi-Granularity Sparse Coding Engine
# 用法: vsim -c -do run_sim.tcl
# ============================================================================

# ===== 创建工作库 =====
vlib work
vmap work work

# ===== 编译RTL源文件 =====
echo "===== Compiling RTL ====="
vlog -work work ../rtl/sparse_pkg.sv
vlog -work work ../rtl/sparsity_analyzer.sv
vlog -work work ../rtl/granularity_decision.sv
vlog -work work ../rtl/encoder_l1.sv
vlog -work work ../rtl/encoder_l2.sv
vlog -work work ../rtl/encoder_l3.sv
vlog -work work ../rtl/granularity_router.sv
vlog -work work ../rtl/encoded_packet_formatter.sv
vlog -work work ../rtl/decoder_l1.sv
vlog -work work ../rtl/decoder_l2.sv
vlog -work work ../rtl/decoder_l3.sv
vlog -work work ../rtl/sparse_engine_top.sv

# ===== 编译测试平台 =====
echo "===== Compiling Testbenches ====="
vlog -work work ../tb/tb_sparsity_analyzer.sv
vlog -work work ../tb/tb_granularity_decision.sv
vlog -work work ../tb/tb_encoder_l2.sv
vlog -work work ../tb/tb_sparse_engine_top.sv

# ===== 运行仿真 =====
echo "===== Running Sparsity Analyzer Test ====="
vsim -c work.tb_sparsity_analyzer -do "run -all; quit -f"

echo "===== Running Granularity Decision Test ====="
vsim -c work.tb_granularity_decision -do "run -all; quit -f"

echo "===== Running L2 Encoder/Decoder Roundtrip Test ====="
vsim -c work.tb_encoder_l2 -do "run -all; quit -f"

echo "===== Running Top-Level Integration Test ====="
vsim -c work.tb_sparse_engine_top -do "run -all; quit -f"

echo "===== All Simulations Complete ====="
