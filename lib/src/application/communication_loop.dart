part of 'communication_runtime.dart';

const _workerLoopMaxBytes = SerialWorkerLoop.maxPayloadBytes;
const _workerLoopMinimumReservation = 256;

enum LoopPhase { waiting, running, delayed, stopped }

class LoopTargetSnapshot {
  const LoopTargetSnapshot({
    required this.connectionId,
    required this.name,
    required this.epoch,
    required this.phase,
    required this.completedRounds,
    required this.awaitingSettlement,
    this.reason,
    this.lastResult,
    this.workerTiming,
  });
  final String connectionId, name;
  final int epoch, completedRounds;
  final LoopPhase phase;
  final bool awaitingSettlement;
  final String? reason;
  final SendTargetResult? lastResult;
  final SerialWorkerTiming? workerTiming;
}

class _LoopRun {
  _LoopRun(
    this.connection,
    this.interval,
    this.timeoutMs,
    this.bytes,
    this.clock,
  ) : nextTick = interval.inMicroseconds;
  final Stopwatch clock;
  int nextTick;

  // 跳过已经错过的节拍，保留原来的周期相位。
  void advanceTick() {
    final now = clock.elapsedMicroseconds;
    final period = interval.inMicroseconds;
    if (nextTick <= now) {
      nextTick += ((now - nextTick) ~/ period + 1) * period;
    }
  }

  Duration get untilNextTick {
    final remaining = nextTick - clock.elapsedMicroseconds;
    if (remaining <= 0) return Duration.zero;
    // Timer 以毫秒调度，向上取整避免反复触发零延迟计时器。
    return Duration(milliseconds: (remaining + 999) ~/ 1000);
  }

  Uint8List bytes;
  final ConnectionSnapshot connection;
  final int timeoutMs;
  final Duration interval;
  bool active = true, awaitingSettlement = false;
  LoopPhase phase = LoopPhase.waiting;
  String? reason;
  int completedRounds = 0;
  int workerReservedBytes = 0;
  SendTargetResult? lastResult;
  SerialWorkerTiming? workerTiming;
  Timer? timer;
  SerialWorkerLoop? worker;
  bool waitingForWorker = false,
      workerImmediate = false,
      workerUnavailable = false;
  WindowsHighResolutionTimer? preciseTimer;
  bool preciseTimerUnavailable = false;
  LoopTargetSnapshot get snapshot => LoopTargetSnapshot(
    connectionId: connection.id,
    name: connection.name,
    epoch: connection.epoch,
    phase: phase,
    completedRounds: completedRounds,
    awaitingSettlement: awaitingSettlement,
    reason: reason,
    lastResult: lastResult,
    workerTiming: workerTiming,
  );
}

extension on CommunicationRuntime {
  void _validateLoops() {
    for (final run in _loops.values.toList()) {
      if (!run.active) continue;
      final c = _connections[run.connection.id];
      if (_disposed ||
          c == null ||
          c.epoch != run.connection.epoch ||
          !_canWrite(c)) {
        _stopLoopRun(run, '连接已断开或链路轮次已变化');
      }
    }
  }

  void _stopLoopRun(_LoopRun run, String reason) {
    if (!run.active) return;
    run.active = false;
    run.waitingForWorker = false;
    run.worker?.stop(cancelInFlight: true);
    run.timer?.cancel();
    run.preciseTimer?.close();
    run.preciseTimer = null;
    run.phase = LoopPhase.stopped;
    run.reason = reason;
    final c = _connections[run.connection.id];
    if (c == null) return;
    // 只撤销本次循环的待写，不误伤手动发送或下一次运行。
    for (final entry in c.queue.toList()) {
      if (!identical(entry.scope, run)) continue;
      c.queue.remove(entry);
      _retire(c, entry);
      entry.result.complete(
        SerialWriteResult.failure(reason, acceptedBytes: 0),
      );
    }
    final transport = c.transport;
    if (_canWrite(c) &&
        transport is CancellableCommunicationTransport &&
        c.activeWrites.values.any((entry) => identical(entry.scope, run))) {
      // cancel 返回不替代 settled；在途屏障仍由内核持有。
      unawaited(
        Future<void>.sync(
          () => (transport as CancellableCommunicationTransport).cancelWrite(),
        ).catchError((Object error) {
          // 只更新旧运行自己的状态，不污染重启后的循环或新链路。
          if (run.awaitingSettlement) {
            run.reason = '$reason；取消写入未确认：$error';
            _notifyLoopProgress();
          }
        }),
      );
    }
  }

