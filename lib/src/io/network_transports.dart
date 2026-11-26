// 网络接口传输实现（dart:io 原生，零新增依赖）
//
// 决策依据 ADR-0004：clovertls 仅有 TCP客户端与 UDP单播，TCP服务端、
// UDP广播、TCP客户端绑定出口网卡均为本项目补齐项。已知坑规避：
// UDP 关闭前需恢复订阅，避免暂停泄漏（clovertls connections.dart 注记）。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'byte_transport.dart';
import 'windows_udp_transport.dart';
import 'interface_params.dart';

/// SO_BROADCAST 在 Windows/Linux/macOS 均为 0x20
const int _kSoBroadcast = 0x20;

/// 把 InternetAddress 字符串或"自动"哨兵解析为绑定/源地址。
InternetAddress? _bindAddressOf(String nicKey, {String autoValue = '0.0.0.0'}) {
  if (nicKey.isEmpty) return InternetAddress.tryParse(autoValue);
  return InternetAddress.tryParse(nicKey);
}

class _StreamPump {
  final _chunks = StreamController<Uint8List>.broadcast();
  final _events = StreamController<TransportEvent>.broadcast();
  StreamSubscription<dynamic>? _source;
  bool _closed = false;

  Stream<Uint8List> get chunks => _chunks.stream;
  Stream<TransportEvent> get events => _events.stream;

  void emit(TransportEventType type, [String? detail]) {
    if (!_closed) _events.add(TransportEvent(type, detail));
  }

  void feed(Uint8List bytes) {
    if (!_closed) _chunks.add(bytes);
  }

  void feedOwned(Uint8List bytes) {
    // Socket 交付的独占缓冲以只读视图发布，所有订阅者共享底层字节。
    if (!_closed) _chunks.add(bytes.asUnmodifiableView());
  }

  /// 登记字节源订阅，shutdown 时统一取消（防 UDP 暂停泄漏，见 ADR-0004）
  void attachSource(StreamSubscription subscription) {
    _source?.cancel();
    _source = subscription;
  }

  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    await _source?.cancel();
    await _chunks.close();
    await _events.close();
  }
}

/// 一次打开的取消信号；登记真实连接任务，取消不冒充资源回收完成。
class TcpConnectCancellation {
  ConnectionTask<Socket>? _task;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _task?.cancel();
  }

  void attach(ConnectionTask<Socket> task) {
    _task = task;
    if (_cancelled) task.cancel();
  }

  void detach() {
    _task = null;
  }
}

/// TCP客户端：连接远端，可选绑定本机网卡作为源出口（决策 Q8）。
class TcpClientTransport implements ByteTransport {
  TcpClientTransport._(this._socket, this._pump);

  final Socket _socket;
  final _StreamPump _pump;

  static Future<TcpClientTransport> connect(
    TcpClientPrefs prefs, {
    Duration timeout = const Duration(seconds: 3),
    TcpConnectCancellation? cancellation,
  }) async {
    final source = _bindAddressOf(prefs.nicKey);
    final task = await Socket.startConnect(
      prefs.remoteHost.trim(),
      prefs.remotePort,
      sourceAddress: prefs.nicKey.isEmpty ? null : source,
      // 本地端口 0 = 系统分配（决策 Q23，与服务端一致）
      sourcePort: prefs.localPort,
    );
    final signal = cancellation ?? TcpConnectCancellation();
    // 先观察 socket Future，再触发可能同步完成的取消。
    final socketFuture = task.socket;
    signal.attach(task);
    final deadline = Timer(timeout, signal.cancel);
    late final Socket socket;
    try {
      socket = await socketFuture;
    } finally {
      deadline.cancel();
      signal.detach();
    }
    final transport = TcpClientTransport._(socket, _StreamPump());
    transport._attach();
    return transport;
  }

