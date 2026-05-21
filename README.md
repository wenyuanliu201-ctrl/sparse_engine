# 自适应多粒度稀疏编码IP核 (Adaptive Multi-Granularity Sparse Coding Engine)

AI芯片专用的稀疏编码加速IP核，支持运行时自适应多粒度稀疏编码，覆盖CNN/Transformer/LLM等多种模型的稀疏模式。

## 核心特性

- **四级稀疏粒度模型**：L1元素级 / L2块级 / L3通道级 / Dense稠密回退
- **运行时自适应决策**：根据输入张量稀疏率和聚集度动态选择最优粒度
- **统一混合编码格式**：2bit粒度标识 + 变长载荷，零开销粒度切换
- **零开销稠密回退**：低稀疏率场景自动回退，性能不降级

## 项目结构

```
sparse_engine/
├── rtl/                            # SystemVerilog RTL源代码
│   ├── sparse_pkg.sv               # 公共类型定义
│   ├── sparsity_analyzer.sv        # 稀疏感知分析器
│   ├── granularity_decision.sv     # 粒度决策引擎
│   ├── encoder_l1/l2/l3.sv         # 三级编码器
│   ├── decoder_l1/l2/l3.sv         # 三级译码器
│   ├── granularity_router.sv       # 粒度路由器
│   ├── encoded_packet_formatter.sv # 编码包格式化
│   └── sparse_engine_top.sv        # 顶层模块
├── tb/                             # 测试平台
│   ├── tb_sparsity_analyzer.sv
│   ├── tb_granularity_decision.sv
│   ├── tb_encoder_l2.sv            # L2编码-译码往返测试
│   └── tb_sparse_engine_top.sv     # 顶层集成测试
├── python/                         # Python参考模型
│   ├── ref_model.py                # 软件参考模型
│   └── end_to_end_test.py          # 端到端模型级评估
├── sim/                            # ModelSim仿真脚本
│   ├── run_sim.tcl                 # 批量仿真
│   └── run_gui.tcl                 # GUI调试
└── doc/                            # 专利文档
    └── patent_report.tex           # 专利报告书(LaTeX)
```

## 验证结果

ModelSim仿真全部通过：

| 测试项 | 用例数 | 结果 |
|--------|--------|------|
| Sparsity Analyzer | 4 | ALL PASSED |
| Granularity Decision | 6 | ALL PASSED |
| L2 Encode/Decode Roundtrip | 25 | ALL PASSED |
| Top-Level Integration | 2 | ALL PASSED |

## 使用方法

### ModelSim仿真

```bash
cd sim
vsim -c -do run_sim.tcl
```

### Python参考模型

```bash
cd python
python3 ref_model.py
python3 end_to_end_test.py
```

### LaTeX文档编译

```bash
cd doc
xelatex patent_report.tex
```

## 工具版本

- ModelSim Intel FPGA Starter Edition 2020.1
- Python 3.8+
- TeX Live 2022 (XeLaTeX)

## License

本项目为AI芯片IP核专利相关代码，所有权利保留。