  int get _workerLoopBudget => min(
    _workerLoopMaxBytes,
    min(sendBudget.maxWriteBytes, sendBudget.bytes - 1),
  );

  bool _canUseWorkerLoop(_Connection c, _LoopRun run) {
    final transport = c.transport;
    return _nativeLoopTimer &&
        !run.workerUnavailable &&
        transport is SerialCommunicationTransport &&
        transport.supportsWorkerLoop(run.interval) &&
        sendBudget.entries > 1 &&
        _workerLoopBudget >= _workerLoopMinimumReservation &&
        run.bytes.length <= _workerLoopBudget;
  }

  void _beginLoop(_Connection c, _LoopRun run, {required bool immediate}) {
    if (_canUseWorkerLoop(c, run)) {
      run.waitingForWorker = true;
      run.workerImmediate = immediate;
      run.phase = LoopPhase.delayed;
      run.reason = '等待连接发送队列';
      _pump(c);
      return;
    }
    if (immediate) {
      unawaited(_loopRound(run));
    } else {
      _scheduleLoop(run);
    }
  }

  void _startWorkerLoop(_Connection c, _LoopRun run) {
    run.waitingForWorker = false;
    if (!_canWrite(c) || c.epoch != run.connection.epoch || c.task != null) {
      _stopLoopRun(run, '连接不可发送或已交给协议任务');
      return;
    }
    final writer = _sessionWriters[run.connection.id];
    final previousTiming = run.workerTiming;
    final worker = _canUseWorkerLoop(c, run)
        ? (c.transport! as SerialCommunicationTransport).startWorkerLoop(
            run.bytes,
            interval: run.interval,
            timeoutMs: run.timeoutMs,
            immediate: run.workerImmediate,
            onRounds: (rounds, timing) =>
                _acceptWorkerRounds(run, writer, rounds, (
                  usesNativeWriter: timing.usesNativeWriter,
                  timerSkipped:
                      (previousTiming?.timerSkipped ?? 0) + timing.timerSkipped,
                  completionPollSkipped:
                      (previousTiming?.completionPollSkipped ?? 0) +
                      timing.completionPollSkipped,
                  rearmSkipped:
                      (previousTiming?.rearmSkipped ?? 0) + timing.rearmSkipped,
                )),
          )
        : null;
    if (worker == null) {
      run.workerUnavailable = true;
      _beginLoop(c, run, immediate: run.workerImmediate);
      return;
    }

    // 占用与普通在途写相同的发送屏障。手动发送先让 worker 停止新轮次，
    // 协议任务和关闭则等到最后一次原生写入终结后才能交接。
    final barrier = Completer<void>();
    c.writes.add(barrier.future);
    c.sendEntries++;
    run.workerReservedBytes = max(
      _workerLoopMinimumReservation,
      run.bytes.length,
    );
    c.sendBytes += run.workerReservedBytes;
    c.workerLoop = run.worker = worker;
    run.awaitingSettlement = true;
    run.phase = run.bytes.isEmpty ? LoopPhase.waiting : LoopPhase.running;
    run.reason = run.bytes.isEmpty ? '草稿为空，等待有效内容' : null;
    unawaited(
      worker.done.then((status) {
        c.workerLoop = run.worker = null;
        c.writes.remove(barrier.future);
        c.sendEntries--;
        c.sendBytes -= run.workerReservedBytes;
        run.workerReservedBytes = 0;
        run.awaitingSettlement = false;
        barrier.complete();
        if (run.active) {
          if (status.reason case final reason?) {
            _stopLoopRun(run, reason);
            _bindingsChanged();
          } else if (_canWrite(c) &&
              c.epoch == run.connection.epoch &&
              c.task == null) {
            if (status.unavailable) run.workerUnavailable = true;
            _beginLoop(c, run, immediate: false);
          } else {
            _stopLoopRun(run, '连接不可发送或已交给协议任务');
          }
        }
        _pump(c);
        _notifyLoopProgress();
      }),
    );
  }

