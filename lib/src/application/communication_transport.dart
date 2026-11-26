import 'dart:async';
import 'dart:typed_data';

import '../../models/serial_port_model.dart';
import '../../services/serial/serial_byte_transport.dart';
import '../../services/serial/serial_config_translation.dart';
import '../io/connections.dart';
import '../io/recording.dart';
import '../io/byte_transport.dart';
import '../io/network_transports.dart';
import '../io/windows_udp_transport.dart';
import '../io/interface_params.dart';
export '../../services/serial/serial_write_result.dart';
export '../../services/serial/serial_byte_transport.dart'
    show
        SerialReceiveOverrun,
        SerialWorkerLoop,
        SerialWorkerRound,
        SerialWorkerTiming;
export '../io/network_transports.dart' show TcpConnectCancellation;
export '../io/recording.dart' show TransportInput;

/// 串口配置以 src 词汇为准；网络参数不猜测 TCP 客户端/服务端模式。
class ConnectionDefinition {
  ConnectionDefinition.serial(ConnectionConfig config)
    : id = config.id,
      name = config.name,
      serial = config,
      protocol = null,
      tcpClient = const TcpClientPrefs(),
      tcpServer = const TcpServerPrefs(),
      udp = const UdpPrefs() {
    if (config.kind != TransportKind.serial) throw ArgumentError('需要串口配置');
  }
  ConnectionDefinition.network({
    required this.id,
    required this.name,
    required InterfaceProtocol this.protocol,
    this.tcpClient = const TcpClientPrefs(),
    this.tcpServer = const TcpServerPrefs(),
    this.udp = const UdpPrefs(),
  }) : serial = null {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('连接标识及名称不能为空');
    }
  }
  final String id;
  final String name;
  final ConnectionConfig? serial;
  final InterfaceProtocol? protocol;
  final TcpClientPrefs tcpClient;
  final TcpServerPrefs tcpServer;
  final UdpPrefs udp;
  bool get isSerial => serial != null;
  bool get autoReconnect =>
      protocol == InterfaceProtocol.tcpClient && tcpClient.autoReconnect;
}

class CommunicationTransportState {
  const CommunicationTransportState({
    required this.writable,
    this.listening = false,
    this.closed = false,
    this.peer,
    this.detail,
    this.error,
  });
  final bool writable;
  final bool listening;
  final bool closed;
  final String? peer;
  final String? error;
  final String? detail;
}

/// 真实传输工厂边界。适配器持句柄；应用内核持适配器，页面不取得它。
abstract interface class CommunicationTransport {
  CommunicationTransportState get state;
  Stream<TransportInput> get incoming;
  Stream<CommunicationTransportState> get states;
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs);
  Future<void> close();
}

/// 可选取消能力；Future 仅在调用时那笔写的原生 I/O 结束后完成。
abstract interface class CancellableCommunicationTransport {
  Future<void> cancelWrite();
}

typedef CommunicationTransportFactory = Future<CommunicationTransport> Function(
  ConnectionDefinition definition,
);

SerialPortConfig serialViewConfig(ConnectionConfig c) => SerialPortConfig(
  portName: c.serialPort,
  baudRate: c.baudRate,
  dataBits: c.dataBits,
  stopBits: c.stopBits,
  parity: SerialConfigTranslation.parityDisplayOf(
    ['none', 'odd', 'even', 'mark', 'space'][c.parity],
  )!,
  flowControl: SerialConfigTranslation.flowDisplayOf(c.flowControl)!,
);
ConnectionConfig serialConnectionConfig(
  String id,
  SerialPortConfig c, {
  String? name,
}) => ConnectionConfig(
  id: id,
  name: name,
  protocolId: '',
  kind: TransportKind.serial,
  serialPort: c.portName,
  baudRate: c.baudRate,
  dataBits: c.dataBits,
  stopBits: c.stopBits,
  parity: SerialConfigTranslation.parityIndexOf(c.parity),
  flowControl: SerialConfigTranslation.flowCodeOf(c.flowControl),
);

class SerialCommunicationTransport
    implements CommunicationTransport, CancellableCommunicationTransport {
  SerialCommunicationTransport(this._inner);
  final SerialByteTransport _inner;
  Future<void>? _activeWrite;
  Completer<void>? _activeCompletion;
  @override
  CommunicationTransportState get state =>
      const CommunicationTransportState(writable: true);
  @override
  Stream<TransportInput> get incoming => switch (_inner) {
    Win32SerialTransport serial => serial.inputs,
    _ => _inner.chunks.map(TransportInput.new),
  };
  @override
  Stream<CommunicationTransportState> get states => const Stream.empty();
  bool supportsWorkerLoop(Duration interval) {
    final serial = _inner;
    return serial is Win32SerialTransport &&
        serial.supportsWorkerLoop(interval);
  }

  SerialWorkerLoop? startWorkerLoop(
    Uint8List bytes, {
    required Duration interval,
    required int timeoutMs,
    required bool immediate,
    required void Function(List<SerialWorkerRound>, SerialWorkerTiming)
    onRounds,
  }) {
    final serial = _inner;
    if (serial is! Win32SerialTransport || _activeWrite != null) return null;
    return serial.startWorkerLoop(
      bytes,
      interval: interval,
      timeoutMs: timeoutMs,
      immediate: immediate,
      onRounds: onRounds,
    );
  }

  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) async {
    if (_activeWrite != null) {
      return SerialWriteResult.failure('当前写入尚未结束', acceptedBytes: 0);
    }
    final finished = Completer<void>();
    _activeWrite = finished.future;
    _activeCompletion = finished;
    void finish() {
      if (identical(_activeWrite, finished.future)) {
        _activeWrite = null;
        _activeCompletion = null;
      }
      if (!finished.isCompleted) finished.complete();
    }

    try {
      final result = await _inner.send(bytes, timeoutMs);
      if (result.needsSettlement) {
        unawaited(
          result.settled.then(
            (_) => finish(),
            onError: (Object _, StackTrace _) {
              // 结束证明失效时保留屏障，由内核拒绝交接并等待明确关闭。
            },
          ),
        );
      } else {
        finish();
      }
      return result;
    } catch (_) {
      // 未取得结果同样没有结束证明；取消回退屏障保留至 close 成功。
      rethrow;
    }
  }

  @override
  Future<void> cancelWrite() {
    // 调用时捕获，不能在异步等待后误取消下一笔写。
    if (_inner is CancellableSerialByteTransport) {
      return (_inner as CancellableSerialByteTransport).cancelWrite();
    }
    return _activeWrite ?? Future<void>.value();
  }

  @override
  Future<void> close() async {
    final active = _activeCompletion;
    await _inner.close();
    if (active != null) {
      if (identical(_activeWrite, active.future)) {
        _activeWrite = null;
        _activeCompletion = null;
      }
      if (!active.isCompleted) active.complete();
    }
  }
}

