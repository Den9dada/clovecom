# 应用通信内核已实现契约（T1–T10）

公共入口为 `lib/src/application/communication_runtime.dart`；传输边界为 `communication_transport.dart`。本文件记录最终接管后的公共契约；全故事证据见 [验收记录](communication-management-acceptance.md)。

- `CommunicationRuntime(transportFactory:, retryBase:, receiveBudget:, sendBudget:, receiveProcessorFactory:, logAppend:)` 是配置、连接所有权、订阅和接收处理的唯一权威，应用根 `await dispose()`；隐藏或销毁视图不会释放注入的应用内核。
- `ConnectionDefinition.serial(ConnectionConfig)` 和 `.network(...)` 明确接口协议。`addConnection` / `updateConnection` / `removeConnection` 管配置；修改和删除要求已完全关闭。`openConnection` / `closeConnection` 管生命周期；迟到打开回收，关闭失败保留占用。删除同时移除全部收发关系。
- `snapshot.connections`、`connection(id)` 为不可变连接快照，包含 definition/id/name、phase、epoch、writable、peer/detail。串口物理名忽略大小写仲裁；TCP 服务端换客户端更新 epoch；网络自动重连由 runtime 持有，主动关闭撤销重试和打开代际。

串口默认工厂异步等待独立 isolate worker 完成 Win32 打开，读/写/取消非阻塞推进，句柄和原生内存由 worker 持有；可选的 CancellableCommunicationTransport.cancelWrite() 只取消调用时的写并等待原生 settled，不清 RX、不取消后来写。发送释放统一调用可选取消能力，并继续等待独立结束证明。详见 [串口 worker 契约](serial-async-write-contract.md)。Windows UDP 使用 [原生适配](windows-udp-transport.md) 绕过 Dart SDK 空报文缺陷。

## 收发订阅与安全释放

`pagePort(PageModuleId.interfaceCommunication / firmwareUpgrade)` 返回稳定页模块入口。页面列表与管理面板均直接观察此入口及 runtime，不维护另一套开关状态。未打开连接仍能配置订阅。

- `setReceiveSubscription(id, enabled)` 独立管理接收，同连接可有多个接收者，同页可接收多个连接。
- `requestSendSubscription(id)` 同步原子裁决唯一发送持有者，返回 accepted/holder/reason；同页可取得多个连接的发送订阅，不自动抢占。
- `subscription(id)` 返回 receive/send/holder/releasing/fault/healthy 只读状态。接收故障保留勾选关系，取消勾选移除该接收关系；TX 与 RX 不相互暗改。
- `writeTo(id, bytes)` 验证发送资格及释放状态；进入与普通发送相同的逐连接有界 FIFO，一连接至多一笔在途写；该入口只写指定目标，保持任务通道的单目标约束。普通成功仅为本地传输接受，不表示协议成功。
- `releaseSendSubscription(id)` 先标记释放中、拒绝新写和新持有者，清除该资格未写队列、调用传输的可选定向取消，再等待已有写的结束证明后交接。网络无取消能力时仅等待，不隐式关闭。循环与正式协议任务均按目标及运行身份停止，释放还须汇合任务 owner 证明。
- **`settled` 异常不是结束证明。** 内核保留无法确认的写占用及释放中；串口包装层也接住异常通知，保留取消回退屏障；提交直接抛错、未取得结果时同样不伪造结束。只有 `settled` 成功，或显式 `transport.close()` 成功证明原生资源回收后，才解除占用。超时结果、异常和计时器停止都不能转交发送资格。
- `bindConnection` / `connectionId` / `write` 仅为旧单目标业务入口的兼容桥；bind 会明确申请该目标 RX/TX，受唯一资格约束。生产订阅 UI 已退出此命令。普通发送使用 send，循环使用 startLoop；文件收发与 Lua 升级分别使用稳定页的 fileTransfers / firmwareUpgrades，后续写仅进入绑定目标的正式任务通道。

## 原始事实与后台处理

adapter → runtime ingress 只生成一次不可变 `RawPacket`，带 connectionId/epoch/sequence/receivedAt/peer/datagram。内容完整扇出给各健康关系及原始观察者；活动任务不再截走普通日志展示。UDP 保留来源地址/端口、数据报边界和合法空报文，发送仍采用配置目的地址。

