# 通信助手 (CloveCom)

CloveCom 是一个基于 Flutter 的 Windows 桌面通信助手。项目面向串口调试、固件传输、二进制文件处理和后续多协议通信场景，采用 `MVVM + Provider` 的结构组织 UI、状态和业务逻辑。

当前版本已经从最初的串口助手扩展为四个主模块：

- 串口通信：已实现，是当前核心通信模块。
- USB 通信：已预留页面，等待后续接入。
- 网络通信：已预留页面，等待后续接入。
- 工具箱：已实现首批固件/二进制处理工具。

## 当前开发状态

### 已完成

- 桌面端基础应用框架、Material 3 主题和顶部模块导航。
- 串口通信主流程：串口枚举、参数配置、连接/断开、收发数据、消息日志、统计信息和错误提示。
- 串口高级收发能力：文本/HEX 发送、HEX 显示、追加 CR/LF、循环发送、接收隐藏、自动滚动、保存日志。
- 文件传输使用 Ymodem-1K；固件升级使用可编辑的 Lua 交互协议，预置点表与标准 YMODEM 脚本。
- 通信协议抽象：通过 `TransferProtocol` 和 `ProtocolRegistry` 注册可用传输协议。
- 工具箱模块：HEX 转 BIN、BIN 编辑、BIN 拼接、文件拖拽/选择导入、HEX/ASCII 预览。
- Windows 发布流水线：支持 Enigma Virtual Box 单文件打包和 Inno Setup 安装向导。
- 自动化测试：覆盖工具箱纯逻辑、工具箱 ViewModel、关键 Widget 布局和 Windows 发布脚本校验。

### 进行中 / 待完善

- USB 通信和网络通信仍是占位模块。
- 串口能力主要面向 Windows，其他平台需要替换底层串口实现。
- 工具箱首版适合常见固件文件；超大文件的虚拟化、分页和性能优化仍可继续增强。
- 文件传输协议已经具备扩展点，但更多设备协议、重试策略和硬件联调仍需按实际设备补充。
- Windows 发布脚本已具备校验流程，仍建议在干净 Windows 10/11 x64 环境或 Windows Sandbox 中做最终验收。

## 技术栈

- Flutter / Dart：桌面 UI 和业务实现。
- Material 3：应用主题、控件和布局风格。
- Provider / ChangeNotifier：ViewModel 状态管理。
- `serial_port_win32`：Windows 串口枚举、打开、写入。
- `ffi` / `win32`：补充 Win32 API 调用，用于更可靠的串口异步读取。
- `file_picker`：文件选择和导出路径选择。
- `desktop_drop` / `cross_file`：桌面文件拖拽导入。
- `path_provider`：日志文件路径。
- `flutter_test`：单元测试和 Widget 测试。

## 总体架构

项目采用 MVVM 分层，并在需要纯逻辑复用的场景额外抽出协议层和服务层。

```text
lib/
├── main.dart                         # 应用入口、主题配置
├── models/                           # 数据模型
├── protocols/                        # 文件传输协议抽象与实现
├── services/                         # 与 UI 无关的纯业务服务
├── utils/                            # 输入格式化等通用工具
├── viewmodels/                       # ChangeNotifier 状态和业务编排
└── views/                            # 页面、模块和可复用 Widget
```

分层职责：

- View：负责界面布局、用户交互和控件状态展示，不直接承载核心业务算法。
- ViewModel：负责连接 UI、模型、协议和服务，管理状态变更并通过 `notifyListeners()` 驱动界面刷新。
- Model：定义串口配置、消息、统计、工具箱文件条目、编辑历史、拼接片段等数据结构。
- Service：封装可测试的纯逻辑，例如 Intel HEX 解析、HEX 文本解析、BIN 插入/覆盖/删除、BIN 地址拼接。
- Protocol：抽象文件传输流程，让串口文件发送可以在不同协议间切换。

### 主界面架构

`HomeView` 是主模块入口，使用顶部 `TabBar` 切换四个一级模块，并通过 `IndexedStack` 保持各模块状态。这样切换到工具箱或预留模块时，串口通信页面不会被销毁，已连接串口、日志和配置可以继续保留。

