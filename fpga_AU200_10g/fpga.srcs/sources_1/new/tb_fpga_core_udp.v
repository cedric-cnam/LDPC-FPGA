`timescale 1ns/1ps
`default_nettype none

module tb_fpga_core_udp;

    // ============================================================
    // Parameters
    // ============================================================
    localparam integer TOTAL_LLR       = 9600;
    localparam integer TOTAL_BITS      = 1920;
    localparam integer TX_BYTES_EXPECT = TOTAL_BITS / 8; // 240 bytes

    // ============================================================
    // Clocks
    // ============================================================
    reg clk = 0;
    reg clk_ldpc = 0;

    always #3.2   clk      = ~clk;      // 156.25 MHz
    always #6.667 clk_ldpc = ~clk_ldpc;  // 75 MHz

    // ============================================================
    // Reset
    // ============================================================
    reg rst = 1;
    reg rst_ldpc = 1;

    // ============================================================
    // DUT
    // ============================================================
    fpga_core dut (
        .clk(clk),
        .rst(rst),
        .clk_ldpc(clk_ldpc),
        .rst_ldpc(rst_ldpc),

        .sw(4'd0),
        .led(),
        .qsfp_led_act(),
        .qsfp_led_stat_g(),
        .qsfp_led_stat_y(),
        .uart_txd(),
        .uart_rxd(1'b0),

        .eth_tx_clk(8'd0),
        .eth_tx_rst(8'd0),
        .eth_txd(),
        .eth_txc(),

        .eth_rx_clk(8'd0),
        .eth_rx_rst(8'd0),
        .eth_rxd(512'd0),
        .eth_rxc(64'd0)
    );

    // ============================================================
    // LLR Memory
    // ============================================================
    reg signed [9:0] llr_mem [0:TOTAL_LLR-1];
    integer i;

    initial begin
        $readmemb("llrs_input_sfix10_En4_frame0.mem", llr_mem);
    end

    // ============================================================
    // Utility: count valid bytes from tkeep (Verilog-2001)
    // ============================================================
    function integer count_keep_bytes;
        input [7:0] keep;
        integer k;
        begin
            count_keep_bytes = 0;
            for (k = 0; k < 8; k = k + 1)
                if (keep[k])
                    count_keep_bytes = count_keep_bytes + 1;
        end
    endfunction

    // ============================================================
    // Task: Send ONE UDP packet (9600 LLRs)
    // ============================================================
    task send_udp_packet;
        integer llr_idx;
        integer n;
        reg [63:0] data_word;
        reg signed [3:0] sfix4;
    begin
        $display("[%0t] ▶ Sending UDP packet", $time);

        // ---------------- UDP header ----------------
        force dut.rx_udp_hdr_valid    = 1'b1;
        force dut.rx_udp_dest_port    = 16'd1234;
        force dut.rx_udp_source_port  = 16'd4000;
        force dut.rx_udp_ip_source_ip = 32'hC0A80101;

        @(posedge clk);
        while (!dut.rx_udp_hdr_ready)
            @(posedge clk);

        release dut.rx_udp_hdr_valid;

        // ---------------- Payload ----------------
        llr_idx = 0;

        while (llr_idx < TOTAL_LLR) begin
            data_word = 64'd0;

            for (n = 0; n < 16 && llr_idx < TOTAL_LLR; n = n + 1) begin
                sfix4 = llr_mem[llr_idx] >>> 4;
                if (sfix4 >  7) sfix4 =  7;
                if (sfix4 < -8) sfix4 = -8;
                data_word[n*4 +: 4] = sfix4[3:0];
                llr_idx = llr_idx + 1;
            end

            force dut.rx_udp_payload_axis_tdata  = data_word;
            force dut.rx_udp_payload_axis_tkeep  = 8'hFF;
            force dut.rx_udp_payload_axis_tvalid = 1'b1;
            force dut.rx_udp_payload_axis_tlast  = (llr_idx >= TOTAL_LLR);
            force dut.rx_udp_payload_axis_tuser  = 1'b0;

            @(posedge clk);
            while (!dut.rx_udp_payload_axis_tready)
                @(posedge clk);

            release dut.rx_udp_payload_axis_tvalid;
            release dut.rx_udp_payload_axis_tlast;
            release dut.rx_udp_payload_axis_tdata;
            release dut.rx_udp_payload_axis_tkeep;
            release dut.rx_udp_payload_axis_tuser;

            @(posedge clk);
        end

        release dut.rx_udp_dest_port;
        release dut.rx_udp_source_port;
        release dut.rx_udp_ip_source_ip;

        $display("[%0t] ✔ UDP payload sent (%0d LLRs)", $time, TOTAL_LLR);
    end
    endtask

    // ============================================================
    // TX Monitor
    // ============================================================
    integer tx_byte_count;

    initial begin
        tx_byte_count = 0;

        forever begin
            @(posedge clk);
            if (dut.tx_udp_payload_axis_tvalid &&
                dut.tx_udp_payload_axis_tready) begin

                tx_byte_count =
                    tx_byte_count +
                    count_keep_bytes(dut.tx_udp_payload_axis_tkeep);

                if (dut.tx_udp_payload_axis_tlast) begin
                    $display("[%0t] ◀ TX tlast asserted", $time);
                end
            end
        end
    end

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin
        $display("=================================================");
        $display(" UDP → LDPC → UDP FULL PIPELINE TEST ");
        $display("=================================================");

        // Reset
        #100;
        rst = 0;
        rst_ldpc = 0;

        repeat (50) @(posedge clk);

        // Send one packet
        send_udp_packet();

        // Wait for TX completion
        while (tx_byte_count < TX_BYTES_EXPECT)
            @(posedge clk);

        // ---------------------------------------------------------
        // Result
        // ---------------------------------------------------------
        if (tx_byte_count == TX_BYTES_EXPECT) begin
            $display("✅ TEST PASSED");
            $display("   TX bytes received: %0d", tx_byte_count);
        end else begin
            $display("❌ TEST FAILED");
            $display("   Expected: %0d bytes", TX_BYTES_EXPECT);
            $display("   Got:      %0d bytes", tx_byte_count);
        end

        $display("=================================================");
        $finish;
    end

endmodule

`default_nettype wire
