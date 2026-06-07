module vga_disp
(
    input              clk25M,
    input              reset_n,
    input      [11:0]  rgb,

    output             VGA_HSYNC,
    output             VGA_VSYNC,
    output reg         de,
    output reg [9:0]   img_x,
    output reg [8:0]   img_y,
    output reg         line_req,
    output reg [8:0]   line_req_y,
    output reg         vblank_pulse,
    output     [18:0]  addr,       // legacy port for vga_bmp compatibility

    output reg [11:0]  VGA_D
);

reg       hs;
reg       vs;
reg [9:0] hcnt;
reg [9:0] vcnt;
reg [9:0] hcnt_d;
reg [9:0] vcnt_d;

// VGA timing remains 640x480, but show the 400x288 SDRAM frame 1:1
// in the center.  The 384x288 photo is centered inside this burst-aligned frame.
wire        dis_en = (hcnt >= 10'd120) && (hcnt < 10'd520) &&
                     (vcnt >= 10'd96) && (vcnt < 10'd384);
wire [9:0]  src_x = hcnt - 10'd120;
wire [8:0]  src_y = vcnt[8:0] - 9'd96;

assign VGA_VSYNC = vs;
assign VGA_HSYNC = hs;
assign addr = dis_en ? ({1'b0, src_y, 8'd0} + {3'b000, src_y, 7'd0} + {4'b0000, src_y, 4'd0} + {9'd0, src_x}) : 19'd0; // y*400 + x

always @(posedge clk25M or negedge reset_n) begin
    if(!reset_n)
        hcnt <= 0;
    else begin
        if (hcnt < 10'd799)
            hcnt <= hcnt + 1'b1;
        else
            hcnt <= 0;
    end
end

always @(posedge clk25M or negedge reset_n) begin
    if(!reset_n)
        vcnt <= 0;
    else begin
        if (hcnt == 10'd799) begin
            if (vcnt < 10'd524)
                vcnt <= vcnt + 1'b1;
            else
                vcnt <= 0;
        end
    end
end

always @(posedge clk25M or negedge reset_n) begin
    if(!reset_n)
        hs <= 1;
    else begin
        if((hcnt >=640+8+8) & (hcnt < 640+8+8+96))
            hs <= 1'b0;
        else
            hs <= 1'b1;
    end
end

always @(vcnt or reset_n) begin
    if(!reset_n)
        vs = 1;
    else begin
        if((vcnt >= 480+8+2) &&(vcnt < 480+8+2+2))
            vs = 1'b0;
        else
            vs = 1'b1;
    end
end

// Request current/next visible image line ahead of active display.
always @(posedge clk25M or negedge reset_n) begin
    if(!reset_n) begin
        hcnt_d       <= 0;
        vcnt_d       <= 0;
        line_req     <= 1'b0;
        line_req_y   <= 9'd0;
        vblank_pulse <= 1'b0;
    end else begin
        hcnt_d       <= hcnt;
        vcnt_d       <= vcnt;
        line_req     <= 1'b0;
        vblank_pulse <= 1'b0;

        // Pulse once per visible 400x288 source line in the centered window.
        if (hcnt == 10'd120 && vcnt >= 10'd96 && vcnt < 10'd384) begin
            line_req   <= 1'b1;
            line_req_y <= vcnt[8:0] - 9'd96;
        end

        if (hcnt == 10'd0 && vcnt == 10'd480)
            vblank_pulse <= 1'b1;
    end
end

always @(posedge clk25M or negedge reset_n) begin
    if(!reset_n) begin
        de    <= 1'b0;
        img_x <= 10'd0;
        img_y <= 9'd0;
        VGA_D <= 12'd0;
    end else begin
        de <= dis_en;
        if (dis_en) begin
            img_x <= src_x;
            img_y <= src_y;
            // RGB444 -> VGA RGB444
            VGA_D <= rgb;
        end else if((hcnt>=0 && hcnt<2) || (vcnt>=0 && vcnt<2) || (hcnt<=639 && hcnt>637) || (vcnt>477 && vcnt<=479)) begin
            VGA_D <= 12'hf00;
            img_x <= 10'd0;
            img_y <= 9'd0;
        end else begin
            VGA_D <= 12'd0;
            img_x <= 10'd0;
            img_y <= 9'd0;
        end
    end
end

endmodule