  void _attach() {
    _socket.done.then(
      (_) {
        _pump.emit(TransportEventType.peerDisconnected);
        _pump.shutdown();
      },
      onError: (Object error) {
        _pump.emit(TransportEventType.error, error.toString());
        _pump.shutdown();
      },
    );
    _pump.attachSource(
      _socket.listen(
        _pump.feedOwned,
        onDone: () {
          _pump.emit(TransportEventType.peerDisconnected);
          _socket.destroy();
          unawaited(_pump.shutdown());
        },
        onError: (Object error) {
          _pump.emit(TransportEventType.error, error.toString());
          _pump.shutdown();
        },
        cancelOnError: false,
      ),
    );
    _pump.emit(
      TransportEventType.opened,
      '${_socket.remoteAddress.address}:${_socket.remotePort}',
    );
  }

  @override
  Stream<Uint8List> get chunks => _pump.chunks;

  @override
  Stream<TransportEvent> get events => _pump.events;

  @override
  Future<void> send(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    _socket.destroy();
    await _pump.shutdown();
    _pump.emit(TransportEventType.closed);
  }
}

/// TCP服务端：监听并只接受一个客户端，占线时新连接直接拒绝（决策 Q19）。
/// 对端断开后回到等待状态，可再次接受连接。
class TcpServerTransport implements ByteTransport {
  TcpServerTransport._(this._server, this._pump);

  final ServerSocket _server;
  final _StreamPump _pump;
  Socket? _client;

  /// 实际监听端口（localPort 为 0 时由系统分配，测试与状态展示用）。
  int get boundPort => _server.port;

  static Future<TcpServerTransport> listen(TcpServerPrefs prefs) async {
    final address = _bindAddressOf(prefs.nicKey) ?? InternetAddress.anyIPv4;
    // localPort 0 = 系统自动分配（决策 Q23）
    final server = await ServerSocket.bind(
      address,
      prefs.localPort,
      shared: false,
    );
    final transport = TcpServerTransport._(server, _StreamPump());
    transport._acceptLoop();
    transport._pump.emit(
      TransportEventType.opened,
      '${address.address}:${server.port}',
    );
    return transport;
  }

  void _acceptLoop() {
    _server.listen(
      (client) {
        if (_client != null) {
          // 单客户端占用中，直接拒绝后来的连接
          client.destroy();
          return;
        }
        _client = client;
        client.listen(
          (data) {
            if (identical(_client, client)) _pump.feedOwned(data);
          },
          onDone: () {
            if (!identical(_client, client)) return;
            _client = null;
            _pump.emit(TransportEventType.peerDisconnected);
          },
          onError: (Object error) {
            if (!identical(_client, client)) return;
            client.destroy();
            _client = null;
            _pump.emit(TransportEventType.peerDisconnected, error.toString());
          },
          cancelOnError: false,
        );
        _pump.emit(
          TransportEventType.peerConnected,
          '${client.remoteAddress.address}:${client.remotePort}',
        );
      },
      onError: (Object error) {
        _pump.emit(TransportEventType.error, error.toString());
      },
    );
  }

  @override
  Stream<Uint8List> get chunks => _pump.chunks;

  @override
  Stream<TransportEvent> get events => _pump.events;

  @override
  Future<void> send(Uint8List bytes) async {
    final client = _client;
    if (client == null) {
      throw StateError('尚无客户端连接，无法发送');
    }
    client.add(bytes);
    await client.flush();
  }

  @override
  Future<void> close() async {
    _client?.destroy();
    _client = null;
    await _server.close();
    await _pump.shutdown();
  }
}

/// 系统已明确报告数据报接受数量；失败仍保留实际计数。
class DatagramSendException implements Exception {
  const DatagramSendException(this.acceptedBytes, this.requestedBytes);
  final int acceptedBytes, requestedBytes;
  @override
  String toString() => 'UDP 未完整接受：$acceptedBytes/$requestedBytes 字节';
}

/// UDP传输：单播/广播（决策 Q9/Q20）。
/// 接收来自任意对端的数据报；发送使用配置的目的地址。
class UdpTransport implements ByteTransport {
  UdpTransport._(this._socket, this._prefs, this._target, this._pump);

  final _datagrams =
      StreamController<({Uint8List bytes, String peer})>.broadcast(sync: true);
  Stream<({Uint8List bytes, String peer})> get datagrams => _datagrams.stream;
  final RawDatagramSocket _socket;
  final UdpPrefs _prefs;
  final InternetAddress? _target;
  final _StreamPump _pump;

