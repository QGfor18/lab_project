`timescale 1ns / 1ps

module top(
    input wire clk,             
    input wire uart_rx,         
    output wire uart_tx,        
    input wire [7:0] key,       // key[3:0] 对应 SW3-SW0
    output wire [7:0] led,      // led[3:0] 显示存储状态
    input wire uart_rx_rst_n,   // 复位 T5
    input wire btn_print_v1     // 打印按钮 V1
);
    
    // 信号连接
    wire [7:0] rx_data;
    wire rx_done;
    wire [7:0] tx_data;
    wire tx_start;
    wire tx_busy;
    
    // 消抖信号
    wire btn_print_stable;
    
    // === 实例化 消抖模块 ===
    debounce u_db (
        .clk(clk),
        .rst_n(uart_rx_rst_n),
        .btn_in(btn_print_v1),
        .btn_out(btn_print_stable)
    );
    
    // UART RX
    uart_rx #( .CLK_FREQ(100_000_000), .BAUD_RATE(115200) ) u_rx (
        .clk(clk), .rst_n(uart_rx_rst_n),
        .rx(uart_rx), .rx_data(rx_data), .rx_done(rx_done)
    );
    
    // UART TX
    uart_tx #( .CLK_FREQ(100_000_000), .BAUD_RATE(115200) ) u_tx (
        .clk(clk), .rst_n(uart_rx_rst_n),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(uart_tx), .tx_busy(tx_busy)
    );
    
    // === 核心控制模块 ===
    matrix_io_ctrl u_ctrl (
        .clk(clk), .rst_n(uart_rx_rst_n),
        .rx_data(rx_data), .rx_done(rx_done),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(tx_busy),
        
        // 关键连接修改
        .print_trigger(btn_print_stable), // 使用消抖后的 V1 信号
        .sw_select(key[3:0]),             // 使用 SW0-SW3 选择输出矩阵
        .led(led[3:0])                    // LED0-3 显示存储状态
    );
    
    // 未使用的 LED 熄灭
    assign led[7:4] = 4'b0000;
    
endmodule
`timescale 1ns / 1ps

module debounce(
    input wire clk,       // 100MHz
    input wire rst_n,
    input wire btn_in,    // 原始按键输入
    output reg btn_out    // 消抖后的按键输出
);

    // 20ms 消抖时间: 100MHz * 0.02s = 2,000,000
    parameter CNT_MAX = 2_000_000;
    
    reg [20:0] cnt;
    reg btn_d1, btn_d2;
    
    // 跨时钟域打两拍，消除亚稳态
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            btn_d1 <= 0;
            btn_d2 <= 0;
        end else begin
            btn_d1 <= btn_in;
            btn_d2 <= btn_d1;
        end
    end

    // 计数器消抖逻辑
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt <= 0;
            btn_out <= 0;
        end else begin
            // 如果输入状态变化，重置计数器
            if(btn_d2 != btn_out) begin
                cnt <= cnt + 1;
                if(cnt >= CNT_MAX) begin
                    btn_out <= btn_d2; // 状态稳定，更新输出
                    cnt <= 0;
                end
            end else begin
                cnt <= 0; // 状态未变，清零
            end
        end
    end
endmodule