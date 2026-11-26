# 串口异步写入与 worker 契约（T1、T3）

`SerialByteTransport.send` 返回 `Future<SerialWriteResult>`，只表示本地传输接受结果，不表示对端协议成功。`acceptedBytes` 是可证实的数量；失败或取消时无法得知数量使用 `null`，不得猜为零。超时不自动重试整条命令。

结果可先于底层停止到达；`result.settled` 只在内核不再访问本次缓冲、且不会再产生本次物理写入时成功完成，不能用 `Future.timeout` 替代。适配器必须自行处理原生错误，结束证明不能用异常代替。串口租约、VM 及会话在等待期间不交接写入资格。

`close` 可等待且幂等：先阻止新写、发起底层停止，在途 I/O 结束和资源回收后完成。租约传输还等待已提交写入的 settled 后才释放物理串口占用。关闭失败保留租约，不能假装安全释放。

协议回调与会话使用 `Future<bool>`，只有真实写入成功且任务仍活动才返回 true。会话取消立即禁止新写并唤醒读取，但保持占用至在途写结束；`done` 表示会话释放。VM/Lua 不将异步提交转换为立即成功。

## T3 已实现的后台串口

- 默认工厂等待 `Win32SerialTransport.open(config)` 就绪后才声明连接打开。每次连接产生独立 Dart isolate；主 isolate 不持 HANDLE、原生缓冲、事件或 OVERLAPPED。遗留同步构造入口只作兼容，新应用使用异步 `open`。
- worker 直接使用 Win32 打开、配置与释放，不创建 `serial_port_win32.SerialPort` 运行期实例。每次读写各有独立 OVERLAPPED、manual-reset event 和计数指针；默认调用 `GetOverlappedResult(false)`；返回 FALSE 且错误码为 0 时，用 `GetOverlappedResultEx(0, false)` 再次查询同一笔操作。两次均未提供明确结果时继续轮询，不确认字节数、不释放缓冲，也不重发。不使用同步 Wait、`FlushFileBuffers` 或 `GetOverlappedResult(true)`。
- 发起返回 `ERROR_IO_PENDING` 与轮询返回 `ERROR_IO_INCOMPLETE` 分开处理。即使发起立即成功，也收集真实完成计数；短写失败但保留可证实计数，不透明重发。取消及原生失败计数未知为 null。
- 单调时钟 deadline 到达可先返回超时结果，并只对 TX OVERLAPPED 调用 `CancelIoEx`。取消成功、`ERROR_NOT_FOUND` 或迟到正常完成都不能提前释放；继续非阻塞轮询，终态后才释放对应事件/缓冲并发送 `settled`。已返回的超时结果不因迟到成功而改变。
- `CancellableSerialByteTransport.cancelWrite()` 是可选能力。应用适配的 `CancellableCommunicationTransport.cancelWrite()` 在调用时捕获当前 writeId，仅取消该次写；不会清 RX、取消读取或关闭连接。重复调用等待同一 `settled`；对不具备原生取消能力的兼容传输只等待在途 `settled`。
- 关闭立即阻止新操作，分别取消 RX/TX；两者原生终结且资源回收后才关闭串口句柄并完成 `close`。关闭幂等。打开失败也在 worker 内回收，回收失败继续持有资源并重试；无法证明终结时不强杀 isolate、不硬超时 free、不释放物理占用。

## 资源预算和接收完整性

- 每连接同时最多一笔 TX，无隐藏写队列；写内容在调用时固定，单次上限 **1 MiB**，超限在传 IPC 前明确拒绝。T5 的有界 FIFO 由应用内核统一持有（含在途字节/条目），适配器不再排第二层队列。
- 每次 RX 最多 **16 KiB**。worker 到主 isolate 采用单批 credit：上一批同步交付并确认后才能再读下一批；未订阅、主线程忙或订阅暂停时最多一批留在 IPC/主线程，不能依靠暂停 Stream 无限缓存。已发起的单笔原生读取仍继续检查终态。
- 每 5 ms 有界推进读、写和取消。Win32 写入仍在途时，由该笔 I/O 的事件唤醒工作 isolate 并查询原生结果。最初 4 ms 内仍保留每 1 ms 快速轮询，提前回执、取消或超时时仍需等待终态。已终结的普通写入在一条 isolate 消息中携带结果和 settled，结果提前返回的写入随后单独投递 settled。已就绪的 RX 在发起读取后同轮查询完成，单批 credit 和 16 KiB 上限继续生效。
- `ClearCommError` 的错误 mask 非零会报告接收完整性故障并安全关闭，不静默拼接已丢字节的流；成功零字节读取不是断开。COMMTIMEOUTS 五个字段显式配置；不在活动写期间修改串口全局超时。
- 现有无流控、RTS/CTS、DTR/DSR、XON/XOFF 语义保持；无流控的 DTR/RTS 仍关闭。清除驱动缓存的 Null/ErrorChar/DSR sensitivity/abort-on-error 等隐藏策略，原始数据不被继承配置丢弃或替换。XON/XOFF 协议字节仍由流控消费。
- `purge()` 仅保留遗留显式兼容入口，任务取消和关闭不调用它。

小于 5 ms 的 Windows 循环使用可重用的高分辨率单次定时器。原生定时器不可用时回退到 Dart 定时器。循环仍遵守逐连接串行发送和取消屏障。

## 验证范围

`test/src/application/serial_worker_runtime_test.dart` 经真实 runtime/页入口与现有传输边界，向 **真实 isolate 内** 注入 `SerialNativeDriver` 系统边界替身；包含真正同步 sleep 的原生发起、可控 pending、同连接 RX/定向取消、超时与 settled 分离、迟到正常完成、短写、打开失败、读写同时 pending 的幂等关闭、接收暂停/恢复和写预算。替身的 `start*` 抛错约定为尚未提交原生 I/O；pending 的资源必须由 `poll*` 终态证明后释放。

未自动操作用户硬件。目标 USB 串口驱动、CTS 停写时持续 RX、拔出、同端口重开及原生 handle/分配计数仍需真机矩阵。某些坏驱动可能在 FFI 发起本身阻塞其 worker；本实现保证主 isolate 和其他连接隔离，不声称对这类驱动有硬实时的同连接取消保证。

## T7 任务 channel 的释放接合

协议任务 `ProtocolTaskChannel.write` 与普通发送、循环共用内核 FIFO，scope 只属于固定目标/epoch/grant/taskId。`stopped` 只禁止后续写并通知 owner 取消；`released` 必须同时具备 owner 成功清理和 native settled/明确 close 的结束证明。owner 通过 holdUntil 在运行前登记，不能等待 released 后才清理自己；owner 证明失败通过 releaseFailure 报告并保留独占。连接 close 直接推进真实 teardown，应用 dispose 随后汇合任务释放并使已知 owner 错误可见。任务和协议不调用 purge，既有兼容 purge 能力不作为取消或握手步骤。
