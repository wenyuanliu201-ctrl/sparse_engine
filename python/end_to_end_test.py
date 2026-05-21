#!/usr/bin/env python3
"""
端到端模型级验证 - 在真实模型上评估自适应多粒度稀疏编码效果
End-to-end Model-Level Validation
"""

import numpy as np
from ref_model import (
    SparseEngine, SparsityAnalyzer, GranularityDecision,
    SparseEncoder, SparseDecoder, Granularity,
    generate_test_tensor
)


def simulate_pruned_weights(weight: np.ndarray, sparsity: float,
                            structured: bool = False) -> np.ndarray:
    """模拟剪枝后的权重"""
    if structured:
        # 结构化剪枝：按通道剪
        n_ch = weight.shape[0]
        n_prune = int(n_ch * sparsity)
        mask = np.ones_like(weight)
        mask[:n_prune, :] = 0
        return weight * mask
    else:
        # 非结构化剪枝：按幅值
        threshold = np.percentile(np.abs(weight), sparsity * 100)
        return weight * (np.abs(weight) >= threshold)


def evaluate_on_cnn_layers():
    """在典型CNN层上评估稀疏编码效果"""
    print("\n" + "=" * 70)
    print("  CNN层稀疏编码评估")
    print("=" * 70)

    engine = SparseEngine(thresh_l1=0.80, thresh_l2=0.50, cluster_thresh=0.50)

    # 模拟典型CNN层维度
    layers = [
        ("Conv1 (3→64, 7x7)",    (64, 3, 7, 7)),
        ("Conv2 (64→128, 3x3)",  (128, 64, 3, 3)),
        ("Conv3 (128→256, 3x3)", (256, 128, 3, 3)),
        ("Conv4 (256→512, 3x3)", (512, 256, 3, 3)),
        ("FC1 (512→1024)",       (1024, 512)),
        ("FC2 (1024→10)",        (10, 1024)),
    ]

    for sparsity in [0.50, 0.70, 0.90]:
        print(f"\n  剪枝率: {sparsity:.0%}")
        print(f"  {'层名':<25} {'粒度':>8} {'原始(KB)':>10} {'编码后(KB)':>12} {'压缩率':>8}")
        print("  " + "-" * 70)

        total_orig = 0
        total_enc = 0

        for name, shape in layers:
            weight = np.random.randn(*shape) * 0.1
            pruned = simulate_pruned_weights(weight, sparsity, structured=False)

            # 逐通道处理
            n_ch = pruned.shape[0]
            ch_orig = 0
            ch_enc = 0
            gran_counts = {}

            for c in range(n_ch):
                w = pruned[c]
                decoded, encoded, stats = engine.process(w)
                orig_bytes = w.size * 2
                ch_orig += orig_bytes
                ch_enc += encoded.storage_bytes
                gran_counts[encoded.granularity.name] = gran_counts.get(encoded.granularity.name, 0) + 1

            total_orig += ch_orig
            total_enc += ch_enc
            compression = ch_enc / ch_orig if ch_orig > 0 else 1.0
            dominant_gran = max(gran_counts, key=gran_counts.get)

            print(f"  {name:<25} {dominant_gran:>8} "
                  f"{ch_orig/1024:>9.1f} {ch_enc/1024:>11.1f} {compression:>7.1%}")

        overall = total_enc / total_orig if total_orig > 0 else 1.0
        print(f"  {'总计':<25} {'':>8} "
              f"{total_orig/1024:>9.1f} {total_enc/1024:>11.1f} {overall:>7.1%}")


