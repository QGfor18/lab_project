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
    input wire print_trigger,    // 消抖后的 V1 按键信号
    input wire [3:0] sw_select,  // SW3-SW0 选择输出矩阵
    input wire config_en,        // SW4 配置模式使能
    output wire [3:0] led        // LED3-LED0 显示存储状态
);

    // ==========================================
    // 1. 存储与参数定义
    // ==========================================
    // 物理硬件上限 (Hard Limit)，代码写死为4，不能动态改大
    localparam MAX_PHYSICAL_CAP = 4; 
    
    reg [7:0] matrix_mem [0:MAX_PHYSICAL_CAP-1][0:24]; // 4个矩阵, 每个最大25元素
    reg [2:0] stored_m [0:MAX_PHYSICAL_CAP-1];         // 存储行数
    reg [2:0] stored_n [0:MAX_PHYSICAL_CAP-1];         // 存储列数
    
    reg [2:0] wr_ptr;                 // 写指针
    reg [MAX_PHYSICAL_CAP-1:0] valid_mask; // 有效位标记
    reg [4:0] data_cnt;               // 数据计数器

    // [逻辑最大数量] 用户可通过 UART 修改，默认值为 2
    reg [2:0] max_cnt; 

    // LED 显示：显示有效数据，但被 max_cnt 掩码限制 (例如设为2时，LED2/3不会亮)
    assign led = valid_mask & ((1 << max_cnt) - 1);

    // ==========================================
    // 2. 输入解析与控制状态机
    // ==========================================
    localparam S_RX_IDLE    = 0;
    localparam S_RX_GET_M   = 1;
    localparam S_RX_GET_N   = 2;
    localparam S_RX_DATA    = 3;
    localparam S_RX_CONFIG  = 4; // 配置模式状态
    
    reg [2:0] rx_state;
    reg [7:0] num_buffer;
    reg       num_valid;

    // --- ASCII 解析逻辑 ---
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
                // 遇到空格或回车认为数字输入结束
                else if(rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) begin
                    num_valid <= 1; 
                end
            end
        end
    end

    // --- 核心控制逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_state <= S_RX_IDLE;
            wr_ptr <= 0;
            valid_mask <= 0;
            data_cnt <= 0;
            max_cnt <= 2; // [默认值] 复位后默认存2个
        end else begin
            // 强制进入配置模式逻辑 (SW4 优先级最高)
            if (config_en && rx_state != S_RX_CONFIG) begin
                rx_state <= S_RX_CONFIG;
            end
            else if (!config_en && rx_state == S_RX_CONFIG) begin
                rx_state <= S_RX_IDLE;
            end
            else begin
                case(rx_state)
                    S_RX_IDLE: begin
                        if(num_valid) begin
                            stored_m[wr_ptr] <= num_buffer[2:0];
                            // 维度检查 1~5
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
                            // 硬件保护：防止越界写入
                            if(wr_ptr < MAX_PHYSICAL_CAP)
                                matrix_mem[wr_ptr][data_cnt] <= num_buffer;
                            
                            // 判断矩阵是否填满
                            if(data_cnt == (stored_m[wr_ptr] * stored_n[wr_ptr]) - 1) begin
                                valid_mask[wr_ptr] <= 1'b1;
                                
                                // [回绕逻辑] 基于用户设定的 max_cnt
                                if(wr_ptr >= max_cnt - 1) 
                                    wr_ptr <= 0;
                                else 
                                    wr_ptr <= wr_ptr + 1;
                                    
                                rx_state <= S_RX_IDLE;
                            end else begin
                                data_cnt <= data_cnt + 1;
                            end
                        end
                    end

                    // [配置模式逻辑]
                    S_RX_CONFIG: begin
                        if(num_valid) begin
                            // 输入值钳位：不能超过物理上限 4，不能小于 1
                            if(num_buffer == 0) max_cnt <= 1;
                            else if(num_buffer <= MAX_PHYSICAL_CAP) max_cnt <= num_buffer[2:0];
                            else max_cnt <= MAX_PHYSICAL_CAP; 
                            
                            // 配置改变后，重置指针和数据
                            wr_ptr <= 0;
                            valid_mask <= 0; 
                        end
                    end
                endcase
            end
        end
    end

    // ==========================================
    // 3. 输出格式化状态机
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
    reg [1:0] rd_ptr;      
    reg [4:0] rd_idx;
    reg [2:0] r_cnt, c_cnt;

    // 边沿检测打印触发信号
    reg trig_d1, trig_d2;
    wire trig_pos = trig_d1 & ~trig_d2;
    always @(posedge clk) begin trig_d1 <= print_trigger; trig_d2 <= trig_d1; end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tx_state <= T_IDLE;
            tx_start <= 0; tx_data <= 0;
        end else begin
            tx_start <= 0; 
            case(tx_state)
                T_IDLE: begin
                    if(trig_pos) begin
                        // 检查开关选择 & 数据有效性 & max_cnt 限制
                        // 优先级：SW0 > SW1 > SW2 > SW3
                        if(sw_select[0] && valid_mask[0] && max_cnt >= 1) begin
                            rd_ptr <= 0; tx_state <= T_PRINT_NUM;
                        end else if(sw_select[1] && valid_mask[1] && max_cnt >= 2) begin
                            rd_ptr <= 1; tx_state <= T_PRINT_NUM;
                        end else if(sw_select[2] && valid_mask[2] && max_cnt >= 3) begin
                            rd_ptr <= 2; tx_state <= T_PRINT_NUM;
                        end else if(sw_select[3] && valid_mask[3] && max_cnt >= 4) begin
                            rd_ptr <= 3; tx_state <= T_PRINT_NUM;
                        end
                        // 初始化打印计数器
                        rd_idx <= 0; r_cnt <= 0; c_cnt <= 0;
                    end
                end

                T_PRINT_NUM: begin
                    tx_data <= matrix_mem[rd_ptr][rd_idx] + "0"; // 转ASCII
                    tx_start <= 1; tx_state <= T_WAIT_NUM;
                end
                
                T_WAIT_NUM: if(!tx_busy) tx_state <= T_PRINT_SP;

                T_PRINT_SP: begin
                    tx_data <= " "; tx_start <= 1; tx_state <= T_WAIT_SP;
                end

                T_WAIT_SP: begin
                    if(!tx_busy) begin
                        // 列结束?
                        if(c_cnt == stored_n[rd_ptr] - 1) tx_state <= T_PRINT_CR;
                        else begin
                            c_cnt <= c_cnt + 1; rd_idx <= rd_idx + 1; tx_state <= T_PRINT_NUM;
                        end
                    end
                end

                T_PRINT_CR: begin tx_data <= 8'h0D; tx_start <= 1; tx_state <= T_WAIT_CR; end
                T_WAIT_CR: if(!tx_busy) tx_state <= T_PRINT_LF;
                T_PRINT_LF: begin tx_data <= 8'h0A; tx_start <= 1; tx_state <= T_WAIT_LF; end

                T_WAIT_LF: begin
                    if(!tx_busy) begin
                        // 行结束?
                        if(r_cnt == stored_m[rd_ptr] - 1) tx_state <= T_IDLE; // 打印完成
                        else begin
                            c_cnt <= 0; r_cnt <= r_cnt + 1; rd_idx <= rd_idx + 1; tx_state <= T_PRINT_NUM;
                        end
                    end
                end
            endcase
        end
    end
endmodule