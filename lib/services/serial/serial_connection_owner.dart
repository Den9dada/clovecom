import 'dart:async';
import 'dart:typed_data';

import '../../models/serial_port_model.dart';
import 'serial_byte_transport.dart';

/// 遗留单连接租约适配器，保留既有异步关闭契约与兼容测试。
/// 当前应用由 CommunicationRuntime 唯一仲裁物理连接，新代码不从此处打开。
///
/// 深模块：调用方只需 [open]（或注入工厂的 [acquire]）一个接口；租约登记、
/// 占用拒绝（不排队）、随 close 释放、防误释新租约等不变量全部内化。
/// 删除它会把端口仲裁逻辑散落到每个持有连接的 ViewModel，复杂度重现。
///
/// 落实 CONTEXT.md 的“串口传输会话”不变量：同一物理串口同时至多承载一个
/// 会话，独占性跨页面成立——由本所有者在连接层强制，而非各页面自律。
class SerialConnectionOwner {
  SerialConnectionOwner();

  /// 遗留入口；当前应用页面均使用根组件注入的 CommunicationRuntime。
  static final SerialConnectionOwner instance = SerialConnectionOwner();

  final Map<String, _LeasedTransport> _leases = {};

  /// 端口当前是否被租用。
  bool isLeased(String portName) => _leases.containsKey(portName);

  /// 以默认 Win32 传输打开并租用端口；已被占用则抛 [StateError]（拒绝，不排队）。
  SerialByteTransport open(SerialPortConfig config) =>
      acquire(config, Win32SerialTransport.new);

  /// 租用端口：先查租约再打开，打开失败不登记租约。
  /// [open] 为传输工厂（测试注入假适配器）。返回的租约传输在 close 时释放租约。
  SerialByteTransport acquire(
    SerialPortConfig config,
    SerialByteTransport Function(SerialPortConfig) open,
  ) {
    final port = config.portName;
    if (_leases.containsKey(port)) {
      throw StateError('串口 $port 已被其他页面占用，请先断开当前连接');
    }
    final inner = open(config);
    final lease = _LeasedTransport(this, port, inner);
    _leases[port] = lease;
    return lease;
  }

  void _release(String port, _LeasedTransport lease) {
    // 仅当当前租约仍是本租约时移除，避免误释后来者的新租约。
    if (identical(_leases[port], lease)) {
      _leases.remove(port);
    }
  }
}

/// 租约传输：底层关闭和在途写都结束后才释放租约。
class _LeasedTransport implements SerialByteTransport {
  _LeasedTransport(this._owner, this._port, this._inner);
  final SerialConnectionOwner _owner;
  final String _port;
  final SerialByteTransport _inner;
  bool _released = false;
  Future<void>? _closing;
  final Set<Future<void>> _writes = {};

  @override
  Stream<Uint8List> get chunks => _inner.chunks;

  @override
  Future<SerialWriteResult> send(Uint8List bytes, int timeoutMs) async {
    if (_released) return SerialWriteResult.failure('串口正在关闭', acceptedBytes: 0);
    final finished = Completer<void>();
    _writes.add(finished.future);
    try {
      final result = await _inner.send(bytes, timeoutMs);
      await result.settled;
      return result;
    } finally {
      _writes.remove(finished.future);
      finished.complete();
    }
  }

  @override
  void purge() => _inner.purge();

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _released = true;
    // 关闭须发起底层取消；完成证明与在途写都满足后才释放租约。
    await _inner.close();
    await Future.wait(_writes.toList());
    _owner._release(_port, this);
  }
}
