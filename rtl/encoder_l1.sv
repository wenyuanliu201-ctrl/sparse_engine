// ============================================================================
// L1 元素级编码器 - 坐标列表 + 非零值紧凑排列
// L1 Element-Level Encoder - Coordinate list + compact nonzero values
// ============================================================================

module encoder_l1 #(
    parameter DATA_W = 16,
    parameter MAX_NZ = 256
) (
    input  logic                clk,
    input  logic                rst_n,

    // 输入数据流
    input  logic [DATA_W-1:0]   data_in,
    input  logic                data_valid,
    input  logic [15:0]         row_idx,
    input  logic [15:0]         col_idx,
    input  logic                tensor_last,

    // 编码输出
    output logic [15:0]         nz_row    [MAX_NZ-1:0],
    output logic [15:0]         nz_col    [MAX_NZ-1:0],
    output logic [DATA_W-1:0]   nz_values [MAX_NZ-1:0],
    output logic [15:0]         nz_count,
    output logic                encoded_valid
);

    logic [15:0] cnt_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_r         <= '0;
            encoded_valid <= 1'b0;
        end else if (tensor_last && data_valid) begin
            nz_count      <= cnt_r;
            encoded_valid <= 1'b1;
        end else if (data_valid) begin
            encoded_valid <= 1'b0;
            if (data_in != '0 && cnt_r < MAX_NZ) begin
                nz_row[cnt_r]    <= row_idx;
                nz_col[cnt_r]    <= col_idx;
                nz_values[cnt_r] <= data_in;
                cnt_r <= cnt_r + 1;
            end
        end else begin
            encoded_valid <= 1'b0;
        end
    end

endmodule
