# Windows UDP 原生适配

`lib/src/io/windows_udp_transport.dart` 提供独立的 `WindowsUdpTransport implements ByteTransport`，由网络工厂选择 Windows 路径；本文件不改变通信内核或页面订阅模型。

## 公共契约

- `static Future<WindowsUdpTransport> open(UdpPrefs prefs)`：绑定配置的本地 IPv4 和本地端口，空网卡键绑定 `0.0.0.0`，端口 `0` 由系统分配；`boundPort` 返回实际端口。
- `Stream<Datagram> datagrams`：同步广播流，每个 OS 数据报对应一条事实，包含 `data/address/port`；合法空数据报也必须交付。
- `chunks`：同一 `datagrams` 流的数据投影，不启动第二条读取管线，也不拼接、拆分或过滤空数据报。
- `send(bytes)`：始终使用打开时配置的当前模式目的 IPv4/端口，接收来源不会改写目的地址；没有有效目的地址时明确失败，仍允许打开仅接收的本地 socket。
- `events`：本地打开、原生接收失败和关闭事件。接收失败停止原生读取并关闭本地 socket。
- `close()`：幂等，原生 socket、接收缓冲及 Winsock 引用释放后完成；关闭所有流，但不等待某个已暂停的消费订阅观察 `done`。

只支持 IPv4 字面地址，不新增 DNS、自动重连、透明重发或 IPv6 语义。UDP 的 `send` 完成仅证明本地 `sendto` 接受完整数据报，不证明对端收到。

## 空报文缺陷与绕过依据

本机 Dart `3.13.4 stable windows_x64` 上，真实回环发送空报文后再发送非空报文，基于 `RawDatagramSocket.receive()` 的基线适配器在 2 秒内不能交付这两条报文，即使应用层不再主动过滤空数据。初次红测使用与最终测试相同的 `open/send/datagrams/chunks` 公共入口。

