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

### refactor: 轨道 B 串口连接所有权与翻译缝收拢（C3→C5 部分）

- C3 新增 `SerialConnectionOwner` 连接所有者深模块：port→租约独占映射，第二个借用者直接拒绝（不排队），租约随 `transport.close()` 释放、防误释新租约、打开失败不登记租约。串口页与固件页 VM 的默认传输工厂改走应用级单例，跨页“一端口一任务”独占在连接层强制成立；占用拒绝经轨道 A 的持久错误 banner 呈现。新增 8 项接口级测试。
- C5 新增 `SerialConfigTranslation` 唯一翻译缝：parity/flowControl 的显示值↔规范码↔索引对照表内化于一处，VM 与固件绑定两份手写映射收敛为单一模块（落实 ADR-0001“新增取值只改一处”）。新增 6 项往返测试。
- 验证：改动目录 `flutter analyze` 零问题；串口服务＋固件视图 34 测试全绿；全套 185 通过／13 既有失败（经基线复核非本轨道引入）。
- 待续（strangler 下一增量）：C5 接收管线 isolate 化＋事件驱动 `WaitCommEvent`（当前为主 isolate 10ms 轮询＋同步 FFI 阻塞≤100ms），需独立 FFI 重写与契约测试（通知≤20Hz／吞吐≥波特率／零 UI 阻塞），按 ADR-0001 渐进推进，不在本次一次性重写。

### refactor: 轨道 C 工具箱性能（C6 查表 CRC＋C7 布局重绘令牌）

- 前提复核：调研确认 BIN 编辑文档的 `BinEditOperation` 编辑历史、导出重定保存基线（`markSaved`）、revision/dirty 均已存在；`EditBuffer` 字节差量为零引用零测试的死代码。故 C4 不是“补历史/重定基”，真正剩余的只是差量存储取舍，本次不动编辑文档语义。
- C6 `CrcCalculator` 深化为查表深模块：对外 `calculate(data, params)` 接口不变，width>=8 走按 (width, poly, refin) 缓存的 256 项查表（每字节一次查表，约 8x 于逐位），width<8 保留逐位；空数据分支与 refout/xorout 后处理严格保持原语义。段 CRC 与每次规划的全量输出 CRC 同受其益。新增 23 项查表/逐位独立 oracle 对拍测试（覆盖全部 21 预设＋自定义 width>=8 参数＋7 种数据模式），连同原有 13 项已知向量全绿。
- C7 拼接布局重绘令牌：`BinLinkViewModel` 新增 `layoutRevision`，仅在 `_refreshPreview()`（规划真正变化）自增；改名/清错误/无效输入失败不自增。`_MinimapPainter`/`_SegmentLayoutPainter` 的 `shouldRepaint` 改用 O(1) 令牌比较，取代此前因 `segments` getter 每次返回新 `List.unmodifiable`、layout 每次新建 `enabled` 列表而恒为真的 List 身份比较——布局/小地图不再随无关重建（改名、滚动、另一工具编辑）无效重绘。新增 5 项修订号语义测试。
- 验证：改动文件 `dart analyze` 零问题；CRC＋拼接 45 测试全绿；整个工具箱目录 91 测试全绿，零回归。
- 待续（strangler 下一增量）：C6 拼接输出惰性化＋相对化布局＋`crc32_combine`/填充闭式合成（当前每次规划 `List.filled(end)` 全量分配＋全量重算 CRC，高地址固件会放大分配；`previewBytes` 被 HEX 预览消费，惰性化需改查看器数据契约）；C7 HEX 查看器通知域细分（根内容 `context.watch` 致编辑单字节整树重建，宜用 Selector）；C4 `EditBuffer` 差量存储取舍（采用或删除死代码）。均按 ADR-0001 渐进推进。

### refactor: 轨道 D 扩展性（C9 删除 ProtocolRegistry，传输协议收为注入依赖）