每个健康的 page×connection 在首包时懒建一个真实长寿命 isolate。生产 UTF-8 分块解码、HEX、带来源日志行和接收统计增量均在该管线生成，两个现有页面的 VM 直接消费页入口历史/统计，不再同步解码原始输入。每关系各有解析状态，UDP 再以来源 host:port 分开；epoch 变化清除旧解析状态，主 isolate 也拒绝旧轮次结果。

`receiveProcessorFactory` 仅为内建处理器的装配接合点；`PageReceiveProcessor(beforeProcess:)` 可在真实 worker 内加入同步负载/异常以验证隔离，不能替换生产加工算法。它不是通用解析插件框架。

普通非法 UTF-8 由实际分块解码器计入 `badSequences`、输出替换字符后重同步，不误停订阅；合法 U+FFFD 不算坏数据。既有业务协议坏校验继续由其协议处理，本票没有虚构通用帧协议。

`packets` 是原始观察流，无法替调用方隔离其任意同步阻塞。生产后台展示不依赖它。为防 `StreamSubscription.pause` 暗中积压，暂停会结束该观察流；恢复监听需重新订阅，只观察新数据。内核不暂停物理接收来替某页缓存。慢处理验收实际进入上述 isolate 管线。

## 资源预算、清理和故障

`ReceiveBudget` 集中设置以下默认值（空包也占一条及 128 字节固定开销）：

| 资源 | 默认上限 |
| --- | --- |
| 每关系输入（待处理＋在途） | 64 KiB / 128 包 |
| 单原始包 | 16 KiB |
| 单次加工输出（含两种日志行） | 512 KiB |
| 每关系 UDP peer 状态 | 32 个，每个至多 3 字节 UTF-8 残留 |
| 全应用输入 / worker | 2 MiB / 32 个 |
| 每页展示历史（RX/TX/协议日志全部） | 1 MiB / 5000 条 |
| 每页文件追加（含在写条目） | 256 KiB / 128 条 |
| 每次实际加工期限 | 5 秒 |

主 isolate 的显式队列包含一个在途请求的 credit，结果通过历史/日志 admission 后才归还；每个 worker 邮箱最多一个输入，结果端口最多一个有界输出，不把无限队列藏进 ReceivePort。文件追加显式串行、有条数和字节上限，RX 追加完成前保留关系 credit；`logAppend` 是文件系统边界接合点。

输入、输出、peer、总预算超限、处理超时、worker 运行异常或意外退出只停止对应关系，标明接收异常和数据不完整，清掉它的积压并使旧 generation 失效。其他页/连接继续；依赖该关系的正式双向任务按连接停止。重连不会清故障。`recoverReceive(id)` 等旧 worker 退出后清故障，新建空状态且只收恢复后的新数据，不重放旧包。

`history` 只读，超出历史预算剪掉旧展示并设置 `historyTruncated`，页面显示截断标记；不把展示截断当作物理数据完整交付的证明。`clearHistory` / VM `clearMessages` 只推进本页展示水位、清统计，不清物理缓冲、不重置半字符状态、不影响其他页；水位以前的在途展示不会回填。

默认预算验证包含两页各 64 包、每包 128 字节的有界突发（8192 字节/页），小预算故障、真实同步忙等隔离、异常退出恢复、慢文件追加，以及两生产日志区桥接测试。容量是保守初值，不代表已完成硬件峰值吞吐标定。串口底层隔离与取消的已实现状态另见 `serial-async-write-contract.md`；普通多目标发送、独立循环和多目标任务见下节。

## 普通多连接发送（T5）

`PageCommunicationPort.send(bytes, timeoutMs: 5000)` 返回 `SendOperation`。调用时一次固定全部有效 TX 订阅的连接身份、名称、epoch、grant 和不可变字节；之后新增订阅不加入此次操作。每目标入队及实际写前都检查资格版本、轮次和可写状态，撤销或换链路的旧请求不进入新资格。

