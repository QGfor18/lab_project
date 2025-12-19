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
    input wire print_trigger,    // 打印触发按钮 V1
    input wire [3:0] sw_select,  // SW3-SW0 选择输出矩阵
    input wire config_en,        // 配置模式使能 (U2)
    input wire calc_trigger,     // 计算触发按钮 (V2)
    input wire [3:0] btn_op,     // 运算模式按钮编码 (V3-V6)
    output wire [7:0] led,       // LED7-LED0 显示状态
    
    // 计算模块接口
    output reg calc_start,           // 启动计算
    output reg [3:0] operation_type, // 运算类型
    output reg [5:0] matrix_a_dim,   // 矩阵A维度
    output reg [5:0] matrix_b_dim,   // 矩阵B维度
    output reg [7:0] scalar_value,   // 标量值
    output reg [199:0] matrix_a_data,// 矩阵A数据
    output reg [199:0] matrix_b_data,// 矩阵B数据
    input wire [399:0] result_data,  // 计算结果
    input wire [5:0] result_dim,     // 结果维度
    input wire calc_done,            // 计算完成
    input wire calc_error            // 计算错误
);

    // ==========================================
    // 1. �洢���������
    // ==========================================
    // ����Ӳ������ (Hard Limit)������д��Ϊ4�����ܶ�̬�Ĵ�
    localparam MAX_PHYSICAL_CAP = 4; 
    
    reg [7:0] matrix_mem [0:MAX_PHYSICAL_CAP-1][0:24]; // 4������, ÿ�����25Ԫ��
    reg [2:0] stored_m [0:MAX_PHYSICAL_CAP-1];         // �洢����
    reg [2:0] stored_n [0:MAX_PHYSICAL_CAP-1];         // �洢����
    
    reg [2:0] wr_ptr;                 // дָ��
    reg [MAX_PHYSICAL_CAP-1:0] valid_mask; // ��Чλ���
    reg [4:0] data_cnt;               // ���ݼ�����

    // [�߼��������] �û���ͨ�� UART �޸ģ�Ĭ��ֵΪ 2
    reg [2:0] max_cnt; 

    // LED 显示逻辑
    // led[3:0]: 显示4个矩阵槽位的存储状态（存储成功则对应LED亮）
    // led[4]: 计算模式指示
    // led[5]: 计算进行中
    // led[6]: 计算完成
    // led[7]: 计算错误/输出中
    assign led[3:0] = valid_mask[3:0];  // 前4个LED显示矩阵存储状态
    assign led[4] = (rx_state == S_CALC_MODE) || (rx_state == S_CALC_WAIT) || (rx_state == S_CALC_STORE);
    assign led[5] = calc_busy;
    assign led[6] = calc_done_flag;
    assign led[7] = output_from_result;

    // ==========================================
    // 2. ������������״̬��
    // ==========================================
    localparam S_RX_IDLE    = 0;
    localparam S_RX_GET_M   = 1;
    localparam S_RX_GET_N   = 2;
    localparam S_RX_DATA    = 3;
    localparam S_RX_CONFIG  = 4; // 配置模式状态
    localparam S_CALC_MODE  = 5; // 计算模式状态
    localparam S_CALC_WAIT  = 6; // 等待计算完成
    localparam S_CALC_STORE = 7; // 存储计算结果（可选）
    
    reg [2:0] rx_state;
    reg [7:0] num_buffer;
    reg       num_valid;
    
    // 计算相关寄存器
    reg [1:0] calc_step;          // 计算参数接收步骤
    reg [1:0] matrix_a_idx;       // 矩阵A索引
    reg [1:0] matrix_b_idx;       // 矩阵B索引
    reg [1:0] result_idx;         // 结果存储索引
    reg [7:0] scalar_buffer;      // 标量值缓存
    reg calc_trigger_stable;      // 计算触发稳定信号
    reg calc_busy;                // 计算进行中标志
    reg calc_done_flag;           // 计算完成标志
    reg calc_error_flag;          // 计算错误标志
    
    // 直接输出模式相关寄存器
    reg output_result_flag;       // 触发直接输出结果
    reg output_done_flag;         // 输出完成标志
    reg [2:0] result_rows;        // 结果矩阵行数
    reg [2:0] result_cols;        // 结果矩阵列数
    reg [7:0] result_mem [0:24];  // 结果临时缓存（8位饱和后）

    // --- ASCII 解析逻辑（支持多位数0-255）---
    reg num_start;  // 标记是否开始接收新数字
    always @(posedge clk) begin
        if(!rst_n) begin
            num_buffer <= 0;
            num_valid <= 0;
            num_start <= 1;  // 复位后准备接收第一个数字
        end else begin
            num_valid <= 0;
            if(rx_done) begin
                if(rx_data >= "0" && rx_data <= "9") begin
                    if(num_start) begin
                        // 新数字开始，从这个数字开始
                        num_buffer <= rx_data - "0";
                        num_start <= 0;
                    end else begin
                        // 继续累加多位数
                        num_buffer <= num_buffer * 10 + (rx_data - "0");
                    end
                end
                // 空格、回车都作为数字分隔符
                else if(rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) begin
                    if(!num_start) begin
                        // 只有在接收过数字后才触发num_valid
                        num_valid <= 1;
                        num_start <= 1;  // 准备接收下一个数字
                    end
                end
            end
        end
    end

    // --- 按钮去抖逻辑（边沿检测）---
    reg calc_trig_d1, calc_trig_d2;
    wire calc_trig_pos = calc_trig_d1 & ~calc_trig_d2;  // 上升沿检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calc_trig_d1 <= 0;
            calc_trig_d2 <= 0;
        end else begin
            calc_trig_d1 <= calc_trigger;
            calc_trig_d2 <= calc_trig_d1;
        end
    end
    
    // --- 矩阵控制逻辑 ---
    integer j; // 用于时序块中的for循环
    always @(posedge clk) begin
        if(!rst_n) begin
            rx_state <= S_RX_IDLE;
            wr_ptr <= 0;
            valid_mask <= 0;
            data_cnt <= 0;
            max_cnt <= 2; // [默认值] 复位时默认存2个
            
            // 计算相关初始化
            calc_step <= 0;
            matrix_a_idx <= 0;
            matrix_b_idx <= 0;
            result_idx <= 0;
            scalar_buffer <= 0;
            calc_busy <= 0;
            calc_done_flag <= 0;
            calc_error_flag <= 0;
            calc_start <= 0;
            operation_type <= 0;
            scalar_value <= 0;
            output_result_flag <= 0;
            // output_done_flag 由输出状态机控制，这里不初始化
            result_rows <= 0;
            result_cols <= 0;
        end else begin
            // 输出完成后返回主状态（只检测，不清除，由输出状态机清除）
            if (output_done_flag) begin
                rx_state <= S_RX_IDLE;
            end
            // 当输出状态机开始处理时，清除触发标志
            if (output_result_flag && output_from_result) begin
                output_result_flag <= 0;
            end
            // 计算完成标志清除
            if (calc_done_flag) calc_done_flag <= 0;
            if (calc_error_flag) calc_error_flag <= 0;
            
            // 强制进入配置模式逻辑 (config_en 优先级最高)
            if (config_en && rx_state != S_RX_CONFIG && rx_state != S_CALC_MODE) begin
                rx_state <= S_RX_CONFIG;
                calc_step <= 0;
            end
            // 进入计算模式逻辑 (通过按钮编码进入，按一下即锁定)
            else if (btn_op != 0 && rx_state != S_CALC_MODE && rx_state != S_CALC_WAIT && rx_state != S_RX_CONFIG) begin
                rx_state <= S_CALC_MODE;
                calc_step <= 0;
                // 按钮编码映射到运算类型
                case(btn_op)
                    4'b0001: operation_type <= 4'd0;  // R3 → 转置
                    4'b0010: operation_type <= 4'd1;  // V4 → 加法
                    4'b0100: operation_type <= 4'd2;  // V5 → 标量乘
                    4'b1000: operation_type <= 4'd3;  // V2 → 矩阵乘
                    default: operation_type <= 4'd0;
                endcase
            end
            // 退出配置模式
            else if (!config_en && rx_state == S_RX_CONFIG) begin
                rx_state <= S_RX_IDLE;
            end
            // 注意：计算模式不再自动退出，只有输出完成后才退出
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
                            // 硬件边界检查防止越界写入
                            if(wr_ptr < MAX_PHYSICAL_CAP)
                                matrix_mem[wr_ptr][data_cnt] <= num_buffer;
                            
                            // 判断矩阵是否接收完成
                            if(data_cnt == (stored_m[wr_ptr] * stored_n[wr_ptr]) - 1) begin
                                valid_mask[wr_ptr] <= 1'b1;
                                
                                // [循环逻辑] 根据用户设定的 max_cnt
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
                            // 配置值钳位，不能超过硬件容量4，不能小于1
                            if(num_buffer == 0) max_cnt <= 1;
                            else if(num_buffer <= MAX_PHYSICAL_CAP) max_cnt <= num_buffer[2:0];
                            else max_cnt <= MAX_PHYSICAL_CAP;
                            
                            // 配置改变后重置指针和有效位
                            wr_ptr <= 0;
                            valid_mask <= 0;
                        end
                    end
                    
                    // [计算模式逻辑]
                    S_CALC_MODE: begin
                        if(num_valid) begin
                            case(calc_step)
                                0: begin // 接收矩阵A索引
                                    matrix_a_idx <= num_buffer[1:0];
                                    calc_step <= 1;
                                end
                                1: begin // 接收矩阵B索引
                                    matrix_b_idx <= num_buffer[1:0];
                                    calc_step <= 2;
                                end
                                2: begin // 接收标量值（如果需要）
                                    scalar_buffer <= num_buffer;
                                    calc_step <= 3;
                                end
                                3: begin // 接收结果存储位置
                                    result_idx <= num_buffer[1:0];
                                    calc_step <= 0;
                                    // 等待计算触发
                                end
                            endcase
                        end
                        
                        // 计算触发
                        if (calc_trig_pos && !calc_busy) begin
                            // 修正：加法(1)和矩阵乘(3)需要两个矩阵，转置(0)和标量乘(2)只需要矩阵A
                            if (valid_mask[matrix_a_idx] &&
                                (operation_type == 4'd0 || operation_type == 4'd2 || valid_mask[matrix_b_idx])) begin
                                calc_busy <= 1;
                                calc_start <= 1;
                                scalar_value <= scalar_buffer;
                                rx_state <= S_CALC_WAIT;
                            end
                        end
                    end
                    
                    // [等待计算完成]
                    S_CALC_WAIT: begin
                        // 延迟一拍再清除calc_start，确保计算模块能采样到
                        if (calc_start) begin
                            calc_start <= 0;
                        end else if (calc_done) begin
                            calc_busy <= 0;
                            if (calc_error) begin
                                calc_error_flag <= 1;
                                rx_state <= S_CALC_MODE;
                            end else begin
                                // 将结果存入临时缓存（饱和处理）
                                for (j = 0; j < 25; j = j + 1) begin
                                    if (result_data[j*16 +: 16] > 255)
                                        result_mem[j] <= 8'd255;
                                    else
                                        result_mem[j] <= result_data[j*16 +: 8];
                                end
                                // 保存结果维度
                                result_rows <= result_dim[5:3];
                                result_cols <= result_dim[2:0];
                                // 先进入STORE状态等待数据稳定，再触发输出
                                calc_done_flag <= 1;
                                rx_state <= S_CALC_STORE;
                            end
                        end
                    end
                    
                    // [存储完成后触发输出]
                    S_CALC_STORE: begin
                        // 此时 result_mem, result_rows, result_cols 已经稳定
                        // 触发直接输出
                        output_result_flag <= 1;
                        rx_state <= S_CALC_MODE;
                    end
                endcase
            end
        end
    end

    // ==========================================
    // 3. 输出格式化状态机（支持多位数0-255）
    // ==========================================
    localparam T_IDLE       = 0;
    localparam T_LOAD_NUM   = 1;  // 加载数值并分解
    localparam T_PRINT_H    = 2;  // 打印百位
    localparam T_WAIT_H     = 3;
    localparam T_PRINT_T    = 4;  // 打印十位
    localparam T_WAIT_T     = 5;
    localparam T_PRINT_U    = 6;  // 打印个位
    localparam T_WAIT_U     = 7;
    localparam T_PRINT_SP   = 8;  // 打印空格
    localparam T_WAIT_SP    = 9;
    localparam T_PRINT_CR   = 10;
    localparam T_WAIT_CR    = 11;
    localparam T_PRINT_LF   = 12;
    localparam T_WAIT_LF    = 13;

    reg [3:0] tx_state;
    reg [1:0] rd_ptr;      
    reg [4:0] rd_idx;
    reg [2:0] r_cnt, c_cnt;
    
    // 多位数打印寄存器
    reg [7:0] print_val;
    reg [3:0] digit_h, digit_t, digit_u;
    reg skip_h, skip_t;
    
    // 输出模式：0=从matrix_mem读取，1=从result_mem读取
    reg output_from_result;
    // 直接输出时使用的行列数
    reg [2:0] out_rows, out_cols;

    // 按键边沿检测
    reg trig_d1, trig_d2;
    wire trig_pos = trig_d1 & ~trig_d2;
    always @(posedge clk) begin trig_d1 <= print_trigger; trig_d2 <= trig_d1; end

    always @(posedge clk) begin
        if(!rst_n) begin
            tx_state <= T_IDLE;
            tx_start <= 0; tx_data <= 0;
            print_val <= 0;
            digit_h <= 0; digit_t <= 0; digit_u <= 0;
            skip_h <= 0; skip_t <= 0;
            rd_ptr <= 0; rd_idx <= 0;
            r_cnt <= 0; c_cnt <= 0;
            output_from_result <= 0;
            output_done_flag <= 0;
            out_rows <= 0; out_cols <= 0;
        end else begin
            tx_start <= 0;
            // 每次进入T_IDLE时清除output_done_flag，避免主状态机多次响应
            if (tx_state == T_IDLE) begin
                output_done_flag <= 0;
            end
            case(tx_state)
                T_IDLE: begin
                    // 优先：计算结果直接输出
                    if (output_result_flag) begin
                        output_from_result <= 1;
                        out_rows <= result_rows;
                        out_cols <= result_cols;
                        rd_idx <= 0; r_cnt <= 0; c_cnt <= 0;
                        tx_state <= T_LOAD_NUM;
                    end
                    // 其次：手动按钮触发打印存储的矩阵
                    else if(trig_pos) begin
                        output_from_result <= 0;
                        // 检查开关选择 & 矩阵有效性 & max_cnt 限制
                        if(sw_select[0] && valid_mask[0] && max_cnt >= 1) begin
                            rd_ptr <= 0; out_rows <= stored_m[0]; out_cols <= stored_n[0]; tx_state <= T_LOAD_NUM;
                        end else if(sw_select[1] && valid_mask[1] && max_cnt >= 2) begin
                            rd_ptr <= 1; out_rows <= stored_m[1]; out_cols <= stored_n[1]; tx_state <= T_LOAD_NUM;
                        end else if(sw_select[2] && valid_mask[2] && max_cnt >= 3) begin
                            rd_ptr <= 2; out_rows <= stored_m[2]; out_cols <= stored_n[2]; tx_state <= T_LOAD_NUM;
                        end else if(sw_select[3] && valid_mask[3] && max_cnt >= 4) begin
                            rd_ptr <= 3; out_rows <= stored_m[3]; out_cols <= stored_n[3]; tx_state <= T_LOAD_NUM;
                        end
                        rd_idx <= 0; r_cnt <= 0; c_cnt <= 0;
                    end
                end

                // 加载数值并分解为百位、十位、个位
                T_LOAD_NUM: begin
                    if (output_from_result) begin
                        // 从计算结果缓存读取
                        print_val <= result_mem[rd_idx];
                        digit_h <= result_mem[rd_idx] / 100;
                        digit_t <= (result_mem[rd_idx] % 100) / 10;
                        digit_u <= result_mem[rd_idx] % 10;
                        skip_h <= (result_mem[rd_idx] < 100);
                        skip_t <= (result_mem[rd_idx] < 10);
                    end else begin
                        // 从矩阵存储器读取
                        print_val <= matrix_mem[rd_ptr][rd_idx];
                        digit_h <= matrix_mem[rd_ptr][rd_idx] / 100;
                        digit_t <= (matrix_mem[rd_ptr][rd_idx] % 100) / 10;
                        digit_u <= matrix_mem[rd_ptr][rd_idx] % 10;
                        skip_h <= (matrix_mem[rd_ptr][rd_idx] < 100);
                        skip_t <= (matrix_mem[rd_ptr][rd_idx] < 10);
                    end
                    tx_state <= T_PRINT_H;
                end

                // 打印百位（跳过前导零）
                T_PRINT_H: begin
                    if (skip_h) begin
                        tx_state <= T_PRINT_T;
                    end else begin
                        tx_data <= digit_h + "0";
                        tx_start <= 1;
                        tx_state <= T_WAIT_H;
                    end
                end
                T_WAIT_H: if(!tx_busy) tx_state <= T_PRINT_T;

                // 打印十位（跳过前导零）
                T_PRINT_T: begin
                    if (skip_t) begin
                        tx_state <= T_PRINT_U;
                    end else begin
                        tx_data <= digit_t + "0";
                        tx_start <= 1;
                        tx_state <= T_WAIT_T;
                    end
                end
                T_WAIT_T: if(!tx_busy) tx_state <= T_PRINT_U;

                // 打印个位（始终打印）
                T_PRINT_U: begin
                    tx_data <= digit_u + "0";
                    tx_start <= 1;
                    tx_state <= T_WAIT_U;
                end
                T_WAIT_U: if(!tx_busy) tx_state <= T_PRINT_SP;

                // 打印空格
                T_PRINT_SP: begin
                    tx_data <= " ";
                    tx_start <= 1;
                    tx_state <= T_WAIT_SP;
                end

                T_WAIT_SP: begin
                    if(!tx_busy) begin
                        if(c_cnt == out_cols - 1) tx_state <= T_PRINT_CR;
                        else begin
                            c_cnt <= c_cnt + 1;
                            rd_idx <= rd_idx + 1;
                            tx_state <= T_LOAD_NUM;
                        end
                    end
                end

                T_PRINT_CR: begin tx_data <= 8'h0D; tx_start <= 1; tx_state <= T_WAIT_CR; end
                T_WAIT_CR: if(!tx_busy) tx_state <= T_PRINT_LF;
                T_PRINT_LF: begin tx_data <= 8'h0A; tx_start <= 1; tx_state <= T_WAIT_LF; end

                T_WAIT_LF: begin
                    if(!tx_busy) begin
                        if(r_cnt == out_rows - 1) begin
                            // 打印完成
                            if (output_from_result) begin
                                output_done_flag <= 1;  // 通知主状态机
                            end
                            output_from_result <= 0;
                            tx_state <= T_IDLE;
                        end else begin
                            c_cnt <= 0;
                            r_cnt <= r_cnt + 1;
                            rd_idx <= rd_idx + 1;
                            tx_state <= T_LOAD_NUM;
                        end
                    end
                end
            endcase
        end
    end
    
    // ==========================================
    // 4. 数据打包逻辑（将存储的矩阵打包成计算模块需要的格式）
    // ==========================================
    integer i;
    always @(*) begin
        // 打包矩阵A数据
        for (i = 0; i < 25; i = i + 1) begin
            matrix_a_data[i*8 +: 8] = matrix_mem[matrix_a_idx][i];
        end
        
        // 打包矩阵B数据
        for (i = 0; i < 25; i = i + 1) begin
            matrix_b_data[i*8 +: 8] = matrix_mem[matrix_b_idx][i];
        end
        
        // 设置矩阵维度
        matrix_a_dim = {stored_m[matrix_a_idx], stored_n[matrix_a_idx]};
        matrix_b_dim = {stored_m[matrix_b_idx], stored_n[matrix_b_idx]};
    end
    
endmodule