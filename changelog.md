# Changelog

## 2026-11-15

### chore: 提交桌面 GUI 迁移基线

- 共享桌面主题层 lib/ui（DesktopAction/DsDialog/DsToast 等）与协议编辑器核心 lib/src 落地，串口/USB/网络/工具箱/CH34x 五个入口接入新主题。
- 移除终端模块（本地 PTY/SSH/串口终端）及相关模型、服务、视图。
- 新增串口服务层 lib/services/serial、CH34x 服务与视图、固件升级页、协议库与 Lua 运行支持（native/lua_runner、third_party/lua）。
- 注册 MiSans 字体与协议资产，补充桌面主题/串口/工具箱/协议编辑器测试。

### docs: 架构评审设计定稿

- 沉淀领域用语 CONTEXT.md：保存基线导出重定基、串口传输会话跨页独占、语义事件四分类。
- 记录 ADR-0001 串口双栈以新 src 词汇为准（strangler 收拢所有权）、ADR-0002 退役 SnackBar 统一四个呈现适配器。

### refactor: 轨道 A 统一异步反馈与提示弹窗（C1→C2）

- C1 复活 `DsDialogAction` 为每动作一个的异步反馈深模块：`run()` 内化防重入、清旧错、错误保留、忙碌复位与销毁守卫；呈现经 `onFailed` 适配器缝注入（缺省由弹窗保留错误、`showDsToast` 瞬态轻提示、ViewModel setter 持久内联）。
- `interaction_editor.perform` 与 `app_controller._perform` 改为委托该模块，删除两处重复的 try-catch 反馈不变量；协议控制器由此补上此前缺失的防重入守卫，`lastError` 改为读取模块错误态。新增 8 项接口级测试（直接实例化模块断言不变量，不 pump 整页）。
- C2 退役 SnackBar（ADR-0002）：串口/固件 `errorStream` 改用 DsToast 瞬态适配器，并新增绑定 `errorMessage` 的持久内联 banner，修复串口打开失败仅靠 3 秒即逝弹窗导致的静默问题。
- 工具箱 `_showError` 统一为 DsToast；冲突检查按 `hasConflicts` 分 warning/success，文件类型忽略用 warning；三处裸 `AlertDialog`（自定义填充、新增 HEX、导出 HEX）迁移到 `DsDialog`/`DsInput`/`DsButton` 外壳；移除主题 `snackBarTheme` 死配置。
- 验证：改动目录 `flutter analyze` 零问题；新增测试 8/8 通过；全套测试 13 个失败经基线复核为既有失败，非本轨道引入。
- 已知遗留：工具箱 `lastError` 混用警告与错误语义（如重复导入提示），语义细分归轨道 C（C4）。

## 2026-10-18

### fix: 消除协议切换时接口参数框闪动

- 载入校验期间保持接口参数框外观，拦截鼠标和键盘操作，避免禁用样式短暂切换。
- 保留连接中和传输中的禁用状态，以及协议参数的单次应用。

### fix: 精简固件升级配置控件

- 固件文件框与选择按钮统一为 32 像素高度。
- 删除独立的卸载和编辑按钮，将卸载图标放入协议选择框。
- 移除已载入协议及载入校验中的文字提示，保留版本更新提示。

### feat: 选择升级协议后自动载入一次

- 删除载入按钮，选择协议后在后台自动校验并载入。
- 页面重建或保存脚本不重复载入，重新选择同一协议可更新快照。
- 载入失败保留原协议并恢复选项，卸载时清空选择。


### feat: 固件升级统一由脚本驱动并增加标准 YMODEM

- 删除升级页每包字节数和发送间隔，删除默认分包升级路径及未注册的分包协议类。
- 未载入升级脚本时禁用升级，卸载后不再回退发送。
- 新增可编辑标准 YMODEM Lua 脚本，支持 CRC/校验和、逐块 ACK、NAK/超时重传、EOT、空文件名结束块与取消。
- 已有协议库一次性补齐 YMODEM，保留用户脚本及既有删除记录，发布程序随附脚本示例。


### fix: 修复选择框常态高度与焦点边框不一致

- 选择框自身绘制唯一边框，解除紧凑密度对常态边框的压缩。
- 默认边框高度统一为 32 像素，与波特率输入框对齐，焦点态保持相同尺寸。
- 添加真实边框尺寸与焦点状态回归测试。


### style: 统一固件升级页控件

- 下拉菜单与波特率输入复用项目统一控件，统一标签、输入边距和主操作颜色。
- 协议菜单独占一行，操作按钮按可用宽度换行，避免挤压长协议名称。


### refactor: 移除 Dart 固件升级脚本支持