- `operation.targets` 是不可修改的目标快照，各 `target.result` 独立完成；慢目标不挡其他目标入队、写出或返回结果。`operation.completed` 返回不可修改的逐目标结果列表，`operation.summary` 提供汇总。
- `page.sendResults` / `sendSummary` 仅保存最近一次普通发送的展示状态并随每目标结果更新；旧操作的迟到结果仍交还自己的调用者，但不覆盖新操作展示。
- `SendOutcome` 为 pending、succeeded、failed、notExecuted、partial、unknown；结果带 connectionId/name/epoch、请求与实际接受字节数、原因和 `completionLayer == localTransport`。succeeded 必须明确接受完整长度；部分数量不被猜为零，未知为 null，不自动重发整条命令。
- `result.settled` 是独立的内核释放屏障。结果超时可以先返回，排队成本和发送资格仍保留至传输 settled 成功或明确 close 成功。settled 异常及提交抛错保持 unknownWrites/故障；关闭失败仍不交接。旧 close 证明后的迟到结果、settled 异常、取消回调不得污染重开的链路。
- 同一连接 FIFO 串行，不同连接独立。离线或服务端尚不可写时直接 notExecuted，不保存到重连后。撤销、断开、服务端换 peer 会立即清未写队列；已提交驱动的数据不声称能撤回。

`SendBudget` 在 runtime 构造时集中配置：每连接 **1 MiB / 128 条**（包含待写及在途/未知写）、单次写最大 **1 MiB**，排队等待期限 **5 秒**。写结果期限从实际提交时单独计算，默认也是 5 秒；期限不替代 native settled，也不释放预算。条目限制覆盖空内容，字节限制在复制入队前检查；适配器自身不再排第二层发送队列。默认容量通过公开入口的字节/条目满队列与恢复、慢写、超时测试验证，尚未作真机峰值标定。

现有接口通信页文本/HEX/CR/LF 经相同 `send` 入口，页面展示逐目标结果与汇总，即使兼容主目标离线，其他在线目标仍执行。日志与统计按目标独立推进并保留 connectionId/epoch，已知部分接受仅计实际字节，未知不虚增。TX 展示/文件日志仍沿用页面的有界历史和追加预算。

旧 VM `sendData` 的 `Future<bool>` 为兼容旧业务保留等待各目标释放证明的返回语义；结果区与 `target.result` 会先独立更新，不需等待该布尔值。未结束的目标不阻断其他目标的日志与统计。固件升级页原本没有普通发送控件，本次不新增该产品能力；共享页入口/VM 受相同发送约束。每目标独立循环、文件任务与多目标 Lua 升级见下节。
## 多目标循环发送（T6）

`page.startLoop(bytes, interval:, timeoutMs: 5000, immediate: true)` 固定启动时全部有效 TX 的连接身份、名称、epoch 和 grant。`immediate: false` 用于旧开关先等待一个周期的行为；点击发送则立即开始首轮。之后新增订阅只在下次明确启动加入；撤销再订阅、断开重连、更换 TCP 服务端客户端均不复活旧目标。循环由应用内核页入口持有，销毁视图不停止。

- 每个目标独立调度，至多一轮入队或在途；不调用 VM 聚合 `Future<bool>` 作为下一轮的全局屏障。共用 T5 有界 FIFO，不另建字节队列。排队中或上一轮超过期望周期显示延后，不生成历史 tick；周期按单调时钟安排。每轮收到本地结果且 `settled` 成功后，选择下一个尚未错过的节拍。写入耗时计入周期，错过的节拍直接跳过。慢目标不阻止其他目标推进。
- 结果超时、`settled` 异常都不能再排下一轮；`awaitingSettlement` 持续为 true，直至独立结束证明。已确认的短写、失败、未执行在本轮结束后停止该目标，原因可见，不透明重试。明确断开直接推进 transport.close，不先等待循环的原生结束而互等。
- `loopTargets` 是只读逐目标快照，含 phase（waiting/running/delayed/stopped）、completedRounds、lastResult、reason、awaitingSettlement。停止只表示后续调度和未写请求已撤销；native 已接收的数据不能承诺撤回。页面停止后仍明确显示“在途写结束待确认”，取消失败保留在该运行原因中。
- `stopLoop(connectionId:, reason:)` 同步取消指定目标；不传目标则停止全部本次循环。未写请求按内部运行 scope 移除，不清其他手动发送，也不释放 TX/隐式关闭连接。可选定向取消只作用于该运行已有在途写，内核继续持有 settled 安全屏障。旧运行的迟到结果、取消和结束异常不改变新运行状态。
- `updateLoopData(bytes)` 保留原 `setLoopSendData` 草稿能力：下次轮次取新的不可变快照，已排队及在途内容不变；空或非法草稿暂停实际写出，恢复有效草稿后继续本次固定目标。VM 文本/HEX 与动态 CR/LF 复用普通发送编码，周期修改在下次启动生效。已知实际接受字节进入有界来源日志和循环统计；未知字节不虚增。
- 现有循环开关、间隔和发送按钮已真实接入。VM `sendDataWithLoopCheck` 在循环模式下返回“至少一个目标已启动调度”，不是所有目标协议成功；实际本地进度及异常看 `loopTargets`，非循环模式仍保留普通发送返回语义。循环、运行 scope、计时和队列都是瞬态，不进入配置持久化。