当前一级模块：

- `SerialPortView`：串口通信。
- `UsbView`：USB 通信占位。
- `NetworkView`：网络通信占位。
- `ToolboxView`：固件和二进制工具箱。

## 串口通信模块

接口通信工作台通过右侧会话列表管理串口和网卡连接。打开会话并连接后，标签页可定向收发、记录数据和运行串口协议任务。

### 功能范围

- 自动刷新和显示系统串口列表。
- 配置端口、波特率、数据位、停止位、校验位和流控选项。
- 打开和关闭串口连接。
- 支持文本发送和 HEX 发送。
- 支持发送时追加 CR、LF。
- 支持循环发送，并可配置发送间隔。
- 接收区支持普通文本显示、HEX 显示、自动换行、隐藏接收、自动滚动。
- 支持保存接收/发送日志到文件。
- 维护发送/接收字节数和消息数量统计。
- 通过 SnackBar 和状态字段提示运行时错误。

### 串口读取实现

项目没有完全依赖 `serial_port_win32` 的读取回调，而是在串口底层驱动中使用 `ffi` 和 `win32` 调用 Win32 API：

- `ClearCommError` 查询接收缓冲区可读字节数。
- `ReadFile` 配合 `OVERLAPPED` 结构执行异步读取。
- `WaitForSingleObject` 和 `GetOverlappedResult` 等待读取完成。

这样做是为了规避部分场景下库内读取逻辑对 OVERLAPPED I/O 处理不完整导致的数据丢失风险。

### 文件发送和固件升级

串口模块内置三个发送入口：

- 数据发送：发送文本或 HEX 输入。
- 文件发送：选择任意文件，通过协议层按配置发送。
- 固件升级：在串口会话的发送配置菜单中打开升级窗口，选择固件和在协议编辑页保存的 Lua 交互协议。分块、超时和重试参数由脚本定义。

固件脚本通过 JSON 行协议和主进程交互：

- 主进程向脚本发送固件数据和串口接收数据。
- 脚本可以请求发送串口数据、上报进度、输出日志、报告错误或完成状态。

## 协议层

协议层位于 `lib/protocols/`，核心接口是 `TransferProtocol`。

```text
lib/protocols/
├── transfer_protocol.dart     # 协议接口和回调定义
├── protocol_registry.dart     # 协议注册表
└── ymodem_protocol.dart       # Ymodem-1K
```

当前已注册协议：

- Ymodem-1K：实现文件名包、1024 字节数据包、CRC-16/XMODEM 校验、ACK 等待和 EOT 结束流程，适合支持 Ymodem 的嵌入式设备。

新增协议时，实现 `TransferProtocol` 并在 `ProtocolRegistry` 注册即可。

## 工具箱模块

工具箱位于 `lib/views/toolbox/`、`lib/viewmodels/toolbox/`、`lib/services/toolbox/` 和 `lib/models/toolbox/`。它通过内部二级 `TabBar` 注册工具页面，后续新增工具只需要扩展工具注册表。

当前工具：

- HEX 转 BIN
- BIN 编辑
- BIN 拼接

### 工具箱架构

```text
lib/views/toolbox/
├── toolbox_view.dart                 # 工具箱外壳和二级 Tab
├── toolbox_tool_registry.dart        # 工具注册表
├── tools/                            # 具体工具页面
└── widgets/                          # 共享导入区、预览区、状态面板

lib/services/toolbox/
├── hex_parser.dart                   # Intel HEX 解析
├── hex_text_parser.dart              # HEX 文本和地址解析
├── bin_editor_service.dart           # BIN 插入/覆盖/删除
└── bin_link_service.dart             # BIN 片段按地址拼接
```

工具箱遵循两个原则：

- UI 和状态分开：每个工具页面都有自己的 ViewModel。
- 核心算法可测试：解析、编辑和拼接逻辑都在纯 Dart service 中，不依赖 Flutter Widget。

### HEX 转 BIN

支持导入 `.hex` 和 `.bin` 文件：