class NetworkCommunicationTransport implements CommunicationTransport {
  NetworkCommunicationTransport(
    this._inner,
    this._protocol, {
    this._localEndpoint,
  }) {
    _state = CommunicationTransportState(
      writable: _protocol != InterfaceProtocol.tcpServer,
      listening: _protocol == InterfaceProtocol.tcpServer,
      detail: _localEndpoint,
    );
    _events = _inner.events.listen((event) {
      final server = _protocol == InterfaceProtocol.tcpServer;
      switch (event.type) {
        case TransportEventType.opened:
          _state = CommunicationTransportState(
            writable: !server,
            listening: server,
            peer: server ? null : event.detail,
            detail: _localEndpoint,
          );
        case TransportEventType.peerConnected:
          _state = CommunicationTransportState(
            writable: true,
            listening: server,
            peer: event.detail,
            detail: _localEndpoint,
          );
        case TransportEventType.peerDisconnected:
          _state = CommunicationTransportState(
            writable: false,
            listening: server,
            closed: !server,
            detail: _localEndpoint,
          );
        case TransportEventType.error:
          _state = CommunicationTransportState(
            writable: false,
            error: event.detail ?? '网络错误',
          );
        case TransportEventType.closed:
          _state = const CommunicationTransportState(
            writable: false,
            closed: true,
          );
        case TransportEventType.reconnecting:
          return;
      }
      _states.add(_state);
    });
  }
  final ByteTransport _inner;
  final InterfaceProtocol _protocol;
  final String? _localEndpoint;
  final _states = StreamController<CommunicationTransportState>.broadcast();
  late final StreamSubscription<TransportEvent> _events;
  late CommunicationTransportState _state;
  Future<void>? _closing;
  @override
  CommunicationTransportState get state => _state;
  @override
  Stream<TransportInput> get incoming => switch (_inner) {
    WindowsUdpTransport t => t.datagrams.map(
      (d) => TransportInput.takeOwned(
        d.data,
        peer: '${d.address.address}:${d.port}',
        datagram: true,
      ),
    ),
    UdpTransport t => t.datagrams.map(
      (d) => TransportInput.takeOwned(d.bytes, peer: d.peer, datagram: true),
    ),
    TcpClientTransport() || TcpServerTransport() => _inner.chunks.map(
      (bytes) => TransportInput.takeOwned(bytes, peer: _state.peer),
    ),
    _ => _inner.chunks.map((bytes) => TransportInput(bytes, peer: _state.peer)),
  };
  @override
  Stream<CommunicationTransportState> get states => _states.stream;
  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) async {
    if (!_state.writable) {
      return SerialWriteResult.failure('当前链路不可发送', acceptedBytes: 0);
    }
    try {
      await _inner.send(bytes);
      return SerialWriteResult.success(bytes.length);
    } on DatagramSendException catch (error) {
      return SerialWriteResult.failure(
        '$error',
        acceptedBytes: error.acceptedBytes,
      );
    } catch (error) {
      return SerialWriteResult.failure('$error');
    }
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _events.cancel();
    await _inner.close();
    await _states.close();
  }
}

Future<CommunicationTransport> openCommunicationTransport(
  ConnectionDefinition d, {
  TcpConnectCancellation? cancellation,
}) async {
  if (d.isSerial) {
    return SerialCommunicationTransport(
      await Win32SerialTransport.open(serialViewConfig(d.serial!)),
    );
  }
  final invalid = validateNetworkParams(
    protocol: d.protocol!,
    tcpClient: d.tcpClient,
    tcpServer: d.tcpServer,
    udp: d.udp,
  );
  if (invalid != null) throw ArgumentError(invalid);
  final inner = await openNetworkTransport(
    cancellation: cancellation,
    protocol: d.protocol!,
    tcpClient: d.tcpClient,
    tcpServer: d.tcpServer,
    udp: d.udp,
  );
  final endpoint = switch (inner) {
    TcpServerTransport t =>
      '${d.tcpServer.nicKey.isEmpty ? '0.0.0.0' : d.tcpServer.nicKey}:${t.boundPort}',
    WindowsUdpTransport t =>
      '${d.udp.nicKey.isEmpty ? '0.0.0.0' : d.udp.nicKey}:${t.boundPort}',
    UdpTransport t =>
      '${d.udp.nicKey.isEmpty ? '0.0.0.0' : d.udp.nicKey}:${t.boundPort}',
    _ => null,
  };
  return NetworkCommunicationTransport(
    inner,
    d.protocol!,
    localEndpoint: endpoint,
  );
}