正式文件与 Lua 任务通道在登记独占后按目标调用 stopLoop，见下节；任务结束不会自动恢复循环。测试不操作真实串口，坏驱动取消及硬件时序仍需真机联调。

## 绑定目标的协议任务与文件收发（T7）

`page.beginProtocolTasks(kind: ProtocolTaskKind.fileSend/fileReceive/firmware)` 同步固定调用时的全部有效 TX 目标。返回不可变 `ProtocolTaskStart` 列表，每项含启动时 `connection` 快照及 `channel`，或 `channel == null` 与未执行 `reason`。仅已打开可写串口、健康 RX 和有效 TX 能取得通道；网络、离线、缺失或故障 RX、已有任务/释放中均逐目标说明原因。通知监听者重入撤销订阅也不遗漏原目标；启动后新增目标不加入。

- `ProtocolTaskChannel` 固定 `pageId/taskId/connection/epoch/grant/kind`，由内核唯一登记独占和原始输入。取得通道时停止该目标循环，清旧未写工作；其他目标循环和所有原始接收观察者继续。普通 `send/writeTo`、其他任务不能写入独占目标；任务只调用自己的 `channel.write`，不二次展开页群发。结束不自动恢复循环。
- `ready` 表示之前已提交的 native 写入已确认结束；输入在取得通道时就已登记，首写受先前native屏障约束也不丢同步首 ACK。`write(bytes, timeoutMs:)` 复制调用时内容，重新核验身份后只进入对应连接的权威 FIFO，返回 `SerialWriteResult`。ready尚未完成时也立即进入权威FIFO计费，不在通道另积一层待写字节。结果可以先到达；`result.settled` 仍是独立 native 结束证明。短写/未知原因及时进入文件目标状态；未知不虚增来源 TX 日志或实际接受字节统计。
- `readByte/readData` 是一套单消费者字节读取；`readData` 每次至多 16 KiB。`rawPackets` 是保留真实来源、时间、epoch、sequence 的另一种单订阅消费模式；同一任务一旦选定模式就不能混读或并发读取，raw 消费不另积一份私有字节队列。尚未消费的输入集中受 `TaskInputBudget` 默认 **64 KiB / 128 包**约束，空包也计条目，部分读取的整包仍计内存成本；raw 已挂消费者时单包仍需符合字节预算。超限只取消该任务且显示数据不完整，不暂停/清空其他接收者，不物理 purge。raw 暂停会停止任务，避免 Stream 隐式积压。
- `cancel([reason])` 与 `finish()` 立即禁止新写、唤醒读取、清该任务 scope 未写、启动针对该 scope 在途写的可选取消，并完成 `stopped`。两者返回 `released`；**stopped 不等于 released**。撤销 TX、取消 RX、RX 故障、断开、轮次变化均走此路径，旧回调和重复 cancel 不改新任务。
- 启动外部协议/进程前，在 channel 仍 active 时同步调用一次 `holdUntil(ownerReleased)`，登记真实 owner 清理证明。推荐先建 Completer，登记其 Future，再创建运行；监听 `channel.stopped` 立即取消 owner，owner 完成进程/协议/订阅清理后完成证明并调用 finish。owner 不能先等待 channel.cancel/released 再取消自己。已登记 owner 时 raw 正常 unsubscribe 仅结束消费，不制造“用户停止”，也不等待 released；其他输入仍有界，owner 必须显式 finish。
- `released` 仅在 ready、scope native 结束、owner 成功清理三者汇合后完成，才清内核任务独占；TX 撤销也等这份证明再允许其他页取得发送资格。owner 证明异常记录持续原因并通过 `releaseFailure` 以值通知，不把 released 改为成功、不清任务独占；未知 native 结束同样不能提前解除。没有强制确认或恢复旧任务的入口。
- `closeConnection` 先启动任务取消，直接推进 transport.close 取得 native 结束证明，不先等 owner/released 造成互等。应用 dispose 在实际 close 后再汇合任务；已知 owner 释放失败明确抛错给现有退出错误流程，尚未结束且无失败才继续等待。任务状态与输入/输出路径/进度不持久化。此通道没有新增 Lua 产品入口或控制线 API；T8 复用它迁移每目标 LuaRun。

