`timescale 1ns/1ps
`default_nettype none

module tb_fpga_core_udp;

    // ============================================================
    // Parameters (now configurable per test)
    // ============================================================
    localparam integer MAX_LLR = 19200;  // Support up to Z=384
    localparam integer NUM_PACKETS = 3;  // Number of test packets

    // Test configuration arrays for multiple Z values
    integer TEST_Z_ARRAY [0:NUM_PACKETS-1];
    integer current_packet;
    
    integer TEST_Z;
    integer TOTAL_LLR;
    integer TOTAL_BITS;
    integer TX_BYTES_EXPECT;
    integer RX_BYTES_TO_SEND;
    integer timeout_counter;

    // Results tracking
    integer detected_z_array [0:NUM_PACKETS-1];
    integer tx_bytes_array [0:NUM_PACKETS-1];
    integer pass_count;
    integer fail_count;

    // ============================================================
    // Clocks
    // ============================================================
    reg clk;
    reg clk_ldpc;

    initial clk = 0;
    initial clk_ldpc = 0;
    
    always #3.2   clk      = ~clk;      // 156.25 MHz
    always #6.667 clk_ldpc = ~clk_ldpc;  // 75 MHz

    // ============================================================
    // Reset
    // ============================================================
    reg rst;
    reg rst_ldpc;

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
    reg signed [9:0] llr_mem [0:MAX_LLR-1];
    integer i;

    initial begin
        // Initialize all to zero first
        for (i = 0; i < MAX_LLR; i = i + 1)
            llr_mem[i] = 10'sd0;
        
        // Load the actual data (your file has 9600 LLRs for Z=192)
        // For Z=48 and Z=96, we'll generate synthetic data
        $readmemb("llrs_input_sfix10_En4_frame0.mem", llr_mem);
    end

    // ============================================================
    // Task: Generate synthetic LLRs for different Z values
    // ============================================================
    task generate_test_llrs;
        input integer num_llrs;
        integer idx;
        reg [9:0] test_value;
    begin
        $display("[%0t] Generating %0d synthetic LLRs", $time, num_llrs);
        
        for (idx = 0; idx < num_llrs; idx = idx + 1) begin
            // Generate a simple pattern: alternating positive/negative values
            // This is just for testing - in real use, you'd have proper test vectors
            if (idx[0])
                test_value = 10'sd50;  // +50 (positive LLR)
            else
                test_value = -10'sd50; // -50 (negative LLR)
            
            llr_mem[idx] = test_value;
        end
    end
    endtask

    // ============================================================
    // Utility: count valid bytes from tkeep (Verilog-2001)
    // ============================================================
    function integer count_keep_bytes;
        input [7:0] keep;
        integer k;
        begin
            count_keep_bytes = 0;
            for (k = 0; k < 8; k = k + 1) begin
                if (keep[k])
                    count_keep_bytes = count_keep_bytes + 1;
            end
        end
    endfunction

    // ============================================================
    // Task: Send ONE UDP packet with configurable Z
    // ============================================================
    task send_udp_packet;
    input integer num_llrs;
    integer llr_idx;
    integer n;
    reg [63:0] data_word;
    reg signed [3:0] sfix4;
    integer bytes_sent;
