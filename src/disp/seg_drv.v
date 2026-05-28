// =============================================================
// seg_drv.v : 8 位共阳数码管动态扫描驱动
// 输入 32bit 表示 8 个 4bit BCD (低 4bit = 最右位)
// =============================================================
`timescale 1ns/1ps
module seg_drv #(
    parameter CLK_HZ      = 50_000_000,
    parameter SCAN_HZ     = 1000          // 1kHz 扫描
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] bcd_in,            // 仅低 16bit 用于 4 位; 用满 8 位则给 32bit
    output reg  [7:0]  seg_n,             // a..g,dp 共阳低有效
    output reg  [7:0]  sel_n              // 位选 共阳低有效
);
    localparam DIV = CLK_HZ/SCAN_HZ;
    reg [$clog2(DIV)-1:0] dcnt;
    reg [2:0] idx;
    reg [3:0] nib;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin dcnt<=0; idx<=0; end
        else if (dcnt==DIV-1) begin dcnt<=0; idx<=idx+1'b1; end
        else dcnt<=dcnt+1'b1;
    end

    always @(*) begin
        case (idx)
            3'd0: nib = bcd_in[ 3: 0];
            3'd1: nib = bcd_in[ 7: 4];
            3'd2: nib = bcd_in[11: 8];
            3'd3: nib = bcd_in[15:12];
            3'd4: nib = bcd_in[19:16];
            3'd5: nib = bcd_in[23:20];
            3'd6: nib = bcd_in[27:24];
            3'd7: nib = bcd_in[31:28];
        endcase
    end

    // 共阳极段码
    always @(*) begin
        case (nib)
            4'h0: seg_n = 8'hC0; 4'h1: seg_n = 8'hF9;
            4'h2: seg_n = 8'hA4; 4'h3: seg_n = 8'hB0;
            4'h4: seg_n = 8'h99; 4'h5: seg_n = 8'h92;
            4'h6: seg_n = 8'h82; 4'h7: seg_n = 8'hF8;
            4'h8: seg_n = 8'h80; 4'h9: seg_n = 8'h90;
            4'hA: seg_n = 8'h88; 4'hB: seg_n = 8'h83;
            4'hC: seg_n = 8'hC6; 4'hD: seg_n = 8'hA1;
            4'hE: seg_n = 8'h86; 4'hF: seg_n = 8'h8E;
        endcase
        sel_n          = 8'hFF;
        sel_n[idx]     = 1'b0;
    end
endmodule