`page.fileTransfers.startSend(load:, fileName:, packetSize:, intervalMs:, protocolFactory:)` 先登记所有合格任务，再异步读取一次文件并固定不可变内容。`startReceive(savePath:, defaultDirectory:, protocolFactory:)` 按目标分别运行真实协议。默认工厂每次产生新的 YmodemProtocol；注入工厂也必须每目标产生新实例，协议缓冲与回调不可共享。`targets` 是逐目标只读进度、结果、原因、释放状态与最终输出路径；`cancel(connectionId:, kind:)` 可停止指定目标或指定方向。本页文件任务由稳定页入口持有，VM/Widget 销毁和后台运行不终止。

接收使用文件系统原子预留的“目标 ID + taskId + 随机后缀”目录，临时文件和 completed 最终目录分离；不同连接同名、同目标多轮/重启和发送端临时同名都不覆盖。单目标手选路径在未存在时保留；若已有文件（包括保存选择器预建空文件），实际输出放任务独立完成目录并明确展示路径。失败/取消只删除本任务临时文件，成功关闭并完成协议后才公布最终文件。Ymodem 按数据块 await 文件追加，声明长度严格截断/拒绝不足，未知长度以常量计数去除末尾 0x1A；重复块不重写，私有粘包余量另有 **64 KiB** 上限，不再累积整份接收文件。

真实文件页保留文件/保存路径选择、协议名称与收发按钮，并展示每个目标的进度、终态、原因、等待释放、输出路径和目标停止按钮；普通发送仍可提交给同页未被任务独占的其他目标。协议日志每目标 **32 KiB / 128 条**，单行最多 2048 字符；页原始观察、展示历史和追加日志沿用各自预算。验证使用独立模拟串口对端与真实 Ymodem，不操作用户硬件；驱动异常和真机峰值仍需联调。

## 配置恢复与管理约束（T9）

生产 `main` 显式创建 `FileCommunicationConfigurationStore` 并注入根内核，等待 `initialize()` 后呈现应用。纯 `CommunicationRuntime()` 和默认/测试 `MyApp` 不访问用户配置；外部注入的内核默认由调用方释放，生产根通过 `ownsRuntime` 明确持有。

- `initialize()` 可重复等待；`configurationReady` 在失败时同样结束等待。载入前或载入期间已有管理命令时保留用户当前意图，不用晚到文件覆盖；通过 `configurationError` 保留原因并由根以 DsToast 提示，管理标题提供持续可见的存储状态图标。
- 配置文件为应用支持目录的 communication_connections.json，版本为 1。文件保存连接定义、稳定连接 ID、接收页列表和发送持有页。旧文件缺少订阅字段时按无订阅载入。
- 仅明确的连接配置或订阅变化安排保存，快照相同去重；首个变更后 200ms 固定期限不会被持续 RX/进度通知推迟。写入串行且只保留一个最新待写快照，`flushConfiguration()` 等待当前和后续快照；失败保留最新快照可重试。
- 文件先在同目录 `.tmp` 完整写入并 flush，再 rename 替换；替换失败保留上一份完整文件。单应用根内核是唯一文件写入者，不提供多个进程同时编辑同一配置的合并能力。
- 重建仅产生未打开的连接；epoch、历史、半包、接收异常、发送结果/队列、原生结束屏障、任务和循环均不保存。TCP 客户端 `autoReconnect` 只恢复参数，不触发启动打开或重试。
- 损坏 JSON、不支持版本保留原文件并报告错误；单项无效/重复 ID 跳过并报告，未知订阅页编码忽略并报告。缺少关键接口/目标字段不会回退为另一串口或默认网络地址。旧 `interface_settings.json` 仅为页面草稿，本票不自动把旧草稿导入为全局事实。
- 根注入既有 `scanInterfaceEndpoints`，`refreshInterfaceAvailability()` 只更新瞬态 `interfaceAvailable` / `availabilityDetail`。缺失接口显示不可用且保留原目标；枚举失败为未知，真实打开成功或手动刷新可更新，迟到扫描不否决实际打开的链路。纯内核不默认扫描，也不会因扫描结果拒绝用户再次打开。
- `completelyClosed` 同时检查生命周期 phase 与打开、重连、关闭、teardown、传输、未确认写/发送资格释放及任务owner独占残留；打开/关闭操作 Future 清空后再次通知，使两处管理操作及时更新。主动断开、链路故障或 TCP 服务端失去客户端时保留收发订阅。链路不可用时，原订阅在页面和管理窗口标为不可用，可删除当前页的收发订阅。重新连接后恢复收发资格。已有写入仍按原来的结束屏障释放，已停止的任务和发送循环需重新启动。修改增加 epoch，后续链路不拼旧半包。
- 桌面根拦截原生/标题栏 close，等待刷盘及拥有的内核释放后直接 destroy，重复请求合并；刷盘或资源关闭失败保留窗口、提示并允许重试。隐藏、最小化和视图卸载不触发退出。初始化已 ready 后清理不重复等待初始化 Future，避免跨调度区域重复等待。

