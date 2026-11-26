# CloveCOM

面向嵌入式开发的 Windows 桌面通信调试与二进制文件处理工作台。

## 核心功能

- **接口通信**
  - 支持串口与网卡（TCP 客户端、TCP 服务端、UDP 单播/广播）多会话并发调试。
  - 支持 ASCII / HEX 收发、定时循环发送、交互式指令发送、会话历史回看与日志录制。
  - 内置文件传输与固件升级能力（支持 YMODEM 与自定义 Lua 协议脚本）。
- **工具箱**
  - **BIN 编辑器**：十六进制与 ASCII 双视图编辑、撤销/重做与导出。
  - **BIN 拼接**：多片段地址规划、对齐填充与冲突检测。
  - **HEX 转 BIN**：Intel HEX 文件解析与转换。
  - **CRC 校验**：常用 CRC 算法与多段 CRC32 合并计算。
- **CH34x 调试**
  - 支持 CH341/CH34x I2C 设备连接、寄存器读写、位域编辑与操作日志。
- **协议编辑**
  - 内置 Lua 协议脚本编辑器、示例模板与宿主 API 文档参考，支持按需扩展自定义通信与升级协议。
- **界面与更新**
  - 内置多套浅色/深色应用与终端配色主题。
  - 支持 Windows 自动检查更新、SHA-256 校验下载与一键重启升级。

## 下载与安装

前往 [GitHub Releases](https://github.com/Den9dada/clovecom/releases) 下载最新 Windows x64 安装包（`*-setup.exe`）、免安装 ZIP 或 MSIX 包。

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
