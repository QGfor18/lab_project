`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/10 21:32:16
// Design Name: 
// Module Name: uart_tx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_tx #(
    parameter CLK_FREQ = 100000000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire tx_start,         // ���������ź�
    input wire [7:0] tx_data,    // Ҫ���͵��ֽ�
    output reg tx,               // ���������
    output reg tx_busy           // ����æ��־
);

    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

    reg [15:0] baud_cnt;
    reg [3:0] bit_idx;
    reg [8:0] tx_shift;  // 9位：停止位(1) + 数据(8位)

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            baud_cnt <= 0;
            bit_idx <= 0;
            tx_shift <= 9'b111111111;
            tx <= 1'b1;
            tx_busy <= 1'b0;
        end else begin
            if(tx_start && !tx_busy) begin
                // 格式：起始位(0) + 数据(LSB first) + 停止位(1)
                // 直接加载数据位到tx_shift，起始位立即输出
                tx_shift <= {1'b1, tx_data};  // 9位：停止位 + 8位数据
                tx_busy <= 1'b1;
                baud_cnt <= 0;
                bit_idx <= 0;
                tx <= 1'b0;  // 立即输出起始位
            end else if(tx_busy) begin
                if(baud_cnt < BAUD_DIV - 1) begin
                    baud_cnt <= baud_cnt + 1;
                end else begin
                    baud_cnt <= 0;
                    tx <= tx_shift[0];  // 输出当前最低位
                    tx_shift <= {1'b1, tx_shift[8:1]};  // 右移一位
                    bit_idx <= bit_idx + 1;
                    if(bit_idx == 8) begin  // 发送完8位数据+1位停止位=9位
                        tx_busy <= 1'b0;
                        tx <= 1'b1;  // 确保回到空闲高电平
                    end
                end
            end
        end
    end
endmodule
