`timescale 1ns / 1ps
`default_nettype none

module ldpc_output_serializer #(
    parameter TOTAL_BITS = 1920  // Total number of bits to serialize
)(
    input  wire        clk,
    input  wire        rst,

    // From HDL_Algorithm
    input  wire        data_in,
    input  wire        valid_in,
    input  wire        start_in,
    input  wire        end_in,

    // To UDP TX
    output reg [63:0]  tx_data,
    output reg [7:0]   tx_keep,
    output reg         tx_valid,
    input  wire        tx_ready,
    output reg         tx_last,
    output reg         tx_user,

    // Debug signals
    output reg [1:0]   dbg_state,
    output reg [5:0]   dbg_bit_count,
    output reg [13:0]  dbg_total_count,
    output reg [13:0]  dbg_data_in_count
);

    // FSM States
    localparam IDLE        = 2'd0;
    localparam FILL        = 2'd1;
    localparam SEND_FINAL  = 2'd2;

    reg [1:0]   state;
    reg [63:0]  bit_buf;
    reg [5:0]   bit_count;
    reg [13:0]  total_count;
    reg         done_receiving;
    reg         final_tx_sent;

    always @(posedge clk) begin
        if (rst) begin
            state             <= IDLE;
            bit_buf           <= 0;
            bit_count         <= 0;
            total_count       <= 0;
            tx_data           <= 0;
            tx_keep           <= 0;
            tx_valid          <= 0;
            tx_last           <= 0;
            tx_user           <= 0;
            done_receiving    <= 0;
            final_tx_sent     <= 0;
            dbg_data_in_count <= 0;
        end else begin
            // Debug signals
            dbg_state       <= state;
            dbg_bit_count   <= bit_count;
            dbg_total_count <= total_count;

            // Count data bits received
            if (valid_in)
                dbg_data_in_count <= dbg_data_in_count + 1;

            // Default outputs
            tx_valid <= 0;
            tx_last  <= 0;
            tx_user  <= 0;

            case (state)
                IDLE: begin
                    bit_buf        <= 0;
                    bit_count      <= 0;
                    total_count    <= 0;
                    done_receiving <= 0;
                    final_tx_sent  <= 0;
                    if (valid_in) begin
                        bit_buf[0] <= data_in;
                        bit_count  <= 1;
                        total_count <= 1;
                        state <= FILL;
                    end
                end

                FILL: begin
                    if (valid_in && total_count < TOTAL_BITS) begin
                        bit_buf[bit_count] <= data_in;
                        bit_count  <= bit_count + 1;
                        total_count <= total_count + 1;

                        if (bit_count == 63) begin
                            tx_data  <= bit_buf;
                            tx_keep  <= 8'hFF;
                            tx_valid <= 1;
                            tx_user  <= (total_count <= 64);
                            tx_last <= (total_count + 1 == TOTAL_BITS);
                            bit_buf  <= 0;
                            bit_count <= 0;
                        end
                    end

                    if (total_count == TOTAL_BITS)
                        done_receiving <= 1;

                    if (done_receiving && bit_count > 0)
                        state <= SEND_FINAL;
                end

                SEND_FINAL: begin
                    tx_data  <= bit_buf;
                    tx_valid <= 1;
                    tx_keep  <= (1 << ((bit_count + 7) / 8)) - 1;
                    tx_user  <= 0;
                    tx_last  <= 1;

                    if (tx_ready) begin
                        state <= IDLE;
                        bit_buf <= 0;
                        bit_count <= 0;
                        final_tx_sent <= 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

`resetall