## 多目标 Lua 固件升级（T8）

`page.firmwareUpgrades.start(protocol:, runtime:, load:, firmwareName:)` 是现有升级流程的稳定页入口。启动同步固定全部有效 TX 目标并调用 `beginProtocolTasks(firmware)`；串口、可写且具有健康 RX/TX 才创建运行，网络、离线、无健康 RX、占用及超预算目标逐项显示未执行。所有通道在异步固件读取之前登记，文件只加载一次并固定不可变快照，后加订阅不加入本轮。`targets` 返回每目标连接 ID/名称、epoch、taskId、协议 digest、进度、协议终态、原因、等待释放和释放失败；`cancel(connectionId:)` 仅停止指定目标，省略 ID 明确全停。

每个目标使用独立的真实 `LuaRun`/工作进程、输入、协议状态、参数快照、日志来源和结果。上下文直接采用 `channel.connection.definition.serial` 与 `channel.rawPackets`，不创建伪来源，也不重新构造包；宿主发送只调用该 `channel.write`，不进入页群发。短写/未知接受保留 `write_state` 与已知接受数量，不能回应完整接受或虚增统计。原始输入仍由其他订阅者观察；任务独占、对应循环停止、结束不恢复、RX/TX 撤销、接收故障和断开终止沿用正式任务通道。VM/Widget 卸载只移除观察者，任务与结果保留在稳定页；不存在按兼容主连接变化全停的桥接。

每个合格通道在构造 LuaRun 前先登记 `holdUntil(ownerCompleter.future)`，`stopped` 立即触发本运行取消。Lua 终态会禁止本任务后续写；真实进程退出、输入/事件订阅和宿主在途操作清理后，才完成 owner 证明并汇合 `finish/released`。写清理没有把五秒超时当作成功或永久失败的捷径；native 未确认仍由通道保留独占。清理异常通过 `releaseFailure` 显示并保留任务独占，实际 close 可先推进，dispose 随后明确失败进入现有窗口退出错误路径。100% 进度、Lua 成功终态和最终释放是三个不同事实；旧进程、写结果和取消不更新新任务。

`LuaRunContext.target` 与 `runtimeSchema` 递归复制冻结；运行参数读取回执、写 patch、基线与结果也按本运行复制。生产升级只传现有目标身份与固件输入，仍未注入运行时控制线能力，不新增通用脚本入口或参数表单。Lua 包保留 `connection_id`、`epoch`、`source_sequence` 和原始 UTC `received_at`；`rx_seq` 继续表示本运行接收顺序，用于脚本的现有 mark/deadline 语义。

默认预算明确如下：每页每批至多 **4** 个 Lua 目标，超额目标未执行；应用所有 LuaRuntime 实例共享最多 **4** 个真实运行/校验进程名额，进程退出确认后归还，超额明确报 ResourceLimit。既有 native 每进程 Lua 分配器上限 **128 MiB**，即同时四份 Lua 堆至多 **512 MiB**，不包含宿主及解释器固定开销。单份固件最多 **16 MiB**，文件读取与逐目标复制前检查，并限制读取范围；一次加载快照和每个运行上下文独立不可变，每页最多四份上下文固件副本。

通道订阅前输入沿用 **64 KiB / 128 包**，Lua 私有待消费输入为 **1 MiB 原始字节 / 4096 包**，在 HEX 转换前检查；HEX/元数据另有对应有界开销。运行期 IPC 行及校验 stdout/stderr 分别限制 **1 MiB UTF8**，运行 stderr 保存至多 **16384 字符**，发送与固件分块沿用 **64 KiB**。SDK 请求一发一答，事件同步交付；暂停事件观察会撤离事件源并令该运行明确失败，不让暂停订阅形成隐式无限邮箱。所有日志（含进度消息）统一截断至 **4 KiB UTF8**，只进入既有有界页历史与批量通知，不另存无界升级日志；页历史默认 **1 MiB / 5000 条**，截断标记在升级页可见，清空只影响展示。

