# 全局通信管理验收记录

日期：2026-11-18。规格：[应用级通信管理与页面收发订阅](../specs/global-communication-management.md)，父规格 #1，最终接管 T10 / #11。

此记录覆盖 T1–T10 候选代码的 84 条故事。下表给出实际操作及断言结果，不能用测试文件存在代替通过证据。领域测试经过真实 CommunicationRuntime 与稳定 PageCommunicationPort，Widget 测试经过实际生产页或管理入口。串口对端是模拟设备；Lua 是随附的真实 runner/进程；网络包含本机真实 socket。未操作用户串口、用户配置或外接硬件。

## 全部故事的行为证据

| 故事 | 验收行为与实际结果 | 公开证据 |
| --- | --- | --- |
| 1–10 | 标题栏菜单右侧打开唯一管理浮窗；可新增、配置、打开、明确断开。不同串口并行，同串口大小写归一后禁止重复打开，同网卡的不同网络连接独立。标题拖动和右下手柄确实改变几何；大幅拖动、调小及主窗口缩至 1120×640 后均夹在内容边界内，无 overflow。标题按钮仍可点击，后方工具箱仍可导航；重复入口聚焦原实例且几何不变，收起不关闭连接。配置仅在管理窗口：串口/网卡二元选择，网卡另选 TCP 客户端/服务端/UDP，本地 IP 只读；串口扫描、手填虚拟串口和完整线路参数保留。UDP 两模式目的独立，协议切换保留各自参数，缺失原接口不替换，非法参数拒绝保存；切换到另一协议也不能把非法端口写入定义或持久化，flush 后重建仍保留原值。 | [management Widget](../../test/views/communication_management_test.dart) 的“管理浮窗真实拖动…”、“标题栏管理连接…”、“管理入口先选网卡…”、“管理串口扫描选择…”及“管理配置保留…”；[runtime](../../test/src/application/communication_runtime_test.dart) 的“应用内同一物理串口只能打开一个连接…”及真实网络回环；[persistence](../../test/src/application/communication_persistence_test.dart) 的完整多定义恢复。 |
| 11–21 | 两业务页以同源订阅列表替换连接配置。未打开/不可用连接仍显示并可订阅；RX/TX 分别操作，一页多个来源、多页同一 RX；一个连接仅一个 TX 持有者，竞争被拒绝并显示占用页，释放完成后才允许新页申请。管理和页面直接观察同一内核关系，无独立开关副本。 | [subscription Widget](../../test/connection_subscriptions_widget_test.dart) 的“页面与管理入口共用 RX/TX 状态并显示占用者”；[subscriptions](../../test/src/application/communication_subscriptions_test.dart) 的“两个独立接收订阅均获得不可变原始数据…”和“撤销发送订阅等待在途写 settled…”；[upgrade Widget](../../test/firmware_upgrade_view_test.dart) 实际断言无旧 SerialPortInput/打开串口，两个页面均有订阅列表。 |
| 22–30 | 原始包向多个健康关系完整扇出且字节不可变，连接/轮次/时间/顺序来源保留；UTF8 半字符按页×连接隔离。清空一页只清本页展示/统计，已在途展示不回填，另一页及半字符状态不受影响。真实 UDP 保留不同 peer、空数据报和边界；不同 peer 的半字符不串联，发送仍到配置目标。 | [subscriptions](../../test/src/application/communication_subscriptions_test.dart) 的“后台加工按页和连接保存 UTF8 状态…”、“清理水位过滤在途旧展示…”、“真实 UDP 保留不同对端、空数据报与目的地址”；[Windows UDP](../../test/src/io/windows_udp_transport_test.dart) 的真实空→非空回环/固定目的/多来源；[management Widget](../../test/views/communication_management_test.dart) 的两生产页后台日志和清理隔离。 |
| 31–41 | 一次普通发送固定当前全部 TX 和不可变内容，后加目标不加入，撤销清未写。相同连接 FIFO 等真实结束、不交错；不同连接的结果独立推进。字节/条目上限包含在途，满队列/超时/离线逐目标失败且不补发。短写显示已知数量，未知接受不猜零；不透明重发，成功明确为本地接受而非协议完成。生产按钮及文本/HEX/CRLF 使用同一入口。 | [send](../../test/src/application/communication_send_test.dart) 的“一次普通发送固定全部 TX 目标和字节…”、“同连接普通写按 FIFO…”、“默认预算容纳128笔共1MiB…”、“排队超时不写入…”、“短写与未知结果逐目标可见…”；[send Widget](../../test/communication_send_view_test.dart) 实际按钮向两个在线目标发送、离线目标未执行、短写原因可见。 |
| 42–44 | 每个循环目标独立等待自己的结果和结束证明再调度；慢目标延后，不补历史 tick，不无限重叠，快目标继续。启动固定目标，新增下次加入；一个目标断开再连不会复活它，也不停止其他目标。显示轮数、延后、停止原因及在途结束待确认。 | [loop](../../test/src/application/communication_loop_test.dart) 的“慢目标等待原生结束时快目标独立循环…”、“启动固定目标…”、“某目标断开并重连不复活…”；[send Widget](../../test/communication_send_view_test.dart) 的真实循环控件与逐目标延后/停止。 |
| 45–51 | 文件/升级启动固定全部 TX，各串口独立真实 Ymodem/Lua、输入、进度、结果及输出。健康 RX+TX、可写、支持串口才执行，混合不合格目标逐项未执行。A 的 ACK/NAK 仅推进 A，B 保持自己的握手/重传；其他 RX 仍观察原始流量。任务只清私有逻辑缓冲，不调用共享物理 purge。接收文件逐块写盘，同名/多轮/已有输出不覆盖。 | [file](../../test/src/application/communication_file_transfer_test.dart) 的“真实 Ymodem 双目标独立握手与完成，混合资格报告未执行，旁观流完整”、“真实Ymodem接收同名文件…”；[firmware](../../test/src/application/communication_firmware_upgrade_test.dart) 的“两台真实预置Ymodem的握手、NAK重传和完成完全独立”、“生产升级入口固定全部目标，真实Lua首ACK只推进对应设备”；[task](../../test/src/application/communication_task_test.dart) 的同步首应答/旁观页和单消费模式；[Ymodem](../../test/protocols/ymodem_protocol_test.dart) 的流式、CRC 重传去重。 |
| 52–59 | 任务只停对应连接循环并拒绝其他普通写，结束不恢复循环。TX 撤销及时停止任务/清未写，但 owner 与 native 两份结束证明成功前保持独占与释放中；RX 撤销/处理故障、断开只终止对应目标。主动关闭能先推进底层关闭，不与任务 owner 清理互等；重开不续跑，旧任务/旧写/旧轮次回调不污染新工作。 | [task](../../test/src/application/communication_task_test.dart) 的“任务只停止合格目标循环…”、“撤销TX后资格保持释放中直到owner清理完成…”、“取消立即通知owner但独占保持到owner与native同时释放…”及四种局部撤销；[firmware](../../test/src/application/communication_firmware_upgrade_test.dart) 的“旧Lua写完成晚到不能污染新任务…”、“未知native写立即报告真实原因…”及 owner 清理失败；[send](../../test/src/application/communication_send_test.dart) 的关闭后旧结果/settled 异常隔离。 |
| 60–67 | 输入、后台 worker、UDP peer、输出、展示、文件追加、任务输入、Lua 输入/IPC/日志/进程均有实际预算。过载/异常仅停止对应关系，保留 RX 勾选及数据不完整；重连不清故障，手动恢复只从新数据解析。非法 UTF8 计数并重同步，合法 U+FFFD 不误计；CRC 坏包走协议重传。真实 worker/isolate 的同步慢处理不阻塞其他页/连接；同串口 pending 写时 RX 和定向取消仍能推进。 | [subscriptions](../../test/src/application/communication_subscriptions_test.dart) 的“慢同步处理在实际后台管线执行…”、“处理期限终止真正卡住的 worker…”、“输入超限只故障对应关系…”、“普通非法 UTF8 计数并重同步…”、“默认预算下有界突发向两页完整交付…”和慢盘预算；[serial worker](../../test/src/application/serial_worker_runtime_test.dart) 的真实 isolate 同步阻塞、pending 写期间 RX/cancel；[Lua isolation](../../test/protocols/lua_runtime_isolation_test.dart) 的真实输入/日志/事件/进程预算；[Ymodem](../../test/protocols/ymodem_protocol_test.dart) 的 64KiB 私有输入及 CRC。预算数值见运行契约，不声称真机峰值定标。 |
| 68 | 真实 Home 中收起管理、切到工具箱、进入 inactive→hidden 后：网络目标循环轮数继续增加；Dart Ymodem 与真实 Lua 升级保持运行并在独立对端应答后完成。恢复后重开管理及升级页显示相同成功结果。另有两生产页隐藏接收/统计继续及 VM/Widget 卸载继续任务证据。 | 新增 [activity Widget](../../test/views/communication_management_activity_test.dart) 的“管理与页面同源展示发送循环及真实协议任务，收起切页和后台状态后继续”；[management Widget](../../test/views/communication_management_test.dart) 的真实两页日志；[file Widget](../../test/communication_file_transfer_view_test.dart) 与 [firmware Widget](../../test/communication_firmware_upgrade_view_test.dart) 的卸载后继续。hidden 是 Flutter 应用生命周期仿真，未手工最小化真实桌面窗口后接硬件测量。 |
| 69–71 | 重建整个内核恢复完整连接配置、稳定页身份和最终 RX/TX 意图，所有连接 closed；不恢复循环/任务/结果/旧队列/半包/故障/轮次，autoReconnect 仅参数不触发打开。释放中的旧 TX 已撤销，不在重启复活。配置写入串行、去重、固定期限保存最新意图，损坏文件保留原因。 | [persistence](../../test/src/application/communication_persistence_test.dart) 的“重建整个内核恢复完整配置与稳定页收发关系且全部未打开”、“循环正在运行时保存销毁重建仅恢复关系…”、“撤销尚在释放中的发送订阅保存最终意图…”、“慢存储期间合并最新配置…”；[root](../../test/communication_persistence_root_test.dart) 实际标题栏关闭等待保存、失败保留窗口、重试仅 destroy 一次。 |
| 72–76 | TCP 客户端首次失败可重试，主动断开停止重试和未完成打开；迟到资源回收。串口无自动重连分支，需明确打开。真实 TCP 服务端区分监听/可写，保持单客户端，断开继续监听，换客户端推进 epoch。 | [runtime](../../test/src/application/communication_runtime_test.dart) 的“TCP 客户端首次失败继续重试…”、“主动断开未完成的打开…”、“真实网络工厂在公开状态报告系统分配端口，客户端断开后继续监听”、“页入口观察服务端监听和可写状态，换客户端刷新数据轮次”；`ConnectionDefinition.autoReconnect` 源码限定 TCP 客户端，串口工厂失败/手动重开由 [serial worker](../../test/src/application/serial_worker_runtime_test.dart) 验证。 |
| 77–81 | 完全断开不仅看 phase，还检查打开/重连/关闭、传输、未知写、释放中及任务 owner 残留；未完成禁止改删。改参保留关系并推进轮次，重开不拼旧半字符；删除移除全部订阅/绑定，复用 ID 不复活。设备缺失/枚举失败不换首项；迟到扫描不否决已成功打开链路。 | [persistence](../../test/src/application/communication_persistence_test.dart) 的“关闭状态先发布但关闭命令尚未完成时仍禁止改删参数”、“断开修改保留收发关系与新轮次…”、“恢复缺失接口时标明不可用但不替换目标…”、“迟到接口扫描不能否决实际打开成功…”；[management Widget](../../test/views/communication_management_test.dart) 的缺失串口/网卡编辑保留；[runtime](../../test/src/application/communication_runtime_test.dart) 的 TCP 换客户端 epoch；[subscriptions](../../test/src/application/communication_subscriptions_test.dart) 的重连半字符隔离。 |
| 82–84 | 系统错误仍走 DsToast，连接/订阅功能状态持续显示故障、占用、释放中及数据不完整；管理和页列表同源显示本地结果、循环轮次和任务进度/终态/原因/释放失败。Lua 宿主只写绑定任务通道，不展开群发，资格撤销和取消与内置协议一致。文本/HEX/CRLF、两页日志清理统计、文件选择/收发保存、协议载入/卸载/版本提示、固件输入和升级保持。 | [subscription Widget](../../test/connection_subscriptions_widget_test.dart) 的故障保留/恢复；[activity Widget](../../test/views/communication_management_activity_test.dart) 实际对照两处摘要；[management Widget](../../test/views/communication_management_test.dart) 的非法端口 DsToast；[send](../../test/src/application/communication_send_test.dart) 与 [loop](../../test/src/application/communication_loop_test.dart) 的生产 VM 编码；[file](../../test/src/application/communication_file_transfer_test.dart) 的真实 VM 文件选择/日志统计；[protocol view](../../test/firmware_protocol_view_test.dart)、[protocol library](../../test/protocols/protocol_library_test.dart)、[Lua upgrade](../../test/protocols/firmware_lua_upgrade_test.dart)。日志保存选择/路径及二进制编辑导出按下述生产代码审计，并由全量既有工具箱回归覆盖其已有部分。 |

