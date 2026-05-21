// ============================================================================
// 粒度路由器 - 根据粒度标识将数据分发到对应编码/译码通路
// Granularity Router - Demux data to corresponding encode/decode path
// ============================================================================

module granularity_router #(
    parameter DATA_W = 128
) (
    input  logic                clk,
    input  logic                rst_n,

    // 输入
    input  logic [1:0]          gran_in,
    input  logic [DATA_W-1:0]   data_in,
    input  logic                valid_in,
    output logic                ready_in,

    // 4路输出
    output logic [DATA_W-1:0]   l1_data,    l2_data,    l3_data,    dense_data,
    output logic                l1_valid,   l2_valid,   l3_valid,   dense_valid,
    input  logic                l1_ready,   l2_ready,   l3_ready,   dense_ready
);

    // 数据直通，根据粒度标识选择valid/ready
    assign l1_data    = data_in;
    assign l2_data    = data_in;
    assign l3_data    = data_in;
    assign dense_data = data_in;

    always_comb begin
        l1_valid    = 1'b0;
        l2_valid    = 1'b0;
        l3_valid    = 1'b0;
        dense_valid = 1'b0;
        ready_in    = 1'b0;

        case (gran_in)
            2'b00: begin  // L1
                l1_valid = valid_in;
                ready_in = l1_ready;
            end
            2'b01: begin  // L2
                l2_valid = valid_in;
                ready_in = l2_ready;
            end
            2'b10: begin  // L3
                l3_valid = valid_in;
                ready_in = l3_ready;
            end
            2'b11: begin  // dense
                dense_valid = valid_in;
                ready_in    = dense_ready;
            end
            default: ;
        endcase
    end

endmodule
