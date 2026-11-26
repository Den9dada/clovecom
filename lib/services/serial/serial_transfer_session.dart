import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import '../../protocols/transfer_protocol.dart';

enum SerialTransferKind { send, receive, firmware }

/// 一个端口只有一个活动任务；旧任务的回调不能影响新任务。
class SerialTransferController {
  SerialTransferSession? _active;
  SerialTransferSession? get active => _active;
  bool get isBusy => _active != null;

  SerialTransferSession begin(
    SerialTransferKind kind, {
    required Future<bool> Function(Uint8List, int) write,
  }) {
    if (isBusy) throw StateError('已有串口传输任务，请先停止当前任务');
    final session = SerialTransferSession._(this, kind, write);
    _active = session;
    return session;
  }

  void cancel() => _active?.cancel();
  bool accept(Uint8List bytes) {
    final session = _active;
    if (session == null) return false;
    session._accept(bytes);
    return true;
  }
}

class SerialTransferSession {
  SerialTransferSession._(this._owner, this.kind, this._write);
  final SerialTransferController _owner;
  final SerialTransferKind kind;
  final Future<bool> Function(Uint8List, int) _write;
  final Queue<int> _bytes = Queue<int>();
  final List<void Function()> _cleanup = [];
  final Completer<void> _done = Completer<void>();
  Completer<void>? _waiting;
  void Function(Uint8List)? onData;
  int _inFlight = 0;
  bool _finishing = false;
  bool _cancelled = false;
  bool _closed = false;
  bool _completed = false;
  bool _hasFailed = false;
  bool get completed => _completed;
  bool get hasFailed => _hasFailed;
  bool get isActive =>
      !_closed && !_finishing && identical(_owner.active, this);
  bool get isCancelled => _cancelled || hasFailed || !isActive;
  Future<void> get done => _done.future;

  void addCleanup(void Function() cleanup) {
    if (!isActive) {
      cleanup();
      return;
    }
    _cleanup.add(cleanup);
  }

  Future<bool> write(Uint8List bytes, int timeoutMs) async {
    if (!isActive || hasFailed || completed) return false;
    _inFlight++;
    try {
      final succeeded = await _write(bytes, timeoutMs);
      return isActive && !hasFailed && !completed && succeeded;
    } finally {
      _inFlight--;
      if (_finishing && _inFlight == 0) _release();
    }
  }

  /// 协议只接触会话字节通道，通知不会越过会话生命周期。
  TransferCallbacks callbacks({
    required void Function(double) onProgress,
    required void Function(String) onLog,
    required void Function(String) onError,
    required void Function(int) onComplete,
    String fileName = '',
    void Function(String, int)? onFileInfo,
  }) => TransferCallbacks(
    onProgress: (value) {
      if (isActive && !hasFailed && !completed) onProgress(value);
    },
    onLog: (value) {
      if (isActive) onLog(value);
    },
    onError: (value) {
      if (!isActive || completed || hasFailed) return;
      _hasFailed = true;
      final waiting = _waiting;
      if (waiting != null && !waiting.isCompleted) waiting.complete();
      onError(value);
    },
    onComplete: (value) {
      if (!isActive || hasFailed || completed) return;
      _completed = true;
      onComplete(value);
    },
    onWaitByte: readByte,
    onWaitData: readData,
    isCancelled: () => isCancelled,
    onWrite: write,
    fileName: fileName,
    onFileInfo: (name, size) {
      if (isActive && !hasFailed) onFileInfo?.call(name, size);
    },
  );

  void _accept(Uint8List data) {
    if (!isActive || data.isEmpty) return;
    final relay = onData;
    if (relay != null) {
      relay(Uint8List.fromList(data));
      return;
    }
    _bytes.addAll(data);
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  Future<bool> _wait(int timeoutMs) async {
    if (isCancelled) return false;
    if (_bytes.isNotEmpty) return true;
    if (_waiting != null) throw StateError('同一传输会话不能并发读取');
    final waiting = Completer<void>();
    _waiting = waiting;
    final timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!waiting.isCompleted) waiting.complete();
    });
    try {
      await waiting.future;
    } finally {
      timer.cancel();
      if (identical(_waiting, waiting)) _waiting = null;
    }
    return !isCancelled && _bytes.isNotEmpty;
  }

  Future<int?> readByte(int timeoutMs) async {
    if (!await _wait(timeoutMs) || isCancelled || _bytes.isEmpty) return null;
    return _bytes.removeFirst();
  }

  Future<Uint8List?> readData(int timeoutMs) async {
    if (!await _wait(timeoutMs) || isCancelled || _bytes.isEmpty) return null;
    final data = Uint8List.fromList(_bytes.toList());
    _bytes.clear();
    return data;
  }

  Future<void> delay(Duration duration) async {
    final elapsed = Completer<void>();
    final timer = Timer(duration, elapsed.complete);
    try {
      await Future.any([elapsed.future, done]);
    } finally {
      timer.cancel();
    }
  }

  void cancel() {
    _cancelled = true;
    finish();
  }

  void finish() {
    if (_closed || _finishing) return;
    _finishing = true;
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    if (_inFlight == 0) _release();
  }

  void _release() {
    if (_closed) return;
    _closed = true;
    if (identical(_owner._active, this)) _owner._active = null;
    _bytes.clear();
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    _done.complete();
    onData = null;
    for (final cleanup in _cleanup.reversed) {
      try {
        cleanup();
      } catch (_) {
        /* 继续释放其余资源。 */
      }
    }
    _cleanup.clear();
  }
}
