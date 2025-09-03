// FIXED DUAL CLOCK LDPC VERSION: 156MHz UDP + 75MHz LDPC
// Built on proven working UDP base with proper clock domain crossing
// ADDED: Multi-packet reset logic based on working testbench
// FIXED: Pipeline reset mechanism ensures all packets are decoded correctly

`resetall
`timescale 1ns / 1ps
`default_nettype none

module fpga_core
(
    /*
     * Clock: 156.25MHz
     * Synchronous reset
     */
    input  wire        clk,
    input  wire        rst,
    
    //ldpc clock: 75MHz
    input  wire clk_ldpc,
    input  wire rst_ldpc,

    /*
     * GPIO
     */
    input  wire [1:0]  btn,
    output wire [1:0]  sfp_1_led,
    output wire [1:0]  sfp_2_led,
    output wire [1:0]  sfp_3_led,
    output wire [1:0]  sfp_4_led,
    output wire [1:0]  led,

    /*
     * I2C
     */
    input  wire        i2c_scl_i,
    output wire        i2c_scl_o,
    output wire        i2c_scl_t,
    input  wire        i2c_sda_i,
    output wire        i2c_sda_o,
    output wire        i2c_sda_t,

    /*
     * Ethernet: SFP+
     */
    input  wire        sfp_1_tx_clk,
    input  wire        sfp_1_tx_rst,
    output wire [63:0] sfp_1_txd,
    output wire [7:0]  sfp_1_txc,
    input  wire        sfp_1_rx_clk,
    input  wire        sfp_1_rx_rst,
    input  wire [63:0] sfp_1_rxd,
    input  wire [7:0]  sfp_1_rxc,
    input  wire        sfp_2_tx_clk,
    input  wire        sfp_2_tx_rst,
    output wire [63:0] sfp_2_txd,
    output wire [7:0]  sfp_2_txc,
    input  wire        sfp_2_rx_clk,
    input  wire        sfp_2_rx_rst,
    input  wire [63:0] sfp_2_rxd,
    input  wire [7:0]  sfp_2_rxc,
    input  wire        sfp_3_tx_clk,
    input  wire        sfp_3_tx_rst,
    output wire [63:0] sfp_3_txd,
    output wire [7:0]  sfp_3_txc,
    input  wire        sfp_3_rx_clk,
    input  wire        sfp_3_rx_rst,
    input  wire [63:0] sfp_3_rxd,
    input  wire [7:0]  sfp_3_rxc,
    input  wire        sfp_4_tx_clk,
    input  wire        sfp_4_tx_rst,
    output wire [63:0] sfp_4_txd,
    output wire [7:0]  sfp_4_txc,
    input  wire        sfp_4_rx_clk,
    input  wire        sfp_4_rx_rst,
    input  wire [63:0] sfp_4_rxd,
    input  wire [7:0]  sfp_4_rxc
);

// ============================================================================
// SIGNAL DECLARATIONS (MUST BE BEFORE USE)
// ============================================================================

// LDPC signals (75MHz domain) - DECLARED EARLY TO AVOID WARNINGS
wire [3:0]  ldpc_data_in;
wire        ldpc_ctrl_start;
wire        ldpc_ctrl_end;
wire        ldpc_ctrl_valid;
wire        ldpc_bgn;
wire [15:0] ldpc_lifting_size_in;

// LDPC output signals (75MHz domain) - DECLARED EARLY TO AVOID WARNINGS
wire        ldpc_data_out;
wire        ldpc_ctrl_out_start;
wire        ldpc_ctrl_out_end;
wire        ldpc_ctrl_out_valid;
wire [15:0] ldpc_lifting_size_out;
wire        ldpc_next_frame;

// ============================================================================
// PIPELINE RESET LOGIC (CRITICAL FOR MULTI-PACKET PROCESSING)
// ============================================================================

// Pipeline reset generation - based on working testbench
reg        pipeline_reset;
reg [7:0]  reset_counter;
reg        packet_completed;
reg        prev_ctrl_out_end;
wire       internal_ldpc_reset;

// Internal reset combines external reset with pipeline reset
assign internal_ldpc_reset = rst_ldpc | pipeline_reset;

// Packet completion detection and auto-reset generation
always @(posedge clk_ldpc) begin
    prev_ctrl_out_end <= ldpc_ctrl_out_end && ldpc_ctrl_out_valid;
    
    if (rst_ldpc) begin
        pipeline_reset <= 1'b0;
        reset_counter <= 8'd0;
        packet_completed <= 1'b0;
    end else begin
        // Detect packet completion (rising edge of ctrl_out_end)
        if ((ldpc_ctrl_out_end && ldpc_ctrl_out_valid) && !prev_ctrl_out_end) begin
            packet_completed <= 1'b1;
        end
        
        // Trigger reset after packet completion with delay
        if (packet_completed && !pipeline_reset && reset_counter == 8'd0) begin
            pipeline_reset <= 1'b1;
            reset_counter <= 8'd75;  // Reset for 75 cycles (1us at 75MHz)
            packet_completed <= 1'b0;
        end else if (reset_counter > 8'd0) begin
            reset_counter <= reset_counter - 8'd1;
            if (reset_counter == 8'd1) begin
                pipeline_reset <= 1'b0;
            end
        end
    end
end

// ============================================================================
// PACKET COUNTER (SYNTHESIZABLE)
// ============================================================================

// Multi-packet tracking (75MHz domain) - Only synthesizable parts
reg [15:0] packets_processed_count;

always @(posedge clk_ldpc) begin
    if (rst_ldpc) begin
        packets_processed_count <= 16'd0;
    end else begin
        // Track packet completion and increment counter
        if ((ldpc_ctrl_out_end && ldpc_ctrl_out_valid) && !prev_ctrl_out_end) begin
            packets_processed_count <= packets_processed_count + 16'd1;
        end
    end
end

// AXI between MAC and Ethernet modules
wire [63:0] rx_axis_tdata;
wire [7:0] rx_axis_tkeep;
wire rx_axis_tvalid;
wire rx_axis_tready;
wire rx_axis_tlast;
wire rx_axis_tuser;

wire [63:0] tx_axis_tdata;
wire [7:0] tx_axis_tkeep;
wire tx_axis_tvalid;
wire tx_axis_tready;
wire tx_axis_tlast;
wire tx_axis_tuser;

// Ethernet frame between Ethernet modules and UDP stack
wire rx_eth_hdr_ready;
wire rx_eth_hdr_valid;
wire [47:0] rx_eth_dest_mac;
wire [47:0] rx_eth_src_mac;
wire [15:0] rx_eth_type;
wire [63:0] rx_eth_payload_axis_tdata;
wire [7:0] rx_eth_payload_axis_tkeep;
wire rx_eth_payload_axis_tvalid;
wire rx_eth_payload_axis_tready;
wire rx_eth_payload_axis_tlast;
wire rx_eth_payload_axis_tuser;

wire tx_eth_hdr_ready;
wire tx_eth_hdr_valid;
wire [47:0] tx_eth_dest_mac;
wire [47:0] tx_eth_src_mac;
wire [15:0] tx_eth_type;
wire [63:0] tx_eth_payload_axis_tdata;
wire [7:0] tx_eth_payload_axis_tkeep;
wire tx_eth_payload_axis_tvalid;
wire tx_eth_payload_axis_tready;
wire tx_eth_payload_axis_tlast;
wire tx_eth_payload_axis_tuser;

// IP frame connections
wire rx_ip_hdr_valid;
wire rx_ip_hdr_ready;
wire [47:0] rx_ip_eth_dest_mac;
wire [47:0] rx_ip_eth_src_mac;
wire [15:0] rx_ip_eth_type;
wire [3:0] rx_ip_version;
wire [3:0] rx_ip_ihl;
wire [5:0] rx_ip_dscp;
wire [1:0] rx_ip_ecn;
wire [15:0] rx_ip_length;
wire [15:0] rx_ip_identification;
wire [2:0] rx_ip_flags;
wire [12:0] rx_ip_fragment_offset;
wire [7:0] rx_ip_ttl;
wire [7:0] rx_ip_protocol;
wire [15:0] rx_ip_header_checksum;
wire [31:0] rx_ip_source_ip;
wire [31:0] rx_ip_dest_ip;
wire [63:0] rx_ip_payload_axis_tdata;
wire [7:0] rx_ip_payload_axis_tkeep;
wire rx_ip_payload_axis_tvalid;
wire rx_ip_payload_axis_tready;
wire rx_ip_payload_axis_tlast;
wire rx_ip_payload_axis_tuser;

wire tx_ip_hdr_valid;
wire tx_ip_hdr_ready;
wire [5:0] tx_ip_dscp;
wire [1:0] tx_ip_ecn;
wire [15:0] tx_ip_length;
wire [7:0] tx_ip_ttl;
wire [7:0] tx_ip_protocol;
wire [31:0] tx_ip_source_ip;
wire [31:0] tx_ip_dest_ip;
wire [63:0] tx_ip_payload_axis_tdata;
wire [7:0] tx_ip_payload_axis_tkeep;
wire tx_ip_payload_axis_tvalid;
wire tx_ip_payload_axis_tready;
wire tx_ip_payload_axis_tlast;
wire tx_ip_payload_axis_tuser;

// UDP frame connections
wire rx_udp_hdr_valid;
wire rx_udp_hdr_ready;
wire [47:0] rx_udp_eth_dest_mac;
wire [47:0] rx_udp_eth_src_mac;
wire [15:0] rx_udp_eth_type;
wire [3:0] rx_udp_ip_version;
wire [3:0] rx_udp_ip_ihl;
wire [5:0] rx_udp_ip_dscp;
wire [1:0] rx_udp_ip_ecn;
wire [15:0] rx_udp_ip_length;
wire [15:0] rx_udp_ip_identification;
wire [2:0] rx_udp_ip_flags;
wire [12:0] rx_udp_ip_fragment_offset;
wire [7:0] rx_udp_ip_ttl;
wire [7:0] rx_udp_ip_protocol;
wire [15:0] rx_udp_ip_header_checksum;
wire [31:0] rx_udp_ip_source_ip;
wire [31:0] rx_udp_ip_dest_ip;
wire [15:0] rx_udp_source_port;
wire [15:0] rx_udp_dest_port;
wire [15:0] rx_udp_length;
wire [15:0] rx_udp_checksum;
wire [63:0] rx_udp_payload_axis_tdata;
wire [7:0] rx_udp_payload_axis_tkeep;
wire rx_udp_payload_axis_tvalid;
wire rx_udp_payload_axis_tready;
wire rx_udp_payload_axis_tlast;
wire rx_udp_payload_axis_tuser;

wire tx_udp_hdr_valid;
wire tx_udp_hdr_ready;
wire [5:0] tx_udp_ip_dscp;
wire [1:0] tx_udp_ip_ecn;
wire [7:0] tx_udp_ip_ttl;
wire [31:0] tx_udp_ip_source_ip;
wire [31:0] tx_udp_ip_dest_ip;
wire [15:0] tx_udp_source_port;
wire [15:0] tx_udp_dest_port;
wire [15:0] tx_udp_length;
wire [15:0] tx_udp_checksum;
wire [63:0] tx_udp_payload_axis_tdata;
wire [7:0] tx_udp_payload_axis_tkeep;
wire tx_udp_payload_axis_tvalid;
wire tx_udp_payload_axis_tready;
wire tx_udp_payload_axis_tlast;
wire tx_udp_payload_axis_tuser;

// FIFO connections (UDP domain - 156MHz)
wire [63:0] rx_fifo_udp_payload_axis_tdata;
wire [7:0] rx_fifo_udp_payload_axis_tkeep;
wire rx_fifo_udp_payload_axis_tvalid;
wire rx_fifo_udp_payload_axis_tready;
wire rx_fifo_udp_payload_axis_tlast;
wire rx_fifo_udp_payload_axis_tuser;

wire [63:0] tx_fifo_udp_payload_axis_tdata;
wire [7:0] tx_fifo_udp_payload_axis_tkeep;
wire tx_fifo_udp_payload_axis_tvalid;
wire tx_fifo_udp_payload_axis_tready;
wire tx_fifo_udp_payload_axis_tlast;
wire tx_fifo_udp_payload_axis_tuser;

// Async FIFO connections (Cross clock domain)
wire [63:0] udp_to_ldpc_tdata;
wire [7:0]  udp_to_ldpc_tkeep;
wire        udp_to_ldpc_tvalid;
wire        udp_to_ldpc_tready;
wire        udp_to_ldpc_tlast;
wire        udp_to_ldpc_tuser;

wire [63:0] ldpc_to_udp_tdata;
wire [7:0]  ldpc_to_udp_tkeep;
wire        ldpc_to_udp_tvalid;
wire        ldpc_to_udp_tready;
wire        ldpc_to_udp_tlast;
wire        ldpc_to_udp_tuser;

// LDPC serializer output
wire [63:0] ldpc_serializer_tdata;
wire [7:0]  ldpc_serializer_tkeep;
wire        ldpc_serializer_tvalid;
wire        ldpc_serializer_tready;
wire        ldpc_serializer_tlast;
wire        ldpc_serializer_tuser;

// Debug signals (156MHz domain)
reg [15:0] debug_udp_rx_count;
reg [15:0] debug_udp_tx_count;
reg [15:0] debug_udp_to_ldpc_count;
reg [15:0] debug_ldpc_to_udp_count;

// Debug signals (75MHz domain)
reg [15:0] debug_ldpc_in_count;
reg [15:0] debug_ldpc_out_count;

// Configuration
wire [47:0] local_mac   = 48'h02_00_00_00_00_00;
wire [31:0] local_ip    = {8'd192, 8'd168, 8'd1,   8'd128};
wire [31:0] gateway_ip  = {8'd192, 8'd168, 8'd1,   8'd1};
wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0};

// IP ports not used
assign rx_ip_hdr_ready = 1'b1;
assign rx_ip_payload_axis_tready = 1'b1;

assign tx_ip_hdr_valid = 1'b0;
assign tx_ip_dscp = 6'd0;
assign tx_ip_ecn = 2'd0;
assign tx_ip_length = 16'd0;
assign tx_ip_ttl = 8'd0;
assign tx_ip_protocol = 8'd0;
assign tx_ip_source_ip = 32'd0;
assign tx_ip_dest_ip = 32'd0;
assign tx_ip_payload_axis_tdata = 64'd0;
assign tx_ip_payload_axis_tkeep = 8'd0;
assign tx_ip_payload_axis_tvalid = 1'b0;
assign tx_ip_payload_axis_tlast = 1'b0;
assign tx_ip_payload_axis_tuser = 1'b0;

// ============================================================================
// UDP Control Logic (PROVEN WORKING - 156MHz domain)
// ============================================================================

// Port filtering - EXACTLY like working version
wire match_cond = rx_udp_dest_port == 16'd1234;
wire no_match = ~match_cond;

reg match_cond_reg;
reg no_match_reg;

always @(posedge clk) begin
    if (rst) begin
        match_cond_reg <= 1'b0;
        no_match_reg <= 1'b0;
    end else begin
        if (rx_udp_payload_axis_tvalid) begin
            if ((~match_cond_reg & ~no_match_reg) |
                (rx_udp_payload_axis_tvalid & rx_udp_payload_axis_tready & rx_udp_payload_axis_tlast)) begin
                match_cond_reg <= match_cond;
                no_match_reg <= no_match;
            end
        end else begin
            match_cond_reg <= 1'b0;
            no_match_reg <= 1'b0;
        end
    end
end

// ============================================================================
// UDP Header Generation with Pipelining (for LDPC TX)
// ============================================================================

// LDPC TX header state machine
reg udp_tx_hdr_state;

// Default PC destination (your PC: 192.168.1.50:5000)
localparam [31:0] DEFAULT_PC_IP   = {8'd192, 8'd168, 8'd1, 8'd50};
localparam [15:0] DEFAULT_PC_PORT = 16'd5000;

// Registered dynamic destination (overridden when receiving a packet)
reg [31:0] udp_tx_dest_ip_reg;
reg [15:0] udp_tx_dest_port_reg;

// Pipelined header outputs (stable across cycles)
reg        tx_udp_hdr_valid_reg;
reg [31:0] tx_udp_ip_dest_ip_reg;
reg [15:0] tx_udp_dest_port_reg;

// UDP TX FSM
always @(posedge clk) begin
    if (rst) begin
        udp_tx_hdr_state        <= 1'b0;
        tx_udp_hdr_valid_reg    <= 1'b0;
        tx_udp_ip_dest_ip_reg   <= 32'd0;
        tx_udp_dest_port_reg    <= 16'd0;
        udp_tx_dest_ip_reg      <= DEFAULT_PC_IP;
        udp_tx_dest_port_reg    <= DEFAULT_PC_PORT;
    end else begin
        tx_udp_hdr_valid_reg <= 1'b0;  // Default deassert every cycle

        case (udp_tx_hdr_state)
            1'b0: begin
                // Trigger header when LDPC output starts
                if (ldpc_to_udp_tvalid && !tx_udp_hdr_valid_reg && !tx_udp_hdr_valid) begin
                    tx_udp_hdr_valid_reg   <= 1'b1;
                    tx_udp_ip_dest_ip_reg  <= udp_tx_dest_ip_reg;
                    tx_udp_dest_port_reg   <= udp_tx_dest_port_reg;
                    udp_tx_hdr_state       <= 1'b1;
                end

                // If receiving a matching packet, update destination info
                if (rx_udp_hdr_valid && match_cond) begin
                    udp_tx_dest_ip_reg   <= rx_udp_ip_source_ip;
                    udp_tx_dest_port_reg <= rx_udp_source_port;
                end
            end

            1'b1: begin
                // Wait for header to be accepted
                if (tx_udp_hdr_ready) begin
                    udp_tx_hdr_state     <= 1'b0;
                end else begin
                    tx_udp_hdr_valid_reg <= 1'b1; // Hold valid high
                end
            end
        endcase
    end
end

// Final UDP TX control logic
wire tx_udp_hdr_valid_response = rx_udp_hdr_valid & match_cond;
assign tx_udp_hdr_valid        = tx_udp_hdr_valid_response | tx_udp_hdr_valid_reg;

assign rx_udp_hdr_ready        = (tx_udp_hdr_ready & match_cond) | no_match;
assign tx_udp_ip_dscp          = 6'd0;
assign tx_udp_ip_ecn           = 2'd0;
assign tx_udp_ip_ttl           = 8'd64;
assign tx_udp_ip_source_ip     = local_ip;
assign tx_udp_ip_dest_ip       = tx_udp_hdr_valid_response ? rx_udp_ip_source_ip : tx_udp_ip_dest_ip_reg;
assign tx_udp_source_port      = rx_udp_dest_port;
assign tx_udp_dest_port        = tx_udp_hdr_valid_response ? rx_udp_source_port : tx_udp_dest_port_reg;
assign tx_udp_length           = 16'd248;
assign tx_udp_checksum         = 16'd0;

// Debug UDP TX header
always @(posedge clk) begin
    if (tx_udp_hdr_valid && tx_udp_hdr_ready) begin
        // Debug counter increment only (no display functions)
        // Synthesis tools will optimize this away if not used
    end
end

// Connect UDP payload
assign tx_udp_payload_axis_tdata = tx_fifo_udp_payload_axis_tdata;
assign tx_udp_payload_axis_tkeep = tx_fifo_udp_payload_axis_tkeep;
assign tx_udp_payload_axis_tvalid = tx_fifo_udp_payload_axis_tvalid;
assign tx_fifo_udp_payload_axis_tready = tx_udp_payload_axis_tready;
assign tx_udp_payload_axis_tlast = tx_fifo_udp_payload_axis_tlast;
assign tx_udp_payload_axis_tuser = tx_fifo_udp_payload_axis_tuser;

assign rx_fifo_udp_payload_axis_tdata = rx_udp_payload_axis_tdata;
assign rx_fifo_udp_payload_axis_tkeep = rx_udp_payload_axis_tkeep;
assign rx_fifo_udp_payload_axis_tvalid = rx_udp_payload_axis_tvalid & match_cond_reg;
assign rx_udp_payload_axis_tready = (rx_fifo_udp_payload_axis_tready & match_cond_reg) | no_match_reg;
assign rx_fifo_udp_payload_axis_tlast = rx_udp_payload_axis_tlast;
assign rx_fifo_udp_payload_axis_tuser = rx_udp_payload_axis_tuser;

// ============================================================================
// DEBUG COUNTERS (156MHz domain)
// ============================================================================
always @(posedge clk) begin
    if (rst) begin
        debug_udp_rx_count <= 16'd0;
        debug_udp_tx_count <= 16'd0;
        debug_udp_to_ldpc_count <= 16'd0;
        debug_ldpc_to_udp_count <= 16'd0;
    end else begin
        // Count UDP RX packets
        if (rx_fifo_udp_payload_axis_tvalid && rx_fifo_udp_payload_axis_tready && rx_fifo_udp_payload_axis_tlast)
            debug_udp_rx_count <= debug_udp_rx_count + 16'd1;
            
        // Count UDP TX packets
        if (tx_fifo_udp_payload_axis_tvalid && tx_fifo_udp_payload_axis_tready && tx_fifo_udp_payload_axis_tlast)
            debug_udp_tx_count <= debug_udp_tx_count + 16'd1;
            
        // Count packets going to LDPC
        if (udp_to_ldpc_tvalid && udp_to_ldpc_tready && udp_to_ldpc_tlast)
            debug_udp_to_ldpc_count <= debug_udp_to_ldpc_count + 16'd1;
            
        // Count packets from LDPC
        if (ldpc_to_udp_tvalid && ldpc_to_udp_tready && ldpc_to_udp_tlast)
            debug_ldpc_to_udp_count <= debug_ldpc_to_udp_count + 16'd1;
    end
end

// ============================================================================
// DEBUG COUNTERS (75MHz domain)
// ============================================================================
always @(posedge clk_ldpc) begin
    if (rst_ldpc) begin
        debug_ldpc_in_count <= 16'd0;
        debug_ldpc_out_count <= 16'd0;
    end else begin
        // Count packets into LDPC pipeline
        if (udp_to_ldpc_tvalid && udp_to_ldpc_tready && udp_to_ldpc_tlast)
            debug_ldpc_in_count <= debug_ldpc_in_count + 16'd1;
            
        // Count packets out of LDPC pipeline
        if (ldpc_serializer_tvalid && ldpc_serializer_tready && ldpc_serializer_tlast)
            debug_ldpc_out_count <= debug_ldpc_out_count + 16'd1;
    end
end

// ============================================================================
// ASYNC FIFO: UDP RX (156MHz) → LDPC (75MHz)
// ============================================================================
axis_async_fifo #(
    .DEPTH(9728),
    .DATA_WIDTH(64),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(8),
    .LAST_ENABLE(1),
    .USER_ENABLE(1),
    .USER_WIDTH(1)
)
udp_to_ldpc_fifo_inst (
    // UDP side (156MHz)
    .s_clk(clk),
    .s_rst(rst),
    .s_axis_tdata(rx_fifo_udp_payload_axis_tdata),
    .s_axis_tkeep(rx_fifo_udp_payload_axis_tkeep),
    .s_axis_tvalid(rx_fifo_udp_payload_axis_tvalid),
    .s_axis_tready(rx_fifo_udp_payload_axis_tready),
    .s_axis_tlast(rx_fifo_udp_payload_axis_tlast),
    .s_axis_tuser(rx_fifo_udp_payload_axis_tuser),

    // LDPC side (75MHz)
    .m_clk(clk_ldpc),
    .m_rst(rst_ldpc),
    .m_axis_tdata(udp_to_ldpc_tdata),
    .m_axis_tkeep(udp_to_ldpc_tkeep),
    .m_axis_tvalid(udp_to_ldpc_tvalid),
    .m_axis_tready(udp_to_ldpc_tready),
    .m_axis_tlast(udp_to_ldpc_tlast),
    .m_axis_tuser(udp_to_ldpc_tuser)
);

// ============================================================================
// LDPC PIPELINE REGISTERS (CRITICAL FOR TIMING)
// ============================================================================

// Pipeline registers between LLR controller and HDL algorithm - WITH INTERNAL RESET
reg [3:0]  ldpc_data_in_reg;
reg        ldpc_ctrl_valid_reg;
reg        ldpc_ctrl_start_reg;
reg        ldpc_ctrl_end_reg;
reg        ldpc_bgn_reg;
reg [15:0] ldpc_lifting_size_in_reg;

always @(posedge clk_ldpc) begin
    if (internal_ldpc_reset) begin
        ldpc_data_in_reg         <= 4'd0;
        ldpc_ctrl_valid_reg      <= 1'b0;
        ldpc_ctrl_start_reg      <= 1'b0;
        ldpc_ctrl_end_reg        <= 1'b0;
        ldpc_bgn_reg             <= 1'b0;
        ldpc_lifting_size_in_reg <= 16'd0;
    end else begin
        ldpc_data_in_reg         <= ldpc_data_in;
        ldpc_ctrl_valid_reg      <= ldpc_ctrl_valid;
        ldpc_ctrl_start_reg      <= ldpc_ctrl_start;
        ldpc_ctrl_end_reg        <= ldpc_ctrl_end;
        ldpc_bgn_reg             <= ldpc_bgn;
        ldpc_lifting_size_in_reg <= ldpc_lifting_size_in;
    end
end

// ============================================================================
// LDPC PIPELINE (75MHz domain with internal reset for proper multi-packet)
// ============================================================================

// LDPC Input Controller (75MHz) - USES INTERNAL RESET
llr_input_controller #(
    .TOTAL_LLR(9600)
) llr_input_inst (
    .clk(clk_ldpc),
    .rst(internal_ldpc_reset),  // ← CRITICAL: Uses pipeline reset

    // From async FIFO
    .in_data(udp_to_ldpc_tdata),
    .in_keep(udp_to_ldpc_tkeep),
    .in_valid(udp_to_ldpc_tvalid),
    .in_ready(udp_to_ldpc_tready),
    .in_last(udp_to_ldpc_tlast),
    .in_user(udp_to_ldpc_tuser),

    // To pipeline registers (not directly to HDL_Algorithm)
    .llr_data(ldpc_data_in),
    .llr_valid(ldpc_ctrl_valid),
    .llr_start(ldpc_ctrl_start),
    .llr_end(ldpc_ctrl_end),
    .llr_ready(1'b1), // Always ready for now

    .bgn(ldpc_bgn),
    .lifting_size(ldpc_lifting_size_in),

    // Debug outputs (unused for now, but available)
    .debug_wr_ptr(),
    .debug_rd_ptr(),
    .debug_fifo_count(),
    .debug_llr_count(),
    .debug_unpacked_data(),
    .debug_unpack_idx(),
    .debug_unpacked_val(),
    .debug_llr_valid_counter(),
    .debug_unload_active(),
    .debug_fifo_underflow(),
    .debug_fifo_blocked()
);

// HDL Algorithm (75MHz) - USES INTERNAL RESET AND REGISTERED SIGNALS
hdl_algorithm_wrapper hdl_algorithm_inst (
    .clk(clk_ldpc),
    .reset(internal_ldpc_reset),        // ← CRITICAL: Uses pipeline reset
    .clk_enable(1'b1),
    .dataIn(ldpc_data_in_reg),          // ← Use registered signal
    .ctrlIn_start(ldpc_ctrl_start_reg), // ← Use registered signal
    .ctrlIn_end(ldpc_ctrl_end_reg),     // ← Use registered signal
    .ctrlIn_valid(ldpc_ctrl_valid_reg), // ← Use registered signal
    .bgn(ldpc_bgn_reg),                 // ← Use registered signal
    .liftingSizeIn(ldpc_lifting_size_in_reg), // ← Use registered signal
    .ce_out(), // unused
    .dataOut(ldpc_data_out),
    .ctrlOut_start(ldpc_ctrl_out_start),
    .ctrlOut_end(ldpc_ctrl_out_end),
    .ctrlOut_valid(ldpc_ctrl_out_valid),
    .liftingSizeOut(ldpc_lifting_size_out),
    .nextFrame(ldpc_next_frame)
);

// LDPC Output Serializer (75MHz) - USES INTERNAL RESET
ldpc_output_serializer #(
    .TOTAL_BITS(1920)
) ldpc_output_inst (
    .clk(clk_ldpc),
    .rst(internal_ldpc_reset),  // ← CRITICAL: Uses pipeline reset

    // From HDL_Algorithm
    .data_in(ldpc_data_out),
    .valid_in(ldpc_ctrl_out_valid),
    .start_in(ldpc_ctrl_out_start),
    .end_in(ldpc_ctrl_out_end),

    // To async FIFO
    .tx_data(ldpc_serializer_tdata),
    .tx_keep(ldpc_serializer_tkeep),
    .tx_valid(ldpc_serializer_tvalid),
    .tx_ready(ldpc_serializer_tready),
    .tx_last(ldpc_serializer_tlast),
    .tx_user(ldpc_serializer_tuser),

    // Debug outputs (unused for now)
    .dbg_state(),
    .dbg_bit_count(),
    .dbg_total_count(),
    .dbg_data_in_count()
);

// ============================================================================
// ASYNC FIFO: LDPC (75MHz) → UDP TX (156MHz)
// ============================================================================
axis_async_fifo #(
    .DEPTH(9728),
    .DATA_WIDTH(64),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(8),
    .LAST_ENABLE(1),
    .USER_ENABLE(1),
    .USER_WIDTH(1)
)
ldpc_to_udp_fifo_inst (
    // LDPC side (75MHz)
    .s_clk(clk_ldpc),
    .s_rst(rst_ldpc),
    .s_axis_tdata(ldpc_serializer_tdata),
    .s_axis_tkeep(ldpc_serializer_tkeep),
    .s_axis_tvalid(ldpc_serializer_tvalid),
    .s_axis_tready(ldpc_serializer_tready),
    .s_axis_tlast(ldpc_serializer_tlast),
    .s_axis_tuser(ldpc_serializer_tuser),

    // UDP side (156MHz)
    .m_clk(clk),
    .m_rst(rst),
    .m_axis_tdata(ldpc_to_udp_tdata),
    .m_axis_tkeep(ldpc_to_udp_tkeep),
    .m_axis_tvalid(ldpc_to_udp_tvalid),
    .m_axis_tready(ldpc_to_udp_tready),
    .m_axis_tlast(ldpc_to_udp_tlast),
    .m_axis_tuser(ldpc_to_udp_tuser)
);

// Connect to UDP TX
assign tx_fifo_udp_payload_axis_tdata = ldpc_to_udp_tdata;
assign tx_fifo_udp_payload_axis_tkeep = ldpc_to_udp_tkeep;
assign tx_fifo_udp_payload_axis_tvalid = ldpc_to_udp_tvalid;
assign ldpc_to_udp_tready = tx_fifo_udp_payload_axis_tready;
assign tx_fifo_udp_payload_axis_tlast = ldpc_to_udp_tlast;
assign tx_fifo_udp_payload_axis_tuser = ldpc_to_udp_tuser;

// ============================================================================
// DEBUG LEDs - Show pipeline activity and multi-packet processing
// ============================================================================
assign led[0] = debug_udp_rx_count[0] ^ debug_ldpc_in_count[0];    // Data flow into LDPC
assign led[1] = debug_ldpc_out_count[0] ^ debug_udp_tx_count[0];   // Data flow out of LDPC

// ============================================================================
// SFP LED Debug - Show actual packet counts and reset activity
// ============================================================================
assign sfp_1_led[0] = debug_udp_rx_count[1];   // UDP RX activity
assign sfp_1_led[1] = debug_udp_tx_count[1];   // UDP TX activity

assign sfp_2_led[0] = packets_processed_count[0]; // LDPC packets processed
assign sfp_2_led[1] = pipeline_reset;             // Pipeline reset activity

// Keep other SFPs idle
assign sfp_2_txd = 64'h0707070707070707;
assign sfp_2_txc = 8'hff;
assign sfp_3_txd = 64'h0707070707070707;
assign sfp_3_txc = 8'hff;
assign sfp_4_txd = 64'h0707070707070707;
assign sfp_4_txc = 8'hff;

assign sfp_3_led = 2'b00;
assign sfp_4_led = 2'b00;

// ============================================================================
// I2C Interface (unused, tie off)
// ============================================================================
assign i2c_scl_o = 1'b1;
assign i2c_scl_t = 1'b1;
assign i2c_sda_o = 1'b1;
assign i2c_sda_t = 1'b1;

// ============================================================================
// Ethernet MAC and UDP Stack (UNCHANGED - 156MHz)
// ============================================================================
eth_mac_10g_fifo #(
    .ENABLE_PADDING(1),
    .ENABLE_DIC(1),
    .MIN_FRAME_LENGTH(64),
    .TX_FIFO_DEPTH(9728),
    .TX_FRAME_FIFO(1),
    .RX_FIFO_DEPTH(9728),
    .RX_FRAME_FIFO(1)
)
eth_mac_10g_fifo_inst (
    .rx_clk(sfp_1_rx_clk),
    .rx_rst(sfp_1_rx_rst),
    .tx_clk(sfp_1_tx_clk),
    .tx_rst(sfp_1_tx_rst),
    .logic_clk(clk),
    .logic_rst(rst),

    .tx_axis_tdata(tx_axis_tdata),
    .tx_axis_tkeep(tx_axis_tkeep),
    .tx_axis_tvalid(tx_axis_tvalid),
    .tx_axis_tready(tx_axis_tready),
    .tx_axis_tlast(tx_axis_tlast),
    .tx_axis_tuser(tx_axis_tuser),

    .rx_axis_tdata(rx_axis_tdata),
    .rx_axis_tkeep(rx_axis_tkeep),
    .rx_axis_tvalid(rx_axis_tvalid),
    .rx_axis_tready(rx_axis_tready),
    .rx_axis_tlast(rx_axis_tlast),
    .rx_axis_tuser(rx_axis_tuser),

    .xgmii_rxd(sfp_1_rxd),
    .xgmii_rxc(sfp_1_rxc),
    .xgmii_txd(sfp_1_txd),
    .xgmii_txc(sfp_1_txc),

    .tx_fifo_overflow(),
    .tx_fifo_bad_frame(),
    .tx_fifo_good_frame(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .rx_fifo_overflow(),
    .rx_fifo_bad_frame(),
    .rx_fifo_good_frame(),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

eth_axis_rx #(
    .DATA_WIDTH(64)
)
eth_axis_rx_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(rx_axis_tdata),
    .s_axis_tkeep(rx_axis_tkeep),
    .s_axis_tvalid(rx_axis_tvalid),
    .s_axis_tready(rx_axis_tready),
    .s_axis_tlast(rx_axis_tlast),
    .s_axis_tuser(rx_axis_tuser),
    .m_eth_hdr_valid(rx_eth_hdr_valid),
    .m_eth_hdr_ready(rx_eth_hdr_ready),
    .m_eth_dest_mac(rx_eth_dest_mac),
    .m_eth_src_mac(rx_eth_src_mac),
    .m_eth_type(rx_eth_type),
    .m_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(rx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
    .busy(),
    .error_header_early_termination()
);

eth_axis_tx #(
    .DATA_WIDTH(64)
)
eth_axis_tx_inst (
    .clk(clk),
    .rst(rst),
    .s_eth_hdr_valid(tx_eth_hdr_valid),
    .s_eth_hdr_ready(tx_eth_hdr_ready),
    .s_eth_dest_mac(tx_eth_dest_mac),
    .s_eth_src_mac(tx_eth_src_mac),
    .s_eth_type(tx_eth_type),
    .s_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
    .s_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(tx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
    .m_axis_tdata(tx_axis_tdata),
    .m_axis_tkeep(tx_axis_tkeep),
    .m_axis_tvalid(tx_axis_tvalid),
    .m_axis_tready(tx_axis_tready),
    .m_axis_tlast(tx_axis_tlast),
    .m_axis_tuser(tx_axis_tuser),
    .busy()
);

udp_complete_64 udp_complete_inst (
    .clk(clk),
    .rst(rst),
    .s_eth_hdr_valid(rx_eth_hdr_valid),
    .s_eth_hdr_ready(rx_eth_hdr_ready),
    .s_eth_dest_mac(rx_eth_dest_mac),
    .s_eth_src_mac(rx_eth_src_mac),
    .s_eth_type(rx_eth_type),
    .s_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
    .s_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
    .m_eth_hdr_valid(tx_eth_hdr_valid),
    .m_eth_hdr_ready(tx_eth_hdr_ready),
    .m_eth_dest_mac(tx_eth_dest_mac),
    .m_eth_src_mac(tx_eth_src_mac),
    .m_eth_type(tx_eth_type),
    .m_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
    .s_ip_hdr_valid(tx_ip_hdr_valid),
    .s_ip_hdr_ready(tx_ip_hdr_ready),
    .s_ip_dscp(tx_ip_dscp),
    .s_ip_ecn(tx_ip_ecn),
    .s_ip_length(tx_ip_length),
    .s_ip_ttl(tx_ip_ttl),
    .s_ip_protocol(tx_ip_protocol),
    .s_ip_source_ip(tx_ip_source_ip),
    .s_ip_dest_ip(tx_ip_dest_ip),
    .s_ip_payload_axis_tdata(tx_ip_payload_axis_tdata),
    .s_ip_payload_axis_tkeep(tx_ip_payload_axis_tkeep),
    .s_ip_payload_axis_tvalid(tx_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(tx_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(tx_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(tx_ip_payload_axis_tuser),
    .m_ip_hdr_valid(rx_ip_hdr_valid),
    .m_ip_hdr_ready(rx_ip_hdr_ready),
    .m_ip_eth_dest_mac(rx_ip_eth_dest_mac),
    .m_ip_eth_src_mac(rx_ip_eth_src_mac),
    .m_ip_eth_type(rx_ip_eth_type),
    .m_ip_version(rx_ip_version),
    .m_ip_ihl(rx_ip_ihl),
    .m_ip_dscp(rx_ip_dscp),
    .m_ip_ecn(rx_ip_ecn),
    .m_ip_length(rx_ip_length),
    .m_ip_identification(rx_ip_identification),
    .m_ip_flags(rx_ip_flags),
    .m_ip_fragment_offset(rx_ip_fragment_offset),
    .m_ip_ttl(rx_ip_ttl),
    .m_ip_protocol(rx_ip_protocol),
    .m_ip_header_checksum(rx_ip_header_checksum),
    .m_ip_source_ip(rx_ip_source_ip),
    .m_ip_dest_ip(rx_ip_dest_ip),
    .m_ip_payload_axis_tdata(rx_ip_payload_axis_tdata),
    .m_ip_payload_axis_tkeep(rx_ip_payload_axis_tkeep),
    .m_ip_payload_axis_tvalid(rx_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(rx_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(rx_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(rx_ip_payload_axis_tuser),
    .s_udp_hdr_valid(tx_udp_hdr_valid),
    .s_udp_hdr_ready(tx_udp_hdr_ready),
    .s_udp_ip_dscp(tx_udp_ip_dscp),
    .s_udp_ip_ecn(tx_udp_ip_ecn),
    .s_udp_ip_ttl(tx_udp_ip_ttl),
    .s_udp_ip_source_ip(tx_udp_ip_source_ip),
    .s_udp_ip_dest_ip(tx_udp_ip_dest_ip),
    .s_udp_source_port(tx_udp_source_port),
    .s_udp_dest_port(tx_udp_dest_port),
    .s_udp_length(tx_udp_length),
    .s_udp_checksum(tx_udp_checksum),
    .s_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
    .s_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
    .s_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready(tx_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
    .m_udp_hdr_valid(rx_udp_hdr_valid),
    .m_udp_hdr_ready(rx_udp_hdr_ready),
    .m_udp_eth_dest_mac(rx_udp_eth_dest_mac),
    .m_udp_eth_src_mac(rx_udp_eth_src_mac),
    .m_udp_eth_type(rx_udp_eth_type),
    .m_udp_ip_version(rx_udp_ip_version),
    .m_udp_ip_ihl(rx_udp_ip_ihl),
    .m_udp_ip_dscp(rx_udp_ip_dscp),
    .m_udp_ip_ecn(rx_udp_ip_ecn),
    .m_udp_ip_length(rx_udp_ip_length),
    .m_udp_ip_identification(rx_udp_ip_identification),
    .m_udp_ip_flags(rx_udp_ip_flags),
    .m_udp_ip_fragment_offset(rx_udp_ip_fragment_offset),
    .m_udp_ip_ttl(rx_udp_ip_ttl),
    .m_udp_ip_protocol(rx_udp_ip_protocol),
    .m_udp_ip_header_checksum(rx_udp_ip_header_checksum),
    .m_udp_ip_source_ip(rx_udp_ip_source_ip),
    .m_udp_ip_dest_ip(rx_udp_ip_dest_ip),
    .m_udp_source_port(rx_udp_source_port),
    .m_udp_dest_port(rx_udp_dest_port),
    .m_udp_length(rx_udp_length),
    .m_udp_checksum(rx_udp_checksum),
    .m_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
    .m_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
    .m_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready(rx_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),
    .ip_rx_busy(),
    .ip_tx_busy(),
    .udp_rx_busy(),
    .udp_tx_busy(),
    .ip_rx_error_header_early_termination(),
    .ip_rx_error_payload_early_termination(),
    .ip_rx_error_invalid_header(),
    .ip_rx_error_invalid_checksum(),
    .ip_tx_error_payload_early_termination(),
    .ip_tx_error_arp_failed(),
    .udp_rx_error_header_early_termination(),
    .udp_rx_error_payload_early_termination(),
    .udp_tx_error_payload_early_termination(),
    .local_mac(local_mac),
    .local_ip(local_ip),
    .gateway_ip(gateway_ip),
    .subnet_mask(subnet_mask),
    .clear_arp_cache(1'b0)
);

endmodule

`resetall