# Changelog

## 2026-11-26

### chore: 清理过时打包脚本与临时文件并精简 README

- 删除已被 `package.ps1` 与 `scripts/packaging/` 取代的旧版打包目录与脚本（`installer/`、`scripts/build_installer_once.ps1`、`scripts/check_*.ps1`、`scripts/prepare_*.ps1`、`release_package/`）以及本地日志/缓存（`flutter_01.log`、`.qoder/`）。
- 在 `.gitignore` 中新增 `/dist/` 忽略规则。
- 重写 `README.md`，精简为面向用户的核心功能与下载说明。

### feat: 实现 Windows 自动升级与应用打包发布流水线

- 新增应用内自动更新模块：`lib/src/application/app_update.dart`（版本比较、AppInstaller 清单安全校验、更新控制器与定时检查）、`lib/src/io/app_update_download.dart`（受信任域名与重定向校验、SHA-256 完整性验证及 256KB 分批落盘）、`lib/src/io/app_update_preferences.dart`（检查间隔持久化）与 `lib/src/platform/windows_app_update.dart`（Windows 宿主与 MSIX/安装版更新交接）。
- 新增 Windows 原生更新通道 `windows/runner/app_update.h` / `app_update.cpp`（`clovecom/app_update` MethodChannel），支持读取 MSIX/非打包应用版本身份及启动静默原位更新（`/S /INPLACE /RESTART /UPDATEPID=`）。
- 新增 `lib/ui/widgets/app_update_dialog.dart` 并在 `lib/main.dart`、`lib/views/home/home_view.dart` 与 `lib/widgets/desktop_title_bar.dart` 中接入自动检查、标题栏一键更新/重启按钮与手动检查更新弹窗。
- 新增 `package.ps1` 与 `scripts/packaging/`（ZIP 免安装、NSIS 单 EXE 便携版、NSIS 安装/原位更新器、MSIX 签名包、AppInstaller 更新清单生成及本仓库 Release / `gh-pages` 清单发布脚本），其中 MSIX 图标直接从 `windows/runner/resources/app_icon.ico` 解析生成。
- 新增 `.github/workflows/release-windows.yml` 自动构建、测试、签名与本仓库 Release 发布工作流（直接使用内建 `GITHUB_TOKEN`）。
- 更新应用图标 `windows/runner/resources/app_icon.ico`（自动裁边居中与透明背景适配，内含 16–256px 多尺寸帧）。
- 在 `test/app_update_test.dart` 新增版本比较、清单校验、配置持久化与本地 HTTP 下载校验测试。

### perf: 优化会话列表点击选中响应延迟与重绘范围

- 在 `lib/widgets/communication_session_list.dart` 中改为通过 `Listener.onPointerDown` 统一处理即时选中与同项双击打开，移除 `InkWell` 的 `onDoubleTap` 与延迟 `onTap` 回调，将列表项 `Material.animationDuration` 设为 `Duration.zero`，彻底消除 300 ms 双击判别延迟、200 ms 背景渐变动效及快速来回点击时的选中回跳问题。
- 在 `lib/widgets/communication_session_workspace.dart` 中将 `_selectedSessionId` 改为 `ValueNotifier<String?>` 并仅局部刷新 `CommunicationSessionList`，避免切换列表选中项时连带重建全部打开的会话工作区。
- 在 `test/communication_session_list_test.dart` 新增单帧选中切换回归测试。

### feat: 将 iTerm2 终端配色提升为全应用主题配色并默认采用 One Half Light