- `.hex` 文件按 Intel HEX 解析为连续二进制数据。
- `.bin` 文件直接读取，用于预览。
- 支持当前文件导出和批量导出。
- 支持重复文件检测和文件级错误状态。

Intel HEX 解析支持：

- Data Record `00`
- End Of File Record `01`
- Extended Segment Address Record `02`
- Extended Linear Address Record `04`
- 校验和验证
- EOF 缺失检测
- EOF 后数据检测
- 地址空洞以 `0xFF` 填充

### BIN 编辑

支持导入单个 `.bin` 文件并进行字节级编辑：

- 插入：在指定地址插入 HEX 字节。
- 修改：从指定地址开始覆盖字节。
- 删除：从指定地址删除指定长度。
- 单字节直接编辑：可在 HEX/ASCII 预览中修改具体字节。
- 撤销：支持撤销上一步编辑。
- 导出：保存为编辑后的 BIN 文件。

地址输入支持十进制和 `0x` 前缀十六进制；HEX 数据支持空格、逗号和换行分隔。

### BIN 拼接

支持把多个二进制片段按地址拼接为一个输出文件：

- 支持导入多个 `.bin` 片段。
- 支持手动添加 HEX 数据片段。
- 每个片段都有起始地址和长度。
- 输出范围由最小起始地址到最大结束地址决定。
- 片段间空洞使用可配置填充值，默认 `0xFF`。
- 地址重叠时明确报错，不静默覆盖。
- 支持实时预览和导出拼接结果。

## 测试与质量保障

测试文件位于 `test/`：

```text
test/
├── widget_test.dart
├── toolbox/
│   ├── bin_editor_service_test.dart
│   ├── bin_link_service_test.dart
│   ├── hex_ascii_line_formatter_test.dart
│   ├── hex_parser_test.dart
│   ├── hex_text_parser_test.dart
│   ├── toolbox_viewmodel_test.dart
│   └── toolbox_widget_test.dart
├── release_packaging_test.ps1
└── inno_setup_release_test.ps1
```

建议日常验证：

```powershell
flutter test
flutter analyze
```

发布脚本相关校验：

```powershell
powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1
powershell -ExecutionPolicy Bypass -File test/inno_setup_release_test.ps1
```

最近一次合并到 `master` 后，`flutter test` 已通过全部 37 个测试。

## 项目结构说明

```text
assets/
└── protocols/                        # Lua 交互协议示例

docs/superpowers/
├── specs/                            # 功能设计文档
└── plans/                            # 实施计划文档

installer/
└── clovecom.iss                      # Inno Setup 安装脚本

lib/
├── main.dart                         # 应用入口和主题配置
├── models/
│   ├── serial_port_model.dart
│   └── toolbox/                      # 工具箱数据模型
├── protocols/                        # 文件传输协议
├── services/
│   └── toolbox/                      # 工具箱纯逻辑服务
├── utils/
│   └── hex_input_formatter.dart
├── viewmodels/
│   ├── serial_port_viewmodel.dart
│   └── toolbox/                      # 工具箱 ViewModel
└── views/
    ├── home/
    ├── network/
    ├── serial_port/
    ├── toolbox/
    └── usb/

scripts/
├── build_installer_once.ps1
├── check_inno_setup_release.ps1
├── check_windows_release_dependencies.ps1
├── prepare_enigma_release.ps1
└── prepare_inno_setup_release.ps1

test/
├── toolbox/
├── widget_test.dart
├── release_packaging_test.ps1
└── inno_setup_release_test.ps1
```

## 安装和运行

### 环境要求

- Flutter SDK：3.50.1 或更高版本，Dart SDK：3.14.0 或更高的 3.x 版本。
- 操作系统：当前主要支持 Windows 桌面端。
- 串口功能：需要目标电脑安装对应 USB 转串口芯片驱动。

### 本地运行

```powershell
flutter pub get
flutter run -d windows
```

### 构建 Windows Release

```powershell
flutter build windows --release
```

普通 Flutter Windows 产物位于：

```text
build/windows/x64/runner/Release/
```

## Windows 发布与交付

