# 终端模块设计规格

## 目标

在应用主导航中新增"终端"模块（位于最左侧第一位），提供类似 MobaXterm 风格的多标签终端工作台。支持三种终端会话类型：本地终端（cmd/PowerShell PTY）、SSH 远程终端、串口终端。左侧会话列表管理连接配置，右侧多标签页承载终端视图。终端 UI 基于 xterm.dart 渲染，本地后端使用 flutter_pty，SSH 后端使用 dartssh2，串口后端复用现有 serial_port_win32。

## 范围

- 主导航新增"终端"Tab，位于第一位（串口通信之前）。
- 三种会话类型：本地终端、SSH 远程、串口终端。
- 多标签页管理：新建/关闭/切换标签，每个标签一个终端会话。
- 左侧会话列表（200px）：树形展示本地终端快捷入口 + SSH 已保存配置 + 串口已保存配置 + 新建连接按钮。
- 右侧主区域：顶部标签栏 + xterm.dart TerminalView + 底部状态栏。
- SSH 连接对话框：主机、端口、用户名、密码认证。
- 串口连接对话框：端口（自动扫描）、波特率（预设+自定义）、数据位、停止位、校验位。
- 终端大小自适应窗口 resize。
- 复制粘贴支持（Ctrl+C/V 通过 xterm 原生处理）。
- 会话连接/断开状态管理与重新连接。

不在本轮范围内：

- SSH 密钥认证（首版仅密码）。
- 串口流控配置（RTS/CTS/XON）高级选项。
- 终端分屏（多终端同时显示）。
- 终端日志记录/导出。
- SFTP 文件传输集成。
- 会话配置持久化（首版内存管理，关闭即丢失）。

## 用户体验方向

终端模块定位为嵌入式工程调试终端，安静地站在应用第一位。参考 MobaXterm 的经典布局——左侧会话导航 + 右侧终端工作区——但做减法：去掉 MobaXterm 过于丰富的菜单和工具，保留最核心的"连接 → 终端"工作流。

核心交互原则：

- **一键启动**：切换到终端 Tab 时自动打开一个本地终端，无需手动操作。
- **连接即终端**：新建连接完成后立即切换到对应标签页，终端获得焦点。
- **左侧导航右侧操作**：会话列表负责管理连接，终端区负责交互，清晰分离。
- **状态可见**：标签页标题显示连接状态指示（绿色圆点=已连接，灰色=断连），状态栏显示详细信息。

## 总体布局

```
┌──────────────────┬──────────────────────────────────────────────┐
│ 左侧会话栏 200px  │  右侧主区域                                    │
│                  │                                              │
│ ┌──────────────┐ │  ┌─── Tab1: 本地Shell ┬ Tab2: COM3 ─────────┐│
│ │ 🔌 会话列表   │ │  ├──────────────────┴───────────────────────┤│
│ │              │ │  │                                           ││
│ │ 📁 本地终端   │ │  │  ┌──────────────────────────────────────┐││
│ │  └ 本地Shell  │ │  │  │  TerminalView (xterm.dart)            │││
│ │              │ │  │  │                                       │││
│ │ 🌐 SSH 连接   │ │  │  │                                       │││
│ │  └ 192.168.. │ │  │  │                                       │││
│ │              │ │  │  └──────────────────────────────────────┘│││
│ │ 🔌 串口连接   │ │  │                                           │││
│ │  └ COM3 115200│ │  │  ● Connected | COM3 | 115200-8-N-1      │││
│ │              │ │  │                                           │││
│ │ ──────────── │ │  │                                           │││
│ │ [+ 新建连接]  │ │  │                                           │││
│ └──────────────┘ │  │                                           │││
└──────────────────┴──┴───────────────────────────────────────────┘
```

### 左侧会话栏

- 宽度固定 200px。
- 树形结构（或分组列表）：
  - "本地终端"分组下固定显示一个"本地Shell"条目（点击创建本地终端标签）。
  - "SSH 连接"分组下列出已配置的 SSH 连接（初始为空，通过新建连接添加）。
  - "串口连接"分组下列出已配置的串口连接。
- 底部"新建连接"按钮，弹出连接对话框。
- 点击会话条目 → 若已有对应标签则切换到该标签，否则创建新标签。

### 右侧主区域

