# 接口通信传输层借鉴 clovertls ByteTransport 抽象，管理层自研

Status: accepted

> 2026-11-17 更新：基于“单连接场景”的管理层决定已由 [ADR-0006](0006-global-communication-management.md) 部分取代，现采用应用级多连接与收发订阅管理。统一传输抽象、自研管理层以及仅 TCP 客户端提供自动重连的方向仍有效；下文保留原决定及其历史背景。

"接口通信"需要 TCP客户端、TCP服务端、UDP单播/广播三种网卡传输实现，clovertls 是最接近的现成参考，但它只有 TCP 客户端与 UDP 单播，且无服务端、无广播（全仓库无 setBroadcast）、TCP 客户端不支持绑定本机网卡。决定：借鉴其 ByteTransport（chunks Stream + send + close + 工厂）抽象范式，在 clovecom 内以 dart:io 原生 API 完整实现三种传输（含 ServerSocket 监听、setBroadcast 广播、Socket.connect sourceAddress 网卡绑定等 clovertls 缺口）；管理层不整套移植其 ConnectionManager/ConnectionLease/LinkState，改写贴合现有 MVVM 的轻量连接管理，仅 TCP 客户端提供自动重连（指数退避）。理由：传输抽象在 clovertls 已被验证测试友好且不破坏测试替身；Lease 是为多会话 + 重连串线防护设计，clovecom 接口通信是单连接场景，整套移植会带入用不上的机器。

## Considered Options

- 整套移植 ConnectionManager/Lease：对单连接场景过度设计，且与现有 SerialPortViewModel 形成两套并存的管理语义（与 ADR-0001 的 strangler 收拢方向冲突）。
- 不做抽象、各协议各自实现：收发流、日志、启停在三协议间三份分叉，接收/发送配置通用化（已定）后无法共享同一缝。

## Consequences

- 未来若让文件传输/固件升级参与网络接口，应接在 ByteTransport 层，而不是管理层。
- 参考 clovertls 代码时需避开其已知坑：串口 config setter 所有权/双重释放、UDP close 前 subscription.resume 防暂停泄漏。