begin
    $display("[%0t] >>> Sending UDP packet (Z=%0d, %0d LLRs, %0d bytes)", 
             $time, TEST_Z, num_llrs, num_llrs / 2);

    bytes_sent = 0;

    // ---------------- UDP header ----------------
    force dut.rx_udp_hdr_valid    = 1'b1;
    force dut.rx_udp_dest_port    = 16'd1234;
    force dut.rx_udp_source_port  = 16'd4000;
    force dut.rx_udp_ip_source_ip = 32'hC0A80101;

    @(posedge clk);
    while (!dut.rx_udp_hdr_ready)
        @(posedge clk);

    release dut.rx_udp_hdr_valid;
    
    // Force match_cond (combinational) instead of match_cond_reg
    // Keep dest_port forced so match_cond stays true
    // DON'T release dest_port yet!

    // ---------------- Payload ----------------
    llr_idx = 0;

    while (llr_idx < num_llrs) begin
        data_word = 64'd0;

        // Pack 16 LLRs (4 bits each) into 64-bit word
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

        bytes_sent = bytes_sent + 8;

        @(posedge clk);
        
        // Debug: print what we see
        if (llr_idx == 16) begin  // First word
            $display("[%0t] [DEBUG] First payload word: dest_port=%0d, match_cond=%b, match_cond_reg=%b, tready=%b",
                     $time, dut.rx_udp_dest_port, dut.match_cond, dut.match_cond_reg, dut.rx_udp_payload_axis_tready);
        end
        
        while (!dut.rx_udp_payload_axis_tready) begin
            $display("[%0t] [WAITING] tready=0, dest_port=%0d, match_cond=%b, match_cond_reg=%b",
                     $time, dut.rx_udp_dest_port, dut.match_cond, dut.match_cond_reg);
            @(posedge clk);
        end

        release dut.rx_udp_payload_axis_tvalid;
        release dut.rx_udp_payload_axis_tlast;
        release dut.rx_udp_payload_axis_tdata;
        release dut.rx_udp_payload_axis_tkeep;
        release dut.rx_udp_payload_axis_tuser;

        @(posedge clk);
    end

    // NOW release the header signals after payload is done
    release dut.rx_udp_dest_port;
    release dut.rx_udp_source_port;
    release dut.rx_udp_ip_source_ip;

    $display("[%0t] <<< UDP payload sent (%0d LLRs, %0d bytes)", 
             $time, num_llrs, bytes_sent);
