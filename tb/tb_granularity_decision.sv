// ============================================================================
// 粒度决策引擎测试平台
// Testbench for Granularity Decision Engine
// ============================================================================

module tb_granularity_decision;

    logic        clk;
    logic        rst_n;
    logic [15:0] sparsity_rate;
    logic [15:0] cluster_score;
    logic        stats_valid;
    logic [31:0] cfg_thresh_l1;
    logic [31:0] cfg_thresh_l2;
    logic [31:0] cfg_cluster_thresh;
    logic        cfg_force_en;
    logic [1:0]  cfg_force_gran;
    logic [1:0]  granularity;
    logic        decision_valid;
    logic [7:0]  decision_reason;

    integer err_count = 0;

    granularity_decision #(
        .Q_FORMAT (8)
    ) uut (
        .clk               (clk),
        .rst_n             (rst_n),
        .sparsity_rate     (sparsity_rate),
        .cluster_score     (cluster_score),
        .stats_valid       (stats_valid),
        .cfg_thresh_l1     (cfg_thresh_l1),
        .cfg_thresh_l2     (cfg_thresh_l2),
        .cfg_cluster_thresh(cfg_cluster_thresh),
        .cfg_force_en      (cfg_force_en),
        .cfg_force_gran    (cfg_force_gran),
        .granularity       (granularity),
        .decision_valid    (decision_valid),
        .decision_reason   (decision_reason)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task apply_input;
        input [15:0] sp;
        input [15:0] cs;
    begin
        @(posedge clk);
        sparsity_rate <= sp;
        cluster_score <= cs;
        stats_valid   <= 1'b1;
        @(posedge clk);
        stats_valid <= 1'b0;
        wait(decision_valid);
        #10;
    end
    endtask

    initial begin
        $display("========================================");
        $display("  Granularity Decision Testbench");
        $display("========================================");

        rst_n = 0; stats_valid = 0;
        sparsity_rate = '0; cluster_score = '0;
        cfg_force_en = 0; cfg_force_gran = '0;
        #20 rst_n = 1;

        // 配置阈值 (Q8.8格式)
        // thresh_l1 = 80% = 0x0140
        cfg_thresh_l1 = 32'h0000_0140;
        // thresh_l2 = 50% = 0x0080
        cfg_thresh_l2 = 32'h0000_0080;
        // cluster_thresh = 0.5 = 0x0080
        cfg_cluster_thresh = 32'h0000_0080;

        #10;

        // ===== 测试1：90%稀疏 + 低聚集 → L1 =====
        $display("[TEST 1] 90%%稀疏 + 低聚集 → 期望L1");
        apply_input(16'h0166, 16'h0040);  // ~90%, 聚集度低
        if (granularity == 2'b00)
            $display("  PASS: granularity=L1 (reason=%0d)", decision_reason);
        else begin
            $display("  FAIL: granularity=%0b (期望00)", granularity);
            err_count = err_count + 1;
        end

        // ===== 测试2：90%稀疏 + 高聚集 → L2 =====
        $display("[TEST 2] 90%%稀疏 + 高聚集 → 期望L2");
        apply_input(16'h0166, 16'h0100);  // ~90%, 聚集度高
        if (granularity == 2'b01)
            $display("  PASS: granularity=L2 (reason=%0d)", decision_reason);
        else begin
            $display("  FAIL: granularity=%0b (期望01)", granularity);
            err_count = err_count + 1;
        end

        // ===== 测试3：60%稀疏 → L2 =====
        $display("[TEST 3] 60%%稀疏 → 期望L2");
        apply_input(16'h0099, 16'h0080);  // ~60%
        if (granularity == 2'b01)
            $display("  PASS: granularity=L2 (reason=%0d)", decision_reason);
        else begin
            $display("  FAIL: granularity=%0b (期望01)", granularity);
            err_count = err_count + 1;
        end

        // ===== 测试4：35%稀疏 → L3 =====
        $display("[TEST 4] 35%%稀疏 → 期望L3");
        apply_input(16'h0059, 16'h0080);  // ~35%
        if (granularity == 2'b10)
            $display("  PASS: granularity=L3 (reason=%0d)", decision_reason);
        else begin
            $display("  FAIL: granularity=%0b (期望10)", granularity);
            err_count = err_count + 1;
        end

        // ===== 测试5：20%稀疏 → dense =====
        $display("[TEST 5] 20%%稀疏 → 期望dense");
        apply_input(16'h0033, 16'h0080);  // ~20%
        if (granularity == 2'b11)
            $display("  PASS: granularity=dense (reason=%0d)", decision_reason);
        else begin
            $display("  FAIL: granularity=%0b (期望11)", granularity);
            err_count = err_count + 1;
        end

        // ===== 测试6：强制粒度模式 =====
        $display("[TEST 6] 强制粒度L3");
        cfg_force_en = 1;
        cfg_force_gran = 2'b10;
        apply_input(16'h0166, 16'h0040);  // 即使是高稀疏
        if (granularity == 2'b10)
            $display("  PASS: force_granularity=L3 (reason=%0d)", decision_reason);
        else begin
            $display("  FAIL: granularity=%0b (期望10)", granularity);
            err_count = err_count + 1;
        end
        cfg_force_en = 0;

        // ===== 汇总 =====
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