- 参考 `mbadolato/iTerm2-Color-Schemes`，在 `lib/ui/theme/terminal_color_schemes.dart` 维护 21 套内置浅色与深色配色（含完整 16 色 ANSI 调色板、边栏、工具栏、选区及语义色），移除原「默认 (CloveCOM)」方案，并将默认应用主题设为 `One Half Light`。
- 新增 `lib/ui/theme/app_theme_controller.dart`（`AppThemeController` / `AppThemeScope`）并在 `lib/main.dart` 与 `lib/widgets/desktop_title_bar.dart` 接入全应用主题切换与持久化（`app_theme.json`）。
- 升级 `lib/ui/desktop_theme.dart` 的 `buildDesktopTheme` 与 `desktopActionStyle`，按当前主题亮度与前景/背景/主色自动推导表面层级、文字对比度、按钮与输入框边框、高亮主色反白文字（`onPrimary`）、菜单及提示框配色，并通过 `ThemeData` 缓存、`TerminalThemeExtension` 与 `MaterialApp.themeAnimationDuration = Duration.zero` 使全应用与会话终端在单帧内同步切换、消除逐帧插值卡顿。
- 新增 `lib/ui/theme/terminal_text_highlighter.dart`，支持在会话终端中解析 ANSI SGR 转义序列（`\x1B[...m`）并对日志级别标签、数字/十六进制字面量及标题横幅进行终端语义着色。
- 清理 `lib/views/toolbox/`、`lib/views/i2c_tool/`、`lib/ui/widgets/`（`DsInteraction`、`DsInput`、`DsCard`、`DsTag`、`DsToast`、`DsDialog`、`LuaApiPanel` 等）以及 `lib/ui/pages/`（`protocol_editor_page.dart`、`interaction_editor.dart`）中的硬编码浅色/白底色值，统一接入 `ColorScheme`，并调优 `surfaceContainerLowest` / `surfaceContainer` 等表面层级混色比例，确保工具箱、CH34x 调试与协议编辑页与当前主题协调融合。
- 在 `test/ui/theme/terminal_color_schemes_test.dart`、`test/desktop_theme_test.dart` 与 `test/communication_send_view_test.dart` 更新并新增全应用主题、对比度、ANSI/语义着色及界面切换测试。

### fix: 修正实时数据日志未满屏或清空后贴底显示的问题

- 在 `lib/widgets/communication_session_data_view.dart` 中仅当数据行预计或实际超出视口高度时才切换 `_tailLayout`（`anchor: 1`）进行尾部高效跟随；少量日志、清空历史或内容回缩不足一屏时均保持 `anchor: 0` 从视口顶部向下排列。
- 在 `test/communication_send_view_test.dart` 新增回归测试，验证初始少量日志顶部对齐从上往下排列、满屏后自动跟随至底部及清空后恢复顶部对齐。

### perf: 优化不换行长 HEX 历史滚动与双窗格帧耗时

- 在 `lib/widgets/communication_session_horizontal_text.dart` 中引入 `_HexGlyphMetrics` 等宽字形宽度表并推迟 `_RenderHorizontalTextPaint` 子段落完整排版，按当前可视窗口裁剪绘制；进入文本选区或清空选区时经 `_SessionSelectionDelegate` 切换回完整段落排版。
- 将 `_VisibleTextLayouts` 的可视片段与空闲 `TextPainter` 缓存上限提升至 2048，并缓存单行近似尺寸度量。
- 在 `lib/src/application/communication_sessions.dart` 与 `lib/widgets/communication_session_data_view.dart` 中将可见会话发布节拍调整为 `16 ms`、禁用列表代理的 `AutomaticKeepAlive` 与 `IndexedSemantics` 冗余包装、将 `_mountedRows` 改为 `HashMap` 并复用 `_hexPrototype`，使 Windows Impeller 双窗格 `4096 B / 20 ms / 256` 负载组回看与跟随 P95 总帧耗时均降至 `16.67 ms` 以内。

### chore: 清理 ADR-0008 迁移前旧页面与测试残留

- 移除已无页面引用的 5 个 ADR-0008 迁移前旧源码文件（`serial_port_viewmodel.dart`、`firmware_upgrade_view.dart`、`network_config_card.dart`、`communication_management_panel.dart`、`connection_subscriptions.dart`）及 17 个依赖已删除 `PageModuleId`/`PageCommunicationPort`/`ReceiveBudget` 接口的旧测试文件。
- 为 `test/protocols/lua_runtime_isolation_test.dart` 内联本地脚本构造辅助函数，恢复全库静态分析零错误与测试全绿。

## 2026-11-21

### perf: 在后台直接调用 Win32 枚举串口

- 串口扫描在后台 isolate 合并 DOS 设备和 SetupAPI 信息，保留热插拔通知、备用枚举与失败处理。

## 2026-11-20

### chore: 迁移至 Flutter 3.50.1

- 最低 SDK 要求更新为 Flutter 3.50.1 和 Dart 3.14.0，应用及测试迁移至独立的 Material 组件库。
- 桌面预览测试在挂载组件前完成字体加载，避免 Flutter 3.50 的字体变更回调跨越测试结束。