项目支持两种 Windows 交付方式：

- Inno Setup 安装向导：推荐给大多数用户。
- Enigma Virtual Box 单文件：适合希望交付单个 EXE 的场景。

### 一键生成安装向导

先构建 Windows Release：

```powershell
flutter build windows --release
```

然后生成安装包：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_installer_once.ps1
```

如果希望脚本同时执行 Flutter 构建：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_installer_once.ps1 -Build
```

输出文件：

```text
release_package/inno_output/CloveComSetup.exe
```

安装向导会检查：

- 当前系统是否为 Windows x64。
- CloveCom 是否正在运行。
- 安装后的关键文件是否缺失。

### 分步生成 Inno Setup 安装包

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_enigma_release.ps1
powershell -ExecutionPolicy Bypass -File scripts/check_windows_release_dependencies.ps1
powershell -ExecutionPolicy Bypass -File scripts/check_inno_setup_release.ps1
powershell -ExecutionPolicy Bypass -File scripts/prepare_inno_setup_release.ps1
```

只校验输入但不编译：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_inno_setup_release.ps1 -SkipCompile
```

### Enigma 单文件发布

先构建 Windows Release：

```powershell
flutter build windows --release
```

生成 Enigma 输入目录和项目文件：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_enigma_release.ps1
```

脚本会生成：

```text
release_package/enigma_input/
release_package/clovecom.evb
```

再用 Enigma Virtual Box 11.30 或更新版本打开 `release_package/clovecom.evb`，确认输入文件为：

```text
release_package/enigma_input/clovecom.exe
```

建议输出为：

```text
release_package/clovecom_packed.exe
```

如果打包后程序双击无反应，请检查：

```text
%TEMP%\clovecom_startup_error.log
```

该日志会记录运行时是否能看到 `flutter_windows.dll`、`native_assets.json`、`data/app.so`、`data/icudtl.dat` 和 `data/flutter_assets`。

## 开发规范

- 文件命名使用小写字母和下划线。
- 类名使用 PascalCase。
- 变量和方法使用 camelCase。
- View 层保持轻量，复杂业务逻辑放入 ViewModel 或 service。
- 可单元测试的算法优先写成纯 Dart service。
- 新增工具箱功能时优先通过 `ToolboxToolRegistry` 注册，避免修改工具箱外壳。
- 新增传输协议时实现 `TransferProtocol`，并在 `ProtocolRegistry` 注册。
- Windows 发布相关改动需要同时运行脚本校验。

## 后续路线

### 短期

- 完善串口通信稳定性和硬件联调记录。
- 补充更多常见串口协议和传输失败重试策略。
- 为工具箱继续补充校验和、CRC、文件差异比较等工程调试工具。
- 优化大文件 HEX/ASCII 预览性能。

### 中期

- 实现 USB 通信模块：设备枚举、设备信息、基础读写。
- 实现网络通信模块：TCP、UDP、WebSocket 和 HTTP 调试能力。
- 将固件升级脚本协议整理成独立开发说明。

### 长期

- 抽象跨平台通信后端，降低 Windows API 绑定。
- 建立设备配置模板、会话保存和日志回放能力。
- 增加持续集成中的 Flutter 测试、静态分析和 Windows 发布脚本校验。

## 常见问题

### 为什么串口列表为空？

请确认串口设备已连接，设备驱动已安装，并且没有被其他软件独占。

### 为什么当前主要支持 Windows？

当前串口实现依赖 `serial_port_win32`、`ffi` 和 Win32 API。Flutter 本身支持多平台，但串口后端需要为不同系统分别适配。

### HEX 转 BIN 的地址空洞如何处理？

Intel HEX 中未覆盖的地址会使用 `0xFF` 填充，最终导出范围为最小出现地址到最大出现地址。

### BIN 拼接遇到地址重叠怎么办？

工具会报错并阻止导出，不会静默覆盖已有片段。

### 发布包是否包含串口硬件驱动？

不包含。USB 转串口芯片驱动仍需要由硬件厂商驱动或系统驱动提供。

## 许可证

本项目为私有项目，仅供学习和研究使用。
