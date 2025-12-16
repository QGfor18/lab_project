`timescale 1ns / 1ps

module top(
    input wire clk,             // 100MHz 系统时钟
    input wire uart_rx,         // 串口接收
    output wire uart_tx,        // 串口发送
    input wire [7:0] key,       // SW7-SW0
                                // key[3:0]: 选择输出矩阵
                                // key[4]:   配置模式
    output wire [7:0] led,      // LED7-LED0
                                // led[3:0]: 显示矩阵存储状态
    input wire uart_rx_rst_n,   // 复位信号 (T5)
    input wire btn_print_v1,    // 打印触发按钮 (V1)
    input wire config_en,       // 配置模式使能 (U2)
    input wire btn_calc_u3,     // 计算触发按钮 (U3)
    input wire btn_op0,         // 运算模式按钮0 (R3)
    input wire btn_op1,         // 运算模式按钮1 (V4)
    input wire btn_op2,         // 运算模式按钮2 (V5)
    input wire btn_op3          // 运算模式按钮3 (V2)
);
    
    // 内部信号定义
    wire [7:0] rx_data;
    wire rx_done;
    wire [7:0] tx_data;
    wire tx_start;
    wire tx_busy;
    
    wire btn_print_stable;   // 打印按钮去抖信号
    wire btn_calc_stable;    // 计算按钮去抖信号
    
    // 计算模块接口信号
    wire calc_start;
    wire [3:0] operation_type;
    wire [5:0] matrix_a_dim;
    wire [5:0] matrix_b_dim;
    wire [7:0] scalar_value;
    wire [199:0] matrix_a_data;
    wire [199:0] matrix_b_data;
    wire [399:0] result_data;
    wire [5:0] result_dim;
    wire calc_done;
    wire calc_error;
    
    // 按钮编码组合
    wire [3:0] btn_op = {btn_op3, btn_op2, btn_op1, btn_op0};
    
    // === 1. 实例化 按钮去抖模块 (防抖电路) ===
    debounce u_db_print (
        .clk(clk),
        .rst_n(uart_rx_rst_n),
        .btn_in(btn_print_v1),
        .btn_out(btn_print_stable)
    );
    
    debounce u_db_calc (
        .clk(clk),
        .rst_n(uart_rx_rst_n),
        .btn_in(btn_calc_u3),
        .btn_out(btn_calc_stable)
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
    
    // === 4. 实例化 矩阵计算器 ===
    matrix_calculator u_calc (
        .clk(clk),
        .rst_n(uart_rx_rst_n),
        .start(calc_start),
        .operation_type(operation_type),
        .matrix_a_dim(matrix_a_dim),
        .matrix_b_dim(matrix_b_dim),
        .scalar_value(scalar_value),
        .matrix_a_data(matrix_a_data),
        .matrix_b_data(matrix_b_data),
        .result_data(result_data),
        .result_dim(result_dim),
        .done(calc_done),
        .error(calc_error)
    );
    
    // === 5. 实例化 矩阵IO控制模块 ===
    matrix_io_ctrl u_ctrl (
        .clk(clk), .rst_n(uart_rx_rst_n),
        .rx_data(rx_data), .rx_done(rx_done),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(tx_busy),
        
        .print_trigger(btn_print_stable), // 使用去抖后的 V1
        .sw_select(key[3:0]),             // SW0-SW3 选择矩阵
        .config_en(config_en),            // 配置模式使能 (U2)
        .calc_trigger(btn_calc_stable),   // 计算触发按钮 (U3)
        .btn_op(btn_op),                  // 运算模式按钮编码 (R3,V4,V5,V2)
        .led(led),                        // LED 显示状态
        
        // 计算模块接口
        .calc_start(calc_start),
        .operation_type(operation_type),
        .matrix_a_dim(matrix_a_dim),
        .matrix_b_dim(matrix_b_dim),
        .scalar_value(scalar_value),
        .matrix_a_data(matrix_a_data),
        .matrix_b_data(matrix_b_data),
        .result_data(result_data),
        .result_dim(result_dim),
        .calc_done(calc_done),
        .calc_error(calc_error)
    );
    
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