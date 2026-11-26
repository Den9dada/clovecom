part of 'serial_byte_transport.dart';

typedef SerialWorkerRound = ({
  Uint8List bytes,
  int? accepted,
  String? reason,
  int timestampMicros,
});

typedef SerialWorkerTiming = ({
  bool usesNativeWriter,
  int timerSkipped,
  int completionPollSkipped,
  int rearmSkipped,
});

/// 发送权的结束证明与确认数据经过同一消息通道，先交付记录再交还发送权。
class SerialWorkerLoop {
  static const maxPayloadBytes = NativeSerialLoop.maxPayloadBytes;
  static const _dartPeriodLimit = 5000;

  SerialWorkerLoop._(this._id, this._commands, this._onRounds);
  final int _id;
  final SendPort _commands;
  final void Function(List<SerialWorkerRound>, SerialWorkerTiming) _onRounds;
  final _done = Completer<({String? reason, bool unavailable})>();
  bool _stopping = false, _cancelling = false;

  Future<({String? reason, bool unavailable})> get done => _done.future;

  void update(Uint8List bytes) {
    RangeError.checkValueInInterval(bytes.length, 0, maxPayloadBytes);
    if (!_stopping && !_done.isCompleted) {
      _commands.send(['loopUpdate', _id, bytes]);
    }
  }

  void stop({required bool cancelInFlight}) {
    if (_done.isCompleted || (_stopping && (!cancelInFlight || _cancelling))) {
      return;
    }
    _stopping = true;
    _cancelling = cancelInFlight;
    _commands.send(['loopStop', _id, cancelInFlight]);
  }
}

class _WorkerLoop {
  _WorkerLoop(this.worker, this.id, this.bytes, this.period, this.timeoutMs);
  final _SerialWorker worker;
  final int id, period, timeoutMs;
  Uint8List bytes;
  WindowsHighResolutionTimer? _timer;
  NativeSerialLoop? _native;
  bool _usesNativeWriter = false;
  String? _nativeFault;
  int _nextTick = 0;
  int _timerSkipped = 0, _completionPollSkipped = 0, _rearmSkipped = 0;
  bool _armed = false, _stopping = false, _credit = true;
  String? _failure;
  List<SerialWorkerRound> _rounds = [];
  static const _maxPending = 128;

  int get _now => worker.clock.elapsedMicroseconds;

  void start({required bool immediate}) {
    final driver = worker.driver;
    if (driver is Win32SerialDriver &&
        NativeSerialLoop.supportsPeriod(period)) {
      _native = driver.startNativeLoop(
        bytes,
        period,
        timeoutMs,
        immediate: immediate,
      );
      if (_native case final native?) {
        _usesNativeWriter = true;
        native.watchRounds(collectAndPublishRounds);
        return;
      }
    }
    if (period >= SerialWorkerLoop._dartPeriodLimit) {
      _finish(unavailable: true);
      return;
    }
    try {
      _timer = WindowsHighResolutionTimer(_tick);
    } catch (_) {
      _finish(unavailable: true);
      return;
    }
    _nextTick = _now + (immediate ? 0 : period);
    if (immediate && bytes.isNotEmpty) {
      _tick();
    } else {
      _schedule();
    }
  }

  void update(Uint8List next) {
    if (_stopping) return;
    bytes = next;
    _native?.update(next);
    if (!_armed) _schedule();
  }

  void _schedule() {
    if (_native != null ||
        _stopping ||
        _armed ||
        worker.write != null ||
        bytes.isEmpty ||
        _rounds.length >= _maxPending) {
      return;
    }
    final now = _now;
    if (_nextTick <= now) {
      final skipped = (now - _nextTick) ~/ period + 1;
      _rearmSkipped += skipped;
      _nextTick += skipped * period;
    }
    try {
      _armed = true;
      _timer!.arm(_nextTick - _now);
    } catch (_) {
      _finish(unavailable: true);
    }
  }

