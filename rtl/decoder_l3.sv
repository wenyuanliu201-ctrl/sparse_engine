// ============================================================================
// L3 通道级译码器 - 从通道掩码恢复稀疏通道
// L3 Channel-Level Decoder - Recover sparse channels from channel mask
// ============================================================================

module decoder_l3 #(
    parameter DATA_W  = 16,
    parameter CH      = 64,
    parameter ELEM_CH = 16
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // 编码输入
    input  logic [CH-1:0]               channel_mask,
    input  logic [CH*ELEM_CH*DATA_W-1:0] nz_channel_data,
    input  logic [7:0]                  nz_channel_count,
    input  logic                        decode_start,

    // 译码输出
    output logic [CH*ELEM_CH*DATA_W-1:0] decoded_channels,
    output logic                         decode_done
);

    // ========== 流水线第1级：锁存 ==========
    logic [CH-1:0]                mask_r;
    logic [CH*ELEM_CH*DATA_W-1:0] nz_data_r;
    logic                         stage1_valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_r        <= '0;
            nz_data_r     <= '0;
            stage1_valid_r <= 1'b0;
        end else begin
            stage1_valid_r <= decode_start;
            if (decode_start) begin
                mask_r    <= channel_mask;
                nz_data_r <= nz_channel_data;
            end
        end
    end

    // ========== 流水线第2级：恢复 (组合+寄存) ==========
    logic [CH*ELEM_CH*DATA_W-1:0] decoded_w;

    always_comb begin
        decoded_w = '0;
        for (int c = 0, int j = 0; c < CH; c++) begin
            if (mask_r[c]) begin
                decoded_w[c*ELEM_CH*DATA_W +: ELEM_CH*DATA_W] =
                    nz_data_r[j*ELEM_CH*DATA_W +: ELEM_CH*DATA_W];
                j = j + 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decoded_channels <= '0;
            decode_done      <= 1'b0;
        end else if (stage1_valid_r) begin
            decoded_channels <= decoded_w;
            decode_done      <= 1'b1;
        end else begin
            decode_done <= 1'b0;
        end
    end

endmodule
