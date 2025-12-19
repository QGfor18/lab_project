`timescale 1ns / 1ps

module top_tb;

    // Inputs
    reg clk;
    reg uart_rx;
    reg [7:0] key;
    reg uart_rx_rst_n;
    reg btn_print_v1;
    reg config_en;
    reg btn_calc_u3;
    reg btn_op0, btn_op1, btn_op2, btn_op3;
    
    // Outputs
    wire uart_tx;
    wire [7:0] led;
    
    // Instantiate the Unit Under Test (UUT)
    top uut (
        .clk(clk),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .key(key),
        .led(led),
        .uart_rx_rst_n(uart_rx_rst_n),
        .btn_print_v1(btn_print_v1),
        .config_en(config_en),
        .btn_calc_u3(btn_calc_u3),
        .btn_op0(btn_op0),
        .btn_op1(btn_op1),
        .btn_op2(btn_op2),
        .btn_op3(btn_op3)
    );
    
    // Clock generation: 100MHz, period 10ns
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // toggle every 5ns
    end
    
    // UART parameters
    localparam CLK_FREQ = 100_000_000;
    localparam BAUD_RATE = 115200;
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE; // in ns
    localparam HALF_BIT = BIT_PERIOD / 2;
    
    // Test control
    integer test_pass = 1;
    integer tx_monitor_en = 0;
    reg [7:0] tx_data_captured;
    integer tx_bit_count;
    
    // Initialization
    initial begin
        // Initialize inputs
        uart_rx = 1'b1; // idle high
        key = 8'h00;
        uart_rx_rst_n = 1'b0;
        btn_print_v1 = 0;
        config_en = 0;
        btn_calc_u3 = 0;
        btn_op0 = 0; btn_op1 = 0; btn_op2 = 0; btn_op3 = 0;
        
        // Reset
        #100;
        uart_rx_rst_n = 1'b1;
        #100;
        
        $display("=== Start Testing ===");
        
        // Test 1: Receive a 2x2 matrix via UART
        $display("Test 1: Receive matrix data");
        send_matrix_via_uart(2, 2, {8'd1, 8'd2, 8'd3, 8'd4});
        #5000; // allow time for processing
        
        // Test 2: Configuration mode, set max stored matrices to 3
        $display("Test 2: Configuration mode");
        config_en = 1;
        #100;
        send_uart_byte("3"); // send ASCII '3'
        #5000;
        config_en = 0;
        #100;
        
        // Test 3: Calculation mode - matrix transpose
        $display("Test 3: Matrix transpose");
        // First receive second matrix (3x2)
        send_matrix_via_uart(3, 2, {8'd5, 8'd6, 8'd7, 8'd8, 8'd9, 8'd2});
        #5000;
        
        // Select operation type: transpose (btn_op0 pressed)
        btn_op0 = 1;
        #100;
        btn_op0 = 0;
        #100;
        
        // Send calculation parameters via UART: matrix A index 0, B index irrelevant, scalar irrelevant, result store location 1
        send_calc_params_via_uart(0, 0, 0, 1);
        #5000;
        
        // Trigger calculation
        btn_calc_u3 = 1;
        #100;
        btn_calc_u3 = 0;
        
        // Wait for calculation completion (via LED status)
        wait_for_calc_done();
        #5000;
        
        // Test 4: Print output
        $display("Test 4: Print matrix");
        key = 8'h01; // SW0 selects matrix 0
        #100;
        btn_print_v1 = 1;
        #100;
        btn_print_v1 = 0;
        
        // Monitor UART transmitted data
        tx_monitor_en = 1;
        #20000; // longer for printing entire matrix
        tx_monitor_en = 0;
        
        // Test 5: Matrix addition
        $display("Test 5: Matrix addition");
        // Receive third matrix (2x2)
        send_matrix_via_uart(2, 2, {8'd2, 8'd3, 8'd4, 8'd5});
        #5000;
        
        // Select addition operation (btn_op1 pressed)
        btn_op1 = 1;
        #100;
        btn_op1 = 0;
        #100;
        
        // Send calculation parameters: matrix A index 0, B index 2, scalar irrelevant, result store location 3
        send_calc_params_via_uart(0, 2, 0, 3);
        #5000;
        
        // Trigger calculation
        btn_calc_u3 = 1;
        #100;
        btn_calc_u3 = 0;
        wait_for_calc_done();
        #5000;
        
        // Print result matrix
        key = 8'h08; // SW3 selects matrix 3
        #100;
        btn_print_v1 = 1;
        #100;
        btn_print_v1 = 0;
        tx_monitor_en = 1;
        #20000;
        tx_monitor_en = 0;
        
        // End test
        #5000;
        if (test_pass) begin
            $display("=== All tests passed ===");
        end else begin
            $display("=== Test failed ===");
        end
        $finish;
    end
    
    // Task: send one byte via UART
    task send_uart_byte;
        input [7:0] data;
        integer i;
        begin
            // Send start bit (0)
            uart_rx = 1'b0;
            #BIT_PERIOD;
            // Send 8 data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #BIT_PERIOD;
            end
            // Send stop bit (1)
            uart_rx = 1'b1;
            #BIT_PERIOD;
        end
    endtask
    
    // Task: send matrix dimensions and data
    task send_matrix_via_uart;
        input [2:0] m, n;
        input [199:0] data; // up to 25 bytes, but only m*n used
        integer i, total;
        begin
            total = m * n;
            // Send M (ASCII digit)
            send_uart_byte("0" + m);
            // Send space separator
            send_uart_byte(" ");
            // Send N
            send_uart_byte("0" + n);
            send_uart_byte(" ");
            // Send matrix elements
            for (i = 0; i < total; i = i + 1) begin
                // data is a single digit 0-9, convert to ASCII
                send_uart_byte("0" + data[i*8 +: 8]);
                if (i != total - 1) send_uart_byte(" ");
            end
            // Send carriage return and line feed to indicate end
            send_uart_byte(8'h0D);
            send_uart_byte(8'h0A);
        end
    endtask
    
    // Task: send calculation parameters
    task send_calc_params_via_uart;
        input [1:0] a_idx, b_idx;
        input [7:0] scalar;
        input [1:0] res_idx;
        begin
            // Matrix A index
            send_uart_byte("0" + a_idx);
            send_uart_byte(" ");
            // Matrix B index
            send_uart_byte("0" + b_idx);
            send_uart_byte(" ");
            // Scalar value
            send_uart_byte("0" + scalar);
            send_uart_byte(" ");
            // Result storage location
            send_uart_byte("0" + res_idx);
            send_uart_byte(" ");
            send_uart_byte(8'h0D);
            send_uart_byte(8'h0A);
        end
    endtask
    
    // Task: wait for calculation completion (via LED[6] flag)
    task wait_for_calc_done;
        integer timeout;
        begin
            timeout = 0;
            while (led[6] !== 1'b1 && timeout < 200000) begin
                #1000;
                timeout = timeout + 1;
            end
            if (timeout >= 200000) begin
                $display("Error: Calculation timeout");
                test_pass = 0;
            end else begin
                $display("Calculation done");
            end
        end
    endtask
    
    // UART transmit monitor
    initial begin
        forever begin
            @(negedge uart_tx) begin // detect start bit
                if (tx_monitor_en) begin
                    #(HALF_BIT); // move to middle of start bit
                    // verify start bit is 0
                    if (uart_tx !== 1'b0) begin
                        $display("UART transmit start bit error");
                        test_pass = 0;
                    end
                    // receive 8 data bits
                    tx_data_captured = 0;
                    for (tx_bit_count = 0; tx_bit_count < 8; tx_bit_count = tx_bit_count + 1) begin
                        #BIT_PERIOD;
                        tx_data_captured[tx_bit_count] = uart_tx;
                    end
                    // stop bit
                    #BIT_PERIOD;
                    if (uart_tx !== 1'b1) begin
                        $display("UART transmit stop bit error");
                        test_pass = 0;
                    end
                    $display("UART transmitted data: 0x%h (%c)", tx_data_captured, tx_data_captured);
                end
            end
        end
    end
    
    // Waveform recording
    initial begin
        $dumpfile("top_tb.vcd");
        $dumpvars(0, top_tb);
    end
    
endmodule