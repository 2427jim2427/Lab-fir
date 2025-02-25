`timescale 1ns / 1ps

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter IDLE = 5'd0,
    parameter INIT_0 = 5'd1,
    parameter INIT_1 = 5'd2,
    parameter INIT_2 = 5'd3,
    parameter COEF_10 = 5'd4,
    parameter COEF_9 = 5'd5,
    parameter COEF_8 = 5'd6,
    parameter COEF_7 = 5'd7,
    parameter COEF_6 = 5'd8,
    parameter COEF_5 = 5'd9,
    parameter COEF_4 = 5'd10,
    parameter COEF_3 = 5'd11,
    parameter COEF_2 = 5'd12,
    parameter COEF_1 = 5'd13,
    parameter COEF_0 = 5'd14,
    parameter OUTPUT = 5'd15,
    parameter WAIT = 5'd16,
    parameter RST_BRAM = 5'd17
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
begin

    // write your code here!
    reg [4:0] curr_state, next_state;
    reg [11:0] addr_buf, data_addr_buf;
    reg signed [31:0] write_buf, data_write_buf, read_buf;
    reg read_flag1, read_flag2, EN_flag, data_EN_flag, WE_flag, data_WE_flag;
    reg [31:0] ap_signals, length;
    reg ap_flag, length_flag;
    reg [3:0] SftReg_ptr;
    reg SftReg_full_flag;
    reg [31:0] AddIn_buf, acc;
    reg ss_tready_buf, sm_tvalid_buf;
    reg [31:0] sm_tdata_buf;
    reg [31:0] cnt;
    reg last_data_flag;
    reg finish_flag;
    reg [3:0] RST_BRAM_cnt;
    
    // BRAM
    assign tap_Di = write_buf;
    assign tap_A = addr_buf<<2;
    assign tap_EN = EN_flag;
    assign tap_WE = {4{WE_flag}};
    assign data_Di = data_write_buf;
    assign data_A = data_addr_buf<<2;
    assign data_EN = data_EN_flag;
    assign data_WE = {4{data_WE_flag}};
    // axi-write
    assign awready = awvalid;
    assign wready = wvalid;
    // axi-read
    assign arready = arvalid;
    assign rvalid = read_flag2;
    assign rdata = read_buf;
    // axi-stream
    assign ss_tready = ss_tready_buf;
    assign sm_tdata = sm_tdata_buf;
    assign sm_tvalid = sm_tvalid_buf;

    always @ (posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            curr_state <= IDLE;
            ap_signals <= 32'h4;
            SftReg_ptr <= 4'h00;
            SftReg_full_flag <= 0;
            AddIn_buf <= 32'd0;
            ss_tready_buf <= 0;
            data_addr_buf <= 12'h00;
            sm_tvalid_buf <= 0;
            sm_tdata_buf <= 32'd0;
            cnt <= 32'd0;
            finish_flag <= 0;
        end
        else begin
            curr_state <= next_state;
            // Coefficient input
            // axilite-write
            if(awvalid) begin
                if(awaddr == 12'h00) begin
                    ap_flag <= 1;
                end
                else ap_flag <= 0;
                if(awaddr == 12'h10) begin
                    length_flag <= 1;
                end
                else length_flag <= 0;
                if(awaddr >= 12'h20) begin
                    addr_buf <= (awaddr - 12'h20) / 12'h04;
                end
            end
            if(wvalid) begin
                if(ap_flag) begin
                    ap_signals <= wdata;
                end
                else if(length_flag) begin
                    length <= wdata;
                end
                else begin
                    write_buf <= wdata;
                    EN_flag <= 1;
                    WE_flag <= 1;
                end
            end
            //axilite-read
            if(arvalid) begin
                if(araddr == 12'h00) begin
                    ap_flag <= 1;
                end
                else ap_flag <= 0;
                if(araddr == 12'h10) begin
                    length_flag <= 1;
                end
                else length_flag <= 0;
                if(araddr >= 12'h20) begin
                    addr_buf <= (araddr - 12'h20) / 12'h04;
                    EN_flag <= 1;
                    WE_flag <= 0;
                end                
            end
            if(rready) begin
                read_flag1 <= 1;
                if(ap_flag)
                    read_buf <= ap_signals;
                else if(length_flag)
                    read_buf <= length;
                else read_buf <= tap_Do; 
            end
            else read_flag1 <= 0;
            read_flag2 <= read_flag1;

            if(ap_signals[0]) begin
                // ap_start = 0, ap_idle = 0
                ap_signals[0] <= 0;
                ap_signals[2] <= 0;
            end
            if(~ap_signals[2]) begin
                if(curr_state == INIT_0) begin
                    // FIR
                    acc <= 32'd0;
                    // Data ram write
                    data_addr_buf <= 12'h00;
                    data_EN_flag <= 1;
                    data_WE_flag <= 1;
                    data_write_buf <= ss_tdata;
                    ss_tready_buf <= 0;
                    // Initialize output signal
                    sm_tvalid_buf <= 0;
                    // Initialize last data flag
                    last_data_flag <= 0;
                end
                if(curr_state == INIT_1) begin
                    // FIR
                    acc <= 32'd0;
                    // Data ram write
                    data_EN_flag <= 1;
                    data_WE_flag <= 1;
                    data_write_buf <= ss_tdata;
                    // Initialize output signal
                    sm_tvalid_buf <= 0;
                end
                else if(curr_state == INIT_2) begin
                    // Tap ram read
                    EN_flag <= 1;
                    WE_flag <= 0;
                    addr_buf <= 12'h0a;
                    // Data ram read
                    data_EN_flag <= 1;
                    data_WE_flag <= 0;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_10) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_9) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_8) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_7) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_6) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_5) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_4) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_3) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_2) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_1) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    addr_buf <= addr_buf - 12'h01;
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;
                end
                else if(curr_state == COEF_0) begin
                    // FIR
                    AddIn_buf <= data_Do * tap_Do;
                    acc <= acc + AddIn_buf;
                    // BRAM addr
                    if(data_addr_buf == 12'h0a)
                            data_addr_buf <= 12'h00;
                    else    data_addr_buf <= data_addr_buf + 12'h01;

                    ss_tready_buf <= 1;
                end
                else if(curr_state == OUTPUT) begin
                    cnt <= cnt + 32'd1;

                    sm_tdata_buf <= acc + AddIn_buf;
                    sm_tvalid_buf <= 1;

                    ss_tready_buf <= 0;
                end
                else if(curr_state == WAIT) begin
                    sm_tvalid_buf <= 0;
                end
                else if(curr_state == RST_BRAM) begin
                    sm_tvalid_buf <= 0;
                    finish_flag <= 0;
                    RST_BRAM_cnt <= RST_BRAM_cnt + 4'd1;
                    // Reset data BRAM value
                    data_EN_flag <= 1;
                    data_WE_flag <= 1;
                    data_write_buf <= 12'h00;
                    if(data_addr_buf == 12'h0a)
                        data_addr_buf <= 12'h00;
                    else
                        data_addr_buf <= data_addr_buf + 12'h01;
                end
                else begin
                
                end
            end
            if(ap_signals[1] == 0 & ap_signals[2] == 1) begin
                // Initialize data BRAM value while coefficient input
                data_EN_flag <= 1;
                data_WE_flag <= 1;
                data_write_buf <= 12'h00;
                if(data_addr_buf == 12'h0a)
                    data_addr_buf <= 12'h00;
                else
                    data_addr_buf <= data_addr_buf + 12'h01;
            end
            if(cnt == length) begin
                cnt <= 32'd0;
                ap_signals[1] <= 1;
                ap_signals[2] <= 1;
                finish_flag <= 1;
                RST_BRAM_cnt <= 4'd0;
            end
        end
    end

    always @ (*) begin
        case (curr_state)
            IDLE: 
                if(ap_signals[0])
                        next_state = INIT_0;
                else    next_state = IDLE;
            INIT_0: next_state = INIT_2;
            INIT_1: next_state = INIT_2;
            INIT_2: next_state = COEF_10;
            COEF_10: next_state = COEF_9;
            COEF_9: next_state = COEF_8;
            COEF_8: next_state = COEF_7;
            COEF_7: next_state = COEF_6;
            COEF_6: next_state = COEF_5;
            COEF_5: next_state = COEF_4;
            COEF_4: next_state = COEF_3;
            COEF_3: next_state = COEF_2;
            COEF_2: next_state = COEF_1;
            COEF_1: next_state = COEF_0;
            COEF_0: next_state = OUTPUT;
            OUTPUT: 
                if(finish_flag)
                        next_state = RST_BRAM;
                else if(cnt == 32'd598)
                        next_state = WAIT;
                else    next_state = INIT_1;
            WAIT:
                if(ss_tlast)
                        next_state = INIT_1;
                else    next_state = WAIT;
            RST_BRAM:
                if(RST_BRAM_cnt == 4'd11)
                        next_state = INIT_0;
                else    next_state = RST_BRAM;
        endcase
    end
end
endmodule
