// ============================================================================
// L3 通道级编码器 - 通道掩码 + 非零通道数据
// L3 Channel-Level Encoder - Channel mask + nonzero channel data
// ============================================================================

module encoder_l3 #(
    parameter DATA_W  = 16,
    parameter CH      = 64,
    parameter ELEM_CH = 16
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // 输入：CH个通道
    input  logic [CH*ELEM_CH*DATA_W-1:0] channel_in,
    input  logic                         channel_valid,

    // 编码输出
    output logic [CH-1:0]               channel_mask,
    output logic [CH*ELEM_CH*DATA_W-1:0] nz_channel_data,
    output logic [7:0]                  nz_channel_count,
    output logic                        encoded_valid
);

    // ========== 通道零值检测 + 掩码生成 (组合) ==========
    logic [CH-1:0] ch_nonzero;
    logic [7:0]    nz_ch_cnt_w;

    always_comb begin
        ch_nonzero = '0;
        nz_ch_cnt_w = '0;
        for (int c = 0; c < CH; c++) begin
            for (int e = 0; e < ELEM_CH; e++) begin
                if (channel_in[(c*ELEM_CH+e)*DATA_W +: DATA_W] != '0)
                    ch_nonzero[c] = 1'b1;
            end
            if (ch_nonzero[c])
                nz_ch_cnt_w = nz_ch_cnt_w + 1;
        end
    end

    // ========== 紧凑排列 (组合) ==========
    logic [CH*ELEM_CH*DATA_W-1:0] nz_data_w;

    always_comb begin
        nz_data_w = '0;
        for (int c = 0, int j = 0; c < CH; c++) begin
            if (ch_nonzero[c]) begin
                nz_data_w[j*ELEM_CH*DATA_W +: ELEM_CH*DATA_W] =
                    channel_in[c*ELEM_CH*DATA_W +: ELEM_CH*DATA_W];
                j = j + 1;
            end
        end
    end

    // ========== 寄存输出 ==========
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_mask     <= '0;
            nz_channel_data  <= '0;
            nz_channel_count <= '0;
            encoded_valid    <= 1'b0;
        end else if (channel_valid) begin
            channel_mask     <= ch_nonzero;
            nz_channel_data  <= nz_data_w;
            nz_channel_count <= nz_ch_cnt_w;
            encoded_valid    <= 1'b1;
        end else begin
            encoded_valid <= 1'b0;
        end
    end

endmodule
