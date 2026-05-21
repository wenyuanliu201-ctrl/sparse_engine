#!/usr/bin/env python3
"""
自适应多粒度稀疏编码IP核 - Python参考模型
Adaptive Multi-Granularity Sparse Coding Engine - Reference Model

用于:
  1. 生成测试向量供RTL仿真比对
  2. 验证编码-译码往返正确性
  3. 端到端模型级稀疏加速评估
"""

import numpy as np
from dataclasses import dataclass
from typing import List, Tuple, Optional
from enum import IntEnum


# ============================================================================
# 枚举与数据结构
# ============================================================================

class Granularity(IntEnum):
    ELEMENT = 0   # L1: 元素级
    BLOCK   = 1   # L2: 块级
    CHANNEL = 2   # L3: 通道级
    DENSE   = 3   # 稠密回退


@dataclass
class AnalyzerStats:
    sparsity_rate: float    # 0.0 ~ 1.0
    cluster_score: float    # 0.0 ~ 1.0+
    total_count: int
    nonzero_count: int
    cluster_count: int


@dataclass
class EncodedResult:
    granularity: Granularity
    bitmap: Optional[np.ndarray]       # L2块位图
    coordinates: Optional[List[Tuple[int, int]]]  # L1坐标列表
    channel_mask: Optional[np.ndarray] # L3通道掩码
    nz_values: np.ndarray              # 非零值
    nz_count: int
    shape: Tuple[int, ...]
    storage_bytes: int                 # 编码后存储量(bytes)


# ============================================================================
# 稀疏感知分析器
# ============================================================================

class SparsityAnalyzer:
    """运行时稀疏特性分析"""

    def __init__(self, blk_h=4, blk_w=4):
        self.blk_h = blk_h
        self.blk_w = blk_w

    def analyze(self, tensor: np.ndarray) -> AnalyzerStats:
        total = tensor.size
        nonzero = int(np.count_nonzero(tensor))
        sparsity = 1.0 - nonzero / total if total > 0 else 0.0

        # 聚集度：非零块数 / 理论最大非零块数
        if tensor.ndim >= 2:
            r, c = tensor.shape[:2]
            n_blocks = 0
            n_nz_blocks = 0
            for i in range(0, r, self.blk_h):
                for j in range(0, c, self.blk_w):
                    block = tensor[i:i+self.blk_h, j:j+self.blk_w]
                    if block.size > 0:
                        n_blocks += 1
                        if np.any(block != 0):
                            n_nz_blocks += 1
            # 聚集度 = 非零块数 / (非零元素数/块大小)
            max_possible_blocks = nonzero / (self.blk_h * self.blk_w)
            cluster = n_nz_blocks / max(1, max_possible_blocks)
        else:
            cluster = 0.0

        return AnalyzerStats(
            sparsity_rate=sparsity,
            cluster_score=cluster,
            total_count=total,
            nonzero_count=nonzero,
            cluster_count=int(cluster * nonzero / (self.blk_h * self.blk_w))
        )


# ============================================================================
# 粒度决策引擎
# ============================================================================

class GranularityDecision:
    """自适应粒度决策"""

    def __init__(self,
                 thresh_l1: float = 0.80,
                 thresh_l2: float = 0.50,
                 cluster_thresh: float = 0.50):
        self.thresh_l1 = thresh_l1
        self.thresh_l2 = thresh_l2
        self.cluster_thresh = cluster_thresh

    def decide(self, stats: AnalyzerStats,
               force: Optional[Granularity] = None) -> Granularity:
        if force is not None:
            return force

        sp = stats.sparsity_rate
        cs = stats.cluster_score

        if sp >= self.thresh_l1:
            if cs < self.cluster_thresh:
                return Granularity.ELEMENT  # 高稀疏+低聚集→L1
            else:
                return Granularity.BLOCK    # 高稀疏+高聚集→L2
        elif sp >= self.thresh_l2:
            return Granularity.BLOCK        # 中稀疏→L2
        elif sp >= 0.30:
            return Granularity.CHANNEL      # 低稀疏→L3
        else:
            return Granularity.DENSE        # 极低稀疏→稠密回退


# ============================================================================
# 编码器
# ============================================================================

