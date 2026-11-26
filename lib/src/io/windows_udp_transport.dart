// Windows UDP 原生适配：绕过 Dart Socket_RecvFrom 将空数据报视作 null 的路径。
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import '../third_party/windows_winsock.g.dart' as native;
import 'byte_transport.dart';
import 'interface_params.dart';
import 'windows_async_wait.dart';

const _socketError = -1;
const _ipprotoUdp = 17;
const _solSocket = 0xffff;
const _wouldBlock = 10035;
const _fdRead = 1;
const _maxPayload = 65507;
const _packetsPerPoll = 64;
const _bytesPerPoll = 256 * 1024;

SocketException _socketException(String operation, [int? code]) =>
    SocketException(
      'UDP $operation 失败',
      osError: OSError('Winsock', code ?? native.WSAGetLastError()),
    );

// 包装器已立即捕获线程错误码，不能丢弃后再跨 FFI 查询线程局部状态。
T _checked<T extends Object>(win32.Win32Result<T> result, String operation) {
  if (result.value == _socketError) {
    throw _socketException(operation, result.error.code);
  }
  return result.value;
}

Pointer<win32.SOCKADDR> _address(InternetAddress address, int port) {
  final result = calloc<win32.SOCKADDR>();
  result.ref.sa_family = win32.AF_INET;
  final bytes = result.cast<Uint8>().asTypedList(sizeOf<win32.SOCKADDR>());
  // sockaddr_in 的端口与 IPv4 地址均按网络字节序存储。
  bytes[2] = port >> 8;
  bytes[3] = port & 0xff;
  bytes.setRange(4, 8, address.rawAddress);
  return result;
}

int _port(Pointer<win32.SOCKADDR> address) {
  final bytes = address.cast<Uint8>().asTypedList(4);
  return (bytes[2] << 8) | bytes[3];
}

/// Windows 非阻塞 UDP：发送目的固定于配置，接收保留任意来源与空数据报。
///
/// [datagrams] 是唯一接收事实源，[chunks] 仅投影其中的数据，不另读 socket。
/// 可读事件唤醒后每轮最多处理 64 报或约 256 KiB。
class WindowsUdpTransport implements ByteTransport {
  WindowsUdpTransport._(
    this._socket,
    this.boundPort,
    this._target,
    this._targetPort,
  );

  final win32.SOCKET _socket;
  final InternetAddress? _target;
  final int _targetPort;
  final _datagrams = StreamController<Datagram>.broadcast(sync: true);
  final _events = StreamController<TransportEvent>.broadcast();
  final _receiveBuffer = calloc<Uint8>(_maxPayload);
  final _peer = calloc<win32.SOCKADDR>();
  final _peerLength = calloc<Int32>();
  final _readEvents = calloc<native.WSANETWORKEVENTS>();
  Pointer<Void> _readEvent = nullptr;
  WindowsEventWait? _readWait;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// 实际本地端口；配置 0 时由系统分配。
  final int boundPort;

  Stream<Datagram> get datagrams => _datagrams.stream;

  @override
  Stream<Uint8List> get chunks => datagrams.map((packet) => packet.data);

  @override
  Stream<TransportEvent> get events => _events.stream;

