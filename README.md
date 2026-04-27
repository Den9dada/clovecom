# 通信助手 (CloveCom)

一个基于Flutter开发的通信助手应用，采用MVVM架构，支持串口通信，预留USB和网络通信模块。

## 项目概述

本项目是一个多功能通信助手应用，旨在提供统一的通信接口管理。目前实现了串口通信功能，后续将扩展USB和网络通信功能。

## 功能特性

### 已实现功能
- **串口通信模块**
  - 自动检测系统可用串口
  - 支持串口参数配置（波特率、数据位、停止位、校验位）
  - 串口连接和断开
  - 数据发送和接收
  - 消息记录显示
  - 错误提示和状态管理

### 预留功能
- **USB通信模块** - 占位页面，待后续开发
- **网络通信模块** - 占位页面，待后续开发

## 技术架构

### MVVM架构
项目采用MVVM（Model-View-ViewModel）架构模式：

```
┌─────────────────────────────────────┐
│              View Layer             │
│  (serial_port_view.dart, etc.)      │
├─────────────────────────────────────┤
│           ViewModel Layer           │
│  (serial_port_viewmodel.dart)       │
├─────────────────────────────────────┤
│              Model Layer            │
│  (serial_port_model.dart)           │
└─────────────────────────────────────┘
```

- **Model层**：定义数据结构和业务实体
- **View层**：负责UI展示和用户交互
- **ViewModel层**：处理业务逻辑，管理状态，连接Model和View

### 依赖包
- `provider`: 状态管理
- `serial_port_win32`: Windows串口通信
- `intl`: 国际化和日期格式化

## 项目结构

```
lib/
├── main.dart                          # 应用入口文件
├── models/
│   └── serial_port_model.dart         # 串口数据模型
├── viewmodels/
│   └── serial_port_viewmodel.dart     # 串口通信业务逻辑
└── views/
    ├── home/
    │   └── home_view.dart             # 主页面（TabBar切换）
    ├── serial_port/
    │   └── serial_port_view.dart      # 串口通信界面
    ├── usb/
    │   └── usb_view.dart              # USB通信（预留）
    └── network/
        └── network_view.dart          # 网络通信（预留）
```

## 文件说明

### 核心文件

#### `main.dart`
应用入口文件，负责启动应用并配置基本主题。使用Material 3设计风格，配置蓝色主题色。

#### `models/serial_port_model.dart`
串口通信数据模型文件，定义了三个核心类：
- `SerialPortConfig`: 串口配置参数（端口号、波特率、数据位、停止位、校验位）
- `SerialPortMessage`: 串口消息数据（消息内容、时间戳、发送方向）
- `SerialPortState`: 串口连接状态（是否连接、是否正在接收、错误信息）

#### `viewmodels/serial_port_viewmodel.dart`
串口通信视图模型文件，实现核心业务逻辑：
- 管理串口配置和连接状态
- 提供串口连接和断开功能
- 处理数据的发送和接收
- 维护消息历史记录

#### `views/home/home_view.dart`
主页面视图文件，使用TabBar实现模块切换：
- 串口通信Tab
- USB通信Tab（预留）
- 网络通信Tab（预留）

#### `views/serial_port/serial_port_view.dart`
串口通信界面文件，包含三个主要区域：
- 配置区域：串口选择、波特率设置、连接控制
- 消息区域：收发消息的显示
- 发送区域：数据输入和发送

#### `views/usb/usb_view.dart`
USB通信视图文件，目前为占位页面，显示"功能开发中"提示。

#### `views/network/network_view.dart`
网络通信视图文件，目前为占位页面，显示"功能开发中"提示。

## 运行要求

- Flutter SDK: ^3.10.1
- Dart SDK: ^3.10.1
- 操作系统: Windows（串口通信功能依赖Windows API）

## 安装和运行

1. 确保已安装Flutter SDK
2. 克隆项目到本地
3. 进入项目目录
4. 运行以下命令：

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run
```

## 开发规范

### 代码风格
- 遵循Dart官方代码规范
- 使用中文注释说明代码功能
- 每个文件顶部添加文件说明注释
- 类和方法添加文档注释

### 命名规范
- 文件名：使用小写字母和下划线（snake_case）
- 类名：使用大驼峰命名法（PascalCase）
- 变量和方法：使用小驼峰命名法（camelCase）
- 常量：使用大写字母和下划线

### 架构规范
- 严格遵循MVVM架构模式
- View层只负责UI展示，不包含业务逻辑
- ViewModel层管理状态和业务逻辑
- Model层定义数据结构，不包含业务逻辑

## 后续开发计划

### 短期目标
- 完善串口通信功能
  - 添加更多串口参数配置
  - 支持数据格式转换（HEX/ASCII）
  - 添加数据发送历史
  - 支持自动重连

### 中期目标
- 实现USB通信模块
  - USB设备枚举
  - USB数据传输
  - USB设备信息显示

### 长期目标
- 实现网络通信模块
  - TCP/UDP通信
  - WebSocket支持
  - HTTP/HTTPS请求
  - 网络状态监控

## 常见问题

### Q: 为什么串口列表为空？
A: 请确保系统中已连接串口设备，并且驱动程序已正确安装。

### Q: 如何修改串口参数？
A: 在串口通信页面的配置区域，可以修改串口端口号和波特率。需要先断开连接才能修改参数。

### Q: 支持哪些操作系统？
A: 目前仅支持Windows系统，因为串口通信功能依赖Windows API。

## 许可证

本项目为私有项目，仅供学习和研究使用。

## 联系方式

如有问题或建议，请通过以下方式联系：
- 提交Issue到项目仓库
- 发送邮件至项目维护者

---

**注意**：本项目仍在开发中，部分功能可能不稳定。请在生产环境谨慎使用。
