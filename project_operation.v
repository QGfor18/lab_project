`timescale 1ns / 1ps
module matrix_calculator (
    input           clk,           
    input           rst_n, 
    input           start,   
    input  [3:0]    operation_type, 
    input  [5:0]    matrix_a_dim,  
    input  [5:0]    matrix_b_dim,
    input  [7:0]    scalar_value, 
    input  [199:0]  matrix_a_data,
    input  [199:0]  matrix_b_data, 
    output reg [399:0] result_data, 
    output reg [5:0]   result_dim, 
    output reg         done,    
    output reg         error      
);

localparam IDLE        = 3'd0;  
localparam LOAD_DATA   = 3'd1;  
localparam CALCULATE   = 3'd2;  
localparam OUTPUT_RES  = 3'd3;  

reg [7:0]  mat_a [0:24];  
reg [7:0]  mat_b [0:24];  
reg [15:0] res_mat [0:24];

reg [2:0]  current_state;
reg [4:0]  row_cnt;       
reg [4:0]  col_cnt;       
reg [4:0]  k_cnt;         
reg [4:0]  idx;           
reg [15:0] mul_acc;       

wire [2:0] a_rows = matrix_a_dim[5:3];
wire [2:0] a_cols = matrix_a_dim[2:0];
wire [2:0] b_rows = matrix_b_dim[5:3];
wire [2:0] b_cols = matrix_b_dim[2:0];
wire [4:0] a_size = a_rows * a_cols;  
wire [4:0] b_size = b_rows * b_cols;  

integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
        done <= 1'b0;
        error <= 1'b0;
        row_cnt <= 5'd0;
        col_cnt <= 5'd0;
        k_cnt <= 5'd0;
        idx <= 5'd0;
        mul_acc <= 16'd0;
        result_dim <= 6'd0;
        result_data <= 400'd0;
        
        for (i = 0; i < 25; i = i + 1) begin
            mat_a[i] <= 8'd0;
            mat_b[i] <= 8'd0;
            res_mat[i] <= 16'd0;
        end
    end else begin
        case (current_state)
            IDLE: begin
                done <= 1'b0;
                error <= 1'b0;
                idx <= 5'd0;
                row_cnt <= 5'd0;
                col_cnt <= 5'd0;
                
                if (start) begin
                    if (operation_type > 3'd3) begin
                        error <= 1'b1;
                        done <= 1'b1;  // ← 添加这行！
                        current_state <= IDLE;
                    end else begin
                        if (a_rows == 0 || a_cols == 0) begin
                            error <= 1'b1;
                            done <= 1'b1;  // ← 添加这行！
                            current_state <= IDLE;
                        end else begin
                            current_state <= LOAD_DATA;
                        end
                    end
                end
            end

            LOAD_DATA: begin
                for (i = 0; i < 25; i = i + 1) begin
                    mat_a[i] <= matrix_a_data[i*8 +: 8];
                    mat_b[i] <= matrix_b_data[i*8 +: 8];
                end
                
                case (operation_type)
                    3'd0: begin
                        current_state <= CALCULATE;
                    end
                    3'd1: begin
                        if (matrix_a_dim != matrix_b_dim || b_rows == 0 || b_cols == 0) begin
                            error <= 1'b1;
                            done <= 1'b1;  // ← 添加这行！
                            current_state <= IDLE;
                        end else begin
                            current_state <= CALCULATE;
                        end
                    end
                    3'd2: begin
                        current_state <= CALCULATE;
                    end
                    3'd3: begin
                        if (a_cols != b_rows || b_rows == 0 || b_cols == 0) begin
                            error <= 1'b1;
                            done <= 1'b1;  // ← 添加这行！
                            current_state <= IDLE;
                        end else begin
                            current_state <= CALCULATE;
                        end
                    end
                endcase
            end

            CALCULATE: begin
                case (operation_type)
                    3'd0: begin
                        if (row_cnt < a_rows) begin
                            if (col_cnt < a_cols) begin
                                res_mat[col_cnt * a_rows + row_cnt] <= {8'd0, mat_a[row_cnt * a_cols + col_cnt]};
                                col_cnt <= col_cnt + 1'b1;
                            end else begin
                                col_cnt <= 5'd0;
                                row_cnt <= row_cnt + 1'b1;
                            end
                        end else begin
                            result_dim <= {a_cols, a_rows};
                            current_state <= OUTPUT_RES;
                        end
                    end
                    3'd1: begin
                        if (idx < a_size) begin
                            res_mat[idx] <= {8'd0, mat_a[idx]} + {8'd0, mat_b[idx]};
                            idx <= idx + 1'b1;
                        end else begin
                            result_dim <= matrix_a_dim;
                            current_state <= OUTPUT_RES;
                        end
                    end
                    3'd2: begin
                        if (idx < a_size) begin
                            res_mat[idx] <= mat_a[idx] * scalar_value;
                            idx <= idx + 1'b1;
                        end else begin
                            result_dim <= matrix_a_dim;
                            current_state <= OUTPUT_RES;
                        end
                    end
                    3'd3: begin
                        if (row_cnt < a_rows) begin
                            if (col_cnt < b_cols) begin
                                if (k_cnt < a_cols) begin
                                    mul_acc <= mul_acc + mat_a[row_cnt * a_cols + k_cnt] * mat_b[k_cnt * b_cols + col_cnt];
                                    k_cnt <= k_cnt + 1'b1;
                                end else begin
                                    // k_cnt == a_cols: 累加完成，存储结果并移动到下一个元素
                                    res_mat[row_cnt * b_cols + col_cnt] <= mul_acc;
                                    mul_acc <= 16'd0;
                                    k_cnt <= 5'd0;
                                    col_cnt <= col_cnt + 1'b1;
                                end
                            end else begin
                                col_cnt <= 5'd0;
                                row_cnt <= row_cnt + 1'b1;
                            end
                        end else begin
                            result_dim <= {a_rows, b_cols};
                            current_state <= OUTPUT_RES;
                        end
                    end
                endcase
            end

            OUTPUT_RES: begin
                for (i = 0; i < 25; i = i + 1) begin
                    result_data[i*16 +: 16] <= res_mat[i];
                end
                done <= 1'b1;  
                current_state <= IDLE; 
            end
            default: current_state <= IDLE;
        endcase
    end
end

endmodule