### feat: 整合会话右键操作并添加左侧边距

- 数据区右键菜单集中布局、显示、历史和发送配置。
- 左侧边距支持独立配置空白、行号、折叠标记、收发符号、时间戳和缩放。

### feat: 接口通信支持多会话与拆分布局

- 通过可复用会话模块提供标签分组、嵌套拆分、拖拽尺寸、合并和重启布局恢复。
- 每个会话定向收发并独立显示、缩放、复制和导出数据。临时历史从打开会话时开始，记录原始接收与确认写入的字节。
- 关闭会话停止本会话的循环与协议任务并删除临时历史，保留订阅。

## 2026-11-18

### fix: 完成通信管理双轴审查四项修复

- 管理六处选择框复用共享锚定菜单，保留受控值、校验与协议草稿；统一普通发送和循环的写结果纯分类。
- 默认 TCP 打开持有真实可取消 ConnectionTask，主动断开和期限终止底层尝试并等待回收；旧工厂继续安全等待。dart:io UDP 核验实际接受数量，失败保留已知计数，不透明重发。
- 公开行为红测覆盖菜单几何、默认生产工厂取消和实际 UDP 适配器零接受；最终完整437项绿，全部有效变更 Dart 零问题，全仓26项诊断与原基线逐项一致，重新生成包含修复的 Windows Release 与完整哈希清单。


### fix: 校验切换协议后保留的本地端口草稿（T10 收尾）

- 保存前校验所有网络协议的本地端口，拒绝非活动协议中的越界或非整数草稿，避免切换协议绕过校验或静默改为自动端口；保留原配置不受无效保存影响。
- 扩展真实管理编辑器的公开交互用例，红测复现原值2002被65536覆盖，修复后绿，flush后重建内核仍保留原定义且提示明确对应协议；管理与配置组合23项绿，最终完整434项再次通过，67个变更Dart分析零问题，全仓26项与基线逐项一致，Windows Release重新构建验证最终代码。没有增加私有测试入口或扩大超时。

### feat: 完成通信管理浮窗与最终统一接管验收（T10 / #11）

- 管理浮窗支持标题拖动、右下调整尺寸、主窗口边界夹紧及缩小修正，重复入口聚焦同一实例；标题按钮和后方导航继续可用，收起保留视图草稿但不停止连接、循环或任务。
- 管理编辑器恢复串口/网卡二元接口与网卡协议层级，共用内核本机接口扫描，只读确认本地 IP；保留缺失原接口、虚拟串口输入、各协议完整参数与 UDP 两模式独立目的，非法参数拒绝保存，不改持久化 schema。
- 管理与页面订阅列表直接显示同一权威的本地发送结果、循环轮次/延后、文件及 Lua 任务进度/终态/原因/等待释放；审计生产唯一 runtime、页面旧配置与旧单目标任务桥退出，保留既有业务和兼容测试类。
- 新增5项真实管理与后台 Widget 回归，完整434项全部通过；真实 Lua runner、Dart Ymodem 和模拟对端证明收起/切页/后台状态后继续。修正两处旧 UI 全局文本计数及一处循环测试过早读状态，不扩大超时。
- reviewBase8d33276 全部67个存在的变更Dart路径分析无问题；全仓26项既有诊断与基线逐项一致。Windows Release最终构建成功（仅Temp目录MSB8029警告），全范围diff检查通过；84故事的具体证据、生产接管和硬件限制记录在 docs/development/communication-management-acceptance.md。尚需后续fresh双轴审查，未操作用户真实配置/硬件。

### feat: 稳定页多目标 Lua 固件升级与独立资源释放（T8 / #9）