[Dart 官方 Socket_RecvFrom 实现](https://raw.githubusercontent.com/dart-lang/sdk/main/runtime/bin/socket.cc) 在 `bytes_read == 0` 时直接返回 `Dart_Null()`，未构造含来源的接收结果。因此应用层仅删除 `data.isNotEmpty` 过滤不足以满足空报文要求。

[Microsoft recvfrom 文档](https://learn.microsoft.com/en-us/windows/win32/api/winsock/nf-winsock-recvfrom) 明确：UDP 空报文返回 `0`，来源写入 `from`；非阻塞无数据返回 `SOCKET_ERROR`，错误码为 `WSAEWOULDBLOCK`。本适配器直接使用 Winsock `recvfrom`，区分上述返回值，不经过 Dart 缺陷路径。

## 原生执行与边界

打开 UDP socket 后通过 `WSAEventSelect` 注册 `FD_READ` 并进入非阻塞模式。线程池单次等待把可读信号投递给 Dart，`WSAEnumNetworkEvents` 原子清除事件记录和信号。每轮最多处理 64 报或约 256 KiB，最后一报保持完整。队列仍有数据时，`recvfrom` 会重新启用可读通知。65507 字节接收缓冲覆盖 IPv4 UDP 最大负载，空报也计入本轮报文预算。关闭时撤销等待，回收事件句柄和接收缓冲。

发送使用一次非阻塞 `sendto`，核对实际返回值恰好等于 payload 长度。`len=0/result=0` 是空报文成功，不能视为忙碌。`SOCKET_ERROR`（含 `WSAEWOULDBLOCK`、`WSAENOBUFS`）或部分接受均抛异常，不重发，不把失败隐藏为发送成功。测试以真实 OS 过大报文错误验证失败传播；内核缓冲耗尽的时间条件不作易抖动断言。

适配器不积累自己的接收队列，每轮同步发布已复制的数据报；同步接收者触发关闭时本轮立即退出。标准 Stream 消费者若自行暂停可能保留其订阅缓冲；页模块有界交付与异常隔离由通信内核负责，调用方不应以暂停原始流充当过载处理。

每次成功 `WSAStartup` 都由打开失败回收或最终关闭对应一次 `WSACleanup`。接收缓冲只在 socket 存活期间持有；临时绑定地址、选项值和每次发送缓冲均由 `finally` 释放。关闭在默认禁用 linger 的非阻塞 UDP socket 上立即释放资源，不借 Future 宣称后台隔离。

## 绑定生成

本机 `win32 6.4.0` 的 `lib/src/win32/ws2_32.g.dart` 已导出 `socket/bind/getsockname/ioctlsocket/recvfrom/sendto/closesocket`，返回 `Win32Result<T>`；`recvfrom` 的缓冲是 `PSTR`，`sendto` 是 `PCSTR`，`SOCKET` 为 `int` extension type。适配器直接复用这些签名，通过 `WSAGetLastError` 读取 Winsock 错误码。

该版本未导出 `WSAStartup/WSACleanup/WSAGetLastError/setsockopt`。窄生成入口位于 `tool/ffigen.dart` 和 `third_party/windows_winsock/windows_winsock.h`，仅引用开发机现有 Windows SDK，不重新分发 SDK 头文件。生成目标为 `lib/src/third_party/windows_winsock.g.dart`，包含启动和清理、Socket 选项、可读事件注册与查询及必要结构。

开发依赖使用 `ffigen 23.0.0`（SDK 要求 `>=3.10.0 <4.0.0`，本机 3.13.4 兼容）。离线缓存的 20.1.1 实际没有 `recordUse/recordUseMapping` API；因此从官方 pub.dev 升级，并按 23.0.0 的真实 `Input/Visitor/DartOutput` API 为纳入白名单的函数设置 `recordUse=true`，生成 `lib/src/third_party/windows_winsock.record_use_mapping.g.dart`。

实际验证发现 `DynamicLibraryBindings` 在实例方法上生成 `@RecordUse` 后，Dart 3.13.4 编译器报 `RecordUse annotation cannot be placed on this element`。生成文件没有手改；改用官方 `NativeExternalBindings` 输出顶层原生声明，并由 `hook/build.dart` 通过 `CodeAsset + DynamicLoadingSystem(Uri.file('ws2_32.dll'))` 映射到系统 Winsock。该配置与现有 `code_assets` 包的 `host_name` 官方示例一致；构建 hook 不编译、下载或打包 DLL，只声明 Windows 自带系统库。`hooks/code_assets` 提升为开发依赖，运行时依赖声明保持不变。使用记录和映射已经生成；系统 DLL 不由本项目重新链接裁剪。

本机未安装 Clang/libclang，最初生成命令确实失败于 `clang -print-file-name=libclang.dll`。本次使用 [.NET ClangSharp 官方说明](https://github.com/dotnet/ClangSharp/blob/main/docs/using-clangsharp-as-a-library.md) 指定的原生 NuGet 包，下载至任务临时工具目录，仅作为开发时的生成工具：

- 包：`libclang.runtime.win-x64 20.1.2`，作者 `.NET Foundation and Contributors`；包内元数据指向 `llvm/llvm-project` 的 `llvmorg-20.1.2`。
- 来源：`https://api.nuget.org/v3-flatcontainer/libclang.runtime.win-x64/20.1.2/libclang.runtime.win-x64.20.1.2.nupkg`。
- 包 SHA-256：`9ABC7F0A31FF399D5482812B3633A8BE64A21B1770F094822FB9AF9EDDEF1E24`。
- 许可：`Apache-2.0 WITH LLVM-exception`。DLL 位于解包目录 `runtimes/win-x64/native/libclang.dll`。
- 下载的 nupkg/DLL 不纳入仓库，不随应用分发；正常测试/构建只需要已提交的生成文件和 Windows 系统库，不要求开发机重新安装 libclang。
生成命令：

```powershell
$env:LIBCLANG_PATH = '解包目录\runtimes\win-x64\native\libclang.dll'
$env:WINDOWS_SDK_INCLUDE = 'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0'
$env:MSVC_INCLUDE = '安装路径\VC\Tools\MSVC\版本\include'
dart run tool/ffigen.dart
```

`LIBCLANG_PATH` 省略时由 ffigen 搜索 Clang；SDK 路径有上述默认值，MSVC 路径用于补充系统 C 头。生成文件必须由真实生成器产生，不手写替代产物。

原生依据：[WSAStartup](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-wsastartup)、[WSACleanup](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-wsacleanup)、[ioctlsocket](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-ioctlsocket)、[sendto](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-sendto)、[setsockopt](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-setsockopt)、[sockaddr_in](https://learn.microsoft.com/en-us/windows/win32/api/winsock/ns-winsock-sockaddr_in)。

## 验证

```powershell
flutter test --no-pub test/src/io --reporter expanded
flutter analyze --no-pub lib/src/io/windows_udp_transport.dart test/src/io/windows_udp_transport_test.dart tool/ffigen.dart hook/build.dart lib/src/third_party
```

独立测试覆盖：原生适配器对原生适配器的空报→非空报真实回环及来源/字节流投影、与 Dart 接收器的非空双向互通、固定目的地址、幂等关闭与端口再绑定、仅在 `127.0.0.0/8` 内发送的广播模式、最大报文/过大报文失败、多来源 130 条空报文跨接收批次交付、配置失败、暂停消费者不阻止原生端口释放。空报文端到端不依赖 Dart 接收器作为 oracle；测试不使用 fake 或外部设备。


2026-11-17 验证结果：网络目录 20 项测试通过，适配器/测试/生成文件/生成入口/hook 定向静态分析零问题；Windows Debug 构建成功。MSBuild 仅提示工作树位于 Temp 目录的 MSB8029 增量构建警告。最终工厂接入与应用整体回归由 T4 主任务执行。
