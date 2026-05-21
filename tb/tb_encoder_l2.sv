// ============================================================================
// L2块级编码器/译码器测试平台
// Testbench for L2 Block-Level Encoder/Decoder
// ============================================================================

module tb_encoder_l2;

    parameter DATA_W   = 16;
    parameter BLK_H    = 4;
    parameter BLK_W    = 4;
    parameter BLK_SIZE = BLK_H * BLK_W;

    logic clk, rst_n;

    // 编码器接口
    logic [BLK_SIZE*DATA_W-1:0]  block_in;
    logic                        block_valid;
    logic [BLK_SIZE-1:0]         block_bitmap;
    logic [BLK_SIZE*DATA_W-1:0]  nz_values;
    logic [7:0]                  nz_count;
    logic                        encoded_valid;

    // 译码器接口
    logic [BLK_SIZE*DATA_W-1:0]  dec_block;
    logic                        decode_done;

    integer err_count = 0;
    integer trial_count = 0;

    // 编码器例化
    encoder_l2 #(
        .DATA_W   (DATA_W),
        .BLK_H    (BLK_H),
        .BLK_W    (BLK_W)
    ) u_enc (
        .clk           (clk),
        .rst_n         (rst_n),
        .block_in      (block_in),
        .block_valid   (block_valid),
        .block_bitmap  (block_bitmap),
        .nz_values     (nz_values),
        .nz_count      (nz_count),
        .encoded_valid (encoded_valid)
    );

    // 译码器例化
    decoder_l2 #(
        .DATA_W   (DATA_W),
        .BLK_H    (BLK_H),
        .BLK_W    (BLK_W)
    ) u_dec (
        .clk           (clk),
        .rst_n         (rst_n),
        .block_bitmap  (block_bitmap),
        .nz_values     (nz_values),
        .nz_count      (nz_count),
        .decode_start  (encoded_valid),
        .decoded_block (dec_block),
        .decode_done   (decode_done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // 测试任务
    task test_block;
        input [BLK_SIZE*DATA_W-1:0] test_vec;
        input [BLK_SIZE*DATA_W-1:0] expected;
    begin
        trial_count = trial_count + 1;

        // 驱动编码器
        @(posedge clk);
        block_in    <= test_vec;
        block_valid <= 1'b1;
        @(posedge clk);
        block_valid <= 1'b0;

        // 等待编码+译码完成
        wait(decode_done);
        #10;

        // 比对
        if (dec_block !== expected) begin
            $display("  FAIL trial %0d: 往返不匹配!", trial_count);
            $display("    input   = %h", test_vec);
            $display("    expected= %h", expected);
            $display("    got     = %h", dec_block);
            err_count = err_count + 1;
        end
    end
    endtask

    // 测试向量（模块级变量）
    logic [BLK_SIZE*DATA_W-1:0] vec_allzero;
    logic [BLK_SIZE*DATA_W-1:0] vec_allone;
    logic [BLK_SIZE*DATA_W-1:0] vec_diag;
    logic [BLK_SIZE*DATA_W-1:0] vec_alternate;
    logic [BLK_SIZE*DATA_W-1:0] vec_topleft;

    initial begin
        $display("========================================");
        $display("  L2 Encoder/Decoder Roundtrip Test");
        $display("========================================");

        rst_n = 0; block_valid = 0; block_in = '0;
        #20 rst_n = 1;
        #10;

        // ===== 测试1：全零块 =====
        $display("[TEST 1] 全零块");
        vec_allzero = '0;
        test_block(vec_allzero, vec_allzero);

        // ===== 测试2：全非零块 =====
        $display("[TEST 2] 全非零块");
        begin : gen_allone
            integer i;
            vec_allone = '0;
            for (i = 0; i < BLK_SIZE; i = i + 1)
                vec_allone[i*DATA_W +: DATA_W] = i[DATA_W-1:0] + 1;
        end
        test_block(vec_allone, vec_allone);

        // ===== 测试3：对角线块 =====
        $display("[TEST 3] 对角线块");
        vec_diag = '0;
        vec_diag[0*DATA_W +: DATA_W]  = 16'h0001;
        vec_diag[5*DATA_W +: DATA_W]  = 16'h0002;
        vec_diag[10*DATA_W +: DATA_W] = 16'h0003;
        vec_diag[15*DATA_W +: DATA_W] = 16'h0004;
        test_block(vec_diag, vec_diag);

        // ===== 测试4：交替零非零 =====
        $display("[TEST 4] 交替零非零");
        begin : gen_alternate
            integer i;
            vec_alternate = '0;
            for (i = 0; i < BLK_SIZE; i = i + 2)
                vec_alternate[i*DATA_W +: DATA_W] = (i + 1);
        end
        test_block(vec_alternate, vec_alternate);

        // ===== 测试5：仅左上角 =====
        $display("[TEST 5] 仅左上角4个元素");
        vec_topleft = '0;
        vec_topleft[0*DATA_W +: DATA_W] = 16'h000A;
        vec_topleft[1*DATA_W +: DATA_W] = 16'h000B;
        vec_topleft[2*DATA_W +: DATA_W] = 16'h000C;
        vec_topleft[3*DATA_W +: DATA_W] = 16'h000D;
        test_block(vec_topleft, vec_topleft);

        // ===== 测试6：随机块 =====
        $display("[TEST 6] 随机块测试 (20次)");
        begin : gen_random
            integer t, i;
            logic [BLK_SIZE*DATA_W-1:0] rand_vec;
            for (t = 0; t < 20; t = t + 1) begin
                rand_vec = '0;
                for (i = 0; i < BLK_SIZE; i = i + 1) begin
                    if ($urandom_range(0, 1))
                        rand_vec[i*DATA_W +: DATA_W] = $urandom_range(1, 255);
                end
                test_block(rand_vec, rand_vec);
            end
        end

        // ===== 汇总 =====
        #100;
        $display("========================================");
        $display("  Total trials: %0d", trial_count);
        if (err_count == 0)
            $display("  ALL ROUNDTRIP TESTS PASSED!");
        else
            $display("  FAILED: %0d / %0d", err_count, trial_count);
        $display("========================================");
        $finish;
    end

endmodule
