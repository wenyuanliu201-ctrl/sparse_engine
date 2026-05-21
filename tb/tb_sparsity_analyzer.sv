// ============================================================================
// 稀疏感知分析器测试平台
// Testbench for Sparsity Analyzer
// ============================================================================

module tb_sparsity_analyzer;

    parameter DATA_W = 16;
    parameter CH     = 4;
    parameter CNT_W  = 32;

    logic                clk;
    logic                rst_n;
    logic [CH*DATA_W-1:0] data_in;
    logic [CH-1:0]       valid_mask;
    logic                data_valid;
    logic                tensor_last;
    logic [15:0]         sparsity_rate;
    logic [15:0]         cluster_score;
    logic [CNT_W-1:0]    total_count;
    logic [CNT_W-1:0]    nonzero_count;
    logic [CNT_W-1:0]    cluster_count;
    logic                stats_valid;

    integer err_count = 0;

    sparsity_analyzer #(
        .DATA_W (DATA_W),
        .CH     (CH),
        .CNT_W  (CNT_W)
    ) uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .valid_mask    (valid_mask),
        .data_valid    (data_valid),
        .tensor_last   (tensor_last),
        .sparsity_rate (sparsity_rate),
        .cluster_score (cluster_score),
        .total_count   (total_count),
        .nonzero_count (nonzero_count),
        .cluster_count (cluster_count),
        .stats_valid   (stats_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task drive_vector;
        input [CH*DATA_W-1:0] vec;
        input [CH-1:0]        mask;
        input                 is_last;
    begin
        @(posedge clk);
        data_in     <= vec;
        valid_mask  <= mask;
        data_valid  <= 1'b1;
        tensor_last <= is_last;
        @(posedge clk);
        data_valid  <= 1'b0;
        tensor_last <= 1'b0;
    end
    endtask

    // 等待除法完成（最多32个周期）
    task wait_result;
    begin
        // stats_valid表示除法启动，等25个周期让除法完成
        repeat(25) @(posedge clk);
    end
    endtask

    initial begin
        $display("========================================");
        $display("  Sparsity Analyzer Testbench");
        $display("========================================");

        rst_n = 0; data_valid = 0; tensor_last = 0;
        data_in = '0; valid_mask = '0;
        #20 rst_n = 1;
        #10;

        // ===== TEST 1: all-zero tensor => sparsity ~100% =====
        $display("[TEST 1] All-zero tensor");
        for (int i = 0; i < 4; i++) begin
            drive_vector('0, 4'hF, (i == 3));
        end
        wait(stats_valid);
        wait_result();
        $display("  sparsity_rate=%0d total=%0d nonzero=%0d", sparsity_rate, total_count, nonzero_count);
        if (sparsity_rate > 16'h00F0)
            $display("  PASS");
        else begin
            $display("  FAIL: expected ~256");
            err_count = err_count + 1;
        end

        // ===== TEST 2: all-nonzero tensor => sparsity ~0% =====
        $display("[TEST 2] All-nonzero tensor");
        #50;
        data_in = {4{16'h0001}};
        for (int i = 0; i < 4; i++) begin
            drive_vector(data_in, 4'hF, (i == 3));
        end
        wait(stats_valid);
        wait_result();
        $display("  sparsity_rate=%0d total=%0d nonzero=%0d", sparsity_rate, total_count, nonzero_count);
        if (sparsity_rate < 16'h0010)
            $display("  PASS");
        else begin
            $display("  FAIL: expected ~0");
            err_count = err_count + 1;
        end

        // ===== TEST 3: 50% sparse tensor =====
        $display("[TEST 3] 50pct sparse tensor");
        #50;
        for (int i = 0; i < 8; i++) begin
            if (i % 2 == 0) begin
                data_in = {16'h0000, 16'h0000, 16'h0001, 16'h0001};
                drive_vector(data_in, 4'hF, (i == 7));
            end else begin
                data_in = {16'h0001, 16'h0001, 16'h0000, 16'h0000};
                drive_vector(data_in, 4'hF, (i == 7));
            end
        end
        wait(stats_valid);
        wait_result();
        $display("  sparsity_rate=%0d total=%0d nonzero=%0d", sparsity_rate, total_count, nonzero_count);
        if (sparsity_rate > 16'h0060 && sparsity_rate < 16'h00A0)
            $display("  PASS");
        else begin
            $display("  FAIL: expected ~128");
            err_count = err_count + 1;
        end

        // ===== TEST 4: cluster score =====
        $display("[TEST 4] Cluster score test");
        #50;
        for (int i = 0; i < 4; i++) begin
            data_in = {4{16'h0001}};
            drive_vector(data_in, 4'hF, (i == 3));
        end
        for (int i = 0; i < 4; i++) begin
            drive_vector('0, 4'hF, (i == 3));
        end
        wait(stats_valid);
        wait_result();
        $display("  cluster_score=%0d", cluster_score);

        // ===== Summary =====
        #100;
        $display("========================================");
        if (err_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  FAILED: %0d errors", err_count);
        $display("========================================");
        $finish;
    end

endmodule