## 生产接管核对

- `main.dart` 只创建一个生产 CommunicationRuntime，显式注入配置存储和既有接口扫描，经根 Provider 传给 Home 下两个业务页；纯测试 MyApp/VM 可独立创建无持久化内核，不能据此推断生产有双所有权。
- `SerialPortView` / `FirmwareUpgradeView` 均显示 `PageConnectionSubscriptions`。生产视图没有实例化 InterfaceInput、SerialPortInput、NetworkConfigCard，也不调用旧 VM connect/disconnect；CH341 的 I²C 连接仍属规格范围外。
- 物理串口由统一工厂/serial worker 持有。旧 SerialConnectionOwner、SerialTransferSession 等兼容测试类没有生产调用者；保留其既有独立测试，没有为删除类而删除。
- 普通发送与循环分别走 `page.send` / `page.startLoop`。文件任务只经 `page.fileTransfers`，Lua 升级只经 `page.firmwareUpgrades`，后续写只走绑定目标的 `ProtocolTaskChannel.write`。兼容 `bindConnection/connectionId/write` 和 VM 的草稿 connect 方法不驱动生产配置或文件/升级任务。
- VM/Widget dispose 仅移除观察者；外部注入的内核不随页销毁。Home IndexedStack 与稳定页入口共同保证后台工作，浮窗 Visibility 只保留视图状态。仅明确窗口退出才 flush 并释放拥有的根内核。
- 代码核对保留 `SerialPortView` 的文本/HEX、回车换行、日志、清理、统计、文件选择/保存路径/默认目录/协议选择；`SerialPortViewModel._initLogFile` 与 `communicationPort.appendLog` 保留日志文件保存；升级页保留固件选择及协议版本功能。二进制编辑导出仍在工具箱域，本票未改协议产品或工具箱导出实现。

