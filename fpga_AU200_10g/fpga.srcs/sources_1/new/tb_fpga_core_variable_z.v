`timescale 1ns/1ps
`default_nettype none

module tb_fpga_core_variable_z;

    // ============================================================
    // Test Configuration - Multiple Z values
    // ============================================================
    localparam NUM_TESTS = 3;
    
    // Test cases: [Z_value, num_LLRs, expected_output_bits, expected_output_bytes]
    integer test_z_values     [0:NUM_TESTS-1];
    integer test_llr_counts   [0:NUM_TESTS-1];
    integer test_output_bits  [0:NUM_TESTS-1];
    integer test_output_bytes [0:NUM_TESTS-1];
    
    initial begin
        // Test 1: Z=48
        test_z_values[0]     = 48;
        test_llr_counts[0]   = 2400;  // 48 * 50
        test_output_bits[0]  = 480;   // 48 * 10
        test_output_bytes[0] = 60;    // 480 / 8
        
        // Test 2: Z=96
        test_z_values[1]     = 96;
        test_llr_counts[1]   = 4800;  // 96 * 50
        test_output_bits[1]  = 960;   // 96 * 10
        test_output_bytes[1] = 120;   // 960 / 8
        
        // Test 3: Z=192
        test_z_values[2]     = 192;
        test_llr_counts[2]   = 9600;  // 192 * 50
        test_output_bits[2]  = 1920;  // 192 * 10
        test_output_bytes[2] = 240;   // 1920 / 8
    end

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
    // LLR Memory (supports up to 9600 LLRs for Z=192)
    // ============================================================
    reg signed [9:0] llr_mem [0:9599];
    integer i;

    initial begin
        $readmemb("llrs_input_sfix10_En4_frame0.mem", llr_mem);
        $display("[INFO] Loaded LLR memory file");
    end

    // ============================================================
    // Utility: count valid bytes from tkeep
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
    // Task: Send ONE UDP packet with specified number of LLRs
    // ============================================================
    task send_udp_packet;
        input integer num_llrs;
        input integer z_value;
        integer llr_idx;
        integer n;
        reg [63:0] data_word;
        reg signed [3:0] sfix4;
    begin
        $display("┌─────────────────────────────────────────────────────────┐");
        $display("│ [%0t] 📤 SENDING UDP PACKET", $time);
        $display("│    Z value:     %0d", z_value);
        $display("│    LLRs to send: %0d", num_llrs);
        $display("│    Bytes:       %0d (payload)", num_llrs * 10 / 8);
        $display("└─────────────────────────────────────────────────────────┘");

        // ---------------- UDP header ----------------
        force dut.rx_udp_hdr_valid    = 1'b1;
        force dut.rx_udp_dest_port    = 16'd1234;
        force dut.rx_udp_source_port  = 16'd4000;
        force dut.rx_udp_ip_source_ip = 32'hC0A80101;

        @(posedge clk);
        while (!dut.rx_udp_hdr_ready)
            @(posedge clk);

        release dut.rx_udp_hdr_valid;
        $display("   ✓ UDP header sent");

        // ---------------- Payload ----------------
        llr_idx = 0;

        while (llr_idx < num_llrs) begin
            data_word = 64'd0;

            // Pack 16 4-bit LLRs into 64-bit word
            for (n = 0; n < 16 && llr_idx < num_llrs; n = n + 1) begin
                sfix4 = llr_mem[llr_idx] >>> 4;
                if (sfix4 >  7) sfix4 =  7;
                if (sfix4 < -8) sfix4 = -8;
                data_word[n*4 +: 4] = sfix4[3:0];
                llr_idx = llr_idx + 1;
            end

            force dut.rx_udp_payload_axis_tdata  = data_word;
            force dut.rx_udp_payload_axis_tkeep  = 8'hFF;
            force dut.rx_udp_payload_axis_tvalid = 1'b1;
            force dut.rx_udp_payload_axis_tlast  = (llr_idx >= num_llrs);
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

        $display("   ✓ Payload sent: %0d LLRs", num_llrs);
    end
    endtask

    // ============================================================
    // TX Monitor - Per packet tracking
    // ============================================================
    integer current_tx_byte_count;
    integer current_tx_bit_count;
    reg     tx_active;
    
    initial begin
        current_tx_byte_count = 0;
        current_tx_bit_count  = 0;
        tx_active = 0;

        forever begin
            @(posedge clk);
            
            if (dut.tx_udp_payload_axis_tvalid && dut.tx_udp_payload_axis_tready) begin
                if (!tx_active) begin
                    $display("   ⚡ TX started");
                    tx_active = 1;
                end
                
                current_tx_byte_count = current_tx_byte_count + 
                                       count_keep_bytes(dut.tx_udp_payload_axis_tkeep);

                if (dut.tx_udp_payload_axis_tlast) begin
                    current_tx_bit_count = current_tx_byte_count * 8;
                    $display("┌─────────────────────────────────────────────────────────┐");
                    $display("│ [%0t] 📥 RECEIVED TX RESPONSE", $time);
                    $display("│    Bytes received: %0d", current_tx_byte_count);
                    $display("│    Bits received:  %0d", current_tx_bit_count);
                    $display("└─────────────────────────────────────────────────────────┘");
                    tx_active = 0;
                end
            end
        end
    end

    // ============================================================
    // Test Execution
    // ============================================================
    integer test_idx;
    integer expected_bytes;
    integer timeout_counter;
    integer test_pass_count;
    integer test_fail_count;
    
    initial begin
        $display("═════════════════════════════════════════════════════════");
        $display("  VARIABLE-Z LDPC DECODER TEST");
        $display("  Testing %0d different lifting sizes", NUM_TESTS);
        $display("═════════════════════════════════════════════════════════");
        
        test_pass_count = 0;
        test_fail_count = 0;

        // Reset
        #100;
        rst = 0;
        rst_ldpc = 0;
        $display("[INFO] Reset released");

        repeat (50) @(posedge clk);

        // ========================================================
        // Run all test cases
        // ========================================================
        for (test_idx = 0; test_idx < NUM_TESTS; test_idx = test_idx + 1) begin
            $display("");
            $display("═════════════════════════════════════════════════════════");
            $display("  TEST %0d of %0d: Z=%0d", 
                     test_idx + 1, NUM_TESTS, test_z_values[test_idx]);
            $display("═════════════════════════════════════════════════════════");
            
            // Reset counters
            current_tx_byte_count = 0;
            current_tx_bit_count  = 0;
            expected_bytes = test_output_bytes[test_idx];
            
            // Send packet
            send_udp_packet(test_llr_counts[test_idx], test_z_values[test_idx]);
            
            // Wait for TX response with timeout
            timeout_counter = 0;
            while (current_tx_byte_count < expected_bytes && timeout_counter < 1000000) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end
            
            // Check results
            if (timeout_counter >= 1000000) begin
                $display("┌─────────────────────────────────────────────────────────┐");
                $display("│ ❌ TEST %0d FAILED: TIMEOUT", test_idx + 1);
                $display("│    Expected: %0d bytes (%0d bits)", 
                         expected_bytes, test_output_bits[test_idx]);
                $display("│    Got:      %0d bytes (%0d bits)", 
                         current_tx_byte_count, current_tx_bit_count);
                $display("└─────────────────────────────────────────────────────────┘");
                test_fail_count = test_fail_count + 1;
            end else if (current_tx_byte_count == expected_bytes) begin
                $display("┌─────────────────────────────────────────────────────────┐");
                $display("│ ✅ TEST %0d PASSED", test_idx + 1);
                $display("│    Z = %0d", test_z_values[test_idx]);
                $display("│    LLRs sent:     %0d", test_llr_counts[test_idx]);
                $display("│    Bits received: %0d (expected %0d)", 
                         current_tx_bit_count, test_output_bits[test_idx]);
                $display("│    Bytes:         %0d (expected %0d)", 
                         current_tx_byte_count, expected_bytes);
                $display("└─────────────────────────────────────────────────────────┘");
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("┌─────────────────────────────────────────────────────────┐");
                $display("│ ❌ TEST %0d FAILED: WRONG SIZE", test_idx + 1);
                $display("│    Expected: %0d bytes (%0d bits)", 
                         expected_bytes, test_output_bits[test_idx]);
                $display("│    Got:      %0d bytes (%0d bits)", 
                         current_tx_byte_count, current_tx_bit_count);
                $display("└─────────────────────────────────────────────────────────┘");
                test_fail_count = test_fail_count + 1;
            end
            
            // Wait between tests
            repeat (100) @(posedge clk);
        end

        // ========================================================
        // Final Summary
        // ========================================================
        $display("");
        $display("═════════════════════════════════════════════════════════");
        $display("  FINAL TEST SUMMARY");
        $display("═════════════════════════════════════════════════════════");
        $display("  Total tests:  %0d", NUM_TESTS);
        $display("  Passed:       %0d", test_pass_count);
        $display("  Failed:       %0d", test_fail_count);
        $display("═════════════════════════════════════════════════════════");
        
        if (test_fail_count == 0) begin
            $display("  🎉 ALL TESTS PASSED! Variable-Z decoder working!");
        end else begin
            $display("  ⚠️  Some tests failed. Check logs above.");
        end
        
        $display("═════════════════════════════════════════════════════════");
        #1000;
        $finish;
    end

    // ============================================================
    // Timeout watchdog
    // ============================================================
    initial begin
        #50000000; // 50ms total timeout
        $display("═════════════════════════════════════════════════════════");
        $display("  ⚠️  GLOBAL TIMEOUT - Test took too long!");
        $display("═════════════════════════════════════════════════════════");
        $finish;
    end

endmodule

`default_nettype wire