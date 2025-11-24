# 源代码目录

## 模块说明

### matrix_core/
- 矩阵运算核心模块
- 包含转置、加法、标量乘法、矩阵乘法、卷积等运算

### input_interface/
- 输入接口模块
- UART接收、按键消抖、拨码开关处理

### output_interface/
- 输出接口模块
- UART发送、LED显示、数码管显示

### storage/
- 存储管理模块
- 矩阵RAM存储、矩阵管理逻辑

### control_fsm/
- 控制状态机
- 主状态机、运算状态机

### top/
- 顶层模块
- 系统顶层设计、时钟生成