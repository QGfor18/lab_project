`timescale 1ns / 1ps

module top(
    input wire clk,             // 100MHz 系统时钟
    input wire uart_rx,         // 串口接收引脚
    output wire uart_tx,        // 串口发送引脚
    input wire [7:0] key,       // SW7-SW0
                                // key[3:0]: 选择输出矩阵
                                // key[4]:   进入配置模式
    output wire [7:0] led,      // LED7-LED0
                                // led[3:0]: 显示矩阵存储状态
    input wire uart_rx_rst_n,   // 复位按键 (T5)
    input wire btn_print_v1     // 打印触发按键 (V1)
);
    
    // 内部信号连接
    wire [7:0] rx_data;
    wire rx_done;
    wire [7:0] tx_data;
    wire tx_start;
    wire tx_busy;
    
    wire btn_print_stable; // 消抖后的按键信号
    
    // === 1. 实例化 按键消抖模块 (代码见下方) ===
    debounce u_db (
        .clk(clk),
        .rst_n(uart_rx_rst_n),
        .btn_in(btn_print_v1),
        .btn_out(btn_print_stable)
    );
    
    // === 2. 实例化 UART 接收 ===
    uart_rx #( .CLK_FREQ(100_000_000), .BAUD_RATE(115200) ) u_rx (
        .clk(clk), .rst_n(uart_rx_rst_n),
        .rx(uart_rx), .rx_data(rx_data), .rx_done(rx_done)
    );
    
    // === 3. 实例化 UART 发送 ===
    uart_tx #( .CLK_FREQ(100_000_000), .BAUD_RATE(115200) ) u_tx (
        .clk(clk), .rst_n(uart_rx_rst_n),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(uart_tx), .tx_busy(tx_busy)
    );
    
    // === 4. 实例化 核心控制模块 ===
    matrix_io_ctrl u_ctrl (
        .clk(clk), .rst_n(uart_rx_rst_n),
        .rx_data(rx_data), .rx_done(rx_done),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(tx_busy),
        
        .print_trigger(btn_print_stable), // 使用消抖后的 V1
        .sw_select(key[3:0]),             // SW0-SW3 选择输出
        .config_en(key[4]),               // SW4 开启配置模式
        .led(led[3:0])                    // LED 显示状态
    );
    
    // 关闭未使用的 LED
    assign led[7:4] = 4'b0000;
    
endmodule
`timescale 1ns / 1ps

module debounce(
    input wire clk,       
    input wire rst_n,
    input wire btn_in,    
    output reg btn_out    
);
    // 20ms @ 100MHz = 2,000,000 cycles
    parameter CNT_MAX = 2_000_000;
    
    reg [20:0] cnt;
    reg btn_d1, btn_d2;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            btn_d1 <= 0; btn_d2 <= 0;
        end else begin
            btn_d1 <= btn_in;
            btn_d2 <= btn_d1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt <= 0; btn_out <= 0;
        end else begin
            if(btn_d2 != btn_out) begin
                cnt <= cnt + 1;
                if(cnt >= CNT_MAX) begin
                    btn_out <= btn_d2;
                    cnt <= 0;
                end
            end else begin
                cnt <= 0;
            end
        end
    end
endmodule