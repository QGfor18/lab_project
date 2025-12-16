`timescale 1ns / 1ps
module random_num_generator (
    input           clk,     
    input           rst_n,      
    input           gen_en,   
    input  [7:0]    min_val,   
    input  [7:0]    max_val, 
    output reg [7:0] random_out,
    output reg      valid,
    output reg      range_error
);
reg [15:0] lfsr_reg; 
wire lfsr_feedback;
assign lfsr_feedback = lfsr_reg[15] ^ lfsr_reg[14] ^ lfsr_reg[13] ^ lfsr_reg[4];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lfsr_reg <= 16'h5A5A; 
    end else if (gen_en) begin
        lfsr_reg <= {lfsr_reg[14:0], lfsr_feedback};  
    end
end
reg [7:0] range_len;  
reg [7:0] mod_result; 
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        random_out <= 8'd0;
        valid <= 1'b0;
        range_error <= 1'b0;
        range_len <= 8'd1;
        mod_result <= 8'd0;
    end else if (gen_en) begin
      
        if (max_val >= min_val) begin
            range_len <= max_val - min_val + 1'b1;
            range_error <= 1'b0;
        end else begin
            range_len <= 8'd1;  
            range_error <= 1'b1;
        end
        mod_result <= lfsr_reg[7:0] % range_len;
        random_out <= mod_result + min_val;
        valid <= 1'b1;
    end else begin
        valid <= 1'b0;
        range_error <= 1'b0;
        random_out <= 8'd0;
    end
end

endmodule