- C9 删除 `ProtocolRegistry` 浅模块（21 行纯转发：`getByName/getByReceiveName` 忽略 name 恒返回 `new YmodemProtocol()`，`defaultProtocol` 零调用方，通过 deletion test）。把“如何取得传输协议”的知识收拢到串口 VM 缝：`SerialPortViewModel` 新增注入依赖 `TransferProtocol? transferProtocol`（默认 `YmodemProtocol()`，与既有 `openTransport`/`directory` 注入模式一致），收发两处改用 `_transferProtocol`，并暴露 `transferProtocol` getter 供视图下拉取唯一选项名。生产 Ymodem 与测试 fake 构成同一缝上的两个适配器（假想缝→真缝），`TransferCallbacks` 测试面保持不变。
- 视图收发下拉改为从 `viewModel.transferProtocol.name/receiveName` 取单选项（注册表本就只含 Ymodem，行为不变）；移除两处注册表导入。新增 2 项注入缝契约测试（默认 Ymodem-1K、注入实例同一性）。
- 验证：改动文件 `dart analyze` 零问题；串口服务目录 34 测试全绿（含 2 新测试）；全套 215 通过／13 失败，失败数与基线一致——12 个为 Lua 工作进程未随测试环境安装（`RuntimeUnavailable`）的环境性失败、1 个 interaction_editor 既有 spinner 计时失败，均非本轨道引入。
- 待续（strangler 下一增量）：C8 工具箱入口描述符＋注册表分配槽位、状态栏按入口 id 键控（当前 `ToolboxToolDefinition` 无 id，4 工具各自硬编码槽位号与 `_isCurrentTab` 索引，`StatusBarService` 按 int 槽键控且工具箱固定 `_statuses[3]`，新增/插入工具需改≥3 处并顺延槽号）。按 ADR-0001 渐进推进。

### refactor: 轨道 D 扩展性（C8 入口描述符＋注册表分配槽位＋状态栏 id 键控）

- C8 把“工具箱入口是谁”的知识收拢到注册表单一来源：`ToolboxToolDefinition` 新增稳定 `id`（hexToBin/binEditor/binLink/crc 四个 const id 定义在 `ToolboxToolRegistry`），槽位不再硬编码——`slotOf(id)`/`idAt(slot)` 按列表位置分配与往返映射。4 个工具的 `_isCurrentTab` 与状态栏上报全部改从注册表取 id/槽位，新增或插入工具只需在列表加一项描述符，不再改≥3 处并顺延槽号（落实 ADR-0001“新增取值只改一处”）。
- `StatusBarService` 工具箱状态由 int 槽键控改为 String id 键控：`updateToolboxStatus(toolId, info)` 缓存各工具状态，`setActiveToolboxTool(toolId)` 由 toolbox 页 tab 切换驱动；仅活跃工具的状态投影到主 tab 状态栏（`_toolboxTabIndex` 常量化），非活跃更新不覆盖、切换即取缓存。id 唯一来源在注册表，状态栏模块不再知晓具体槽位号。
- 验证：改动文件 `dart analyze` 零问题；新增 5 项注册表/状态栏序列契约测试（槽位互异、idAt/slotOf 往返、未知 id/越界、活跃投影与非活跃缓存）；工具箱目录 92 测试全绿（含既有 tab 标题断言），零回归。

### refactor: 轨道 C 性能（C7 HEX 查看器通知域细分）

- 三个工具（BIN 编辑/HEX 转换/BIN 拼接）的根内容 `context.watch` 整树订阅改为按域 Selector：工具栏只依赖能力域（hasFile／四个导出能力／填充值＋可导出性），查看器只依赖内容域（file/bytes 身份记录），控制区域（状态/历史/文件列表）局部 Consumer。编辑单字节不再重建工具栏；清错误/改名不再重建查看器与布局。
- BIN 拼接的滚动指示器从 `setState` 整树重建改为 `ValueNotifier` 滚动域，仅小地图订阅；规划域（布局＋HEX 预览＋小地图数据）整体只依赖 `layoutRevision`，builder 内 read 取规划快照（painter 不画段名，改名无需重绘）。
- 两个 VM 的空态 bytes getter 规范化为 `const <int>[]`，保证查看器域 Selector 的相等判定廉价且身份稳定（内容不变则不重建）。
- 验证：改动文件 `dart analyze` 零问题；新增 9 项内容域身份契约测试（空态身份、相同内容编辑早退、清错误/改名/重复选中不换身份、真实编辑/切换条目/规划变更换身份）；工具箱目录 101 测试全绿，零回归。