- 升级按当前发送订阅固定目标，各自运行真实 Lua 进程，通过单目标 ProtocolTaskChannel 写入并保留真实配置、RawPacket 来源及链路轮次；应答、重传、进度、停止与结果互不串线，混合无资格目标逐项未执行。逐目标 UI 显示进度、终态、原因、等待释放与停止操作，VM/视图销毁后稳定任务继续。
- 构造前登记 owner 释放证明，stopped 及时取消本进程，真实进程、订阅和宿主写清理后再汇合 native 屏障；修正旧五秒超时造成永久 owner 失败及清理异常重复抛出导致 released 悬挂。未知写/owner 异常保留独占并进入现有可见退出失败流程，旧回调不污染新任务。
- 协议载入只保存不可变配置建议，连接中允许载入且不暗改任何共享参数；实际修改只经管理入口完全断开后执行。保留固定版本、失败保留、引用保护、固件快照和既有点表/Ymodem能力，移除旧单会话固件分发/写桥。
- 明确每页每批四目标、全应用运行/校验四进程、单固件16 MiB及已有128 MiB进程Lua堆预算；输入字节/包数、IPC、事件暂停和UTF8日志有界，嵌套上下文深隔离，日志复用有界页历史并显示截断。未新增通用Lua、控制线或参数表单能力。
- 新增26项公开领域/真实Lua/Widget回归，完整Flutter回归429项通过；全部12个变更Dart路径静态分析无问题，整票相对9e5f10a的diff --check通过。实际随附runner验证双设备与预置Ymodem，没有操作真实串口或用户配置。测试和红绿证据保留在共享交接目录。


### merge: 同步配置恢复并完成文件任务释放验证（T7）

- 合入当前集成4276f873，保留T9持久化意图、flush、关闭失败重试及T6循环scope；任务状态不进入配置。完全断开判据增加未释放任务owner，owner残留时禁止改删连接。
- 补齐停止信号与owner/native双释放、owner异常可见退出失败、TX转交等待owner、正常raw取消订阅不互等、ready前写立即受权威FIFO预算、独立消费模式及旧回调隔离公开回归。
- 最终完整Flutter回归403项通过（在T9的374项上新增29项）；T7自身11个、包含已合T9的整个起始候选17个Dart路径静态分析无问题。整票相对9f4478f的差异diff --check通过。有效红绿与最终日志保留在共享交接目录，不操作真实硬件。
- 保留原文件选择与保存能力；同名、多轮及临时同名接收不覆盖，协议私有64KiB预算和未知长度中间填充不丢失。path沿用已有锁定版本1.9.1，仅补直接依赖声明。

### feat: 多目标文件协议任务通道与独立 Ymodem 收发（T7 / #8，检查点）

- 内核登记固定目标、epoch、grant、taskId 的协议独占通道，首写前绑定有界原始输入；字节/原始包只选一种消费模式。协议写只进绑定目标 FIFO，任务开始仅停对应循环，其他接收者与目标继续。
- 区分 stopped、native settled、owner 释放与 released；撤销 RX/TX、故障和断开局部取消，未知结束/owner 清理错误保留独占，应用退出先关闭底层再汇合 owner 并报告已知失败。
- 文件选择和收发迁移至稳定页入口，每目标创建独立真实 Ymodem，展示进度/终态/释放状态/原因/输出路径及按目标停止；VM/视图销毁不结束任务。TX 来源日志与实际接受统计保留，未知不虚增。
- Ymodem 接收逐块写文件，不累积整文件；私有输入限额64 KiB。接收原子预留目标/任务目录、分离临时和完成路径，同名、多轮、重启与临时同名不覆盖；失败/取消清本任务临时文件。
- 检查点公开 TDD 已通过任务17项、文件7项与真实 Widget1项；另有协议流式接收与工厂注入回归。最终合并 T9、完整回归和变更静态分析结果在收尾提交记录。未操作真实串口或原工作区。
### merge: 同步循环发送契约并验证持久化恢复收尾（T9）

- 合入当前集成 9f4478f 的 T6 实现，保留逐目标循环、队列 scope、awaitingSettlement 与退出 stopLoop；持久化仅记录定义及最终收发意图，不保存这些运行状态。增加真实活动循环保存、销毁和重建的公开验证，关系恢复且循环与结果为空，连接不打开。
- 最终验证：T9 共新增 17 项领域测试和 1 项窗口退出 Widget；组合定向 30 项通过；已合入 T6 的完整 Flutter 回归 374 项通过。相对本票起始 af3b42f 的全部 12 个变更 Dart 文件静态分析无问题，整个起始基点差异 diff --check 通过。
- 相对当前集成的 T9 专属 Dart 变更为根装配、内核、配置存储/编解码、管理面板及两个测试文件，共 7 路径。未操作用户真实配置或真实设备；旧草稿不自动迁移，配置文件为单应用根唯一写入者，驱动与硬件取消仍由真机联调验证。