  /// 实际绑定的本地端口（localPort 传 0 时由系统分配）。
  int get boundPort => _socket.port;

  static Future<UdpTransport> open(
    UdpPrefs prefs, {
    Future<RawDatagramSocket> Function(InternetAddress, int)? bindSocket,
  }) async {
    final address = _bindAddressOf(prefs.nicKey) ?? InternetAddress.anyIPv4;
    final socket = await (bindSocket ?? RawDatagramSocket.bind)(
      address,
      prefs.localPort,
    );
    if (prefs.mode == UdpMode.broadcast) {
      // dart:io 无 setBroadcast，经原生选项打开 SO_BROADCAST
      socket.setRawOption(
        RawSocketOption.fromInt(RawSocketOption.levelSocket, _kSoBroadcast, 1),
      );
    }
    InternetAddress? target;
    if (prefs.hasValidTarget) {
      target = InternetAddress.tryParse(prefs.targetHost.trim());
    }
    final transport = UdpTransport._(socket, prefs, target, _StreamPump());
    transport._pump.emit(
      TransportEventType.opened,
      '${address.address}:${socket.port}',
    );
    transport._readLoop();
    return transport;
  }

  void _readLoop() {
    _pump.attachSource(
      _socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          for (var n = 0; n < 64; n++) {
            final datagram = _socket.receive();
            if (datagram == null) break;
            final bytes = Uint8List.fromList(datagram.data)
                .asUnmodifiableView();
            _datagrams.add((
              bytes: bytes,
              peer: '${datagram.address.address}:${datagram.port}',
            ));
            _pump.feed(bytes);
          }
        },
        onError: (Object error) {
          _pump.emit(TransportEventType.error, error.toString());
          _pump.shutdown();
        },
      ),
    );
  }

  @override
  Stream<Uint8List> get chunks => _pump.chunks;

  @override
  Stream<TransportEvent> get events => _pump.events;

  @override
  Future<void> send(Uint8List bytes) async {
    final target = _target;
    if (target == null) {
      throw StateError('需要先配置有效的目的地址与端口');
    }
    final accepted = _socket.send(bytes, target, _prefs.targetPort);
    if (accepted != bytes.length) {
      throw DatagramSendException(accepted, bytes.length);
    }
  }

  @override
  Future<void> close() async {
    // clovertls 已知坑：close 前恢复订阅，防暂停泄漏
    _socket.close();
    await _datagrams.close();
    await _pump.shutdown();
  }
}

/// 打开一个网卡通信接口的传输（工厂）。
Future<ByteTransport> openNetworkTransport({
  required InterfaceProtocol protocol,
  required TcpClientPrefs tcpClient,
  required TcpServerPrefs tcpServer,
  required UdpPrefs udp,
  TcpConnectCancellation? cancellation,
}) {
  switch (protocol) {
    case InterfaceProtocol.tcpClient:
      return TcpClientTransport.connect(tcpClient, cancellation: cancellation);
    case InterfaceProtocol.tcpServer:
      return TcpServerTransport.listen(tcpServer);
    case InterfaceProtocol.udp:
      return Platform.isWindows
          ? WindowsUdpTransport.open(udp)
          : UdpTransport.open(udp);
  }
}

/// 网卡接口的参数有效性检查（连接前守卫，返回可读原因或 null）。
String? validateNetworkParams({
  required InterfaceProtocol protocol,
  required TcpClientPrefs tcpClient,
  required TcpServerPrefs tcpServer,
  required UdpPrefs udp,
}) {
  switch (protocol) {
    case InterfaceProtocol.tcpClient:
      return tcpClient.hasValidTarget ? null : 'TCP客户端需要有效的远端地址与端口';
    case InterfaceProtocol.tcpServer:
      return tcpServer.hasValidPort ? null : 'TCP服务端本地端口无效（留空 = 系统自动分配）';
    case InterfaceProtocol.udp:
      if (!udp.hasValidTarget) {
        return udp.mode == UdpMode.broadcast
            ? 'UDP 广播需要有效的目的地址与端口（切换广播模式将自动填入）'
            : 'UDP 单播需要有效的目的地址与端口';
      }
      return null;
  }
}
