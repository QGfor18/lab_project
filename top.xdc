create_clock -period 10.000 -name sys_clk_pin -
set_property PACKAGE_PIN V1 [get_ports btn_prin
set_property IOSTANDARD LVCMOS33 [get_ports btn
set_property IOSTANDARD LVCMOS33 [get_ports {le
set_property IOSTANDARD LVCMOS33 [get_ports {ke
set_property IOSTANDARD LVCMOS33 [get_ports clk
set_property IOSTANDARD LVCMOS33 [get_ports sen
set_property IOSTANDARD LVCMOS33 [get_ports uar
set_property IOSTANDARD LVCMOS33 [get_ports uar
set_property IOSTANDARD LVCMOS33 [get_ports uar
set_property IOSTANDARD LVCMOS33 [get_ports uar
set_property IOSTANDARD LVCMOS33 [get_ports uar
set_property IOSTANDARD LVCMOS33 [get_ports uar
                                               
# =============================================
# 寮曡剼缁戝畾 (閽堝 Minisys-1 XC7A100T)              
# =============================================
# LED 0-7                                      
set_property PACKAGE_PIN F6 [get_ports {led[7]}
set_property PACKAGE_PIN G4 [get_ports {led[6]}
set_property PACKAGE_PIN G3 [get_ports {led[5]}
set_property PACKAGE_PIN J4 [get_ports {led[4]}
set_property PACKAGE_PIN H4 [get_ports {led[3]}
set_property PACKAGE_PIN J3 [get_ports {led[2]}
set_property PACKAGE_PIN J2 [get_ports {led[1]}
set_property PACKAGE_PIN K2 [get_ports {led[0]}
                                               
# 鎷ㄧ爜寮?鍏? SW0-SW7 (鏁版嵁杈撳叆)                     
set_property PACKAGE_PIN P5 [get_ports {key[7]}
set_property PACKAGE_PIN P4 [get_ports {key[6]}
set_property PACKAGE_PIN P3 [get_ports {key[5]}
set_property PACKAGE_PIN P2 [get_ports {key[4]}
set_property PACKAGE_PIN R2 [get_ports {key[3]}
set_property PACKAGE_PIN M4 [get_ports {key[2]}
set_property PACKAGE_PIN N4 [get_ports {key[1]}
set_property PACKAGE_PIN R1 [get_ports {key[0]}
                                               
# 绯荤粺鏃堕挓                                       
set_property PACKAGE_PIN P17 [get_ports clk]   
                                               
# 鎺у埗淇″彿                                       
# send_one -> BTN (娉ㄦ剰锛氬彲鑳芥湁鎸夐敭鎶栧姩)            
set_property PACKAGE_PIN R11 [get_ports send_on
                                               
# 澶嶄綅淇″彿 -> 鏄犲皠鍒颁腑闂寸殑鎷ㄧ爜寮?鍏? SW12, SW10        
set_property PACKAGE_PIN T3 [get_ports uart_tx_
set_property PACKAGE_PIN T5 [get_ports uart_rx_
                                               
# 宸ヤ綔鐘舵?佹寚绀? -> 鏄犲皠鍒? LED17, LED16             
set_property PACKAGE_PIN M1 [get_ports uart_tx_
set_property PACKAGE_PIN K3 [get_ports uart_rx_
                                               
# UART 涓插彛                                     
set_property PACKAGE_PIN T4 [get_ports uart_tx]
set_property PACKAGE_PIN N5 [get_ports uart_rx]