end
endtask
    
    // ============================================================
    // TX Monitor (Enhanced)
    // ============================================================
    integer tx_byte_count;
    integer tx_word_count;
    reg     tx_completed;

    initial begin
        tx_byte_count = 0;
        tx_word_count = 0;
        tx_completed = 0;

        forever begin
            @(posedge clk);
            if (dut.tx_udp_payload_axis_tvalid &&
                dut.tx_udp_payload_axis_tready) begin

                tx_byte_count = tx_byte_count + 
                                count_keep_bytes(dut.tx_udp_payload_axis_tkeep);
                tx_word_count = tx_word_count + 1;

                if (dut.tx_udp_payload_axis_tlast) begin
                    $display("[%0t] TX tlast asserted (total: %0d bytes, %0d words)", 
                             $time, tx_byte_count, tx_word_count);
                    tx_completed = 1;
                end
            end
        end
    end

    // ============================================================
    // Z Detection Monitor
    // ============================================================
    initial begin
        forever begin
            @(posedge clk_ldpc);
            if (dut.llr_input_inst.size_determined) begin
                $display("[%0t] Z detected: Z=%0d, Total LLRs=%0d", 
                         $time, 
                         dut.llr_input_inst.lifting_size,
                         dut.llr_input_inst.total_llr_target);
            end
        end
    end

    // ============================================================
    // Timeout Watchdog
    // ============================================================
    initial begin
        #20_000_000;  // Increased for multiple packets
        $display("SIMULATION TIMEOUT");
        $finish;
    end

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin
        $display("==========================================================");
        $display(" UDP -> LDPC -> UDP MULTI-Z DYNAMIC DETECTION TEST ");
        $display("==========================================================");

        // Initialize
        rst = 1;
        rst_ldpc = 1;
        pass_count = 0;
        fail_count = 0;

        // Configure test Z values: 48, 96, 192
        TEST_Z_ARRAY[0] = 48;   // Packet 1: Z=48  (2400 LLRs, 1200 bytes, 480 bits out)
        TEST_Z_ARRAY[1] = 96;   // Packet 2: Z=96  (4800 LLRs, 2400 bytes, 960 bits out)
        TEST_Z_ARRAY[2] = 192;  // Packet 3: Z=192 (9600 LLRs, 4800 bytes, 1920 bits out)

        $display("");
        $display("Test will send %0d packets with different Z values:", NUM_PACKETS);
        for (i = 0; i < NUM_PACKETS; i = i + 1) begin
            $display("  Packet %0d: Z=%0d (%0d LLRs, %0d bytes in, %0d bits out)", 
                     i+1, TEST_Z_ARRAY[i], 
                     50 * TEST_Z_ARRAY[i],
                     (50 * TEST_Z_ARRAY[i]) / 2,
                     10 * TEST_Z_ARRAY[i]);
        end
        $display("==========================================================");

        // Reset
        #100;
        rst = 0;
        rst_ldpc = 0;

        repeat (50) @(posedge clk);

        // ========== LOOP THROUGH ALL TEST PACKETS ==========
        for (current_packet = 0; current_packet < NUM_PACKETS; current_packet = current_packet + 1) begin
            
            $display("");
            $display("##########################################################");
            $display("# PACKET %0d of %0d", current_packet + 1, NUM_PACKETS);
            $display("##########################################################");
            
            // Set current test parameters
            TEST_Z = TEST_Z_ARRAY[current_packet];
            TOTAL_LLR = 50 * TEST_Z;
            TOTAL_BITS = 10 * TEST_Z;
            TX_BYTES_EXPECT = TOTAL_BITS / 8;
            RX_BYTES_TO_SEND = TOTAL_LLR / 2;

            $display("Configuration for packet %0d:", current_packet + 1);
            $display("  Z              = %0d", TEST_Z);
            $display("  Total LLRs     = %0d", TOTAL_LLR);
            $display("  RX bytes       = %0d", RX_BYTES_TO_SEND);
            $display("  Expected output = %0d bits = %0d bytes", TOTAL_BITS, TX_BYTES_EXPECT);

            // Generate test data for packets 1 and 2
            if (current_packet < 2) begin
                generate_test_llrs(TOTAL_LLR);
            end
            // Packet 3 (Z=192) uses the loaded .mem file

            // Reset TX monitor
            tx_byte_count = 0;
            tx_word_count = 0;
            tx_completed = 0;

            // Send packet
            send_udp_packet(TOTAL_LLR);

            // Wait for TX completion with timeout
            timeout_counter = 0;
            while (!tx_completed && timeout_counter < 1000000) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end
            
            if (timeout_counter >= 1000000) begin
                $display("WARNING: TIMEOUT waiting for TX completion on packet %0d", current_packet + 1);
            end

            // Small delay to ensure all data is captured
            repeat (100) @(posedge clk);

            // Store results
            detected_z_array[current_packet] = dut.llr_input_inst.lifting_size;
            tx_bytes_array[current_packet] = tx_byte_count;

            // Verify this packet
            $display("----------------------------------------------------------");
            $display("Packet %0d Results:", current_packet + 1);
            $display("  Expected Z       = %0d", TEST_Z);
            $display("  Detected Z       = %0d", detected_z_array[current_packet]);
            $display("  Expected bytes   = %0d", TX_BYTES_EXPECT);
            $display("  Received bytes   = %0d", tx_bytes_array[current_packet]);

            if (tx_bytes_array[current_packet] == TX_BYTES_EXPECT && 
                detected_z_array[current_packet] == TEST_Z) begin
                $display("  Result: PASS");
                pass_count = pass_count + 1;
            end else begin
                $display("  Result: FAIL");
                fail_count = fail_count + 1;
                if (detected_z_array[current_packet] != TEST_Z)
                    $display("    - Z detection mismatch: expected %0d, got %0d", 
                             TEST_Z, detected_z_array[current_packet]);
                if (tx_bytes_array[current_packet] != TX_BYTES_EXPECT)
                    $display("    - Byte count mismatch: expected %0d, got %0d", 
                             TX_BYTES_EXPECT, tx_bytes_array[current_packet]);
            end
            $display("----------------------------------------------------------");

            // Wait between packetspacket_started
            if (current_packet < NUM_PACKETS - 1) begin
                $display("Waiting before next packet...");
                repeat (1000) @(posedge clk);
                repeat (100) @(posedge clk_ldpc);
            end
        end

        // ========== FINAL SUMMARY ==========
        $display("");
        $display("==========================================================");
        $display(" FINAL TEST SUMMARY");
        $display("==========================================================");
        $display("Total packets tested: %0d", NUM_PACKETS);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("");
        
        $display("Detailed Results:");
        $display("  Packet | Expected Z | Detected Z | Expected Bytes | RX Bytes | Status");
        $display("  -------|------------|------------|----------------|----------|--------");
        
        for (i = 0; i < NUM_PACKETS; i = i + 1) begin
            TEST_Z = TEST_Z_ARRAY[i];
            TX_BYTES_EXPECT = (10 * TEST_Z) / 8;
            
            if (detected_z_array[i] == TEST_Z && tx_bytes_array[i] == TX_BYTES_EXPECT)
                $display("    %0d    |     %0d     |     %0d     |       %0d       |    %0d    | PASS",
                         i+1, TEST_Z, detected_z_array[i], TX_BYTES_EXPECT, tx_bytes_array[i]);
            else
                $display("    %0d    |     %0d     |     %0d     |       %0d       |    %0d    | FAIL",
                         i+1, TEST_Z, detected_z_array[i], TX_BYTES_EXPECT, tx_bytes_array[i]);
        end

        $display("");
        if (fail_count == 0) begin
            $display("========== ALL TESTS PASSED ==========");
        end else begin
            $display("========== SOME TESTS FAILED ==========");
        end
        $display("==========================================================");
        $finish;
    end
    