## 最终验证

- `flutter test --no-pub --reporter expanded`：**434 项全部通过**，429 项集成基线＋T10 新增 5 项管理/后台 Widget。日志：共享实施目录 `t10-full-tests.log`。领域替身控制底层慢写/失败，原生隔离另有真实 worker，Lua 使用真实进程；没有私有队列/Timer 或内部类数量断言。
- 相对 reviewBase `8d33276c6411bc9b1e2af631754693a09adf4195` 全部 **67 个存在的变更 Dart 路径**（含 T10 新文件）定向分析：**No issues found**。路径清单 `t10-all-changed-dart-paths.txt`，日志 `t10-all-changed-analyze.log`。
- `flutter analyze --no-pub`：**26 项既有范围外诊断**，与 `baseline-analysis.log` 的每项完整诊断文本逐项一致，无新增；比较记录 `t10-analysis-baseline-diff.log`，全量输出 `t10-full-analyze.log`。全仓并非零诊断。
- `flutter build windows --release --no-pub`：**成功**，首次完整构建 82 秒，端口校验收尾后增量构建 39.1 秒，产物 `build/windows/x64/runner/Release/clovecom.exe`，含最终 Dart/native hook/Lua runner；只有工作树位于 Temp 的 MSB8029 增量构建警告。日志 `t10-windows-release-build.log`。未启动 Release 应用读取真实用户配置。
- 全范围 `git diff --check` 包含 reviewBase→最终候选所有变更与新文件；最终提交交接记录给出执行结果。结束前已同步集成 `db532345593cb9dc5be87461afd744a6ff5b046e`，返回 Already up to date。

