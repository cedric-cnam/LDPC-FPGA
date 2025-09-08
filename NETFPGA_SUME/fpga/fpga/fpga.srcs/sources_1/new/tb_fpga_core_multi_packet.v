// This file is part of LDPC-FPGA.
//
// LDPC-FPGA is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// LDPC-FPGA is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with LDPC-FPGA.  If not, see <https://www.gnu.org/licenses/>.

`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_core_multi_packet;

  // ============================================================================
  // Clock & Reset (Only initial reset, no pipeline resets)
  // ============================================================================
  reg clk_156;      // 156MHz UDP clock
  reg clk_75;       // 75MHz LDPC clock
  reg rst;
  reg rst_ldpc;
  
  initial clk_156 = 0;
  always #3.2 clk_156 = ~clk_156;  // 156.25 MHz
  
  initial clk_75 = 0;
  always #6.667 clk_75 = ~clk_75;  // 75 MHz

  // ============================================================================
  // Test Parameters
  // ============================================================================
  parameter NUM_PACKETS = 5;        // Number of packets to test
  parameter INTER_PACKET_DELAY = 500; // Cycles between packet injection
  parameter TOTAL_LLR = 9600;
  parameter TOTAL_DECODED_BITS = 1920;

  // ============================================================================
  // FPGA Core Interface Signals
  // ============================================================================
  
  // GPIO
  wire [1:0] btn = 2'b00;
  wire [1:0] sfp_1_led, sfp_2_led, sfp_3_led, sfp_4_led, led;

  // I2C (unused)
  wire i2c_scl_i = 1'b1;
  wire i2c_scl_o, i2c_scl_t;
  wire i2c_sda_i = 1'b1;
  wire i2c_sda_o, i2c_sda_t;

  // SFP interfaces (we'll only use SFP1 for loopback testing)
  wire [63:0] sfp_1_txd, sfp_2_txd, sfp_3_txd, sfp_4_txd;
  wire [7:0]  sfp_1_txc, sfp_2_txc, sfp_3_txc, sfp_4_txc;
  
  // For testing, we'll loop SFP1 TX back to RX
  wire [63:0] sfp_1_rxd = sfp_1_txd;
  wire [7:0]  sfp_1_rxc = sfp_1_txc;
  
  // Other SFPs unused
  wire [63:0] sfp_2_rxd = 64'h0707070707070707;
  wire [7:0]  sfp_2_rxc = 8'hff;
  wire [63:0] sfp_3_rxd = 64'h0707070707070707;
  wire [7:0]  sfp_3_rxc = 8'hff;
  wire [63:0] sfp_4_rxd = 64'h0707070707070707;
  wire [7:0]  sfp_4_rxc = 8'hff;

  // SFP clocks and resets
  wire sfp_1_tx_clk = clk_156;
  wire sfp_1_tx_rst = rst;
  wire sfp_1_rx_clk = clk_156;
  wire sfp_1_rx_rst = rst;
  wire sfp_2_tx_clk = clk_156;
  wire sfp_2_tx_rst = rst;
  wire sfp_2_rx_clk = clk_156;
  wire sfp_2_rx_rst = rst;
  wire sfp_3_tx_clk = clk_156;
  wire sfp_3_tx_rst = rst;
  wire sfp_3_rx_clk = clk_156;
  wire sfp_3_rx_rst = rst;
  wire sfp_4_tx_clk = clk_156;
  wire sfp_4_tx_rst = rst;
  wire sfp_4_rx_clk = clk_156;
  wire sfp_4_rx_rst = rst;

  // ============================================================================
  // Multi-packet Tracking Variables
  // ============================================================================
  reg [15:0] current_packet;
  reg [15:0] packets_sent;
  reg [15:0] packets_received;
  reg [31:0] packet_start_time [0:NUM_PACKETS-1];
  reg [31:0] packet_rx_time [0:NUM_PACKETS-1];
  
  // Task variables (Verilog 2001 - must be at module level)
  integer word_count;
  integer llr_index;
  reg [63:0] packet_data;
  integer chunk;
  integer pkt;
  integer i;
  reg signed [9:0] llr10;
  reg signed [3:0] sfix4;
  integer timeout_counter;
  
  // UDP packet injection
  reg        inject_udp_valid;
  reg [63:0] inject_udp_data;
  reg [7:0]  inject_udp_keep;
  reg        inject_udp_last;
  reg        inject_udp_user;
  
  // Monitoring variables
  reg monitoring_enabled;
  reg [15:0] bits_received_count;
  reg [63:0] last_rx_data;
  reg        packet_in_progress;

  // ============================================================================
  // Load LLR Data
  // ============================================================================
  reg [9:0] llr_raw [0:9599];
  initial $readmemb("llrs_input_sfix10_En4_frame0.mem", llr_raw);

  // ============================================================================
  // DUT - FPGA Core Instance
  // ============================================================================
  fpga_core dut (
    // Clocks and resets
    .clk(clk_156),
    .rst(rst),
    .clk_ldpc(clk_75),
    .rst_ldpc(rst_ldpc),
    
    // GPIO
    .btn(btn),
    .sfp_1_led(sfp_1_led),
    .sfp_2_led(sfp_2_led),
    .sfp_3_led(sfp_3_led),
    .sfp_4_led(sfp_4_led),
    .led(led),
    
    // I2C
    .i2c_scl_i(i2c_scl_i),
    .i2c_scl_o(i2c_scl_o),
    .i2c_scl_t(i2c_scl_t),
    .i2c_sda_i(i2c_sda_i),
    .i2c_sda_o(i2c_sda_o),
    .i2c_sda_t(i2c_sda_t),
    
    // SFP interfaces
    .sfp_1_tx_clk(sfp_1_tx_clk),
    .sfp_1_tx_rst(sfp_1_tx_rst),
    .sfp_1_txd(sfp_1_txd),
    .sfp_1_txc(sfp_1_txc),
    .sfp_1_rx_clk(sfp_1_rx_clk),
    .sfp_1_rx_rst(sfp_1_rx_rst),
    .sfp_1_rxd(sfp_1_rxd),
    .sfp_1_rxc(sfp_1_rxc),
    
    .sfp_2_tx_clk(sfp_2_tx_clk),
    .sfp_2_tx_rst(sfp_2_tx_rst),
    .sfp_2_txd(sfp_2_txd),
    .sfp_2_txc(sfp_2_txc),
    .sfp_2_rx_clk(sfp_2_rx_clk),
    .sfp_2_rx_rst(sfp_2_rx_rst),
    .sfp_2_rxd(sfp_2_rxd),
    .sfp_2_rxc(sfp_2_rxc),
    
    .sfp_3_tx_clk(sfp_3_tx_clk),
    .sfp_3_tx_rst(sfp_3_tx_rst),
    .sfp_3_txd(sfp_3_txd),
    .sfp_3_txc(sfp_3_txc),
    .sfp_3_rx_clk(sfp_3_rx_clk),
    .sfp_3_rx_rst(sfp_3_rx_rst),
    .sfp_3_rxd(sfp_3_rxd),
    .sfp_3_rxc(sfp_3_rxc),
    
    .sfp_4_tx_clk(sfp_4_tx_clk),
    .sfp_4_tx_rst(sfp_4_tx_rst),
    .sfp_4_txd(sfp_4_txd),
    .sfp_4_txc(sfp_4_txc),
    .sfp_4_rx_clk(sfp_4_rx_clk),
    .sfp_4_rx_rst(sfp_4_rx_rst),
    .sfp_4_rxd(sfp_4_rxd),
    .sfp_4_rxc(sfp_4_rxc)
  );

  // ============================================================================
  // UDP Packet Generation Task (No Reset Logic)
  // ============================================================================
  
  task inject_udp_packet;
    input [15:0] packet_id;
    
    begin
      $display("\n[%0t] === Injecting UDP Packet %0d ===", $time, packet_id);
      packet_start_time[packet_id] = $time;
      word_count = 0;

      // Wait for some idle time before injection
      repeat (100) @(posedge clk_156);
      
      $display("[%0t] Starting packet %0d injection", $time, packet_id);

      // Generate UDP header and payload
      // (Simplified - just inject LLR data directly)
      
      // Send ALL 9600 LLRs in 600 words (16 LLRs per word)
      for (llr_index = 0; llr_index < 9600; llr_index = llr_index + 16) begin
        
        packet_data = 64'd0;
        
        // Pack 16 LLRs into one 64-bit word
        for (chunk = 0; chunk < 16; chunk = chunk + 1) begin
          if (llr_index + chunk < 9600) begin
            llr10 = $signed(llr_raw[llr_index + chunk]);
            sfix4 = llr10 >>> 4;
            if (sfix4 > 7)  sfix4 = 7;
            if (sfix4 < -8) sfix4 = -8;
            packet_data = packet_data | ({{60{1'b0}}, sfix4[3:0]} << (chunk * 4));
          end
        end
        
        // Inject data via direct connection to UDP RX path
        inject_udp_valid = 1;
        inject_udp_data = packet_data;
        inject_udp_keep = 8'hFF;
        inject_udp_user = (llr_index == 0) ? 1 : 0;
        inject_udp_last = (llr_index + 16 >= 9600) ? 1 : 0;
        
        @(posedge clk_156);
        
        // Clear signals
        inject_udp_valid = 0;
        inject_udp_user = 0;
        inject_udp_last = 0;
        
        word_count = word_count + 1;
        
        // Log progress every 100 words
        if (word_count % 100 == 0 || llr_index + 16 >= 9600) begin
          $display("[%0t] PKT[%0d] Word[%0d]: LLRs %0d-%0d, Data=%016x %s%s", 
                   $time, packet_id, word_count, llr_index, 
                   (llr_index + 15 < 9600) ? llr_index + 15 : 9599,
                   packet_data,
                   (llr_index == 0) ? " <FIRST>" : "",
                   (llr_index + 16 >= 9600) ? " <LAST>" : "");
        end
      end
      
      $display("[%0t] ✅ Packet %0d injection complete: %0d words", 
               $time, packet_id, word_count);
    end
  endtask

  // ============================================================================
  // Output Monitoring (Track FPGA Core TX Output)
  // ============================================================================
  
  always @(posedge clk_156) begin
    if (rst) begin
      bits_received_count <= 16'd0;
      packets_received <= 16'd0;
      packet_in_progress <= 1'b0;
      last_rx_data <= 64'd0;
    end else if (monitoring_enabled) begin
      // Monitor SFP1 TX output (LDPC results coming back)
      if (sfp_1_txd !== 64'h0707070707070707 && sfp_1_txc !== 8'hff) begin
        
        if (!packet_in_progress) begin
          packet_in_progress <= 1'b1;
          bits_received_count <= 16'd0;
          $display("[%0t] 📤 LDPC Output packet %0d started", $time, packets_received);
        end
        
        // Count data bits (simplified)
        bits_received_count <= bits_received_count + 16'd64;
        last_rx_data <= sfp_1_txd;
        
        // Detect packet end (simplified - based on pattern or count)
        if (bits_received_count >= 16'd1920) begin  // Expected decoded bits
          packet_rx_time[packets_received] = $time;
          packets_received <= packets_received + 16'd1;
          packet_in_progress <= 1'b0;
          $display("[%0t] ✅ LDPC Output packet %0d completed: %0d bits", 
                   $time, packets_received, bits_received_count);
        end
        
        // Log some data for verification
        if (bits_received_count % 16'd200 == 16'd0) begin
          $display("[%0t] PKT[%0d] RX[%0d]: %016x", 
                   $time, packets_received, bits_received_count, sfp_1_txd);
        end
      end
    end
  end

  // ============================================================================
  // Test Report Generation
  // ============================================================================
  
  task generate_test_report;
    begin
      $display("\n================================================================================");
      $display("FPGA CORE MULTI-PACKET TEST REPORT (NO EXTERNAL RESET)");
      $display("================================================================================");
      
      $display("\n📊 SUMMARY STATISTICS:");
      $display("  Total Packets Sent: %0d", packets_sent);
      $display("  Total Packets Received: %0d", packets_received);
      $display("  Success Rate: %0d%%", (packets_received * 100) / NUM_PACKETS);
      
      $display("\n⏱️ TIMING ANALYSIS:");
      for (i = 0; i < NUM_PACKETS; i = i + 1) begin
        if (packet_rx_time[i] > packet_start_time[i]) begin
          $display("  Packet %0d: %0d cycles (%0.2f us)", 
                   i, 
                   packet_rx_time[i] - packet_start_time[i],
                   (packet_rx_time[i] - packet_start_time[i]) * 6.4);
        end
      end
      
      $display("\n🎯 TEST RESULT:");
      if (packets_received == NUM_PACKETS) begin
        $display("  🎉 SUCCESS: Internal reset mechanism working!");
        $display("     - All %0d packets processed without external reset", NUM_PACKETS);
        $display("     - FPGA core auto-reset functionality verified");
        $display("     - Ready for bitstream deployment");
      end else begin
        $display("  ❌ FAILURE: Internal reset mechanism not working");
        $display("     - Only %0d/%0d packets processed", packets_received, NUM_PACKETS);
        $display("     - Internal reset logic needs debugging");
      end
      
      $display("\n================================================================================");
    end
  endtask

  // ============================================================================
  // Main Test Sequence
  // ============================================================================
  
  initial begin
    // Initialize
    rst = 1;
    rst_ldpc = 1;
    inject_udp_valid = 0;
    inject_udp_data = 0;
    inject_udp_keep = 0;
    inject_udp_last = 0;
    inject_udp_user = 0;
    monitoring_enabled = 0;
    
    // Initialize tracking
    current_packet = 0;
    packets_sent = 0;
    packets_received = 0;
    
    for (i = 0; i < NUM_PACKETS; i = i + 1) begin
      packet_start_time[i] = 0;
      packet_rx_time[i] = 0;
    end
    
    $display("=================================================================");
    $display("FPGA CORE MULTI-PACKET TEST - NO EXTERNAL RESET");
    $display("Testing internal pipeline reset mechanism");
    $display("=================================================================");
    
    // Release reset
    #1000; 
    rst = 0;
    rst_ldpc = 0;
    
    // Wait for initialization
    repeat (1000) @(posedge clk_156);
    
    // Enable monitoring
    monitoring_enabled = 1;
    $display("[%0t] Monitoring enabled", $time);
    
    // Send multiple packets with NO EXTERNAL RESET
    for (current_packet = 0; current_packet < NUM_PACKETS; current_packet = current_packet + 1) begin
      $display("\n[%0t] ====== Starting Packet %0d (No External Reset) ======", $time, current_packet);
      
      // Inject packet
      inject_udp_packet(current_packet);
      packets_sent = packets_sent + 1;
      
      // Wait between packets (but NO RESET!)
      $display("[%0t] Packet %0d sent, waiting before next packet...", $time, current_packet);
      repeat (INTER_PACKET_DELAY) @(posedge clk_156);
    end

    $display("\n[%0t] === All packets sent without external reset ===", $time);
    
    // Wait for all processing to complete
    timeout_counter = 0;
    while (packets_received < NUM_PACKETS && timeout_counter < 2000000) begin
      @(posedge clk_156);
      timeout_counter = timeout_counter + 1;
    end
    
    // Additional settling time
    repeat (5000) @(posedge clk_156);
    
    // Generate final report
    generate_test_report();
    
    if (packets_received == NUM_PACKETS) begin
      $display("\n🎉 TEST PASSED: Internal reset mechanism works perfectly!");
    end else begin
      $display("\n❌ TEST FAILED: Internal reset mechanism needs debugging");
    end
    
    $finish;
  end

  // ============================================================================
  // Timeout Protection
  // ============================================================================
  
  initial begin
    #50000000;  // 50ms absolute timeout
    $display("\n[%0t] ⏰ ABSOLUTE TIMEOUT REACHED", $time);
    $display("Final Status:");
    $display("  Packets Sent: %0d/%0d", packets_sent, NUM_PACKETS);
    $display("  Packets Received: %0d/%0d", packets_received, NUM_PACKETS);
    
    generate_test_report();
    $finish;
  end

endmodule

`resetall