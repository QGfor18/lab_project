# =============================================================================
# 系统时钟约束 (100MHz, 周期10ns)
# =============================================================================
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]

# =============================================================================
# IO电平标准 (LVCMOS 3.3V)
# =============================================================================
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports btn_print_v1]

# =============================================================================
# 引脚绑定 (Minisys-1 XC7A100T)
# =============================================================================

# 系统时钟 -> P17
set_property PACKAGE_PIN P17 [get_ports clk]

# 复位按键 (使用 T5 拨码开关)
set_property PACKAGE_PIN T5 [get_ports uart_rx_rst_n]

# 打印触发按键 -> V1
set_property PACKAGE_PIN V1 [get_ports btn_print_v1]

# UART 串口
set_property PACKAGE_PIN T4 [get_ports uart_tx]
set_property PACKAGE_PIN N5 [get_ports uart_rx]

# LED 0-7 (这里我们只用到了 led[3:0], 但绑定全部防止报错)
set_property PACKAGE_PIN K2 [get_ports {led[0]}]
set_property PACKAGE_PIN J2 [get_ports {led[1]}]
set_property PACKAGE_PIN J3 [get_ports {led[2]}]
set_property PACKAGE_PIN H4 [get_ports {led[3]}]
set_property PACKAGE_PIN J4 [get_ports {led[4]}]
set_property PACKAGE_PIN G3 [get_ports {led[5]}]
set_property PACKAGE_PIN G4 [get_ports {led[6]}]
set_property PACKAGE_PIN F6 [get_ports {led[7]}]

# 拨码开关 SW0-SW7
# key[3:0] 选择矩阵, key[4] 配置模式
set_property PACKAGE_PIN R1 [get_ports {key[0]}]
set_property PACKAGE_PIN N4 [get_ports {key[1]}]
set_property PACKAGE_PIN M4 [get_ports {key[2]}]
set_property PACKAGE_PIN R2 [get_ports {key[3]}]
set_property PACKAGE_PIN P2 [get_ports {key[4]}]
set_property PACKAGE_PIN P3 [get_ports {key[5]}]
set_property PACKAGE_PIN P4 [get_ports {key[6]}]
set_property PACKAGE_PIN P5 [get_ports {key[7]}]