首次全量曾出现新增摘要导致两处旧 Widget 全局文本计数重复，以及一处循环测试在传输提交后、结果未结算时过早取状态。已限定既有结果区断言，并等待公开 completedRounds/awaitingSettlement 结算；定向 14 项及上述完整 434 项通过。工具/fixture 编译错误、协议模拟对端错误和不合法生命周期跳转不算有效红测；实际功能红绿为浮窗几何、二元接口/只读 IP、协议参数保留、非活动协议端口校验及管理任务摘要，见共享 `t10-red-*` / `t10-green-*`。

## 验收边界

软件行为证据已覆盖 84 故事；真实串口驱动慢写、拔出、取消时序、真实多设备升级和峰值吞吐仍需硬件联调。默认预算经过公开容量/压力行为测试，不代表硬件标定。文件系统安全替换未做断电/损坏测试，不提供多进程并写合并。主窗口内浮窗没有新建 OS 窗口，也不持久化几何。最终 Standards / Spec 双轴 fresh 审查和发现修复由后续审查阶段完成，本记录不代替该阶段结论。

## Fresh 审查修复验收（2026-11-18）

审查基点 8d33276，候选集成 71d4572；Standards 与 Spec 分轴追踪，本节仅记录修复实施证据，独立复核由后续审查者执行。

