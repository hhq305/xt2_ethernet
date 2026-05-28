// =============================================================
// tb_top.v : 应用层快速验证测试平台。
// 直接驱动 cmd_decode / img_rx_fb / img_proc / obj_detect 的接口,
// 不实例化 PHY/MAC, 用以验证应用层逻辑。
// =============================================================
`timescale 1ns/1ps
`include "../src/common/pkt_fmt.vh"

module tb_top;
    reg clk = 0;  always #5 clk = ~clk;     // 100MHz
    reg rst_n = 0;

    // ---- DUT: cmd_decode ----
    reg  [7:0] rx_data;
    reg        rx_valid;
    reg [15:0] rx_length;
    wire [7:0]  led;
    wire [31:0] seg;
    wire [1:0]  pmode;
    wire        ack;
    cmd_decode dut_cmd (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_length(rx_length),
        .led_o(led), .seg_bcd_o(seg), .proc_mode_o(pmode), .ack_pulse_o(ack));

    task send_byte(input [7:0] b);
        begin @(posedge clk); rx_data<=b; rx_valid<=1; @(posedge clk); rx_valid<=0; end
    endtask

    task send_led(input [7:0] pat);
        begin
            send_byte(`MAGIC0); send_byte(`MAGIC1);
            send_byte(`CMD_LED_SET);
            send_byte(8'h00); send_byte(8'h01);    // LEN=1
            send_byte(pat);
        end
    endtask

    task send_seg(input [7:0] b0, input [7:0] b1, input [7:0] b2, input [7:0] b3);
        begin
            send_byte(`MAGIC0); send_byte(`MAGIC1);
            send_byte(`CMD_SEG_SET);
            send_byte(8'h00); send_byte(8'h04);
            send_byte(b0); send_byte(b1); send_byte(b2); send_byte(b3);
        end
    endtask

    integer fails = 0;
    initial begin
        rx_data=0; rx_valid=0; rx_length=16'h0006;
        #20 rst_n = 1;
        #50;

        // ---- 关键测试: 连续多个 LED 命令是否都能正确更新 led_o ----
        $display("[%0t] -- send LED 0xF (first)", $time);
        send_led(8'h0F);
        #100;
        $display("[%0t] LED=%h (expect 0F)", $time, led);
        if (led !== 8'h0F) begin $display("FAIL led 0xF"); fails=fails+1; end

        $display("[%0t] -- send LED 0x0 (second, key test)", $time);
        send_led(8'h00);
        #100;
        $display("[%0t] LED=%h (expect 00)", $time, led);
        if (led !== 8'h00) begin $display("FAIL led 0x0 -- FSM 卡死!"); fails=fails+1; end

        $display("[%0t] -- send LED 0xA (third)", $time);
        send_led(8'h0A);
        #100;
        $display("[%0t] LED=%h (expect 0A)", $time, led);
        if (led !== 8'h0A) begin $display("FAIL led 0xA"); fails=fails+1; end

        $display("[%0t] -- send LED 0x5 (fourth)", $time);
        send_led(8'h05);
        #100;
        $display("[%0t] LED=%h (expect 05)", $time, led);
        if (led !== 8'h05) begin $display("FAIL led 0x5"); fails=fails+1; end

        // ---- 原有 SEG 测试 ----
        $display("[%0t] -- send SEG 12 34 56 78", $time);
        send_seg(8'h12, 8'h34, 8'h56, 8'h78);
        #100 $display("[%0t] SEG=%h", $time, seg);
        if (seg !== 32'h12_34_56_78) begin $display("FAIL seg"); fails=fails+1; end

        if (fails==0) $display("==== ALL PASS ====");
        else          $display("==== %0d FAIL ====", fails);
        $finish;
    end
endmodule