- 顶部：可滚动标签栏（`TabBar` isScrollable），每个标签显示会话名称 + 连接状态指示圆点。
- 中间：`Expanded` 终端视图区，渲染当前选中标签的 `TerminalView`。
- 底部：状态栏（约 24px 高），显示：
  - 连接状态（Connected / Disconnected / Connecting）
  - 远程地址或串口名
  - 终端尺寸（cols × rows）

### 新建连接对话框

对话框通过顶部 SegmentedButton 切换 SSH / 串口模式：

```
┌─────────────────────────────────────┐
│  新建连接                    [ ✕ ]  │
│                                     │
│  [ SSH ]  [ 串口 ]                  │
│                                     │
│  ── SSH 模式 ──                      │
│  主机/IP:   [______________]        │
│  端口:      [ 22             ]      │
│  会话名称:   [______________]        │
│  用户名:    [______________]        │
│  密码:      [______________]        │
│                                     │
│  ── 串口模式 ──                      │
│  端口:      [ COM3 ▼        ]       │
│  波特率:    [ 115200 ▼     ]        │
│  自定义:    [______________]        │  ← 仅选中"自定义"时显示
│  数据位:    [ 8 ▼          ]        │
│  停止位:    [ 1 ▼          ]        │
│  校验位:    [ None ▼       ]        │
│                                     │
│          [ 取消 ]  [ 连接 ]          │
└─────────────────────────────────────┘
```

波特率选项列表：
```
300, 1200, 2400, 4800, 9600, 14400, 19200, 38400, 57600,
115200, 230400, 460800, 921600, 自定义
```

## 三种会话类型

### 本地终端

- 后端：`flutter_pty` → `Pty.start('cmd.exe')` 或 PowerShell。
- 创建方式：点击左侧"本地Shell"条目。
- 终端尺寸：跟随 `TerminalView` 容器大小，通过 `pty.resize()` 通知。
- 连接状态：启动即连接，关闭标签时 `pty.kill()`。
- 默认名称："本地Shell"。

### SSH 远程终端

- 后端：`dartssh2` → `SSHClient` → 认证 → `client.shell()`。
- 创建方式：点击"新建连接" → SSH 模式 → 填写信息 → 连接。
- 终端尺寸：通过 `ptyResize` SSH 消息通知远端。
- 连接状态：Connecting → Connected / Failed。
- 断连后可重新连接。
- 认证方式（首版）：密码认证。
- 远程 shell：默认使用远端用户的默认 shell。

### 串口终端

- 后端：复用现有 `serial_port_win32` → 打开串口 → 读线程 + 写通道。
- 创建方式：点击"新建连接" → 串口模式 → 配置参数 → 连接。
- 可用串口列表通过 `SerialPort.getAvailablePorts()` 动态扫描。
- 数据收发：
  - 读：后台隔离线程循环读取串口数据 → 写入 `Terminal.write()`。
  - 写：监听 `Terminal.onOutput` → 写入串口。
- 连接状态：Connected / Disconnected（串口拔出时自动断连并提示）。
- 不支持终端尺寸概念（串口无 resize 机制），状态栏显示串口参数代替尺寸。

## 架构设计

### 依赖关系

```
pubspec.yaml 新增依赖:
  xterm: ^4.0.0       # 终端 UI (Terminal + TerminalView)
  flutter_pty: ^0.4.3 # 本地 PTY
  dartssh2: ^4.0.1    # SSH 协议

  已有依赖复用:
  serial_port_win32: ^1.0.2  # 串口终端后端
  provider: ^6.1.2            # 状态管理
```

### 目录结构

```
lib/
├── models/terminal/
│   ├── terminal_session_type.dart        # [新增] enum SessionType { local, ssh, serial }
│   ├── terminal_session.dart             # [新增] 会话模型 (id, name, type, status, params)
│   ├── ssh_connection_params.dart        # [新增] SSH 连接参数
│   └── serial_connection_params.dart     # [新增] 串口连接参数
├── services/terminal/
│   ├── local_pty_service.dart            # [新增] 本地 PTY 生命周期管理
│   ├── ssh_client_service.dart           # [新增] SSH 连接/断连/认证
│   └── serial_terminal_service.dart      # [新增] 串口终端读写后端
├── viewmodels/terminal/
│   └── terminal_viewmodel.dart           # [新增] 标签页/会话列表状态管理
└── views/terminal/
    ├── terminal_view.dart                 # [新增] 终端主页面 (左侧栏 + 右侧区域)
    └── widgets/
        ├── terminal_session_list.dart     # [新增] 左侧会话列表
        ├── terminal_tab_bar.dart          # [新增] 标签栏
        ├── connect_dialog.dart            # [新增] 新建连接对话框 (SSH/串口切换)
        └── terminal_pane.dart             # [新增] 单个终端面板 (TerminalView)

修改:
lib/views/home/home_view.dart              # Tab 4→5，"终端"Tab 插入首位
pubspec.yaml                                # + 3 依赖
```