### feat: 通信配置与收发关系持久化及完整管理约束（T9 / #10）

- 应用根装配独立版本化配置存储，恢复完整串口和三种网络协议参数、稳定连接与页模块 ID 及 RX/TX 意图；全部连接保持未打开，不保存队列、任务、循环、半包、异常与运行结果，TCP 自动重连参数不变为启动连接。
- 明确配置变更去重、固定期限自动保存、单写入者合并最新快照与同目录安全替换；初始化晚到不覆盖新用户命令，损坏/缺字段/未知页/重复 ID 有可见状态和统一浮层提示，保存失败保留最新意图可重试。旧页面草稿不作为全局配置权威。
- 收紧完全断开判据，覆盖打开、重连、关闭、传输及未知在途写残留；修改保留关系并推进新轮次，删除移除全部关系。发送撤销期间保存最终用户意图，不在重启复活旧持有者。
- 复用既有接口枚举标明恢复后的缺失串口/网卡，保留原目标，失败扫描标未知，实际打开或刷新可恢复。生产根拦截标题栏与原生关闭，刷盘和资源回收成功才退出，失败可重试，重复请求合并。
- 阶段验证：新增 16 项公开内核持久化/管理测试及 1 项真实标题栏退出 Widget 测试；含 Temp 文件重建/替换、慢存储串行、RX 去重、旧半包、迟到载入/扫描、releasing 意图和关闭失败重试。相关领域/Widget 定向 51 项通过，全部 7 个变更 Dart 路径分析无问题。既有后台接收 Widget 暴露跨虚拟时钟重复等待初始化的问题，ready 后直接清理修复并保留该公开回归。

### feat: 多目标独立循环发送（T6 / #7）

- 应用页入口启动时固定 TX 目标、epoch 与 grant，各目标独立调度；一个目标慢写、离线或失败不挡其他目标。每目标至多一轮入队/在途，沿用 T5 有界 FIFO，不累积历史 tick，等待本地结果及 native settled 后再按间隔推进。
- 停止按目标与本次运行 scope 撤销待写，只定向取消该运行在途写，不误删手动发送、不释放 TX、不隐式关闭连接。撤销/断开/更换客户端即停止对应目标，重连和重新订阅不复活；旧结果、取消和结束异常隔离新运行。明确 close 直接推进并提供结束证明，不与停止互等。
- 现有循环开关、周期和发送按钮真实接入，逐目标显示等待/发送中/延后/停止、完成轮次、实际本地接受字节和原因。停止后原生未结束继续显示“在途写结束待确认”，取消异常可见；结果超时与结束异常不再排下一轮。修复开始状态监听者立即停止遗漏取消的竞态。
- 保留原循环草稿的文本/HEX、动态 CR/LF 与空/非法草稿暂停语义；后续轮次使用新快照，在途及已排队字节不变。来源日志/统计复用页面历史和追加预算。循环运行由应用内核持有，页面隐藏或销毁不停止；旧 VM 单目标断开和任务桥不再停止其他目标循环。
- 提供按目标 stopLoop 协调点供 T7 创建协议任务时调用，任务结束不自动恢复循环；长期单目标任务资格与独占 channel 仍由 T7/T8 交付。循环、队列与 scope 均为瞬态，不进入 T9 配置持久化。
- 验证：12 项新增公开领域/VM 测试与 1 项真实 Widget 测试，覆盖慢快目标、停止排队、断开重连、订阅变化、草稿、未知结束、迟到结果/取消、立即停止竞态、小窗口和隐藏视图；完整 Flutter 回归 356 项通过，全部 6 个变更 Dart 路径静态分析无问题。本票未操作真实串口，硬件取消时序留待联调。

### feat: 普通多连接发送与安全有界 FIFO（T5 / #6）

