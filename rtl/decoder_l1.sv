// ============================================================================
// L1 元素级译码器 - 从坐标列表恢复稀疏张量
// L1 Element-Level Decoder - Recover sparse tensor from coordinate list
// ============================================================================

module decoder_l1 #(
    parameter DATA_W  = 16,
    parameter TENSOR_SIZE = 256
) (
    input  logic                clk,
    input  logic                rst_n,

    // 编码输入
    input  logic [15:0]         nz_row,
    input  logic [15:0]         nz_col,
    input  logic [DATA_W-1:0]   nz_value,
    input  logic [15:0]         nz_count,
    input  logic                decode_start,

    // 译码输出：恢复的稀疏张量
    output logic [DATA_W-1:0]   decoded_data [0:TENSOR_SIZE-1],
    output logic                decode_done
);

    logic [15:0] idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx        <= '0;
            decode_done <= 1'b0;
            for (int i = 0; i < TENSOR_SIZE; i++) begin
                decoded_data[i] <= '0;
            end
        end else if (decode_start) begin
            // 清零输出
            for (int i = 0; i < TENSOR_SIZE; i++) begin
                decoded_data[i] <= '0;
            end
            idx        <= '0;
            decode_done <= 1'b0;
        end else if (idx < nz_count) begin
            // 逐个恢复非零元素
            decoded_data[nz_row * 16 + nz_col] <= nz_value;
            idx <= idx + 1;
            if (idx + 1 >= nz_count) begin
                decode_done <= 1'b1;
            end
        end else begin
            decode_done <= 1'b0;
        end
    end

endmodule
