// ============================================================================
// L2 块级译码器 - 从块位图恢复稀疏块
// L2 Block-Level Decoder - Recover sparse block from block bitmap
// ============================================================================

module decoder_l2 #(
    parameter DATA_W   = 16,
    parameter BLK_H    = 4,
    parameter BLK_W    = 4,
    parameter BLK_SIZE = BLK_H * BLK_W
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // 编码输入
    input  logic [BLK_SIZE-1:0]         block_bitmap,
    input  logic [BLK_SIZE*DATA_W-1:0]  nz_values,
    input  logic [7:0]                  nz_count,
    input  logic                        decode_start,

    // 译码输出
    output logic [BLK_SIZE*DATA_W-1:0]  decoded_block,
    output logic                        decode_done
);

    // ========== 流水线第1级：锁存输入 ==========
    logic [BLK_SIZE-1:0]        bitmap_r;
    logic [BLK_SIZE*DATA_W-1:0] nz_vals_r;
    logic                       stage1_valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bitmap_r       <= '0;
            nz_vals_r      <= '0;
            stage1_valid_r <= 1'b0;
        end else begin
            stage1_valid_r <= decode_start;
            if (decode_start) begin
                bitmap_r  <= block_bitmap;
                nz_vals_r <= nz_values;
            end
        end
    end

    // ========== 流水线第2级：从位图恢复块 (组合+寄存) ==========
    logic [BLK_SIZE*DATA_W-1:0] decoded_w;

    always_comb begin
        decoded_w = '0;
        for (int i = 0, int j = 0; i < BLK_SIZE; i++) begin
            if (bitmap_r[i]) begin
                decoded_w[i*DATA_W +: DATA_W] = nz_vals_r[j*DATA_W +: DATA_W];
                j = j + 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decoded_block <= '0;
            decode_done   <= 1'b0;
        end else if (stage1_valid_r) begin
            decoded_block <= decoded_w;
            decode_done   <= 1'b1;
        end else begin
            decode_done <= 1'b0;
        end
    end

endmodule