- 页入口普通发送一次固定全部 TX 目标、资格版本、链路轮次及同一字节快照；目标独立入队、写出、返回结果，离线主目标或局部慢写不挡其他连接，后加订阅不加入当前操作。
- 内核统一持有每连接 1 MiB / 128 条 FIFO（含在途与未知写成本），单次最大 1 MiB，排队默认 5 秒超时；实际写结果另有限期。拒绝离线积压、满队列、过期资格与旧轮次，不透明重发短写或未知结果。
- 发送结果与 native settled 分离，逐目标区分成功、失败、未执行、部分已写、接受数量未知，提供本地传输层汇总。撤销清未写队列并调用可选定向取消，保持释放中直到原生结束证明；网络不隐式关闭，settled 异常/提交异常不释放屏障，明确 close 成功可作为独立结束证明。关闭重开后的旧结果与旧取消异常不污染新链路。
- 现有接口通信页文本/HEX/CR/LF 接入真实群发入口，展示逐目标结果与汇总，来源日志和已知实际接受字节统计按目标独立推进，沿用页历史及文件追加预算。保留 VM 布尔返回等待释放的兼容语义；固件页不新增其原本没有的普通发送能力。
- 验证：公开行为 TDD 红绿日志覆盖 FIFO、结果/结束分离、全部 TX 快照、明确关闭、生产 VM 与真实发送按钮；新增 13 项领域测试和 1 项 Widget 测试，默认 128 笔 / 1 MiB 突发与第 129 笔拒绝通过。完整 Flutter 回归 343 项通过，全部 8 个变更 Dart 文件分析无问题；两条旧 busy/close 替身断言按新契约迁移，保留真实 worker 原生结束前不续写验证。
- 公共契约更新预算、结果、取消及兼容边界；本票未操作真实串口，默认容量尚未真机峰值标定。T6 每目标循环、T7 协议任务与 T8 Lua 多目标升级继续按后续票交付。

### chore: 清理 T4 完整候选差异中的尾空白

- 清理 Windows UDP 开发说明第 71/72 行和窄头文件第 7 行的三处行尾空白；不改变文档内容或头文件编译语义。
- 校正前次检查范围：此前仅检查本票主体暂存差异，本次对相对 T3 集成基线的整个 T4 候选运行 diff --check。保留 329 项测试及 24 个变更 Dart 文件分析证据，不重复执行无关验证。

### feat: 独立收发订阅与有界页面后台接收（T4 / #5）

- 应用内核统一维护多接收者与唯一发送订阅，页面列表和管理浮窗直接观察同一份状态，显示持有者、释放中、接收异常与恢复操作；两个业务页移除接口配置与连接控件，保留原收发和升级业务控件。
- 每个页模块×连接懒建真实 isolate，迁移生产 UTF-8 分块解码、HEX、来源日志行与接收统计；按连接、epoch 和 UDP 对端隔离状态，普通坏 UTF-8 计数重同步，不误停关系。原始输入不再被旧单目标任务截走展示。
- 输入、在途、输出、peer 状态、全局 worker、展示历史和串行文件追加均有显式字节/条目预算；超限或处理异常只停止对应关系，保留勾选并标记数据不完整。恢复等待旧 worker 退出，只收新数据；重连不自动清故障。清日志仅推进本页展示水位，不清半字符和物理缓冲。
- 接入 Windows UDP 原生路径，真实保留来源、边界及合法空报文，发送仍使用配置目的地址；修复即时错误码与 Dart 发送测试在途约束，空报之后的数据继续进入同一后台管线。
- 发送撤销先保持释放中并拒绝新持有者，等待 settled 成功或明确关闭成功。修复串口包装层 settled/提交异常的未处理通知和过早取消屏障释放：异常不作为结束证明，未知写占用留待安全关闭。
- 验证：完整 Flutter 回归 329 项通过；相对 T3 集成基线的全部 24 个变更 Dart 文件分析无问题，本票主体暂存差异检查通过；全项目分析保留原有 26 项未改文件告警。Windows UDP 候选已通过 Debug 构建与系统 ws2_32.dll 映射验证，本票接线后通过真实回环。
- 公共契约记录已实现 API、默认预算与观察流边界。T5 继续实现全部发送订阅的目标快照、有界 FIFO 与统一取消，T7/T8 才完整迁移多目标协议/Lua 任务，本票不提前宣称完成。

## 2026-11-17

### feat: 每串口独立 worker 与安全定向取消（T3 / #4）

