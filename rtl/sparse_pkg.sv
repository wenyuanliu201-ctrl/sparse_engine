// ============================================================================
// 自适应多粒度稀疏编码IP核 - 公共定义
// Adaptive Multi-Granularity Sparse Coding Engine - Common Definitions
// ============================================================================

package sparse_pkg;

    // ========== 稀疏粒度枚举 ==========
    typedef enum logic [1:0] {
        GRAN_ELEMENT  = 2'b00,  // L1: 元素级稀疏
        GRAN_BLOCK    = 2'b01,  // L2: 块级稀疏
        GRAN_CHANNEL  = 2'b10,  // L3: 通道级稀疏
        GRAN_DENSE    = 2'b11   // 稠密回退
    } granularity_e;

    // ========== 配置寄存器结构 ==========
    typedef struct packed {
        logic [31:0] thresh_l1;         // L1选择稀疏率阈值 (Q8.24)
        logic [31:0] thresh_l2;         // L2选择稀疏率阈值
        logic [31:0] cluster_thresh;    // 聚集度阈值
        logic [3:0]  block_size;        // L2块大小: 0=2x2, 1=4x4, 2=8x8
        logic [15:0] update_period;     // 自适应更新周期(batches)
        logic        force_enable;      // 强制粒度使能
        logic [1:0]  force_granularity; // 强制粒度值
        logic        engine_enable;     // IP核使能
        logic [15:0] reserved;          // 保留
    } cfg_reg_t;

    // ========== 统计结果结构 ==========
    typedef struct packed {
        logic [15:0] sparsity_rate;   // 稀疏率 Q8.8
        logic [15:0] cluster_score;   // 聚集度 Q8.8
        logic [31:0] total_count;     // 总元素数
        logic [31:0] nonzero_count;   // 非零元素数
        logic [31:0] cluster_count;   // 聚集块数
        logic        valid;           // 统计有效
    } stats_t;

    // ========== 编码包格式 ==========
    typedef struct packed {
        logic [1:0]   granularity;  // 粒度标识
        logic [13:0]  rows;         // 行数
        logic [15:0]  cols;         // 列数
        logic [15:0]  channels;     // 通道数
        logic [7:0]   nz_count;     // 非零元素数
        logic [7:0]   index_len;    // 索引长度(bytes)
        logic [127:0] index_data;   // 索引/位图数据
        logic [255:0] value_data;   // 非零值数据
        logic         valid;        // 包有效
        logic         last;         // 包结束
    } encoded_pkt_t;

    // ========== 参数常量 ==========
    localparam DATA_W     = 16;     // 数据位宽
    localparam CH         = 64;     // 通道数
    localparam BLK_H      = 4;      // 默认块高度
    localparam BLK_W      = 4;      // 默认块宽度
    localparam CNT_W      = 32;     // 计数器位宽
    localparam MAX_PKT_W  = 512;    // 最大包宽度
    localparam Q_FORMAT   = 8;      // 定点小数位数

endpackage