  void _acceptWorkerRounds(
    _LoopRun run,
    _SessionWriteObserver? writer,
    List<SerialWorkerRound> rounds,
    SerialWorkerTiming timing,
  ) {
    run.workerTiming = timing;
    for (final round in rounds) {
      _recordAccepted(
        writer,
        round.bytes,
        run.connection.epoch,
        round.accepted,
        timestampMicros: round.timestampMicros,
        takeOwnedPayload: true,
      );
    }
    run.completedRounds += rounds.length;
    final round = rounds.last;
    final result = SerialWriteResult(
      succeeded: round.reason == null && round.accepted == round.bytes.length,
      acceptedBytes: round.accepted,
      reason: round.reason,
    );
    run.lastResult = SendTargetResult(
      connectionId: run.connection.id,
      name: run.connection.name,
      epoch: run.connection.epoch,
      requestedBytes: round.bytes.length,
      acceptedBytes: round.accepted,
      reason: round.reason,
      settled: result.settled,
      outcome: classifySendResult(
        result,
        started: true,
        requestedBytes: round.bytes.length,
      ),
    );
    _notifyLoopProgress();
  }

  void _scheduleLoop(_LoopRun run) {
    if (!run.active) return;
    run.phase = LoopPhase.waiting;
    run.reason = null;
    run.advanceTick();
    if (_nativeLoopTimer &&
        run.interval.inMicroseconds < 5000 &&
        !run.preciseTimerUnavailable) {
      try {
        final timer = run.preciseTimer ??= WindowsHighResolutionTimer(
          () => _wakeLoop(run),
        );
        timer.arm(run.nextTick - run.clock.elapsedMicroseconds);
        return;
      } catch (_) {
        run.preciseTimer?.close();
        run.preciseTimer = null;
        run.preciseTimerUnavailable = true;
      }
    }
    run.timer = Timer(run.untilNextTick, () => _wakeLoop(run));
  }

  void _wakeLoop(_LoopRun run) {
    if (!run.active) return;
    if (run.clock.elapsedMicroseconds < run.nextTick) {
      _scheduleLoop(run);
    } else {
      unawaited(_loopRound(run));
    }
  }

  Future<void> _loopRound(_LoopRun run) async {
    _validateLoops();
    if (!run.active) return;
    run.advanceTick();
    final bytes = run.bytes;
    if (bytes.isEmpty) {
      _scheduleLoop(run);
      run.reason = '草稿为空，等待有效内容';
      _notifyLoopProgress();
      return;
    }
    var started = false;
    run.phase = LoopPhase.delayed;
    run.reason = '等待连接发送队列';
    run.timer = Timer(run.untilNextTick, () {
      if (!run.active) return;
      run.phase = LoopPhase.delayed;
      run.reason = '上一轮尚未确认结束，已延后';
      _notifyLoopProgress();
    });
    final result = await _enqueue(
      run.connection.id,
      bytes,
      run.timeoutMs,
      expectedEpoch: run.connection.epoch,
      scope: run,
      onStarted: () {
        started = true;
        run.awaitingSettlement = true;
        if (!run.active) return;
        run.phase = LoopPhase.running;
        run.reason = null;
        // 等内核登记并提交在途写后再通知，监听者可立即安全停止。
        scheduleMicrotask(_notifyLoopProgress);
      },
    );
    final count = result.acceptedBytes;
    run.lastResult = SendTargetResult(
      connectionId: run.connection.id,
      name: run.connection.name,
      epoch: run.connection.epoch,
      requestedBytes: bytes.length,
      acceptedBytes: count,
      reason: result.reason,
      settled: result.settled,
      outcome: classifySendResult(
        result,
        started: started,
        requestedBytes: bytes.length,
      ),
    );
    _notifyLoopProgress();
    // 结果可以提前超时；未知底层结束时绝不继续排下一轮。
    await result.settled;
    run.timer?.cancel();
    run.awaitingSettlement = false;
    if (started) run.completedRounds++;
    if (!run.active) {
      _notifyLoopProgress();
      return;
    }
    if (!result.succeeded) {
      _stopLoopRun(run, result.reason ?? '本轮未完整发送，请手动重新启动');
      _bindingsChanged();
    } else {
      _scheduleLoop(run);
      _notifyLoopProgress();
    }
  }
}
