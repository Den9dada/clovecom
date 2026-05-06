# 终端模块实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增终端模块（主导航第一位），支持本地终端/SSH远程/串口终端三种会话，MobaXterm 风格左侧会话列表+右侧多标签页布局。

**Architecture:** xterm.dart 渲染终端 UI，flutter_pty 驱动本地 PTY，dartssh2 驱动 SSH，serial_port_win32 驱动串口。通过 `TerminalBackend` 接口统一接入。

**Tech Stack:** xterm ^4.0.0, flutter_pty ^0.4.2, dartssh2 ^4.0.1, serial_port_win32, provider

---

## 文件清单

| 操作 | 文件路径 |
|------|---------|
| 修改 | `pubspec.yaml` |
| 新建 | `lib/models/terminal/session_type.dart` |
| 新建 | `lib/models/terminal/terminal_session.dart` |
| 新建 | `lib/models/terminal/ssh_connection_params.dart` |
| 新建 | `lib/models/terminal/serial_connection_params.dart` |
| 新建 | `lib/services/terminal/local_pty_service.dart` |
| 新建 | `lib/services/terminal/ssh_terminal_service.dart` |
| 新建 | `lib/services/terminal/serial_terminal_service.dart` |
| 新建 | `lib/viewmodels/terminal/terminal_viewmodel.dart` |
| 新建 | `lib/views/terminal/terminal_view.dart` |
| 新建 | `lib/views/terminal/widgets/terminal_session_list.dart` |
| 新建 | `lib/views/terminal/widgets/terminal_tab_bar.dart` |
| 新建 | `lib/views/terminal/widgets/connect_dialog.dart` |
| 新建 | `lib/views/terminal/widgets/terminal_pane.dart` |
| 修改 | `lib/views/home/home_view.dart` |
| 新建 | `test/terminal/terminal_viewmodel_test.dart` |

---

### Task 1: 依赖 + 模型层

**Files:** 修改 `pubspec.yaml`，新建 `lib/models/terminal/` 下 4 个文件

- [ ] **Step 1: 添加 pubspec.yaml 依赖**

在 `dependencies:` 块末尾追加：

```yaml
  xterm: ^4.0.0
  flutter_pty: ^0.4.2
  dartssh2: ^4.0.1
```

