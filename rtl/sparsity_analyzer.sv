// ============================================================================
// 稀疏感知分析器 - 运行时统计稀疏率和空间聚集度
// Sparsity-Aware Analyzer - Runtime sparsity ratio & clustering statistics
// ============================================================================

module sparsity_analyzer #(
    parameter DATA_W = 16,
    parameter CH     = 64,
    parameter CNT_W  = 32
) (
    input  logic                clk,
    input  logic                rst_n,

    // 数据流输入
    input  logic [CH*DATA_W-1:0] data_in,
    input  logic [CH-1:0]        valid_mask,
    input  logic                 data_valid,
    input  logic                 tensor_last,

    // 统计输出
    output logic [15:0]          sparsity_rate,   // Q8.8
    output logic [15:0]          cluster_score,   // Q8.8
    output logic [CNT_W-1:0]     total_count,
    output logic [CNT_W-1:0]     nonzero_count,
    output logic [CNT_W-1:0]     cluster_count,
    output logic                 stats_valid
);

    // ========== 零值检测 ==========
    logic [CH-1:0] is_nonzero;

    generate
        for (genvar i = 0; i < CH; i++) begin : gen_zero_det
            assign is_nonzero[i] = valid_mask[i] & (data_in[i*DATA_W +: DATA_W] != '0);
        end
    endgenerate

    // ========== 计数器 ==========
    logic [CNT_W-1:0] total_cnt_r;
    logic [CNT_W-1:0] nonzero_cnt_r;
    logic [CNT_W-1:0] cluster_cnt_r;
    logic [CH-1:0]    prev_nonzero;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cnt_r   <= '0;
            nonzero_cnt_r <= '0;
            cluster_cnt_r <= '0;
            prev_nonzero  <= '0;
        end else if (stats_valid) begin
            // 统计输出后清零计数器，为下一个张量做准备
            total_cnt_r   <= '0;
            nonzero_cnt_r <= '0;
            cluster_cnt_r <= '0;
            prev_nonzero  <= '0;
        end else if (data_valid) begin
            total_cnt_r   <= total_cnt_r + $countones(valid_mask);
            nonzero_cnt_r <= nonzero_cnt_r + $countones(is_nonzero);

            // 聚集度：检测从全零行到有非零行的跳变
            if ($countones(is_nonzero & valid_mask) > 0 &&
                $countones(prev_nonzero & valid_mask) == 0) begin
                cluster_cnt_r <= cluster_cnt_r + 1;
            end
            prev_nonzero <= is_nonzero;
        end
    end

    // ========== 张量结束：输出统计 ==========
    logic [CNT_W-1:0] total_snap, nonzero_snap, cluster_snap;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stats_valid   <= 1'b0;
            sparsity_rate <= '0;
            cluster_score <= '0;
            total_snap    <= '0;
            nonzero_snap  <= '0;
            cluster_snap  <= '0;
        end else if (tensor_last && data_valid) begin
            total_snap    <= total_cnt_r + $countones(valid_mask);
            nonzero_snap  <= nonzero_cnt_r + $countones(is_nonzero);
            cluster_snap  <= cluster_cnt_r;
            stats_valid   <= 1'b1;
        end else begin
            stats_valid <= 1'b0;
        end
    end

    // ========== 定点除法：稀疏率计算 ==========
    // sparsity_rate = (total - nonzero) / total * 256 (Q8.8)
    // 使用迭代除法器，避免在always_ff内声明变量
    logic [31:0] dividend_r;
    logic [31:0] divisor_r;
    logic [15:0] quotient_r;
    logic [4:0]  div_step_r;
    logic        div_busy_r;
    logic [31:0] temp_w;

    // 组合逻辑：计算当前步的临时结果
    assign temp_w = dividend_r - (divisor_r << (div_step_r - 1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_busy_r     <= 1'b0;
            div_step_r     <= '0;
            quotient_r     <= '0;
            sparsity_rate  <= '0;
            cluster_score  <= '0;
            total_count    <= '0;
            nonzero_count  <= '0;
            cluster_count  <= '0;
            dividend_r     <= '0;
            divisor_r      <= '0;
        end else if (stats_valid && !div_busy_r) begin
            // 启动除法
            total_count    <= total_snap;
            nonzero_count  <= nonzero_snap;
            cluster_count  <= cluster_snap;

            if (total_snap > 0) begin
                dividend_r <= (total_snap - nonzero_snap) << 8;
                divisor_r  <= total_snap;
                div_step_r <= 5'd16;
                div_busy_r <= 1'b1;
                quotient_r <= '0;
            end else begin
                sparsity_rate <= 16'h0000;
                cluster_score <= 16'h0000;
            end
        end else if (div_busy_r) begin
            if (div_step_r > 0) begin
                if (temp_w[31] == 0) begin
                    dividend_r <= temp_w;
                    quotient_r[div_step_r - 1] <= 1'b1;
                end
                div_step_r <= div_step_r - 1;
            end else begin
                div_busy_r    <= 1'b0;
                sparsity_rate <= quotient_r[15:0];

                // 聚集度近似计算
                if (nonzero_count > 0) begin
                    cluster_score <= (cluster_count << 8) / nonzero_count[15:0];
                end else begin
                    cluster_score <= 16'h0000;
                end
            end
        end
    end

endmodule