  static Future<WindowsUdpTransport> open(UdpPrefs prefs) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsUdpTransport 仅支持 Windows');
    }
    if (!isValidLocalPort(prefs.localPort)) {
      throw ArgumentError.value(prefs.localPort, 'localPort', '本地端口无效');
    }
    final local = InternetAddress.tryParse(
      prefs.nicKey.isEmpty ? '0.0.0.0' : prefs.nicKey.trim(),
    );
    if (local == null || local.type != InternetAddressType.IPv4) {
      throw ArgumentError.value(prefs.nicKey, 'nicKey', '需要有效的本地 IPv4 地址');
    }
    final parsedTarget = InternetAddress.tryParse(prefs.targetHost.trim());
    final target =
        prefs.hasValidTarget && parsedTarget?.type == InternetAddressType.IPv4
        ? parsedTarget
        : null;

    // 使用真实 SDK 生成的 WSADATA 布局，缓冲只覆盖本次初始化。
    final startupData = calloc<native.WSAData>();
    try {
      final result = native.WSAStartup(0x0202, startupData);
      if (result != 0) throw _socketException('WSAStartup', result);
    } finally {
      calloc.free(startupData);
    }

    win32.SOCKET? socket;
    WindowsUdpTransport? openedTransport;
    try {
      socket = _checked(
        win32.socket(win32.AF_INET, win32.SOCK_DGRAM, _ipprotoUdp),
        'socket',
      );
      if (prefs.mode == UdpMode.broadcast) {
        final enabled = calloc<Int32>()..value = 1;
        try {
          if (native.setsockopt(
                socket,
                _solSocket,
                win32.SO_BROADCAST,
                enabled.cast(),
                sizeOf<Int32>(),
              ) ==
              _socketError) {
            throw _socketException('SO_BROADCAST');
          }
        } finally {
          calloc.free(enabled);
        }
      }
      final localAddress = _address(local, prefs.localPort);
      final length = calloc<Int32>()..value = sizeOf<win32.SOCKADDR>();
      late int boundPort;
      try {
        _checked(win32.bind(socket, localAddress, length.value), 'bind');
        _checked(
          win32.getsockname(socket, localAddress, length),
          'getsockname',
        );
        boundPort = _port(localAddress);
      } finally {
        calloc.free(length);
        calloc.free(localAddress);
      }
      final transport = WindowsUdpTransport._(
        socket,
        boundPort,
        target,
        prefs.targetPort,
      );
      openedTransport = transport;
      transport._watchReads();
      Timer.run(() {
        if (!transport._closed) {
          transport._events.add(
            TransportEvent(
              TransportEventType.opened,
              '${local.address}:$boundPort',
            ),
          );
        }
      });
      return transport;
    } catch (_) {
      if (openedTransport != null) {
        await openedTransport.close();
      } else {
        if (socket != null && socket != _socketError) win32.closesocket(socket);
        native.WSACleanup();
      }
      rethrow;
    }
  }

  void _watchReads() {
    _readEvent = native.WSACreateEvent();
    if (_readEvent == nullptr) throw _socketException('WSACreateEvent');
    if (native.WSAEventSelect(_socket, _readEvent, _fdRead) == _socketError) {
      throw _socketException('WSAEventSelect');
    }
    _readWait = WindowsEventWait(_onReadable)..watch(_readEvent);
  }

  void _onReadable() {
    if (_closed) return;
    if (native.WSAEnumNetworkEvents(_socket, _readEvent, _readEvents) ==
        _socketError) {
      _failReceive('WSAEnumNetworkEvents', native.WSAGetLastError());
      return;
    }
    final events = _readEvents.ref;
    if ((events.lNetworkEvents & _fdRead) != 0) {
      final error = events.iErrorCode[0];
      if (error != 0) {
        _failReceive('FD_READ', error);
        return;
      }
      _readAvailable();
    }
    // recvfrom 会重新启用 FD_READ。仍有积压时，重新注册即可继续分批处理。
    if (!_closed) _readWait!.watch(_readEvent);
  }

  void _failReceive(String operation, int code) {
    _events.add(
      TransportEvent(
        TransportEventType.error,
        _socketException(operation, code).toString(),
      ),
    );
    unawaited(close());
  }

  void _readAvailable() {
    if (_closed) return;
    var bytesRead = 0;
    for (
      var count = 0;
      !_closed && count < _packetsPerPoll && bytesRead < _bytesPerPoll;
      count++
    ) {
      _peerLength.value = sizeOf<win32.SOCKADDR>();
      final result = win32.recvfrom(
        _socket,
        win32.PSTR(_receiveBuffer.cast()),
        _maxPayload,
        0,
        _peer,
        _peerLength,
      );
      final received = result.value;
      if (received == _socketError) {
        final code = result.error.code;
        if (code == _wouldBlock) return;
        _failReceive('recvfrom', code);
        return;
      }
      // 复制原生复用缓冲后，以只读视图交给每个订阅者；空包同样保留来源。
      final addressBytes = _peer.cast<Uint8>().asTypedList(8);
      _datagrams.add(
        Datagram(
          Uint8List.fromList(_receiveBuffer.asTypedList(received))
              .asUnmodifiableView(),
          InternetAddress.fromRawAddress(
            Uint8List.fromList(addressBytes.sublist(4, 8)),
          ),
          _port(_peer),
        ),
      );
      bytesRead += received;
    }
  }

  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed) throw StateError('UDP 已关闭，无法发送');
    final target = _target;
    if (target == null) throw StateError('需要先配置有效的 IPv4 目的地址与端口');
    final address = _address(target, _targetPort);
    // 即使是空 payload 也提供有效指针，以 len=0 调用 sendto。
    final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final sent = _checked(
        win32.sendto(
          _socket,
          win32.PCSTR(buffer.cast()),
          bytes.length,
          0,
          address,
          sizeOf<win32.SOCKADDR>(),
        ),
        'sendto',
      );
      if (sent != bytes.length) {
        throw SocketException('UDP 数据报未完整发送：$sent/${bytes.length} 字节');
      }
    } finally {
      calloc.free(buffer);
      calloc.free(address);
    }
  }

  @override
  Future<void> close() {
    if (_closeFuture case final existing?) return existing;
    final result = win32.closesocket(_socket);
    if (result.value == _socketError) {
      return Future.error(_socketException('closesocket', result.error.code));
    }
    _closed = true;
    _readWait?.close();
    final eventError =
        _readEvent != nullptr && native.WSACloseEvent(_readEvent) == 0
        ? _socketException('WSACloseEvent')
        : null;
    calloc.free(_readEvents);
    calloc.free(_receiveBuffer);
    calloc.free(_peer);
    calloc.free(_peerLength);
    final cleanupResult = native.WSACleanup();
    final cleanupError = cleanupResult == 0
        ? null
        : _socketException('WSACleanup');
    _events.add(const TransportEvent(TransportEventType.closed));
    // 原生资源已释放；不让某个暂停的消费者拖住所有权释放。
    scheduleMicrotask(() {
      unawaited(_datagrams.close());
    });
    unawaited(_events.close());
    final error = eventError ?? cleanupError;
    return _closeFuture = error == null ? Future.value() : Future.error(error);
  }
}