class SparseEncoder:
    """多粒度稀疏编码器"""

    def __init__(self, data_w: int = 16, blk_h: int = 4, blk_w: int = 4):
        self.data_w = data_w
        self.blk_h = blk_h
        self.blk_w = blk_w

    def encode(self, tensor: np.ndarray,
               granularity: Granularity) -> EncodedResult:
        if granularity == Granularity.ELEMENT:
            return self._encode_l1(tensor)
        elif granularity == Granularity.BLOCK:
            return self._encode_l2(tensor)
        elif granularity == Granularity.CHANNEL:
            return self._encode_l3(tensor)
        else:
            return self._encode_dense(tensor)

    def _encode_l1(self, tensor: np.ndarray) -> EncodedResult:
        """L1元素级编码：坐标列表 + 非零值"""
        flat = tensor.flatten()
        nz_mask = flat != 0
        nz_indices = np.where(nz_mask)[0]
        nz_values = flat[nz_indices]

        # 坐标转换（2D索引）
        coords = []
        for idx in nz_indices:
            if tensor.ndim >= 2:
                r, c = divmod(int(idx), tensor.shape[1])
                coords.append((r, c))
            else:
                coords.append((0, int(idx)))

        # 存储量：每个非零元素 = 坐标(2*16bit) + 值(16bit) = 6 bytes
        storage = len(nz_values) * 6

        return EncodedResult(
            granularity=Granularity.ELEMENT,
            bitmap=None,
            coordinates=coords,
            channel_mask=None,
            nz_values=nz_values,
            nz_count=len(nz_values),
            shape=tensor.shape,
            storage_bytes=storage
        )

    def _encode_l2(self, tensor: np.ndarray) -> EncodedResult:
        """L2块级编码：块位图 + 非零值紧凑排列"""
        if tensor.ndim < 2:
            tensor = tensor.reshape(1, -1)

        rows, cols = tensor.shape[:2]
        blk_size = self.blk_h * self.blk_w
        all_nz_values = []
        all_bitmaps = []
        n_blocks = 0

        for i in range(0, rows, self.blk_h):
            for j in range(0, cols, self.blk_w):
                block = tensor[i:i+self.blk_h, j:j+self.blk_w]
                # 补零到块大小
                padded = np.zeros((self.blk_h, self.blk_w))
                padded[:block.shape[0], :block.shape[1]] = block
                flat = padded.flatten()

                bitmap = (flat != 0).astype(np.uint8)
                nz_vals = flat[bitmap != 0]
                all_bitmaps.append(bitmap)
                all_nz_values.extend(nz_vals)
                n_blocks += 1

        # 存储量：位图(n_blocks * blk_size bits) + 非零值
        bitmap_bytes = n_blocks * blk_size // 8
        value_bytes = len(all_nz_values) * (self.data_w // 8)
        storage = bitmap_bytes + value_bytes

        return EncodedResult(
            granularity=Granularity.BLOCK,
            bitmap=np.array(all_bitmaps),
            coordinates=None,
            channel_mask=None,
            nz_values=np.array(all_nz_values, dtype=np.float32),
            nz_count=len(all_nz_values),
            shape=tensor.shape,
            storage_bytes=storage
        )

    def _encode_l3(self, tensor: np.ndarray) -> EncodedResult:
        """L3通道级编码：通道掩码 + 非零通道数据"""
        if tensor.ndim < 3:
            # 自动reshape: (C, H, W) 或 (C, N)
            if tensor.ndim == 2:
                n_ch = tensor.shape[0]
                tensor = tensor.reshape(n_ch, 1, -1)
            else:
                tensor = tensor.reshape(1, 1, -1)

        n_ch = tensor.shape[0]
        ch_mask = np.any(tensor != 0, axis=tuple(range(1, tensor.ndim)))
        ch_mask = ch_mask.astype(np.uint8)

        nz_channel_data = []
        for c in range(n_ch):
            if ch_mask[c]:
                nz_channel_data.append(tensor[c].flatten())

        # 存储量：掩码(n_ch bits) + 非零通道数据
        mask_bytes = n_ch // 8
        elem_per_ch = int(np.prod(tensor.shape[1:]))
        value_bytes = int(ch_mask.sum()) * elem_per_ch * (self.data_w // 8)
        storage = mask_bytes + value_bytes

        return EncodedResult(
            granularity=Granularity.CHANNEL,
            bitmap=None,
            coordinates=None,
            channel_mask=ch_mask,
            nz_values=np.concatenate(nz_channel_data) if nz_channel_data else np.array([]),
            nz_count=int(ch_mask.sum()),
            shape=tensor.shape,
            storage_bytes=storage
        )

    def _encode_dense(self, tensor: np.ndarray) -> EncodedResult:
        """稠密回退：无编码开销"""
        storage = tensor.size * (self.data_w // 8)
        return EncodedResult(
            granularity=Granularity.DENSE,
            bitmap=None,
            coordinates=None,
            channel_mask=None,
            nz_values=tensor.flatten(),
            nz_count=tensor.size,
            shape=tensor.shape,
            storage_bytes=storage
        )


# ============================================================================
# 译码器
# ============================================================================

class SparseDecoder:
    """多粒度稀疏译码器"""

    def __init__(self, blk_h=4, blk_w=4):
        self.blk_h = blk_h
        self.blk_w = blk_w

    def decode(self, encoded: EncodedResult) -> np.ndarray:
        if encoded.granularity == Granularity.ELEMENT:
            return self._decode_l1(encoded)
        elif encoded.granularity == Granularity.BLOCK:
            return self._decode_l2(encoded)
        elif encoded.granularity == Granularity.CHANNEL:
            return self._decode_l3(encoded)
        else:
            return encoded.nz_values.reshape(encoded.shape)

    def _decode_l1(self, encoded: EncodedResult) -> np.ndarray:
        result = np.zeros(encoded.shape)
        for idx, (r, c) in enumerate(encoded.coordinates):
            result[r, c] = encoded.nz_values[idx]
        return result

    def _decode_l2(self, encoded: EncodedResult) -> np.ndarray:
        result = np.zeros(encoded.shape)
        rows, cols = encoded.shape[:2]
        val_idx = 0
        blk_idx = 0
        blk_size = self.blk_h * self.blk_w

        for i in range(0, rows, self.blk_h):
            for j in range(0, cols, self.blk_w):
                bitmap = encoded.bitmap[blk_idx]
                for k in range(blk_size):
                    if bitmap[k]:
                        bi = k // self.blk_w
                        bj = k % self.blk_w
                        ri, cj = i + bi, j + bj
                        if ri < rows and cj < cols and val_idx < len(encoded.nz_values):
                            result[ri, cj] = encoded.nz_values[val_idx]
                            val_idx += 1
                blk_idx += 1
        return result

    def _decode_l3(self, encoded: EncodedResult) -> np.ndarray:
        result = np.zeros(encoded.shape)
        val_idx = 0
        n_ch = encoded.shape[0]
        elem_per_ch = int(np.prod(encoded.shape[1:]))

        for c in range(n_ch):
            if encoded.channel_mask[c]:
                result[c] = encoded.nz_values[val_idx:val_idx+elem_per_ch].reshape(encoded.shape[1:])
                val_idx += elem_per_ch
        return result


# ============================================================================
# 端到端流水线
# ============================================================================

class SparseEngine:
    """自适应多粒度稀疏编码引擎 - 完整流水线"""

    def __init__(self,
                 thresh_l1=0.80, thresh_l2=0.50, cluster_thresh=0.50,
                 blk_h=4, blk_w=4, data_w=16):
        self.analyzer = SparsityAnalyzer(blk_h, blk_w)
        self.decision = GranularityDecision(thresh_l1, thresh_l2, cluster_thresh)
        self.encoder  = SparseEncoder(data_w, blk_h, blk_w)
        self.decoder  = SparseDecoder(blk_h, blk_w)

        # 统计
        self.granularity_stats = {g: 0 for g in Granularity}

    def process(self, tensor: np.ndarray,
                force_gran: Optional[Granularity] = None) -> Tuple[np.ndarray, EncodedResult]:
        """完整流水线：分析→决策→编码→译码→比对"""
        # 1. 分析
        stats = self.analyzer.analyze(tensor)

        # 2. 决策
        gran = self.decision.decide(stats, force=force_gran)
        self.granularity_stats[gran] += 1

        # 3. 编码
        encoded = self.encoder.encode(tensor, gran)

        # 4. 译码
        decoded = self.decoder.decode(encoded)

        return decoded, encoded, stats

    def roundtrip_test(self, tensor: np.ndarray,
                       force_gran: Optional[Granularity] = None) -> bool:
        """往返正确性测试：Decode(Encode(x)) == x"""
        decoded, encoded, stats = self.process(tensor, force_gran)
        return np.allclose(tensor, decoded, atol=1e-6)


# ============================================================================
# 测试向量生成器
# ============================================================================

def generate_test_tensor(rows: int, cols: int,
                         sparsity: float = 0.5,
                         clustered: bool = False,
                         seed: Optional[int] = None) -> np.ndarray:
    """生成测试用稀疏张量"""
    if seed is not None:
        np.random.seed(seed)

    tensor = np.random.randn(rows, cols)
    if clustered:
        # 高聚集：前N行全非零，其余全零
        n_keep = max(1, int(rows * (1 - sparsity)))
        mask = np.zeros((rows, cols))
        mask[:n_keep, :] = 1
    else:
        # 随机分布
        mask = (np.random.rand(rows, cols) > sparsity).astype(float)

    return tensor * mask


def generate_sv_test_vector(tensor: np.ndarray, data_w: int = 16) -> str:
    """生成SystemVerilog测试向量"""
    flat = tensor.flatten()
    n = len(flat)

    lines = []
    lines.append(f"// Test vector: shape={tensor.shape}, sparsity={1.0 - np.count_nonzero(tensor)/tensor.size:.1%}")
    lines.append(f"// Format: {n} x {data_w}bit values")

    # 生成位向量
    hex_w = data_w // 4
    vec = ""
    for i, v in enumerate(flat):
        # 量化为16bit整数
        if v == 0:
            hex_val = "0" * hex_w
        else:
            int_val = int(v * 256) & ((1 << data_w) - 1)
            hex_val = f"{int_val:0{hex_w}x}"
        vec = hex_val + vec  # 大端排列

    lines.append(f"data_in = {n*data_w}'h{vec};")
    return "\n".join(lines)


# ============================================================================
// 主程序
// ============================================================================

if __name__ == "__main__":
    print("=" * 60)
    print("  自适应多粒度稀疏编码引擎 - Python参考模型验证")
    print("=" * 60)

    engine = SparseEngine(thresh_l1=0.80, thresh_l2=0.50, cluster_thresh=0.50)

    # ===== 测试1：各粒度往返正确性 =====
    print("\n[TEST 1] 各粒度往返正确性")
    all_pass = True

    for gran in Granularity:
        name = gran.name
        for trial in range(20):
            sparsity = np.random.uniform(0.1, 0.95)
            tensor = generate_test_tensor(16, 16, sparsity=sparsity, seed=trial)
            ok = engine.roundtrip_test(tensor, force_gran=gran)
            if not ok:
                print(f"  FAIL: {name} trial {trial}")
                all_pass = False
        print(f"  {name}: 20次往返测试 {'PASS' if all_pass else 'FAIL'}")
        all_pass = True

    # ===== 测试2：自适应决策 =====
    print("\n[TEST 2] 自适应粒度决策")
    test_cases = [
        (0.90, False, "90%稀疏+分散", Granularity.ELEMENT),
        (0.90, True,  "90%稀疏+聚集", Granularity.BLOCK),
        (0.60, False, "60%稀疏",      Granularity.BLOCK),
        (0.40, False, "40%稀疏",      Granularity.CHANNEL),
        (0.15, False, "15%稀疏",      Granularity.DENSE),
    ]

    for sp, clustered, desc, expected in test_cases:
        tensor = generate_test_tensor(64, 64, sparsity=sp, clustered=clustered, seed=42)
        stats = engine.analyzer.analyze(tensor)
        gran = engine.decision.decide(stats)
        result = "PASS" if gran == expected else "FAIL"
        print(f"  {desc}: sparsity={stats.sparsity_rate:.1%} "
              f"cluster={stats.cluster_score:.2f} → {gran.name} "
              f"(期望{expected.name}) [{result}]")

    # ===== 测试3：压缩率评估 =====
    print("\n[TEST 3] 不同稀疏率下的压缩率")
    print(f"  {'稀疏率':>8} {'粒度':>10} {'压缩率':>8} {'节省':>8}")
    print("  " + "-" * 40)

    for sp in [0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.30, 0.20]:
        tensor = generate_test_tensor(64, 64, sparsity=sp, seed=100)
        decoded, encoded, stats = engine.process(tensor)
        original_bytes = tensor.size * 2  # 16bit = 2 bytes
        compression = encoded.storage_bytes / original_bytes
        saving = 1.0 - compression
        print(f"  {sp:>7.0%} {encoded.granularity.name:>10} "
              f"{compression:>7.1%} {saving:>7.1%}")

    # ===== 测试4：生成SV测试向量 =====
    print("\n[TEST 4] 生成SV测试向量示例")
    tensor = generate_test_tensor(4, 4, sparsity=0.5, seed=42)
    print(generate_sv_test_vector(tensor))

    print("\n" + "=" * 60)
    print("  验证完成!")
    print("=" * 60)