| 审查轴 / 发现 | 修复 | 公开行为证据 |
| --- | --- | --- |
| Standards S1 / P2：六个新增下拉覆盖控件 | 复用 AppDropdownFormField 共享底部锚定菜单，受控选择更新 | 管理串口交互基线红测：菜单文字 top=145，小于锚点 bottom=217；修复后向下展开、缩小并拖至底部向上翻转、安全边距与流控保存通过。缺失串口/网卡原目标、文本校验、网络协议草稿和 UDP 两模式目的保存继续通过 |
| Standards S2 / P3：写结果分类重复 | communication_send.dart 提取 classifySendResult，普通发送与循环共享 | 既有公开发送与循环行为回归及 UDP 零接受组合 26 项通过；调度、日志和 settled 仍各自持有，没有新增镜像 helper 测试 |
| Spec R1 / P2：TCP 未完成尝试未真正取消 | 默认工厂贯通 Socket.startConnect 与 ConnectionTask.cancel，期限同样取消真实任务 | 新公开 runtime 测试从默认生产工厂进入，控制 SDK IO 边界，红测 cancel=0；修复后 cancel=1，250ms 内关闭，之后真实本地回环新连接打开成功。旧 factory 的迟到回收与全量生命周期回归保留 |
| Spec R2 / P2：dart:io UDP 丢弃 send 数量 | 实际 UdpTransport 核验系统 send 返回值，包装层保留明确数量 | 控制 RawDatagramSocket 系统边界而保留真实适配器逻辑，红测为 succeeded；修复后 0 失败、1/3 部分、3/3 完整、合法空报文成功；零接受循环停止、TX=0、仅两次显式发送，无透明重发 |

最终代码一次全量 **437 项通过**；reviewBase 8d 范围所有有效变更 Dart 分析零问题；全仓 **26 项既有诊断逐项位置与规则相同**；合并最新 integration 返回 Already up to date。完整范围 diff --check 通过。Windows Release 构建与完整文件 SHA-256 清单见共享实施目录 fix-windows-release-build.log / fix-release-bundle-manifest.json；修复版完整目录位于 review-fixes/build/windows/x64/runner/Release，不能以旧 T10 构建替代。

未访问真实设备、外网或用户真实配置；硬件慢写、拔出及实际多设备峰值吞吐仍沿用此前联调边界。