def evaluate_on_transformer_layers():
    """在Transformer层上评估稀疏编码效果"""
    print("\n" + "=" * 70)
    print("  Transformer层稀疏编码评估")
    print("=" * 70)

    engine = SparseEngine(thresh_l1=0.80, thresh_l2=0.50, cluster_thresh=0.50)

    # 模拟典型Transformer权重
    d_model = 512
    n_heads = 8
    d_ff = 2048

    layers = [
        ("Q_proj",  (d_model, d_model)),
        ("K_proj",  (d_model, d_model)),
        ("V_proj",  (d_model, d_model)),
        ("O_proj",  (d_model, d_model)),
        ("FFN_W1",  (d_model, d_ff)),
        ("FFN_W2",  (d_ff, d_model)),
    ]

    for sparsity in [0.50, 0.70, 0.90]:
        print(f"\n  剪枝率: {sparsity:.0%}")
        print(f"  {'层名':<15} {'粒度':>8} {'原始(KB)':>10} {'编码后(KB)':>12} {'压缩率':>8}")
        print("  " + "-" * 60)

        total_orig = 0
        total_enc = 0
        gran_dist = {g: 0 for g in Granularity}

        for name, shape in layers:
            weight = np.random.randn(*shape) * 0.02
            pruned = simulate_pruned_weights(weight, sparsity)

            n_ch = pruned.shape[0]
            ch_orig = 0
            ch_enc = 0
            gran_counts = {}

            for c in range(n_ch):
                w = pruned[c]
                decoded, encoded, stats = engine.process(w)
                orig_bytes = w.size * 2
                ch_orig += orig_bytes
                ch_enc += encoded.storage_bytes
                gran_counts[encoded.granularity.name] = gran_counts.get(encoded.granularity.name, 0) + 1
                gran_dist[encoded.granularity] += 1

            total_orig += ch_orig
            total_enc += ch_enc
            compression = ch_enc / ch_orig if ch_orig > 0 else 1.0
            dominant_gran = max(gran_counts, key=gran_counts.get) if gran_counts else "N/A"

            print(f"  {name:<15} {dominant_gran:>8} "
                  f"{ch_orig/1024:>9.1f} {ch_enc/1024:>11.1f} {compression:>7.1%}")

        overall = total_enc / total_orig if total_orig > 0 else 1.0
        print(f"  {'总计':<15} {'':>8} "
              f"{total_orig/1024:>9.1f} {total_enc/1024:>11.1f} {overall:>7.1%}")

    print(f"\n  粒度分布: {dict((g.name, c) for g, c in gran_dist.items() if c > 0)}")


def compare_with_fixed_granularity():
    """对比自适应粒度 vs 固定粒度的压缩效果"""
    print("\n" + "=" * 70)
    print("  自适应粒度 vs 固定粒度对比")
    print("=" * 70)

    adaptive_engine = SparseEngine(thresh_l1=0.80, thresh_l2=0.50, cluster_thresh=0.50)
    encoder = SparseEncoder(data_w=16)
    decoder = SparseDecoder()

    sparsities = [0.30, 0.50, 0.70, 0.80, 0.90, 0.95]

    print(f"\n  {'稀疏率':>8} {'自适应':>8} {'固定L1':>8} {'固定L2':>8} {'固定L3':>8} {'自适应vs最优':>14}")
    print("  " + "-" * 60)

    for sp in sparsities:
        # 生成混合模式张量
        tensor = generate_test_tensor(64, 64, sparsity=sp, seed=42)

        # 自适应
        _, enc_adaptive, _ = adaptive_engine.process(tensor)
        comp_adaptive = enc_adaptive.storage_bytes / (tensor.size * 2)

        # 固定L1
        enc_l1 = encoder.encode(tensor, Granularity.ELEMENT)
        comp_l1 = enc_l1.storage_bytes / (tensor.size * 2)

        # 固定L2
        enc_l2 = encoder.encode(tensor, Granularity.BLOCK)
        comp_l2 = enc_l2.storage_bytes / (tensor.size * 2)

        # 固定L3
        enc_l3 = encoder.encode(tensor, Granularity.CHANNEL)
        comp_l3 = enc_l3.storage_bytes / (tensor.size * 2)

        best_fixed = min(comp_l1, comp_l2, comp_l3)
        ratio = comp_adaptive / best_fixed if best_fixed > 0 else 1.0

        print(f"  {sp:>7.0%} {comp_adaptive:>7.1%} {comp_l1:>7.1%} "
              f"{comp_l2:>7.1%} {comp_l3:>7.1%} {ratio:>13.2f}x")


if __name__ == "__main__":
    print("=" * 70)
    print("  自适应多粒度稀疏编码IP核 - 端到端验证")
    print("=" * 70)

    evaluate_on_cnn_layers()
    evaluate_on_transformer_layers()
    compare_with_fixed_granularity()

    print("\n" + "=" * 70)
    print("  端到端验证完成!")
    print("=" * 70)
