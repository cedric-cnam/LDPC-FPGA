`timescale 1ns / 1ps
`default_nettype none

module llr_input_controller #(
    parameter TOTAL_LLR  = 9600,  // ✅ Updated
    parameter FIFO_DEPTH = 9728   // Holds all LLRs
)(
    input  wire        clk,
    input  wire        rst,

    // AXI Stream Input
    input  wire [63:0] in_data,
    input  wire [7:0]  in_keep,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_last,
    input  wire        in_user,

    // To HDL_Algorithm
    output reg  [3:0]  llr_data,
    output reg         llr_valid,
    output reg         llr_start,
    output reg         llr_end,
    input  wire        llr_ready,

    output reg         bgn,
    output reg [15:0]  lifting_size,

    // Debug signals
    output wire [13:0] debug_wr_ptr,
    output wire [13:0] debug_rd_ptr,
    output wire [13:0] debug_fifo_count,
    output wire [13:0] debug_llr_count,
    output wire [63:0] debug_unpacked_data,
    output wire [3:0]  debug_unpack_idx,
    output wire [3:0]  debug_unpacked_val,
    output reg  [13:0] debug_llr_valid_counter,
    output reg         debug_unload_active,
    output reg         debug_fifo_underflow,
    output reg         debug_fifo_blocked
);

    // FIFO
    reg [3:0] fifo [0:FIFO_DEPTH-1];
    reg [13:0] wr_ptr = 0;
    reg [13:0] rd_ptr = 0;
    reg [13:0] fifo_count = 0;

    // Unpacking state
    reg [63:0] unpack_data = 0;
    reg [3:0]  unpack_idx = 0;
    reg        unpacking = 0;
    reg [3:0]  unpacked_val = 0;

    reg [13:0] unpack_count = 0;
    reg [13:0] llr_out_count = 0;
    reg        streaming = 0;

    // Read/Output delay pipeline
    reg [3:0]  fifo_read_val = 0;
    reg        stream_delay  = 0;

    assign in_ready = (!unpacking && fifo_count <= FIFO_DEPTH - 16);

    assign debug_wr_ptr         = wr_ptr;
    assign debug_rd_ptr         = rd_ptr;
    assign debug_fifo_count     = fifo_count;
    assign debug_llr_count      = llr_out_count;
    assign debug_unpacked_data  = unpack_data;
    assign debug_unpack_idx     = unpack_idx;
    assign debug_unpacked_val   = unpacked_val;

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            fifo_count <= 0;
            unpack_data <= 0;
            unpack_idx <= 0;
            unpacking <= 0;
            unpacked_val <= 0;

            llr_data <= 0;
            fifo_read_val <= 0;
            stream_delay <= 0;

            llr_valid <= 0;
            llr_start <= 0;
            llr_end <= 0;
            bgn <= 0;
            lifting_size <= 16'd192;

            unpack_count <= 0;
            llr_out_count <= 0;
            streaming <= 0;

            debug_llr_valid_counter <= 0;
            debug_unload_active <= 0;
            debug_fifo_underflow <= 0;
            debug_fifo_blocked <= 0;
        end else begin
            // UNPACKING
            if (in_valid && in_ready && unpack_count < TOTAL_LLR) begin
                unpack_data <= in_data;
                unpack_idx <= 0;
                unpacking <= 1;
                debug_fifo_blocked <= 0;
                $display("[T%0t] ✅ in_data accepted | FIFO = %0d", $time, fifo_count);
            end

            if (unpacking && unpack_count < TOTAL_LLR) begin
                if (fifo_count < FIFO_DEPTH) begin
                    unpacked_val <= unpack_data[3:0];
                    fifo[wr_ptr] <= unpack_data[3:0];
                    wr_ptr <= wr_ptr + 1;
                    fifo_count <= fifo_count + 1;
                    unpack_data <= unpack_data >> 4;
                    unpack_count <= unpack_count + 1;

                    if (unpack_idx == 15 || unpack_count + 1 == TOTAL_LLR)
                        unpacking <= 0;
                    else
                        unpack_idx <= unpack_idx + 1;

                    $display("[T%0t] ↳ Unpack[%0d] = %0d → FIFO[%0d]", $time, unpack_count, unpack_data[3:0], wr_ptr);
                end else begin
                    debug_fifo_blocked <= 1;
                    $display("[T%0t] ⚠️ FIFO full during unpacking!", $time);
                end
            end else if (unpacking) begin
                unpacking <= 0;
            end

            // ENABLE STREAMING AFTER FULL UNPACK
            if (!streaming && unpack_count >= TOTAL_LLR) begin
                streaming <= 1;
                $display("[T%0t] ▶️ STREAMING ENABLED", $time);
            end

            // DEFAULTS
            llr_valid <= 0;
            llr_start <= 0;
            llr_end <= 0;
            debug_unload_active <= 0;
            debug_fifo_underflow <= 0;

            // PHASE 1: READ
            if (streaming && fifo_count > 0 && llr_out_count < TOTAL_LLR) begin
                fifo_read_val <= fifo[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                fifo_count <= fifo_count - 1;
                stream_delay <= 1;
            end else begin
                stream_delay <= 0;
            end

            // PHASE 2: DELAYED OUTPUT
            if (stream_delay) begin
                llr_data <= fifo_read_val;
                llr_valid <= 1;
                debug_llr_valid_counter <= debug_llr_valid_counter + 1;
                debug_unload_active <= 1;

                llr_start <= (llr_out_count == 0);
                bgn <= (streaming && llr_out_count < TOTAL_LLR);
                llr_end   <= (llr_out_count == TOTAL_LLR - 1);

                $display("[T%0t] 🔁 Output LLR[%0d] = %0d", $time, llr_out_count, fifo_read_val);

                llr_out_count <= llr_out_count + 1;
            end else begin
                llr_data <= 4'd0;
            end

            if (streaming && fifo_count == 0 && llr_out_count < TOTAL_LLR) begin
                debug_fifo_underflow <= 1;
                $display("[T%0t] 🚨 Underflow! FIFO empty while streaming.", $time);
            end
        end
    end

endmodule

`resetall