### refactor: 轨道 C 模块框架（C4 删除 EditBuffer 死代码）

- C4 前提复核（轨道 C 已记录）：BIN 编辑文档的编辑历史/保存基线/revision 均已存在，`EditBuffer` 字节差量是零引用零测试的死代码。本次删除整文件 `lib/services/toolbox/binary_data_source.dart`（`BinaryDataSource` 抽象/`MemoryDataSource`/`EditBuffer`/`BinaryDataSourceRaw` 扩展，110 行）——通过 deletion test：删除后无任何调用方需要承接复杂度，只消除“编辑文档有两套存储语义”的误导。差量存储的采纳暂缓：需改 HEX 查看器 painter 的数据契约且收益不明，不在本次动编辑文档语义。
- 验证：`dart analyze lib/services/toolbox/` 零问题；工具箱目录 101 测试全绿，零回归。
- 附带发现（未动，登记待续）：`BinLinkStatusBar` widget 零引用（拼接工具的状态信息走应用级状态栏），属同类死代码，留待下一增量一并清理。

### refactor: 轨道 C 性能（C6 crc32_combine＋填充闭式合成）

- 新增 `crc32_combine.dart` 深模块：接口为“按输出顺序的游程列表 → 整图标准 CRC-32”；实现为 GF(2) 矩阵幂（zlib crc32_combine 同款；init==xorout==0xFFFFFFFF 时可直接对最终 CRC 值合成，无需还原初值）＋填充游程闭式倍增 O(log n)。通过 deletion test：删除则退回全量扫描，GF(2) 复杂度集中于单一可测模块。
- `BinLinkService.plan` 的输出 CRC 改由段 CRC＋填充游程合成，取代对完整输出的 O(end) 全量扫描；高地址稀疏镜像收益显著（仅扫描 O(originalSize) 段数据＋O(段数×log) 合成）。输出字节仍物化供 HEX 预览消费（查看器数据契约不变）。
- 验证：改动文件 `dart analyze` 零问题；新增 6 项 oracle 对拍测试（空/单游程、填充闭式 24 组、随机布局 200 组、高地址稀疏、plan 集成 50 组），合成结果与“物化后全量扫描”逐位一致；工具箱目录 107 测试全绿，零回归。
- 诚实说明：收益为结构性（去除 O(end) CRC 扫描），未做运行时 profiling；稠密低地址镜像 originalSize≈end，合成开销与扫描相当；分配主导成本（`List.filled(end)` 双份拷贝）由待续的惰性化/相对化解决。
- 待续（strangler 下一增量）：C6 拼接输出惰性化（需改 HEX 查看器数据契约）＋相对化布局（改导出语义，需先定域）。

### docs: C5 接收管线 isolate 化调研定稿（硬件验证门槛）

- 后台调研结论：`WaitCommEvent`/`SetCommMask` 等 13 个符号在 package:win32 6.4.0 齐全（此前“缺失”仅是仓库零使用）；`HANDLE` 是 `Pointer` 的 extension type，跨 isolate 发送 address（int）后在 isolate 内重建可行；主 isolate 保留写/控制，isolate 内重建读循环。
- 渐进计划（ADR-0001）：增量 A＝读循环移 isolate、保留 10ms 轮询、`ReceivePort` 单订阅桥接保持 `Stream<Uint8List>` 接口（上层 VM/4 个 fake 零改动，可独立验证）；增量 B＝isolate 内 `WaitCommEvent` 事件驱动＋stop 事件关闭协议（EV_RXCHAR 兼容性需实测）；大改（独立 session）＝写路径与逐 chunk 格式化移 isolate。
- 关键风险：close 须 stop→`CancelIoEx`→等完成→`CloseHandle`，跨 isolate HANDLE 生命周期存在竞态；真实传输路径零单测、需真机回归。
- 决策：本环境无串口硬件，无法对正在工作的读循环做真机回归。按 ADR-0001 与“先核对最新构建再改方案”守则，不在无硬件验证下替换工作路径——C5 作为需真机验证的独立 session 推进，计划与风险已就绪，未改任何串口代码。

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