  void _tick() {
    if (_stopping) return;
    // 前一笔的完成唤醒可能还在队列里。到达节拍时查询一次原生终态。
    // 查询期间保留已安排标记，onRound 不再为同一个节拍安排第二个定时器。
    final started = _now;
    final hadWrite = worker.write != null;
    if (hadWrite) worker.pump(pollReceive: false);
    _armed = false;
    if (_stopping ||
        worker.write != null ||
        bytes.isEmpty ||
        _rounds.length >= _maxPending) {
      return;
    }
    final now = hadWrite ? _now : started;
    if (now < _nextTick) {
      _schedule();
      return;
    }
    final skipped = (now - _nextTick) ~/ period;
    // 回调尚未开始和回调内原生终态查询，分别统计漏拍。
    if (skipped != 0) {
      final beforePoll = math.max(0, started - _nextTick) ~/ period;
      _timerSkipped += beforePoll;
      _completionPollSkipped += skipped - beforePoll;
    }
    _nextTick += (skipped + 1) * period;
    // 下一拍先交给 Windows。超过一个周期仍在途时，暂停计时直到写入结束。
    _schedule();
    if (_stopping) return;
    worker.beginWrite(id, bytes, timeoutMs, owner: this);
    worker.pump();
  }

  void onRound(
    Uint8List payload,
    int? count,
    String? reason, {
    required bool cancelled,
  }) {
    _rounds.add((
      bytes: payload,
      accepted: count,
      reason: reason,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    ));
    if (_stopping || reason != null) {
      if (!cancelled) _failure ??= reason;
      _finish();
    } else {
      _schedule();
    }
  }

  void collectAndPublishRounds() {
    if (_native case final current?) {
      final collect = _credit || _stopping;
      final status = current.drain(_acceptNativeRound, collect: collect);
      _timerSkipped = status.skipped;
      if (status.done) {
        if (!collect) current.drain(_acceptNativeRound, collect: true);
        if (status.error != 0) {
          _nativeFault ??= '串口原生循环等待失败：${status.error}';
          _failure ??= _nativeFault;
        }
        (worker.driver as Win32SerialDriver).releaseNativeLoop();
        _native = null;
        _finish();
        if (_nativeFault case final reason?) worker.fault(StateError(reason));
        return;
      }
    }
    publishRounds();
  }

  void _acceptNativeRound(NativeSerialRound round) {
    final cancelled = _stopping && round.error == ERROR_OPERATION_ABORTED;
    final String? reason;
    if (cancelled) {
      reason = _failure ?? '循环已停止';
    } else if (round.error == ERROR_TIMEOUT) {
      reason = '串口写入超时';
    } else if (round.error != 0) {
      reason = _nativeFault ??= '串口 I/O 失败：${round.error}';
    } else {
      reason = round.accepted == round.bytes.length ? null : '串口短写';
    }
    if (!cancelled) _failure ??= reason;
    _rounds.add((
      bytes: round.bytes,
      accepted: round.accepted,
      reason: reason,
      timestampMicros: round.timestampMicros,
    ));
  }

  void acknowledge() {
    _credit = true;
    if (_native != null) {
      collectAndPublishRounds();
      return;
    }
    if (_rounds.length >= _maxPending) publishRounds();
    _schedule();
  }

  void publishRounds({bool force = false}) {
    if (_rounds.isEmpty || (!_credit && !force)) return;
    _credit = false;
    final timing = (
      usesNativeWriter: _usesNativeWriter,
      timerSkipped: _timerSkipped,
      completionPollSkipped: _completionPollSkipped,
      rearmSkipped: _rearmSkipped,
    );
    worker.host.send(['loopRounds', id, _rounds, timing]);
    _rounds = [];
  }

  void stop({required bool cancelInFlight, String? reason}) {
    _stopping = true;
    _failure ??= reason;
    if (_native case final current?) {
      current.stop(cancelInFlight: cancelInFlight);
      return;
    }
    _timer?.close();
    _timer = null;
    final pending = worker.write;
    if (pending == null) {
      _finish();
    } else if (cancelInFlight) {
      worker.cancel(pending, reason ?? '循环已停止');
    }
  }

  void _finish({bool unavailable = false}) {
    _stopping = true;
    _timer?.close();
    _timer = null;
    publishRounds(force: true);
    worker.loop = null;
    worker.host.send(['loopStopped', id, _failure, unavailable]);
  }
}