// Add this to testbench - detailed monitoring
initial begin
    forever begin
        @(posedge clk);
        if (dut.rx_udp_payload_axis_tvalid) begin
            $display("[%0t] [TB] Payload: tvalid=1, tready=%b, data=0x%h", 
                     $time, dut.rx_udp_payload_axis_tready, 
                     dut.rx_udp_payload_axis_tdata[7:0]);
        end
    end
end

initial begin
    forever begin
        @(posedge clk);
        if (dut.llr_input_inst.in_valid) begin
            $display("[%0t] [INPUT_CTRL] in_valid=1, in_ready=%b, packet_started=%b, size_det=%b, total_target=%0d", 
                     $time, 
                     dut.llr_input_inst.in_ready,
                     dut.llr_input_inst.packet_started,
                     dut.llr_input_inst.size_determined,
                     dut.llr_input_inst.total_llr_target);
        end
    end
end
    
    
// In testbench, add monitoring
initial begin
    forever begin
        @(posedge clk);
        if (dut.rx_udp_hdr_valid && dut.rx_udp_hdr_ready) begin
            $display("[%0t] [TB] UDP header accepted for new packet", $time);
        end
        if (dut.rx_udp_payload_axis_tvalid && dut.rx_udp_payload_axis_tready) begin
            $display("[%0t] [TB] UDP payload data flowing", $time);
        end
    end
end

initial begin
    forever begin
        @(posedge clk);
        if (dut.udp_to_ldpc_fifo_inst.s_axis_tvalid && dut.udp_to_ldpc_fifo_inst.s_axis_tready) begin
            $display("[%0t] [FIFO IN] Data entering async FIFO", $time);
        end
    end
end

initial begin
    forever begin
        @(posedge clk_ldpc);
        if (dut.udp_to_ldpc_fifo_inst.m_axis_tvalid && dut.udp_to_ldpc_fifo_inst.m_axis_tready) begin
            $display("[%0t] [FIFO OUT] Data leaving async FIFO", $time);
        end
    end
end

endmodule

`default_nettype wire


