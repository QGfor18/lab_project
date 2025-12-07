`timescale 1ns / 1ps

module matrix_io_ctrl(
    input wire clk,
    input wire rst_n,
    
    // UART 接口
    input wire [7:0] rx_data,
    input wire rx_done,
    output reg [7:0] tx_data,
    output reg tx_start,
    input wire tx_busy,
    
    // 控制接口
    input wire print_trigger,    // 消抖后的按键信号 (高电平有效)
    input wire [3:0] sw_select,  // SW3-SW0 选择开关
    output wire [3:0] led        // LED3-LED0 显示存储状态
);

    // ==========================================
    // 1. 存储定义
    // ==========================================
    reg [7:0] matrix_mem [0:3][0:24]; // 4个矩阵
    reg [2:0] stored_m [0:3];
    reg [2:0] stored_n [0:3];
    
    reg [1:0] wr_ptr;                 // 写指针 (0-3)
    reg [3:0] valid_mask;             // 有效位标记 (1代表有数据)
    
    reg [4:0] data_cnt;
    
    // LED 直接对应有效位，亮=有数据
    assign led = valid_mask;

    // ==========================================
    // 2. 输入解析状态机
    // ==========================================
    localparam S_RX_IDLE    = 0;
    localparam S_RX_GET_M   = 1;
    localparam S_RX_GET_N   = 2;
    localparam S_RX_DATA    = 3;
    
    reg [2:0] rx_state;
    reg [7:0] num_buffer;
    reg       num_valid;

    // ASCII 解析
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            num_buffer <= 0;
            num_valid <= 0;
        end else begin
            num_valid <= 0;
            if(rx_done) begin
                if(rx_data >= "0" && rx_data <= "9") begin
                    num_buffer <= rx_data - "0"; 
                end
                else if(rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) begin
                    num_valid <= 1; 
                end
            end
        end
    end

    // 写入控制
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_state <= S_RX_IDLE;
            wr_ptr <= 0;
            valid_mask <= 0;
            data_cnt <= 0;
        end else begin
            case(rx_state)
                S_RX_IDLE: begin
                    if(num_valid) begin
                        stored_m[wr_ptr] <= num_buffer[2:0];
                        if(num_buffer > 0 && num_buffer <= 5) rx_state <= S_RX_GET_N;
                    end
                end
                
                S_RX_GET_N: begin
                    if(num_valid) begin
                        stored_n[wr_ptr] <= num_buffer[2:0];
                        data_cnt <= 0;
                        if(num_buffer > 0 && num_buffer <= 5) rx_state <= S_RX_DATA;
                        else rx_state <= S_RX_IDLE;
                    end
                end
                
                S_RX_DATA: begin
                    if(num_valid) begin
                        matrix_mem[wr_ptr][data_cnt] <= num_buffer;
                        
                        if(data_cnt == (stored_m[wr_ptr] * stored_n[wr_ptr]) - 1) begin
                            // 当前矩阵写满
                            valid_mask[wr_ptr] <= 1'b1; // 标记 LED 亮
                            wr_ptr <= wr_ptr + 1;       // 指向下一个槽位
                            rx_state <= S_RX_IDLE;
                        end else begin
                            data_cnt <= data_cnt + 1;
                        end
                    end
                end
            endcase
        end
    end

    // ==========================================
    // 3. 输出控制状态机 (支持 SW 选择)
    // ==========================================
    localparam T_IDLE       = 0;
    localparam T_PRINT_NUM  = 1;
    localparam T_WAIT_NUM   = 2;
    localparam T_PRINT_SP   = 3;
    localparam T_WAIT_SP    = 4;
    localparam T_PRINT_CR   = 5;
    localparam T_WAIT_CR    = 6;
    localparam T_PRINT_LF   = 7;
    localparam T_WAIT_LF    = 8;

    reg [3:0] tx_state;
    reg [1:0] rd_ptr;       // 读指针
    reg [4:0] rd_idx;
    reg [2:0] r_cnt, c_cnt;

    // 边沿检测消抖后的按键信号
    reg trig_d1, trig_d2;
    wire trig_pos = trig_d1 & ~trig_d2;
    always @(posedge clk) begin trig_d1 <= print_trigger; trig_d2 <= trig_d1; end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tx_state <= T_IDLE;
            tx_start <= 0;
            tx_data <= 0;
        end else begin
            tx_start <= 0; 

            case(tx_state)
                T_IDLE: begin
                    if(trig_pos) begin
                        // 优先级选择逻辑：SW0 > SW1 > SW2 > SW3
                        // 且必须该位置 valid_mask 为 1 (有数据) 才能打印
                        if(sw_select[0] && valid_mask[0]) begin
                            rd_ptr <= 0; tx_state <= T_PRINT_NUM;
                        end else if(sw_select[1] && valid_mask[1]) begin
                            rd_ptr <= 1; tx_state <= T_PRINT_NUM;
                        end else if(sw_select[2] && valid_mask[2]) begin
                            rd_ptr <= 2; tx_state <= T_PRINT_NUM;
                        end else if(sw_select[3] && valid_mask[3]) begin
                            rd_ptr <= 3; tx_state <= T_PRINT_NUM;
                        end
                        // 如果没选中任何开关，或选中的是空的，则不动作
                        
                        // 初始化计数器
                        rd_idx <= 0;
                        r_cnt <= 0;
                        c_cnt <= 0;
                    end
                end

                T_PRINT_NUM: begin
                    tx_data <= matrix_mem[rd_ptr][rd_idx] + "0";
                    tx_start <= 1;
                    tx_state <= T_WAIT_NUM;
                end
                
                T_WAIT_NUM: if(!tx_busy) tx_state <= T_PRINT_SP;

                T_PRINT_SP: begin
                    tx_data <= " ";
                    tx_start <= 1;
                    tx_state <= T_WAIT_SP;
                end

                T_WAIT_SP: begin
                    if(!tx_busy) begin
                        if(c_cnt == stored_n[rd_ptr] - 1) tx_state <= T_PRINT_CR;
                        else begin
                            c_cnt <= c_cnt + 1;
                            rd_idx <= rd_idx + 1;
                            tx_state <= T_PRINT_NUM;
                        end
                    end
                end

                T_PRINT_CR: begin
                    tx_data <= 8'h0D; tx_start <= 1; tx_state <= T_WAIT_CR;
                end
                
                T_WAIT_CR: if(!tx_busy) tx_state <= T_PRINT_LF;

                T_PRINT_LF: begin
                    tx_data <= 8'h0A; tx_start <= 1; tx_state <= T_WAIT_LF;
                end

                T_WAIT_LF: begin
                    if(!tx_busy) begin
                        if(r_cnt == stored_m[rd_ptr] - 1) tx_state <= T_IDLE;
                        else begin
                            c_cnt <= 0;
                            r_cnt <= r_cnt + 1;
                            rd_idx <= rd_idx + 1;
                            tx_state <= T_PRINT_NUM;
                        end
                    end
                end
            endcase
        end
    end

endmodule