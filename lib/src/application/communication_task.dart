part of 'communication_runtime.dart';

enum ProtocolTaskKind { fileSend, fileReceive, firmware }

/// 每个任务的原始输入预算；输入与页面展示、其他任务互不借用。
class TaskInputBudget {
  const TaskInputBudget({this.bytes = 64 * 1024, this.entries = 128});
  final int bytes, entries;
}

class ProtocolTaskStart {
  const ProtocolTaskStart(this.connection, {this.channel, this.reason});
  final ConnectionSnapshot connection;
  final ProtocolTaskChannel? channel;
  final String? reason;
}

enum _TaskInputMode { undecided, bytes, raw }

/// 绑定连接、链路轮次与任务身份的独占协议通道。
class ProtocolTaskChannel {
  ProtocolTaskChannel._(this._runtime, this.connection, this.kind)
    : taskId = 'task-${++_runtime._nextTaskId}',
      ready = Future.wait(_runtime._connections[connection.id]!.writes.toList())
          .then((_) {});
  final CommunicationRuntime _runtime;
  final ConnectionSnapshot connection;
  final ProtocolTaskKind kind;
  final String taskId;

  /// 输入已登记；首次写入还须等待之前的 native 写入确认结束。
  final Future<void> ready;
  final _released = Completer<void>();
  final _stopped = Completer<void>();
  final _releaseFailure = Completer<Object>();
  Future<Object> get releaseFailure => _releaseFailure.future;
  Future<void> _waitReleasedOrFailure() => Future.any([
    released,
    releaseFailure.then<void>((error) => throw StateError('任务资源释放未确认：$error')),
  ]);
  Future<void> get stopped => _stopped.future;
  Future<void>? _owner;

  /// 在启动协议/进程前登记owner释放证明。owner清理不能等待released。
  void holdUntil(Future<void> ownerReleased) {
    if (!active || _owner != null) throw StateError('只能为活动任务登记一次owner');
    final confirmed = Completer<void>();
    _owner = confirmed.future;
    unawaited(
      ownerReleased.then(
        (_) => confirmed.complete(),
        onError: (Object error) {
          // owner失败不证明其清理完成；继续保留独占，禁止接续新任务。
          _reason = '任务资源释放未确认：$error';
          if (!_releaseFailure.isCompleted) _releaseFailure.complete(error);
          if (active) unawaited(cancel(_reason!));
          _runtime._bindingsChanged();
        },
      ),
    );
  }

  Future<void> get released => _released.future;
  bool _active = true;
  String? _reason;
  bool get active => _active;
  String? get reason => _reason;
  final Queue<RawPacket> _input = Queue();
  int _inputBytes = 0, _offset = 0;
  _TaskInputMode _mode = _TaskInputMode.undecided;
  MultiStreamController<RawPacket>? _raw;
  Completer<void>? _waiting;
  final Set<Future<void>> _writes = {};
  bool _ending = false, _reading = false, _rawListened = false;

  void _claim(_TaskInputMode mode) {
    if (_mode != _TaskInputMode.undecided && _mode != mode) {
      throw StateError('任务输入只能选择原始包或字节读取一种消费模式');
    }
    _mode = mode;
  }

  void _offer(RawPacket packet) {
    if (!active || packet.epoch != connection.epoch) return;
    final budget = _runtime.taskInputBudget;
    if (packet.bytes.length > budget.bytes) {
      unawaited(cancel('任务单包超出输入预算，数据不完整'));
      return;
    }
    final raw = _raw;
    if (raw != null) {
      raw.addSync(packet);
      return;
    }
    if (_inputBytes + packet.bytes.length > budget.bytes ||
        _input.length >= budget.entries) {
      unawaited(cancel('任务输入超出预算，数据不完整'));
      return;
    }
    _input.add(packet);
    _inputBytes += packet.bytes.length;
    _wake();
  }

  /// 保留真实来源与序号。单订阅，暂停会取消任务，防止隐式邮箱积压。
  Stream<RawPacket> get rawPackets {
    _claim(_TaskInputMode.raw);
    return Stream.multi((controller) {
      if (_rawListened || _raw != null) {
        controller.addErrorSync(StateError('任务原始输入只能消费一次'));
        controller.closeSync();
        return;
      }
      _rawListened = true;
      if (!active) {
        controller.closeSync();
        return;
      }
      _raw = controller;
      controller.onPause = () => unawaited(cancel('任务原始输入已暂停'));
      controller.onCancel = () {
        _raw = null;
        if (active && _owner == null) unawaited(cancel('任务原始输入订阅已取消'));
      };
      while (active && _input.isNotEmpty) {
        final packet = _input.removeFirst();
        _inputBytes -= packet.bytes.length;
        controller.addSync(packet);
      }
    });
  }