- 默认工厂等待后台串口就绪；每连接独立 isolate 直接管理 Win32 句柄、读写各自 OVERLAPPED/event/buffer，移除原同步 writer，不再同步 Wait 或等待式 GetOverlappedResult。
- 读、写、取消分别 pending 推进；短写保留实际计数，超时/取消未知数量与 native settled 分离，迟到正常完成不覆盖已返回结果，终结前禁止新写和资源释放。
- 新增可选 CancellableCommunicationTransport.cancelWrite，仅取消调用时的 TX，保留本连接 RX；幂等关闭等待读写分别终结再回收资源，打开失败在 worker 安全回收。
- 单次 TX 限 1 MiB、RX 限 16 KiB，接收单批 credit 确认与控制消息合并覆盖 IPC/Stream 隐式积压；暂停恢复可继续交付，原生接收错误显式报告完整性故障。
- 验证：新增 10 项真实 isolate/应用入口回归，包含同步阻塞、pending RX/取消、短写、超时、迟到完成、关闭与容量；完整 Flutter 测试 294 项通过。未操作真实串口，驱动真机矩阵留待联调。
### feat: 应用级连接所有权与非模态通信管理（T2 / #3）

- 新增 CommunicationRuntime、稳定连接/页模块身份及不可变快照；集中仲裁物理串口，允许不同串口和网络连接并存，参数修改/删除须等待完全关闭。
- 根组件注入同一内核，旧 VM 仅保留页入口和业务状态，不持有原生传输或网络控制器；旧配置入口转发同一管理命令，销毁页面不关闭应用连接。
- 标题栏新增非模态通信管理，可创建/配置串口、TCP 客户端、TCP 服务端及 UDP，打开/断开、删除并绑定现有业务页；收起浮窗、重复打开和切页不改变连接生命周期。
- TCP 首次失败也重连；主动断开撤销重试与在途打开，迟到资源回收失败时保留关闭中与物理占用。修复客户端读侧 EOF 后残留可写状态，服务端继续监听并按客户端变化刷新 epoch。
- 原始输入经内核赋予 connectionId/epoch/sequence；工厂支持真实异步传输注入，写超时与 settled 分离，底层未结束不释放串口。公共契约见 docs/development/communication-runtime-contract.md。
- 验证：完整 Flutter 测试 284 项通过，全部变更 Dart 文件静态分析无问题；覆盖内核、真实 TCP 回环、兼容转发及非模态 Widget。
- 本票仍使用同步 Win32 适配，不宣称完成 T3 后台隔离；独立收发订阅、有界处理及 FIFO 按后续票扩展。

### refactor: 贯通可等待串口写入与关闭契约（T1 / #2）

- 串口传输改为异步写结果与异步关闭；结果保留实际接受字节数（未知为 null）、失败原因及独立底层结束证明 settled，不把超时当作零字节或资源已释放。
- Ymodem 包、控制字节、会话、普通发送与 Lua 宿主发送均等待真实结果；取消中的会话保持占用直到在途写结束，迟到成功不会推进协议或更新发送统计。
- 串口租约仅在底层关闭及在途写结束后释放，保留关闭幂等；现有 UI 和协议规则保持。
- 新增延迟写、取消及迟到完成、延迟关闭公开行为回归；完整 Flutter 测试 273 项通过。本票仍使用原同步 Win32 实现，不宣称完成 worker 隔离。

### chore: 保存接口通信统一与全局通信管理实现基线

- 保留串口与网卡统一接口、网络协议参数与传输实现，移除 USB/网络占位导航并同步状态栏索引。
- 收录全局通信管理设计、领域术语、ADR-0006、规格 #1 和工程技能配置，作为后续分票实现的可追溯基线。
- 本提交保存已有接口统一行为，不宣称已完成全局订阅或后台 I/O 实现。

### fix: Windows UDP 原生适配保留空数据报与来源（T4 子任务）

