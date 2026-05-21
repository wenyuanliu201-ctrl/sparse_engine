// ============================================================================
// 编码包格式化器 - 将编码结果打包成统一格式
// Encoded Packet Formatter - Pack encoding results into unified format
// ============================================================================

module encoded_packet_formatter #(
    parameter DATA_W    = 16,
    parameter MAX_PKT_W = 512
) (
    input  logic                clk,
    input  logic                rst_n,

    // 编码输入
    input  logic [1:0]          granularity,
    input  logic [15:0]         shape_rows,
    input  logic [15:0]         shape_cols,
    input  logic [15:0]         shape_ch,
    input  logic [127:0]        index_data,
    input  logic [255:0]        value_data,
    input  logic [7:0]          nz_count,
    input  logic                pkt_valid,

    // 打包输出
    output logic [MAX_PKT_W-1:0] encoded_pkt,
    output logic                  pkt_out_valid
);

    // ========== 计算index_len ==========
    logic [7:0] index_len;

    always_comb begin
        case (granularity)
            2'b00:   index_len = nz_count;          // L1: 坐标数=nz_count
            2'b01:   index_len = 8'd2;              // L2: 块位图(4x4=16bit=2bytes)
            2'b10:   index_len = shape_ch[7:0];     // L3: 通道掩码字节数
            2'b11:   index_len = 8'd0;              // dense: 无索引
            default: index_len = 8'd0;
        endcase
    end

    // ========== 打包 ==========
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            encoded_pkt   <= '0;
            pkt_out_valid <= 1'b0;
        end else if (pkt_valid) begin
            encoded_pkt[MAX_PKT_W-1:MAX_PKT_W-2] <= granularity;
            encoded_pkt[MAX_PKT_W-3:MAX_PKT_W-16] <= shape_rows[13:0];
            encoded_pkt[MAX_PKT_W-17:MAX_PKT_W-32] <= shape_cols;
            encoded_pkt[MAX_PKT_W-33:MAX_PKT_W-48] <= shape_ch;
            encoded_pkt[MAX_PKT_W-49:MAX_PKT_W-56] <= nz_count;
            encoded_pkt[MAX_PKT_W-57:MAX_PKT_W-64] <= index_len;
            encoded_pkt[MAX_PKT_W-65:MAX_PKT_W-192] <= index_data;
            encoded_pkt[MAX_PKT_W-193:MAX_PKT_W-448] <= value_data;
            pkt_out_valid <= 1'b1;
        end else begin
            pkt_out_valid <= 1'b0;
        end
    end

endmodule
