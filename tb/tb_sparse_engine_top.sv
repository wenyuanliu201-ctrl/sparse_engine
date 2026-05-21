// ============================================================================
// 顶层集成测试平台 - 端到端编码-译码往返验证
// Top-Level Integration Testbench - End-to-end encode-decode roundtrip
// ============================================================================

module tb_sparse_engine_top;

    parameter DATA_W   = 16;
    parameter CH       = 4;
    parameter BLK_H    = 4;
    parameter BLK_W    = 4;

    logic clk, rst_n;

    // 配置
    logic [31:0] cfg_wdata;
    logic [7:0]  cfg_addr;
    logic        cfg_valid;

    // 数据输入
    logic [CH*DATA_W-1:0]  data_in;
    logic [CH-1:0]         valid_mask;
    logic                  data_valid;
    logic                  tensor_last;

    // 编码输出
    logic [1:0]            out_granularity;
    logic [7:0]            out_nz_count;
    logic [BLK_H*BLK_W*DATA_W-1:0] out_encoded_data;
    logic [BLK_H*BLK_W-1:0]        out_bitmap;
    logic                  out_valid;

    // 译码输入
    logic [1:0]            dec_granularity;
    logic [BLK_H*BLK_W*DATA_W-1:0] dec_encoded_data;
    logic [BLK_H*BLK_W-1:0]        dec_bitmap;
    logic [7:0]            dec_nz_count;
    logic                  dec_start;

    // 译码输出
    logic [BLK_H*BLK_W*DATA_W-1:0] dec_output;
    logic                  dec_done;

    // 状态
    logic [1:0]            current_granularity;
    logic [15:0]           current_sparsity;
    logic [15:0]           current_cluster;
    logic [7:0]            decision_reason;
    logic                  engine_busy;

    integer err_count = 0;

    sparse_engine_top #(
        .DATA_W   (DATA_W),
        .CH       (CH),
        .BLK_H    (BLK_H),
        .BLK_W    (BLK_W)
    ) uut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cfg_wdata        (cfg_wdata),
        .cfg_addr         (cfg_addr),
        .cfg_valid        (cfg_valid),
        .data_in          (data_in),
        .valid_mask       (valid_mask),
        .data_valid       (data_valid),
        .tensor_last      (tensor_last),
        .out_granularity  (out_granularity),
        .out_nz_count     (out_nz_count),
        .out_encoded_data (out_encoded_data),
        .out_bitmap       (out_bitmap),
        .out_valid        (out_valid),
        .dec_granularity  (dec_granularity),
        .dec_encoded_data (dec_encoded_data),
        .dec_bitmap       (dec_bitmap),
        .dec_nz_count     (dec_nz_count),
        .dec_start        (dec_start),
        .dec_output       (dec_output),
        .dec_done         (dec_done),
        .current_granularity (current_granularity),
        .current_sparsity   (current_sparsity),
        .current_cluster    (current_cluster),
        .decision_reason    (decision_reason),
        .engine_busy        (engine_busy)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // 存储原始数据用于比对
    logic [DATA_W-1:0] original_block [0:15];
    logic [DATA_W-1:0] decoded_block  [0:15];

    initial begin
        $display("========================================");
        $display("  Sparse Engine Top-Level Testbench");
        $display("========================================");

        // 复位
        rst_n = 0;
        cfg_valid = 0; cfg_wdata = '0; cfg_addr = '0;
        data_valid = 0; tensor_last = 0;
        data_in = '0; valid_mask = '0;
        dec_start = 0; dec_granularity = '0;
        dec_encoded_data = '0; dec_bitmap = '0; dec_nz_count = '0;
        #20 rst_n = 1;
        #10;

        // ===== 测试1：强制L2模式，编码-译码往返 =====
        $display("[TEST 1] 强制L2粒度 - 往返测试");

        // 配置：强制L2模式
        @(posedge clk);
        cfg_addr  <= 8'h10;
        cfg_wdata <= 32'h1;     // force_enable = 1
        cfg_valid <= 1'b1;
        @(posedge clk);
        cfg_valid <= 1'b0;

        @(posedge clk);
        cfg_addr  <= 8'h14;
        cfg_wdata <= 32'h1;     // force_granularity = L2
        cfg_valid <= 1'b1;
        @(posedge clk);
        cfg_valid <= 1'b0;

        #50;

        // 送入一个4x4测试块
        begin
            logic [CH*DATA_W-1:0] test_vec;
            test_vec = '0;
            test_vec[0*DATA_W +: DATA_W]  = 16'h0005;
            test_vec[1*DATA_W +: DATA_W]  = 16'h0000;
            test_vec[2*DATA_W +: DATA_W]  = 16'h0003;
            test_vec[3*DATA_W +: DATA_W]  = 16'h0000;

            // 存储原始数据
            original_block[0]  = 16'h0005;
            original_block[1]  = 16'h0000;
            original_block[2]  = 16'h0003;
            original_block[3]  = 16'h0000;
            for (int i = 4; i < 16; i++) original_block[i] = '0;

            @(posedge clk);
            data_in     <= test_vec;
            valid_mask  <= 4'hF;
            data_valid  <= 1'b1;
            @(posedge clk);
            data_valid  <= 1'b0;

            // 等待编码完成
            wait(out_valid);
            $display("  编码完成: granularity=%0b nz_count=%0d bitmap=%b",
                     out_granularity, out_nz_count, out_bitmap);

            // 送入译码器
            @(posedge clk);
            dec_granularity  <= out_granularity;
            dec_encoded_data <= out_encoded_data;
            dec_bitmap       <= out_bitmap;
            dec_nz_count     <= out_nz_count;
            dec_start        <= 1'b1;
            @(posedge clk);
            dec_start <= 1'b0;

            // 等待译码完成
            wait(dec_done);
            #10;

            // 比对
            for (int i = 0; i < 16; i++) begin
                decoded_block[i] = dec_output[i*DATA_W +: DATA_W];
            end

            begin
                logic pass;
                pass = 1'b1;
                for (int i = 0; i < 4; i++) begin
                    if (decoded_block[i] !== original_block[i]) begin
                        $display("  FAIL: idx=%0d orig=%h dec=%h",
                                 i, original_block[i], decoded_block[i]);
                        pass = 1'b0;
                    end
                end
                if (pass)
                    $display("  PASS: L2往返正确!");
                else
                    err_count = err_count + 1;
            end
        end

        // ===== 测试2：自适应模式 =====
        $display("[TEST 2] 自适应粒度选择");

        // 关闭强制模式
        @(posedge clk);
        cfg_addr  <= 8'h10;
        cfg_wdata <= 32'h0;     // force_enable = 0
        cfg_valid <= 1'b1;
        @(posedge clk);
        cfg_valid <= 1'b0;

        #50;

        // 送入高稀疏数据 (>80%)
        $display("  送入90%%稀疏数据...");
        for (int i = 0; i < 8; i++) begin
            logic [CH*DATA_W-1:0] vec;
            vec = '0;
            if (i == 0) vec[0*DATA_W +: DATA_W] = 16'h0001;  // 仅1个非零
            @(posedge clk);
            data_in     <= vec;
            valid_mask  <= 4'hF;
            data_valid  <= 1'b1;
            tensor_last <= (i == 7);
            @(posedge clk);
            data_valid  <= 1'b0;
            tensor_last <= 1'b0;
        end

        // 等待决策
        #500;
        $display("  决策结果: granularity=%0b sparsity=%0d reason=%0d",
                 current_granularity, current_sparsity, decision_reason);

        // ===== 汇总 =====
        #200;
        $display("========================================");
        if (err_count == 0)
            $display("  ALL TOP-LEVEL TESTS PASSED!");
        else
            $display("  FAILED: %0d errors", err_count);
        $display("========================================");
        $finish;
    end

endmodule