`FirmwareProtocolBinding.load(id, locked:)` 只校验、固定并引用已保存版本；`configSuggestion` 是不可变的脚本持久参数 patch，载入和重载均不自动改 VM 或共享连接参数。连接中可载入纯脚本并展示“尚未应用”的建议；实际修改仍是通信管理 `updateConnection` 的明确命令，必须通过 `completelyClosed` 守卫。失败载入保留旧版本与建议，卸载使迟到校验失效。已有点表、Ymodem、文件快照与版本提示能力保留。

验证使用真实随附 Lua runner 和独立模拟串口对端；覆盖双设备 ACK/NAK 重传隔离、逐目标停止、首输入、未知 native、迟到回调、owner 清理失败、输入/事件/日志/进程预算及真实逐目标界面。默认值经过公开容量行为压力验证，尚未进行真机驱动取消、拔出或峰值吞吐标定。

## 管理浮窗与最终接管（T10）

`HomeView` 只呈现一个 `CommunicationManagementWindow`，由 LayoutBuilder 约束在主窗口内容区域。标题空白/标题文字拖动，右下手柄调尺寸；标题按钮独立命中。几何在每次约束变化后夹紧，最小 380×280（宿主更小时让位于宿主边界）；不持久化几何，不创建第二个 OS 窗口。重复入口请求该实例焦点，隐藏只改变 Visibility，保留编辑草稿与几何，不改变内核、循环或任务。

`runtime.interfaceScan` 是最近一次既有接口扫描的只读列表快照，管理可用性与编辑器共用。刷新失败保留最后结果并显示扫描原因。编辑器先选串口/网卡，本机网卡选择后另选三种接口协议，参数区本地 IP 只读；保留自动（全部网卡）、手动虚拟串口、缺失原目标和 UDP 两模式的独立目的。各协议本地参数草稿独立，刚明确选择的网卡随本次协议切换保留，不因扫描结果换首项。配置保存格式仍为版本 1。

页面和管理均从稳定页入口读取已连接接口的 RX/TX、故障、占用和释放状态。发送、循环和任务摘要在业务页面呈现。接口管理的网络列表显示具体网卡和已有的具体网卡配置。本地接受、协议成功、100% 和资源释放仍分别显示；状态摘要不持有任务或第二份运行态。生产两业务页没有旧配置/连接组件调用，兼容 VM connect/bind/write 和旧会话工具类只保留已有独立入口/测试，不驱动生产文件与升级。

真实 Home Widget 验证收起、切页及 inactive/hidden 生命周期后循环轮次继续，真实 Dart Ymodem 与 Lua runner 应答后完成，恢复显示同一结果；这不等同于外接硬件和桌面真实最小化联调。完整证据与验证边界见 [全故事验收记录](communication-management-acceptance.md)。

## Fresh 审查修复契约（2026-11-18）

- 默认 TCP 客户端通过 SDK 的 Socket.startConnect / ConnectionTask 打开；每次打开独立取消信号，主动断开与三秒打开期限都实际调用 task.cancel，再等待该打开结束证明。代际检查继续回收迟到 socket，旧回调不能进入新链路。自定义旧 transportFactory 不声明可取消能力，关闭继续等待原打开并回收，不能假释放。
- dart:io UdpTransport 核验 RawDatagramSocket.send 的实际接受数量。未完整接受抛出携带已知数量的 DatagramSendException；统一包装层保留 count，零接受失败、短接受 partial，不透明重发、不虚增统计，合法空数据报仍按零长度完整接受处理。open 的可选 bindSocket 仅位于系统 socket 装配边界，默认仍使用 RawDatagramSocket.bind，不向页面暴露句柄。
- 普通发送与循环通过 communication_send.dart 的同一纯分类函数解释 SerialWriteResult；各自调度、日志、统计与 settled 屏障保持独立。
- 管理编辑器六个选择框使用 AppDropdownFormField 的共享菜单锚定，受控值随状态更新；表单文本校验、缺失原目标、协议草稿与 UDP 两模式目的配置保持原契约。