### 依赖关系图

```
terminal_view.dart (View)
  └─ context.watch<TerminalViewModel>()
       └─ TerminalViewModel (ChangeNotifier)
            ├─ List<TerminalSession>
            ├─ LocalPtyService  → flutter_pty.Pty
            ├─ SshClientService → dartssh2.SSHClient
            └─ SerialTerminalService → serial_port_win32

terminal_pane.dart
  └─ TerminalView(terminal: Terminal, backend: TerminalBackend)
       ├─ 本地: PseudoTerminal(pty.input, pty.output, pty.resize)
       ├─ SSH:  自定义 SshBackend(session.stdout, session.stdin)
       └─ 串口: SerialBackend(service.readStream, service.writeSink)
```

### 状态管理

```dart
class TerminalViewModel extends ChangeNotifier {
  final List<TerminalSession> _sessions = [];
  int _selectedSessionIndex = -1;

  List<TerminalSession> get sessions;
  TerminalSession? get selectedSession;

  // Tab 操作
  void createLocalTerminal();
  Future<void> createSshSession(SshConnectionParams params);
  Future<void> createSerialSession(SerialConnectionParams params);
  void closeSession(int index);
  void selectSession(int index);

  // 连接操作
  Future<void> reconnect(int index);
  Future<void> disconnect(int index);
}
```

```dart
class TerminalSession {
  final String id;
  String name;
  SessionType type;
  SessionStatus status;  // connecting / connected / disconnected
  final Terminal terminal;
  TerminalBackend? backend;
  dynamic connectionParams;  // SshConnectionParams or SerialConnectionParams

  Pty? pty;              // 仅本地
  SSHClient? sshClient;  // 仅 SSH
}
```

### 串口终端后端关键实现

```dart
class SerialBackend implements TerminalBackend {
  final Stream<List<int>> readStream;
  final void Function(List<int> data) write;

  @override
  void write(String data) => write(utf8.encode(data));

  @override
  void init() { /* 启动读循环 */ }

  @override
  void dispose() { /* 关闭串口 */ }
}

class SerialTerminalService {
  SerialPort? _port;
  StreamController<List<int>>? _readController;

  Future<void> connect(SerialConnectionParams params) async {
    _port = SerialPort(params.port, openNow: false);
    _port!.openWithConfig(SerialPortConfig(
      baudRate: params.baudRate,
      byteSize: params.dataBits,
      stopBits: params.stopBits,
      parity: params.parity,
    ));
    // 启动读线程...
  }

  void write(List<int> data) => _port!.write(Uint8List.fromList(data));
  void dispose() { _port?.close(); _readController?.close(); }
}
```

## 测试计划

单元测试覆盖：

- SerialConnectionParams 默认值正确性。
- SshConnectionParams 验证（必填字段检查）。
- TerminalSession 状态流转（connecting → connected → disconnected）。
- TerminalViewModel 会话创建/关闭/切换。
- SerialBackend 数据收发。

Widget 测试：

- 终端 Tab 显示在主导航第一位。
- 左侧会话列表渲染三种分组。
- 新建连接对话框 SSH/串口模式切换正常。
- 串口模式波特率"自定义"选项展开/收起。
- 本地终端标签页创建和关闭。

验证命令：

- `flutter test`
- `flutter analyze`
- `flutter build windows --debug`

## 风险与处理

- **xterm.dart 4.0 API 兼容性**：该库仍在快速迭代，API 可能变化。锁定 `^4.0.0` 版本，实现时查阅最新文档确认。
- **串口终端性能**：大数据量下轮询读可能卡 UI。使用 Isolate 或独立线程读串口，通过 Stream 传递数据到主线程的 TerminalView。
- **PTY 跨平台**：`flutter_pty` 支持 Windows/Linux/macOS，cmd.exe 仅 Windows 可用。后续可配置为跨平台检测。
- **SSH 密码安全**：密码明文存储在内存中。首版不持久化配置，关闭应用即清除；若后续需要持久化，引入 flutter_secure_storage 加密存储。
