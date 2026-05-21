// ============================================================================
// 粒度决策引擎 - 根据稀疏率和聚集度自适应选择最优编码粒度
// Granularity Decision Engine - Adaptive optimal granularity selection
// ============================================================================

module granularity_decision #(
    parameter Q_FORMAT = 8
) (
    input  logic        clk,
    input  logic        rst_n,

    // 来自分析器的统计
    input  logic [15:0] sparsity_rate,    // Q8.8
    input  logic [15:0] cluster_score,    // Q8.8
    input  logic        stats_valid,

    // 配置寄存器
    input  logic [31:0] cfg_thresh_l1,    // 稀疏率>此值且低聚集→L1
    input  logic [31:0] cfg_thresh_l2,    // 稀疏率>此值→L2候选
    input  logic [31:0] cfg_cluster_thresh, // 聚集度阈值
    input  logic        cfg_force_en,
    input  logic [1:0]  cfg_force_gran,

    // 决策输出
    output logic [1:0]  granularity,      // 00=L1, 01=L2, 10=L3, 11=dense
    output logic        decision_valid,

    // 调试信息
    output logic [7:0]  decision_reason   // 决策原因编码
);

    import sparse_pkg::*;

    // ========== 决策寄存器 ==========
    logic [1:0] gran_r;
    logic       dec_valid_r;
    logic [7:0] reason_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gran_r      <= GRAN_DENSE;
            dec_valid_r <= 1'b0;
            reason_r    <= '0;
        end else if (cfg_force_en) begin
            // 强制模式：直接使用配置的粒度
            gran_r      <= cfg_force_gran;
            dec_valid_r <= 1'b1;
            reason_r    <= 8'hFF;  // 强制模式
        end else if (stats_valid) begin
            dec_valid_r <= 1'b1;

            /*
             * 决策树:
             *   稀疏率 >= thresh_l1 (>80%) && 聚集度低 → L1 元素级
             *   稀疏率 >= thresh_l1 (>80%) && 聚集度高 → L2 块级
             *   稀疏率 >= thresh_l2 (>50%)             → L2 块级
             *   稀疏率 >= 30%                          → L3 通道级
             *   稀疏率 <  30%                          → dense 回退
             */
            if (sparsity_rate >= cfg_thresh_l1[15:0]) begin
                // 高稀疏区
                if (cluster_score < cfg_cluster_thresh[15:0]) begin
                    gran_r   <= GRAN_ELEMENT;
                    reason_r <= 8'h01;  // 高稀疏+低聚集→L1
                end else begin
                    gran_r   <= GRAN_BLOCK;
                    reason_r <= 8'h02;  // 高稀疏+高聚集→L2
                end
            end else if (sparsity_rate >= cfg_thresh_l2[15:0]) begin
                // 中稀疏区
                gran_r   <= GRAN_BLOCK;
                reason_r <= 8'h03;  // 中稀疏→L2
            end else if (sparsity_rate >= (16'd30 << Q_FORMAT) / 16'd100) begin
                // 低稀疏区 (>30%)
                gran_r   <= GRAN_CHANNEL;
                reason_r <= 8'h04;  // 低稀疏→L3
            end else begin
                // 极低稀疏 (<30%)，编码不划算
                gran_r   <= GRAN_DENSE;
                reason_r <= 8'h05;  // 极低稀疏→dense回退
            end
        end else begin
            dec_valid_r <= 1'b0;
        end
    end

    assign granularity    = gran_r;
    assign decision_valid = dec_valid_r;
    assign decision_reason = reason_r;

endmodule