- 删除外部脚本选择、子进程执行及 JSON 通信桥，清除相关配置字段。
- 删除旧脚本示例和资源声明；固件升级仅保留 Lua 交互协议与内置分包发送。
- Lua 卸载操作统一到协议选择区，并同步使用说明与回归测试。

### feat: 移植协议编辑并接通 Lua 固件升级

- 增加解析协议与 Lua 交互协议编辑、导入导出、校验、预览和本地协议库。
- 升级页增加协议选择与明确载入，固定脚本快照，提示新版本并保护引用。
- Lua 流程复用串口独占会话，接通固件输入、握手收发、进度日志、失败和停止释放。
- 预置可编辑点表升级脚本，Windows 发布目录随附 Lua 解释器和宿主 SDK。
- 固件成功完整读取后才替换输入，补充解析、编辑器、协议库和升级回归测试。
- 使用说明见 `docs/protocol-editor.md`。


## 2026-05-19

### refactor: 全面移除终端模块

移除串口终端/SSH 终端模拟器模块，精简应用架构。

**移除目录：**
- `lib/models/terminal/` — TerminalSession, TerminalThemeScheme, 连接参数模型
- `lib/services/terminal/` — SerialTerminalService, SshTerminalService
- `lib/viewmodels/terminal/` — TerminalViewmodel
- `lib/views/terminal/` — TerminalView 及子组件 (TerminalPane, ConnectDialog 等)

**移除依赖：**
- `xterm` (终端模拟器核心)
- `flutter_pty` (PTY 原生插件)
- `dartssh2` (SSH 客户端)

**关联改动：**
- `home_view.dart` Tab 数 6→5，移除"终端"Tab
- `build_all.ps1` 过时文件清理列表增加 `flutter_pty.dll`

### fix: 完善 Windows 兼容性 (DLL 打包与系统版本检查)

解决在旧版本 Windows 上出现 "无法定位程序输入点 GetHostNameW 于 WS2_32.dll" 的问题。

**问题根因：**
- `GetHostNameW` 是 Windows 8 才加入 ws2_32.dll 的函数
- Flutter 3.x 引擎初始化网络子系统时会调用此函数
- 目标机器为 Windows 7 时，系统 DLL 中不存在该入口点

**改动：**
- 清理过时残留 `flutter_ymodem_plugin.dll`（代码中已无引用）
- 补充打包 `CH341DLLA64.dll`（I2C 工具所需，之前遗漏）
- 移除无用的 `native_assets.json` 占位文件
- Inno Setup 安装程序增加 Windows 10+ 版本检查（Win32MajorVersion >= 10）
- 构建脚本 `build_all.ps1` 新增 Copy-Ch341Dll / Remove-StaleDlls 辅助函数

## 2026-05-15

### feat: 新增 CH341 I2C 寄存器映射工具

基于 CH341DLLA64.dll 实现 I2C 寄存器映射工具，作为独立 Tab 页（I2C工具）。

**功能特性：**
- 支持 CH341 USB-I2C 设备的连接与通信（20K/100K/400K/750K 速率）
- 加载芯片寄存器定义 Excel（.xlsx），解析寄存器映射表（元数据 + 寄存器 + 位域）
- 寄存器列表视图：状态指示（已读/已修改/未读）、偏移地址、名称、权限
- 寄存器详情卡片：位域展开视图，支持 HEX 值 ↔ 位域值双向联动解码
- 单寄存器读写：高层 API 读/低层写（读-改-写保护）
- 批量操作：全部读取、全部写入（带进度条）
- 操作日志面板（时间戳 + 操作描述 + 数据 + 成功/失败状态）
- 全屏拖入 .xlsx 文件导入（desktop_drop DropTarget + 拖入提示覆盖层）
- 反向导出当前寄存器值为 Excel（保持导入格式，更新 F 列值）
- 响应式布局（宽屏双栏 / 窄屏单栏）

**技术实现：**
- FFI 封装 CH341DLLA64.dll（基于 WCH 官方 CH341DLL.H V2.2 头文件）
- Win32 设备枚举（探针法 CH341OpenDevice 0-15）
- Excel 解析：纯 Dart xlsx 读取（archive 包解压 + XML 解析）
- Excel 生成：纯 Dart xlsx 构建（zip 压缩 + XML 生成）
- MVVM 分层架构（Ch341ServiceBase → Ch341ServiceWin32 → I2cToolViewModel → I2cToolView）
- 跨平台预留（Service 抽象接口）

**文件清单：**
- 新建：18 个文件（3 models + 4 services + 1 viewmodel + 1 view + 7 widgets + 2 docs）
- 修改：home_view.dart（TabController length 5→6）、pubspec.yaml（新增 archive 依赖）

**参考：**
- SC7061 电池充电 IC 寄存器映射 Excel
- WCH CH341PAR 开发包 CH341DLL.H 头文件