- [ ] **Step 2: flutter pub get**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter pub get
```

- [ ] **Step 3: 创建 `lib/models/terminal/session_type.dart`**

```dart
enum SessionType { local, ssh, serial }
enum SessionStatus { disconnected, connecting, connected }
```

- [ ] **Step 4: 创建 `lib/models/terminal/terminal_session.dart`**

```dart
import 'package:xterm/xterm.dart';
import 'session_type.dart';

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.name,
    required this.type,
    required this.terminal,
    this.status = SessionStatus.disconnected,
    this.backend,
  });
  final String id;
  final String name;
  final SessionType type;
  SessionStatus status;
  final Terminal terminal;
  TerminalBackend? backend;
  bool get isConnected => status == SessionStatus.connected;
  String get statusLabel => switch (status) {
    SessionStatus.connected => 'Connected',
    SessionStatus.connecting => 'Connecting',
    SessionStatus.disconnected => 'Disconnected',
  };
}
```

- [ ] **Step 5: 创建 `lib/models/terminal/ssh_connection_params.dart`**

```dart
class SshConnectionParams {
  SshConnectionParams({required this.host, this.port = 22, this.sessionName = '', this.username = 'root', this.password = ''});
  final String host; final int port; final String sessionName; final String username; final String password;
  String get displayName => sessionName.isNotEmpty ? sessionName : '$username@$host:$port';
}
```

- [ ] **Step 6: 创建 `lib/models/terminal/serial_connection_params.dart`**

```dart
class SerialConnectionParams {
  SerialConnectionParams({required this.port, this.baudRate = 115200, this.dataBits = 8, this.stopBits = 1, this.parity = 'None'});
  final String port; final int baudRate; final int dataBits; final int stopBits; final String parity;
  String get displayName => '$port ${baudRate}bps';
  static const baudRatePresets = [300, 1200, 2400, 4800, 9600, 14400, 19200, 38400, 57600, 115200, 230400, 460800, 921600];
  static const dataBitsOptions = [5, 6, 7, 8];
  static const stopBitsOptions = [1, 2];
  static const parityOptions = ['None', 'Odd', 'Even', 'Mark', 'Space'];
}
```

- [ ] **Step 7: 提交**

```bash
git add pubspec.yaml lib/models/terminal/; git commit -m "feat: add terminal dependencies and models"
```

---

### Task 2: 本地 PTY 服务

**Files:** 新建 `lib/services/terminal/local_pty_service.dart`

- [ ] **Step 1: 创建**

```dart
import 'dart:io';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class LocalPtyService {
  Pty? _pty;
  TerminalBackend? _backend;

  TerminalBackend? get backend => _backend;

  static String get defaultShell {
    if (Platform.isWindows) return 'cmd.exe';
    if (Platform.isMacOS || Platform.isLinux) return 'bash';
    return 'sh';
  }

  void start({String? shell, int columns = 80, int rows = 24}) {
    _pty = Pty.start(shell ?? defaultShell, columns: columns, rows: rows);
    _backend = PseudoTerminal(
      (data) => _pty!.write(data),
      _pty!.output.cast<List<int>>(),
      (int newRows, int newCols) => _pty?.resize(newCols, newRows),
    );
  }

  void resize(int columns, int rows) => _pty?.resize(columns, rows);

  void dispose() {
    try { _pty?.kill(); } catch (_) {}
    _pty = null; _backend = null;
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/terminal/local_pty_service.dart; git commit -m "feat: add local PTY service"
```

---

### Task 3: SSH 终端服务

**Files:** 新建 `lib/services/terminal/ssh_terminal_service.dart`

- [ ] **Step 1: 创建**

```dart
import 'dart:async'; import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import '../../models/terminal/ssh_connection_params.dart';

class SshTerminalService {
  SSHClient? _client;
  TerminalBackend? _backend;
  StreamSubscription? _stdoutSub;

  TerminalBackend? get backend => _backend;
  bool get isConnected => _client != null;

  Future<void> connect(SshConnectionParams params, Terminal terminal) async {
    final socket = await SSHSocket.connect(params.host, params.port);
    _client = SSHClient(socket, username: params.username, onPasswordRequest: () => params.password);
    final session = await _client!.shell(ptyTermType: 'xterm-256color', ptyColumns: 80, ptyRows: 24);
    _stdoutSub = session.stdout.cast<List<int>>().listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });
    _backend = TerminalBackend(
      onWrite: (data) => session.write(utf8.encode(data)),
      onResize: (cols, rows) => session.ptyResize(cols, rows),
      onDispose: () => disconnect(),
    );
  }

  void disconnect() { _stdoutSub?.cancel(); _client?.close(); _client = null; _backend = null; }
  void dispose() => disconnect();
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/terminal/ssh_terminal_service.dart; git commit -m "feat: add SSH terminal service"
```

---

### Task 4: 串口终端服务

**Files:** 新建 `lib/services/terminal/serial_terminal_service.dart`

- [ ] **Step 1: 创建**

```dart
import 'dart:async'; import 'dart:convert'; import 'dart:ffi'; import 'dart:typed_data';
import 'package:ffi/ffi.dart'; import 'package:serial_port_win32/serial_port_win32.dart'; import 'package:win32/win32.dart';
import 'package:xterm/xterm.dart'; import '../../models/terminal/serial_connection_params.dart';

class SerialTerminalService {
  SerialPort? _port; TerminalBackend? _backend; Timer? _readTimer; Terminal? _terminal;
  DWORD? _readBytesRead; COMSTAT? _readComStat; DWORD? _readErrors; OVERLAPPED? _readOver;

  TerminalBackend? get backend => _backend;
  bool get isConnected => _port != null;

  void connect(SerialConnectionParams params, Terminal terminal) {
    _terminal = terminal;
    _port = SerialPort(params.port, openNow: false);
    _port!.openWithSettings(BaudRate: params.baudRate, ByteSize: params.dataBits,
      StopBits: params.stopBits == 1 ? 0 : 2, Parity: _parityValue(params.parity));
    _startReading();
    _backend = TerminalBackend(
      onWrite: (data) { if (_port != null) _port!.writeBytesFromUint8List(utf8.encode(data) as Uint8List); },
      onResize: (cols, rows) {},
      onDispose: () => disconnect(),
    );
  }

  void _startReading() {
    _readBytesRead = calloc<DWORD>(); _readComStat = calloc<COMSTAT>();
    _readErrors = calloc<DWORD>(); _readOver = calloc<OVERLAPPED>();
    _readOver!.ref.hEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    _readTimer = Timer.periodic(const Duration(milliseconds: 20), (_) => _readLoop());
  }

  void _readLoop() {
    if (_port == null || _terminal == null) return;
    final handler = _port!.handler!;
    ClearCommError(handler, _readErrors!, _readComStat!);
    final available = _readComStat!.ref.cbInQue; if (available == 0) return;
    final bytesToRead = available < 1024 ? available : 1024;
    final buffer = calloc<Uint8>(bytesToRead);
    try {
      ResetEvent(_readOver!.ref.hEvent);
      final result = ReadFile(handler, buffer, bytesToRead, _readBytesRead!, _readOver!);
      int bytesRead = 0;
      if (result != FALSE) { bytesRead = _readBytesRead!.value; }
      else if (GetLastError() == ERROR_IO_PENDING) {
        if (WaitForSingleObject(_readOver!.ref.hEvent, 50) == 0) {
          GetOverlappedResult(handler, _readOver!, _readBytesRead!, FALSE);
          bytesRead = _readBytesRead!.value;
        }
      }
      if (bytesRead > 0) _terminal!.write(utf8.decode(buffer.asTypedList(bytesRead), allowMalformed: true));
    } finally { free(buffer); }
  }

  void disconnect() {
    _readTimer?.cancel(); _readTimer = null;
    if (_readOver != null) { CloseHandle(_readOver!.ref.hEvent); free(_readOver!); _readOver = null; }
    free(_readBytesRead!); free(_readComStat!); free(_readErrors!);
    _readBytesRead = null; _readComStat = null; _readErrors = null;
    try { _port?.close(); } catch (_) {}
    _port = null; _backend = null;
  }

  void dispose() => disconnect();
  static int _parityValue(String parity) { switch (parity) { case 'Odd': return 1; case 'Even': return 2; case 'Mark': return 3; case 'Space': return 4; default: return 0; } }
  static List<String> getAvailablePorts() { try { return SerialPort.getAvailablePorts(); } catch (_) { return []; } }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/terminal/serial_terminal_service.dart; git commit -m "feat: add serial terminal service"
```

---

### Task 5: HomeView 修改

**Files:** 修改 `lib/views/home/home_view.dart`

- [ ] **Step 1:** 在 imports 顶部添加 `import '../terminal/terminal_view.dart';`
- [ ] **Step 2:** `TabController(length: 4...)` → `TabController(length: 5...)`
- [ ] **Step 3:** 在 `tabs` 列表最前面插入终端 Tab：

```dart
Tab(height: 38, child: Row(mainAxisSize: MainAxisSize.min, children: [
  Icon(Icons.terminal, size: 16), SizedBox(width: 6), Text('终端'),
])),
```

- [ ] **Step 4:** 在 `IndexedStack` 的 children 最前面插入 `TerminalView(),`

- [ ] **Step 5: 提交**

```bash
git add lib/views/home/home_view.dart; git commit -m "feat: add terminal tab to home view"
```

---

### Task 6: 终端 ViewModel

**Files:** 新建 `lib/viewmodels/terminal/terminal_viewmodel.dart`

- [ ] **Step 1: 创建**

```dart
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../models/terminal/session_type.dart';
import '../../models/terminal/terminal_session.dart';
import '../../models/terminal/ssh_connection_params.dart';
import '../../models/terminal/serial_connection_params.dart';
import '../../services/terminal/local_pty_service.dart';
import '../../services/terminal/ssh_terminal_service.dart';
import '../../services/terminal/serial_terminal_service.dart';

class TerminalViewModel extends ChangeNotifier {
  final List<TerminalSession> _sessions = [];
  int _selectedSessionIndex = -1;

  final LocalPtyService _localPty = LocalPtyService();
  final SshTerminalService _sshService = SshTerminalService();
  final SerialTerminalService _serialService = SerialTerminalService();

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  int get selectedSessionIndex => _selectedSessionIndex;
  TerminalSession? get selectedSession =>
      _selectedSessionIndex >= 0 && _selectedSessionIndex < _sessions.length
          ? _sessions[_selectedSessionIndex] : null;

  bool get hasLocal => _sessions.any((s) => s.type == SessionType.local);
  List<TerminalSession> get sshSessions => _sessions.where((s) => s.type == SessionType.ssh).toList();
  List<TerminalSession> get serialSessions => _sessions.where((s) => s.type == SessionType.serial).toList();

  void selectSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _selectedSessionIndex = index;
    notifyListeners();
  }

  void createLocalTerminal() {
    if (hasLocal) {
      final idx = _sessions.indexWhere((s) => s.type == SessionType.local);
      if (idx >= 0) { _selectedSessionIndex = idx; notifyListeners(); }
      return;
    }
    final terminal = Terminal(maxLines: 5000);
    final session = TerminalSession(id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '本地Shell', type: SessionType.local, terminal: terminal, status: SessionStatus.connected);
    _localPty.start();
    final backend = _localPty.backend;
    if (backend != null) session.backend = backend;
    terminal.onOutput = (data) => _localPty.pty?.write(Uint8List.fromList(data.codeUnits));
    _localPty.pty?.output.cast<List<int>>().listen((data) => terminal.write(String.fromCharCodes(data)));
    _sessions.add(session); _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();
  }

  Future<void> createSshSession(SshConnectionParams params) async {
    final terminal = Terminal(maxLines: 5000);
    final session = TerminalSession(id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: params.displayName, type: SessionType.ssh, terminal: terminal, status: SessionStatus.connecting);
    _sessions.add(session); _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();
    try {
      await _sshService.connect(params, terminal);
      session.status = SessionStatus.connected;
      final backend = _sshService.backend;
      if (backend != null) session.backend = backend;
      terminal.onOutput = (data) { if (_sshService.isConnected) session.backend?.write(data); };
    } catch (e) {
      session.status = SessionStatus.disconnected;
      terminal.write('\r\n\x1b[31mConnection failed: $e\x1b[0m\r\n');
    }
    notifyListeners();
  }

  void createSerialSession(SerialConnectionParams params) {
    final terminal = Terminal(maxLines: 5000);
    final session = TerminalSession(id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: params.displayName, type: SessionType.serial, terminal: terminal, status: SessionStatus.connected);
    _serialService.connect(params, terminal);
    final backend = _serialService.backend;
    if (backend != null) session.backend = backend;
    terminal.onOutput = (data) { if (_serialService.isConnected) session.backend?.write(data); };
    _sessions.add(session); _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();
  }

  void closeSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    final session = _sessions[index];
    session.backend?.dispose();
    if (session.type == SessionType.local) _localPty.dispose();
    else if (session.type == SessionType.ssh) _sshService.disconnect();
    else if (session.type == SessionType.serial) _serialService.disconnect();
    _sessions.removeAt(index);
    if (_sessions.isEmpty) _selectedSessionIndex = -1;
    else if (_selectedSessionIndex >= _sessions.length) _selectedSessionIndex = _sessions.length - 1;
    else if (index <= _selectedSessionIndex) _selectedSessionIndex--;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _sessions) s.backend?.dispose();
    _localPty.dispose(); _sshService.dispose(); _serialService.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/viewmodels/terminal/terminal_viewmodel.dart; git commit -m "feat: add terminal ViewModel"
```

---

### Task 7: UI 层（主页面 + 4个组件）

**Files:** 新建 `lib/views/terminal/` 下 5 个文件

- [ ] **Step 1:** `terminal_view.dart` — 左侧 200px 会话列表 + 右侧标签栏 + TerminalView + 底部状态栏
- [ ] **Step 2:** `terminal_session_list.dart` — 三组会话列表 + 新建连接按钮
- [ ] **Step 3:** `terminal_tab_bar.dart` — 可滚动标签栏，每标签含状态圆点+关闭按钮
- [ ] **Step 4:** `terminal_pane.dart` — xterm.dart `TerminalView(terminal:, backend:)`
- [ ] **Step 5:** `connect_dialog.dart` — SSH/串口 SegmentedButton 切换，串口波特率自定义
- [ ] **Step 6: 提交**

```bash
git add lib/views/terminal/; git commit -m "feat: add terminal UI views"
```

---

### Task 8: 编译验证

- [ ] **Step 1: flutter analyze**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter analyze
```

Expected: No issues found.

- [ ] **Step 2: flutter build windows --debug**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter build windows --debug
```

Expected: Build successful.

- [ ] **Step 3: flutter test**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter test
```

Expected: All tests PASS.

---

## 实现顺序依赖

```
Task 1 (deps + models) ──> Task 2 (PTY) ──┐
                       ──> Task 3 (SSH)  ──┤
                       ──> Task 4 (Serial)──┤
                                            ├──> Task 6 (ViewModel)
Task 5 (HomeView) ─────────────────────────┤
                                            │
Task 7 (UI Views) ─────────────────────────┘
                                            │
                                            └──> Task 8 (Build Verify)
```

Task 1-4 须先于 6，Task 5/7 可并行于服务层。

---

## 关键 API 速查

| 场景 | API |
|------|-----|
| 创建本地 PTY | `Pty.start('cmd.exe', columns: 80, rows: 24)` |
| PTY 输出流 | `pty.output.cast<List<int>>()` |
| PTY 写入 | `pty.write(data)` |
| PTY resize | `pty.resize(cols, rows)` |
| SSH 连接 | `SSHSocket.connect(host, port)` |
| SSH 认证 | `SSHClient(socket, username:, onPasswordRequest:)` |
| SSH Shell | `client.shell(ptyTermType: 'xterm-256color')` |
| SSH 输出 | `session.stdout.cast<List<int>>()` |
| SSH 写入 | `session.write(utf8.encode(data))` |
| 串口打开 | `SerialPort(port, openNow: false).openWithSettings(...)` |
| 串口读 | `ReadFile + OVERLAPPED + WaitForSingleObject` |
| 串口写 | `port.writeBytesFromUint8List(data)` |
| xterm 创建 | `Terminal(maxLines: 5000)` |
| xterm 用户输入 | `terminal.onOutput = (data) {...}` |
| xterm 写入 | `terminal.write(text)` |
| xterm 渲染 | `TerminalView(terminal:, backend:)` |
| xterm PTY后端 | `PseudoTerminal(onWrite, outputStream, onResize)` |
