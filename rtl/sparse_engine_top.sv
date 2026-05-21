// ============================================================================
// 自适应多粒度稀疏编码IP核 - 顶层模块
// Adaptive Multi-Granularity Sparse Coding Engine - Top Level
// ============================================================================

module sparse_engine_top #(
    parameter DATA_W   = 16,
    parameter CH       = 64,
    parameter BLK_H    = 4,
    parameter BLK_W    = 4,
    parameter CNT_W    = 32,
    parameter TENSOR_R = 64,     // 张量行数
    parameter TENSOR_C = 64      // 张量列数
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // ========== AXI-Lite 配置接口 ==========
    input  logic [31:0]                 cfg_wdata,
    input  logic [7:0]                  cfg_addr,
    input  logic                        cfg_valid,

    // ========== 数据流输入 ==========
    input  logic [CH*DATA_W-1:0]        data_in,
    input  logic [CH-1:0]               valid_mask,
    input  logic                        data_valid,
    input  logic                        tensor_last,

    // ========== 编码输出 ==========
    output logic [1:0]                  out_granularity,
    output logic [7:0]                  out_nz_count,
    output logic [BLK_H*BLK_W*DATA_W-1:0] out_encoded_data,
    output logic [BLK_H*BLK_W-1:0]     out_bitmap,
    output logic                        out_valid,

    // ========== 译码输入 (回读模式) ==========
    input  logic [1:0]                  dec_granularity,
    input  logic [BLK_H*BLK_W*DATA_W-1:0] dec_encoded_data,
    input  logic [BLK_H*BLK_W-1:0]     dec_bitmap,
    input  logic [7:0]                  dec_nz_count,
    input  logic                        dec_start,

    // ========== 译码输出 ==========
    output logic [BLK_H*BLK_W*DATA_W-1:0] dec_output,
    output logic                        dec_done,

    // ========== 状态 ==========
    output logic [1:0]                  current_granularity,
    output logic [15:0]                 current_sparsity,
    output logic [15:0]                 current_cluster,
    output logic [7:0]                  decision_reason,
    output logic                        engine_busy
);

    import sparse_pkg::*;

    // ========== 配置寄存器 ==========
    logic [31:0] cfg_thresh_l1;
    logic [31:0] cfg_thresh_l2;
    logic [31:0] cfg_cluster_thresh;
    logic [3:0]  cfg_block_size;
    logic        cfg_force_en;
    logic [1:0]  cfg_force_gran;
    logic        cfg_engine_en;

    // 配置寄存器写入
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_thresh_l1      <= 32'h0080_0000;  // 80% in Q8.24
            cfg_thresh_l2      <= 32'h0050_0000;  // 50% in Q8.24
            cfg_cluster_thresh <= 32'h0080_0000;  // 0.5 in Q8.24
            cfg_block_size     <= 4'd1;            // 4x4
            cfg_force_en       <= 1'b0;
            cfg_force_gran     <= 2'b00;
            cfg_engine_en      <= 1'b1;
        end else if (cfg_valid) begin
            case (cfg_addr)
                8'h00: cfg_thresh_l1      <= cfg_wdata;
                8'h04: cfg_thresh_l2      <= cfg_wdata;
                8'h08: cfg_cluster_thresh <= cfg_wdata;
                8'h0C: cfg_block_size     <= cfg_wdata[3:0];
                8'h10: cfg_force_en       <= cfg_wdata[0];
                8'h14: cfg_force_gran     <= cfg_wdata[1:0];
                8'h18: cfg_engine_en      <= cfg_wdata[0];
                default: ;
            endcase
        end
    end

    // ========== 稀疏感知分析器 ==========
    logic [15:0]  ana_sparsity_rate;
    logic [15:0]  ana_cluster_score;
    logic [CNT_W-1:0] ana_total, ana_nonzero, ana_cluster;
    logic         ana_stats_valid;

    sparsity_analyzer #(
        .DATA_W (DATA_W),
        .CH     (CH),
        .CNT_W  (CNT_W)
    ) u_analyzer (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .valid_mask    (valid_mask),
        .data_valid    (data_valid),
        .tensor_last   (tensor_last),
        .sparsity_rate (ana_sparsity_rate),
        .cluster_score (ana_cluster_score),
        .total_count   (ana_total),
        .nonzero_count (ana_nonzero),
        .cluster_count (ana_cluster),
        .stats_valid   (ana_stats_valid)
    );

    // ========== 粒度决策引擎 ==========
    logic [1:0]  dec_gran_out;
    logic        dec_valid_out;
    logic [7:0]  dec_reason_out;

    granularity_decision #(
        .Q_FORMAT (8)
    ) u_decision (
        .clk               (clk),
        .rst_n             (rst_n),
        .sparsity_rate     (ana_sparsity_rate),
        .cluster_score     (ana_cluster_score),
        .stats_valid       (ana_stats_valid),
        .cfg_thresh_l1     (cfg_thresh_l1),
        .cfg_thresh_l2     (cfg_thresh_l2),
        .cfg_cluster_thresh(cfg_cluster_thresh),
        .cfg_force_en      (cfg_force_en),
        .cfg_force_gran    (cfg_force_gran),
        .granularity       (dec_gran_out),
        .decision_valid    (dec_valid_out),
        .decision_reason   (dec_reason_out)
    );

    // ========== 当前粒度锁存 ==========
    logic [1:0] current_gran_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_gran_r <= GRAN_DENSE;
        else if (dec_valid_out)
            current_gran_r <= dec_gran_out;
    end

    // ========== L2 块级编码器 ==========
    localparam BLK_SIZE = BLK_H * BLK_W;

    logic [BLK_SIZE-1:0]        l2_bitmap;
    logic [BLK_SIZE*DATA_W-1:0] l2_nz_values;
    logic [7:0]                 l2_nz_count;
    logic                       l2_encoded_valid;

    encoder_l2 #(
        .DATA_W   (DATA_W),
        .BLK_H    (BLK_H),
        .BLK_W    (BLK_W)
    ) u_encoder_l2 (
        .clk           (clk),
        .rst_n         (rst_n),
        .block_in      (data_in[BLK_SIZE*DATA_W-1:0]),
        .block_valid   (data_valid && current_gran_r == GRAN_BLOCK),
        .block_bitmap  (l2_bitmap),
        .nz_values     (l2_nz_values),
        .nz_count      (l2_nz_count),
        .encoded_valid (l2_encoded_valid)
    );

    // ========== L2 块级译码器 ==========
    logic [BLK_SIZE*DATA_W-1:0] l2_decoded;
    logic                       l2_decode_done;

    decoder_l2 #(
        .DATA_W   (DATA_W),
        .BLK_H    (BLK_H),
        .BLK_W    (BLK_W)
    ) u_decoder_l2 (
        .clk           (clk),
        .rst_n         (rst_n),
        .block_bitmap  (dec_bitmap),
        .nz_values     (dec_encoded_data),
        .nz_count      (dec_nz_count),
        .decode_start  (dec_start && dec_granularity == GRAN_BLOCK),
        .decoded_block (l2_decoded),
        .decode_done   (l2_decode_done)
    );

    // ========== 输出选择 ==========
    // 编码输出
    assign out_granularity = current_gran_r;
    assign out_nz_count    = l2_nz_count;
    assign out_encoded_data = l2_nz_values;
    assign out_bitmap      = l2_bitmap;
    assign out_valid       = l2_encoded_valid;

    // 译码输出
    assign dec_output = l2_decoded;
    assign dec_done   = l2_decode_done;

    // 状态输出
    assign current_granularity = current_gran_r;
    assign current_sparsity    = ana_sparsity_rate;
    assign current_cluster     = ana_cluster_score;
    assign decision_reason     = dec_reason_out;
    assign engine_busy         = data_valid || ana_stats_valid || dec_valid_out;

endmodule