  void _wake() {
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  Future<bool> _wait(int timeoutMs) async {
    if (!active) return false;
    if (_input.isNotEmpty) return true;
    final waiting = _waiting = Completer<void>();
    final timer = Timer(Duration(milliseconds: timeoutMs), _wake);
    try {
      await waiting.future;
    } finally {
      timer.cancel();
      if (identical(_waiting, waiting)) _waiting = null;
    }
    return active && _input.isNotEmpty;
  }

  Future<Uint8List?> _read(int timeoutMs, bool byte) async {
    _claim(_TaskInputMode.bytes);
    if (_reading) throw StateError('任务不能并发读取字节');
    _reading = true;
    try {
      while (await _wait(timeoutMs)) {
        final packet = _input.first;
        final available = packet.bytes.length - _offset;
        if (available == 0) {
          _input.removeFirst();
          _offset = 0;
          continue;
        }
        final count = byte ? 1 : available.clamp(0, 16384);
        final result = Uint8List.fromList(
          packet.bytes.sublist(_offset, _offset + count),
        );
        _offset += count;
        if (_offset == packet.bytes.length) {
          _inputBytes -= packet.bytes.length;
          _input.removeFirst();
          _offset = 0;
        }
        return result;
      }
      return null;
    } finally {
      _reading = false;
    }
  }

  Future<int?> readByte(int timeoutMs) async =>
      (await _read(timeoutMs, true))?.first;
  Future<Uint8List?> readData(int timeoutMs) => _read(timeoutMs, false);

  Future<SerialWriteResult> write(
    Uint8List bytes, {
    int timeoutMs = 5000,
  }) async {
    if (!active) {
      return SerialWriteResult.failure(reason ?? '任务已结束', acceptedBytes: 0);
    }
    final c = _runtime._connections[connection.id];
    final budget = _runtime.sendBudget;
    if (bytes.length > budget.maxWriteBytes ||
        (c != null &&
            (c.sendEntries >= budget.entries ||
                c.sendBytes + bytes.length > budget.bytes))) {
      return SerialWriteResult.failure('发送队列已满或内容超出预算', acceptedBytes: 0);
    }
    // 调用时复制内容，等待 ready 期间调用者修改草稿不会改变本次请求。
    final snapshot = Uint8List.fromList(bytes);
    final done = Completer<void>();
    _writes.add(done.future);
    var submitted = false;
    try {
      // ready之前同样立即入权威FIFO，实际提交由native屏障串行推进。
      final result = await _runtime._enqueue(
        connection.id,
        snapshot,
        timeoutMs,
        expectedEpoch: connection.epoch,
        scope: this,
      );
      submitted = true;
      // 将独立 native 屏障留在本任务，结果本身可以先到达。
      unawaited(
        result.settled.then((_) {
          _writes.remove(done.future);
          done.complete();
        }),
      );
      return result;
    } finally {
      if (!submitted) {
        _writes.remove(done.future);
        done.complete();
      }
    }
  }

  Future<void> cancel([String reason = '用户停止']) {
    if (!active) return released;
    _reason = reason;
    return _end();
  }

  Future<void> finish() => _end();

  Future<void> _end() {
    if (_ending) return released;
    _ending = true;
    _active = false;
    _stopped.complete();
    _input.clear();
    _inputBytes = _offset = 0;
    _wake();
    final raw = _raw;
    _raw = null;
    raw?.closeSync();
    final c = _runtime._connections[connection.id];
    if (c != null && identical(c.task, this)) {
      for (final entry in c.queue.toList()) {
        if (!identical(entry.scope, this)) continue;
        c.queue.remove(entry);
        _runtime._retire(c, entry);
        entry.result.complete(
          SerialWriteResult.failure(reason ?? '任务已结束', acceptedBytes: 0),
        );
      }
      final transport = c.transport;
      if (_runtime._canWrite(c) &&
          transport is CancellableCommunicationTransport &&
          c.activeWrites.values.any((e) => identical(e.scope, this))) {
        unawaited(
          Future<void>.sync(
            () =>
                (transport as CancellableCommunicationTransport).cancelWrite(),
          ).catchError((Object error) {
            if (!_released.isCompleted) {
              _reason = '${reason ?? '任务结束'}；取消写入未确认：$error';
              _runtime._bindingsChanged();
            }
          }),
        );
      }
    }
    unawaited(() async {
      await ready;
      await Future.wait(_writes.toList());
      await _owner;
      if (c != null && identical(c.task, this)) c.task = null;
      _released.complete();
      _runtime._bindingsChanged();
    }());
    _runtime._bindingsChanged();
    return released;
  }
}

extension ProtocolTasks on CommunicationRuntime {
  ProtocolTaskStart? beginProtocolTask(String id, ProtocolTaskKind kind) {
    final c = _connections[id];
    if (_disposed || c == null) return null;
    final reason = c.definition.serial == null
        ? '该任务仅支持串口连接'
        : !_canWrite(c)
        ? '连接当前不可发送'
        : c.task != null
        ? '连接已有协议任务或正在释放'
        : null;
    if (reason != null) return ProtocolTaskStart(c.snapshot, reason: reason);
    final channel = ProtocolTaskChannel._(this, c.snapshot, kind);
    c.task = channel;
    _clearQueue(c, '协议任务独占连接，旧待写未执行');
    stopLoop(id, reason: '协议任务已启动');
    return ProtocolTaskStart(channel.connection, channel: channel);
  }

  ProtocolTaskChannel? taskFor(String id) => _connections[id]?.task;

  void _validateTasks() {
    for (final c in _connections.values.toList()) {
      final task = c.task;
      if (task == null || !task.active) continue;
      if (_disposed || c.epoch != task.connection.epoch || !_canWrite(c)) {
        unawaited(task.cancel('连接已断开或链路轮次已变化'));
      }
    }
  }
}
