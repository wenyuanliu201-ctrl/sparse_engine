// ============================================================================
// L2 块级编码器 - 块位图 + 非零值紧凑排列
// L2 Block-Level Encoder - Block bitmap + compact nonzero values
// ============================================================================

module encoder_l2 #(
    parameter DATA_W   = 16,
    parameter BLK_H    = 4,
    parameter BLK_W    = 4,
    parameter BLK_SIZE = BLK_H * BLK_W
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // 块输入
    input  logic [BLK_SIZE*DATA_W-1:0]  block_in,
    input  logic                        block_valid,

    // 编码输出
    output logic [BLK_SIZE-1:0]         block_bitmap,
    output logic [BLK_SIZE*DATA_W-1:0]  nz_values,
    output logic [7:0]                  nz_count,
    output logic                        encoded_valid
);

    // ========== 流水线第1级：生成位图 (组合) ==========
    logic [BLK_SIZE-1:0]        bitmap_w;
    logic [BLK_SIZE*DATA_W-1:0] block_r;
    logic                       stage1_valid_r;
    logic [7:0]                 nz_cnt_w;

    always_comb begin
        bitmap_w = '0;
        nz_cnt_w = '0;
        for (int i = 0; i < BLK_SIZE; i++) begin
            bitmap_w[i] = (block_in[i*DATA_W +: DATA_W] != '0);
            if (bitmap_w[i])
                nz_cnt_w = nz_cnt_w + 1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_r        <= '0;
            stage1_valid_r <= 1'b0;
        end else begin
            stage1_valid_r <= block_valid;
            if (block_valid)
                block_r <= block_in;
        end
    end

    // ========== 流水线第2级：紧凑排列非零值 (组合+寄存) ==========
    logic [BLK_SIZE*DATA_W-1:0] nz_vals_w;

    always_comb begin
        nz_vals_w = '0;
        for (int i = 0, int j = 0; i < BLK_SIZE; i++) begin
            if (bitmap_w[i]) begin
                nz_vals_w[j*DATA_W +: DATA_W] = block_r[i*DATA_W +: DATA_W];
                j = j + 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_bitmap  <= '0;
            nz_values     <= '0;
            nz_count      <= '0;
            encoded_valid <= 1'b0;
        end else if (stage1_valid_r) begin
            block_bitmap  <= bitmap_w;
            nz_values     <= nz_vals_w;
            nz_count      <= nz_cnt_w;
            encoded_valid <= 1'b1;
        end else begin
            encoded_valid <= 1'b0;
        end
    end

endmodule