- 新增独立 WindowsUdpTransport，通过非阻塞 Winsock recvfrom 区分合法空数据报与 WSAEWOULDBLOCK，保留来源地址/端口，chunks 只投影同一同步数据报事实源。
- 支持 IPv4 本地IP绑定、系统分配端口、配置固定目的地址及广播 SO_BROADCAST；发送核对实际接受长度，空 payload 正常发送，内核忙或错误明确失败且不透明重发。每轮限定 64 报或约 256KiB，关闭幂等并回收 socket、native 缓冲与 Winsock 引用。
- 四个 win32 6.4 未导出的 API 使用 ffigen 23 从本机 SDK 真实生成，保留 RecordUse 映射；系统 DLL 资产 hook 仅映射 Windows 自带 ws2_32.dll，无额外运行时依赖或分发 DLL。生成工具来源/哈希、Dart 缺陷与 Microsoft 依据见 docs/development/windows-udp-transport.md。
- TDD 真实 OS 空报→非空报红测先复现 Dart 3.13.4 丢报路径；原生适配后 8 项独立回环测试、现有网络测试共 20 项通过。覆盖非空 Dart 互通、多个来源、130 条空报跨轮询、最大/过大报文、广播、端口释放与暂停消费者；定向静态分析零问题，Windows Debug 构建成功（仅 Temp 工作树 MSB8029 警告）；工厂及通信内核接入由 T4 主任务完成。
### fix: UDP 错误判断沿用 Win32 立即捕获结果（T4 回归修复）

- 真实 Dart 发送端的非空/空/非空回环发现，recvfrom 已捕获 WSAEWOULDBLOCK=10035，后续跨 FFI 查询线程错误却得到 0，误判致命错误并关闭原生流。接收、发送、绑定及关闭的 Win32Result 错误路径统一使用其已捕获 error.code，不再丢弃后重查。
- 新增 Dart 发送端真实回归，按 Windows 异步发送的 writable 事件等待并核验非空报实际接受长度，空报由接收事实验证；确认空报前后均持续接收且无 error/closed。过大数据报同时校验原生错误码 10040。网络目录 21 项通过，适配器与测试定向静态分析零问题；本次未改生成绑定或资产 hook。
## 2026-11-16

### refactor: 系统提示统一走 clovertls 式 DsToast 浮层（修订 C2/ADR-0002）

- 用户真机实测串口后指令："所有的系统提示参考 clovertls 的提示弹窗的实现，而不是将提示夹杂在页内容里。" 调研确认 clovertls 系统提示（错误/警告/成功，含"串口已拔出，升级已中断"）一律经 `showDsToast` 全局浮层：左下角 3 秒倒计时、悬停暂停、单击淡出、同文同语义去重、剥离 `Bad state:`/`FormatException:` 前缀；持久错误可见性由连接态补偿。`InterfaceStatusHost` 是接口占用功能浮窗，非事件提示。
- 移除三处内联系统提示：串口视图 `_buildErrorBanner`、固件视图 `_buildErrorBanner`、固件连接卡内联 `state.error` 红字。每条错误本已经 `errorStream→showDsToast`，移除内联不丢提示；拔出另有端口"未连接"态补偿（clovertls 同款）。
- 统一错误呈现 seam：`connect()` 空端口校验与打开失败改走 `_setError→errorStream→toast`，真正修复串口打开失败静默——ADR-0002 曾声称修复，实际仅固件视图内联渲染 `state.error`，串口端口栏不渲染故静默。`state.error` 保留供连接态语义与测试，连接成功清 `_errorMessage`。
- `ds_toast.show()` 同步 clovertls 归一化＋去重（两边 toast 其余部分本就同源，直接修掉截图里"Bad state: 串口读取失败或设备已移除"的前缀）；`errorMessage` 字段保留为 VM 错误态测试面（11 处升级测试断言），不再内联渲染。
- 保留非事件提示的功能态内容：固件"协议有新版本"上下文 hint（绑定 hasNewVersion）、i2c 日志条目错误（日志记录）、工具箱规划状态面板（功能态）。
- 记录 ADR-0003 取代 ADR-0002 的"内联面板（持久错误）"适配器与 DsDialog 持久错误角色；ADR-0002 标注被取代部分。权衡：toast 3 秒自动消失，持久错误可见性由连接态补偿；若未来需持久错误清单应走功能态浮窗而非页面内联。
- 验证：改动文件 `flutter analyze` 零问题；新增 4 项 toast 归一化/去重测试＋1 项连接失败/空端口 errorStream 提示测试，串口连接 4 测试＋toast 4 测试全绿。协议升级测试的 12 个失败为既有 Lua `RuntimeUnavailable` 环境性失败（发生在 prepare→载入协议→Lua 校验，与本次改动无关），非回归。

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
