`timescale 1ns/1ps
`default_nettype none

module tb_fpga_core;

    localparam integer TOTAL_LLR  = 9600;
    localparam integer TOTAL_BITS = 1920;

    reg clk = 0;
    reg clk_ldpc = 0;
    reg rst = 1;
    reg rst_ldpc = 1;

    always #3.2  clk      = ~clk;
    always #6.666 clk_ldpc = ~clk_ldpc;

    wire [3:0] led;

    fpga_core #(
        .SW_CNT(4),
        .LED_CNT(3),
        .UART_CNT(1),
        .QSFP_CNT(2),
        .CH_CNT(8)
    )
    dut (
        .clk(clk),
        .rst(rst),
        .clk_ldpc(clk_ldpc),
        .rst_ldpc(rst_ldpc),
        .sw(4'd0),
        .led(led),
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

    integer i, f_out;
    reg [9:0] llr_mem [0:TOTAL_LLR-1];
    reg [63:0] word;
    integer llr_idx;
    integer bit_count;

    initial begin
        $readmemb("llrs_input_sfix10_En4_frame0.mem", llr_mem);

        #100;
        rst = 0;
        rst_ldpc = 0;

        force dut.rx_udp_hdr_valid = 1'b1;
        force dut.rx_udp_dest_port = 16'd1234;
        force dut.rx_udp_source_port = 16'd4000;
        force dut.rx_udp_ip_source_ip = 32'hC0A80132;

        llr_idx = 0;

        while (llr_idx < TOTAL_LLR) begin
            word = 64'd0;
            for (i = 0; i < 6 && llr_idx < TOTAL_LLR; i = i + 1) begin
                word[i*10 +: 10] = llr_mem[llr_idx];
                llr_idx = llr_idx + 1;
            end

            force dut.rx_udp_payload_axis_tdata  = word;
            force dut.rx_udp_payload_axis_tkeep  = 8'hFF;
            force dut.rx_udp_payload_axis_tvalid = 1'b1;
            force dut.rx_udp_payload_axis_tlast  = (llr_idx >= TOTAL_LLR);

            @(posedge clk);
            while (!dut.rx_udp_payload_axis_tready) @(posedge clk);

            release dut.rx_udp_payload_axis_tdata;
            release dut.rx_udp_payload_axis_tkeep;
            release dut.rx_udp_payload_axis_tvalid;
            release dut.rx_udp_payload_axis_tlast;

            @(posedge clk);
        end

        release dut.rx_udp_hdr_valid;

        f_out = $fopen("decoded_bits.txt", "w");
        bit_count = 0;

        while (bit_count < TOTAL_BITS) begin
            @(posedge clk);
            if (dut.tx_udp_payload_axis_tvalid) begin
                for (i = 0; i < 64; i = i + 1) begin
                    if (dut.tx_udp_payload_axis_tkeep[i/8]) begin
                        $fwrite(f_out, "%0d\n", dut.tx_udp_payload_axis_tdata[i]);
                        bit_count = bit_count + 1;
                    end
                end
            end
        end

        $fclose(f_out);
        $finish;
    end

endmodule

`default_nettype wire
