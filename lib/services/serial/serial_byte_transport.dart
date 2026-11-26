import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:win32/win32.dart' show ERROR_OPERATION_ABORTED, ERROR_TIMEOUT;

import '../../models/serial_port_model.dart';
import '../../src/io/windows_async_wait.dart';
import '../../src/io/recording.dart' show TransportInput;
import 'native_serial_loop.dart';
import 'serial_native_driver.dart';
import 'serial_write_result.dart';
import 'win32_serial_driver.dart';
export 'serial_native_driver.dart' show SerialReceiveOverrun;
export 'serial_write_result.dart';

part 'serial_worker_loop.dart';

abstract interface class SerialByteTransport {
  Stream<Uint8List> get chunks;
  Future<SerialWriteResult> send(Uint8List bytes, int timeoutMs);
  void purge();
  Future<void> close();
}

/// 可选能力：只取消调用时的写，完成 Future 才是原生终结证明。
abstract interface class CancellableSerialByteTransport {
  Future<void> cancelWrite();
}

/// 每连接一个真实 isolate；主 isolate 不接触任何原生句柄。
class Win32SerialTransport
    implements SerialByteTransport, CancellableSerialByteTransport {
  Win32SerialTransport(
    SerialPortConfig config, {
    SerialNativeDriverFactory? driverFactory,
  }) {
    _chunks = StreamController<Uint8List>(
      sync: true,
      onListen: _deliverRead,
      onPause: () => _paused = true,
      onResume: () {
        _paused = false;
        _deliverRead();
      },
      onCancel: () {
        _listening = false;
      },
    );
    _messages.listen(_receive);
    // 遗留构造入口可能只观察 chunks；静态 open 仍可 await 原始错误。
    unawaited(_ready.future.then((_) {}, onError: (Object _) {}));
    unawaited(_spawn(config, driverFactory ?? createWin32SerialDriver));
  }
  static Future<Win32SerialTransport> open(
    SerialPortConfig config, {
    SerialNativeDriverFactory? driverFactory,
  }) async {
    final transport = Win32SerialTransport(
      config,
      driverFactory: driverFactory,
    );
    await transport._ready.future;
    return transport;
  }

  static const maxWriteBytes = 1024 * 1024;
  static const readBatchBytes = 16 * 1024;
  final _messages = ReceivePort();
  final _ready = Completer<void>();
  final _closed = Completer<void>();
  late final StreamController<Uint8List> _chunks;
  SendPort? _commands;
  bool _nativeLoopAvailable = false;
  _HostWrite? _write;
  SerialWorkerLoop? _loop;
  int _nextId = 0;
  bool _closing = false;
  bool _paused = false;
  bool _listening = true;
  bool _purgePending = false;
  bool _readCreditOwed = false;
  Uint8List? _read;
  int _readOverrun = 0;
  Object? _failure;
  @override
  Stream<Uint8List> get chunks => _chunks.stream;

  /// 同一个单订阅流。串口 worker 已独立复制缓冲，宿主直接移交给会话。
  Stream<TransportInput> get inputs => chunks.map(TransportInput.takeOwned);

  Future<void> _spawn(
    SerialPortConfig config,
    SerialNativeDriverFactory factory,
  ) async {
    try {
      await Isolate.spawn(_serialWorker, (_messages.sendPort, config, factory));
    } catch (error, stack) {
      _openFailed(error, stack);
    }
  }

  void _receive(dynamic raw) {
    if (raw is Uint8List) {
      _acceptRead(raw, 0);
      return;
    }
    final m = raw as List;
    switch (m[0]) {
      case 'ready':
        _commands = m[1] as SendPort;
        _nativeLoopAvailable = m[2] as bool;
        _ready.complete();
        if (_closing) _commands!.send(['close']);
      case 'openError':
        _openFailed(StateError(m[1] as String), StackTrace.current);
      case 'rx':
        _acceptRead(m[1] as Uint8List?, m[2] as int);
      case 'result':
        final w = _write;
        if (w == null || w.id != m[1] || w.result.isCompleted) return;
        final terminal = m[5] == true;
        w.result.complete(
          SerialWriteResult(
            succeeded: m[2] as bool,
            acceptedBytes: m[3] as int?,
            reason: m[4] as String?,
            settled: terminal ? null : w.settled.future,
          ),
        );
        if (terminal) _settleWrite(w);
      case 'settled':
        final w = _write;
        if (w != null && w.id == m[1]) _settleWrite(w);
      case 'loopRounds':
        final loop = _loop;
        if (loop == null || loop._id != m[1]) return;
        try {
          loop._onRounds(
            m[2] as List<SerialWorkerRound>,
            m[3] as SerialWorkerTiming,
          );
        } finally {
          loop._commands.send(['loopCredit', loop._id]);
        }
      case 'loopStopped':
        final loop = _loop;
        if (loop != null && loop._id == m[1]) {
          _loop = null;
          loop._done.complete((
            reason: m[2] as String?,
            unavailable: m[3] as bool,
          ));
        }
      case 'fault':
        _failure = StateError(m[1] as String);
        _closing = true;
        // 故障最多一项；无监听者时在订阅建立后再投递。
        _deliverRead();
      case 'purged':
        _purgePending = false;
      case 'closed':
        _closing = true;
        if (_loop case final loop?) {
          _loop = null;
          loop._done.complete((reason: '串口已关闭', unavailable: false));
        }
        _messages.close();
        _closed.complete();
        _finishStream();
    }
  }

  void _settleWrite(_HostWrite write) {
    _write = null;
    write.settled.complete();
  }

  void _openFailed(Object error, StackTrace stack) {
    _closing = true;
    _failure = error;
    _ready.completeError(error, stack);
    _messages.close();
    _closed.complete();
    _deliverRead();
    _finishStream();
  }

  void _finishStream() {
    // 迟订阅也只能保留最后一个有界批次和一项故障；close 后不再 add。
    final error = _failure;
    _failure = null;
    if (error != null) _chunks.addError(error);
    _emitRead();
    _readCreditOwed = false;
    unawaited(_chunks.close());
  }

  void _acceptRead(Uint8List? bytes, int overrun) {
    _readCreditOwed = true;
    _read = bytes;
    _readOverrun = overrun;
    _deliverRead();
  }

  void _deliverRead() {
    if (!_listening || !_chunks.hasListener || _paused) return;
    final failure = _failure;
    if (failure != null) {
      _failure = null;
      _chunks.addError(failure);
    }
    _emitRead();
    // 同步交付后才给一个 credit；暂停不向 StreamController 堆积数据。
    if (!_paused && _readCreditOwed) {
      _readCreditOwed = false;
      _commands?.send(const ['credit']);
    }
  }

  void _emitRead() {
    final overrun = _readOverrun;
    final bytes = _read;
    _readOverrun = 0;
    _read = null;
    if (overrun != 0) _chunks.addError(SerialReceiveOverrun(overrun));
    if (bytes != null) _chunks.add(bytes);
  }

  @override
  Future<SerialWriteResult> send(Uint8List bytes, int timeoutMs) {
    if (_closing) {
      return Future.value(
        SerialWriteResult.failure('串口正在关闭', acceptedBytes: 0),
      );
    }
    if (_write != null || _loop != null) {
      return Future.value(
        SerialWriteResult.failure('当前写入尚未结束', acceptedBytes: 0),
      );
    }
    if (bytes.length > maxWriteBytes) {
      return Future.value(
        SerialWriteResult.failure('串口单次写入超过 1 MiB 上限', acceptedBytes: 0),
      );
    }
    if (bytes.isEmpty) return Future.value(SerialWriteResult.success(0));
    final w = _HostWrite(++_nextId);
    _write = w;
    final commands = _commands;
    if (commands != null) {
      // SendPort 立即复制可变数据，只在等待打开时需要提前保留快照。
      commands.send(['write', w.id, bytes, timeoutMs]);
      return w.result.future;
    }
    final snapshot = Uint8List.fromList(bytes);
    _ready.future.then(
      (_) {
        _commands!.send(['write', w.id, snapshot, timeoutMs]);
      },
      onError: (Object error) {
        _write = null;
        w.result.complete(
          SerialWriteResult.failure('$error', acceptedBytes: 0),
        );
        w.settled.complete();
      },
    );
    return w.result.future;
  }

  bool supportsWorkerLoop(Duration interval) {
    final period = interval.inMicroseconds;
    return period > 0 &&
        (period < SerialWorkerLoop._dartPeriodLimit ||
            (_nativeLoopAvailable && NativeSerialLoop.supportsPeriod(period)));
  }

  /// 在持有本连接发送权期间，由串口 isolate 独立安排短周期写入。
  SerialWorkerLoop? startWorkerLoop(
    Uint8List bytes, {
    required Duration interval,
    required int timeoutMs,
    required bool immediate,
    required void Function(List<SerialWorkerRound>, SerialWorkerTiming)
    onRounds,
  }) {
    if (!supportsWorkerLoop(interval) ||
        bytes.length > SerialWorkerLoop.maxPayloadBytes) {
      return null;
    }
    final commands = _commands;
    if (_closing || commands == null || _write != null || _loop != null) {
      return null;
    }
    final loop = _loop = SerialWorkerLoop._(++_nextId, commands, onRounds);
    commands.send([
      'loopStart',
      loop._id,
      bytes,
      interval.inMicroseconds,
      timeoutMs,
      immediate,
    ]);
    return loop;
  }

  @override
  Future<void> cancelWrite() {
    final w = _write;
    if (w == null) return Future.value();
    if (!w.cancelRequested) {
      w.cancelRequested = true;
      _ready.future.then(
        (_) => _commands!.send(['cancel', w.id]),
        onError: (Object _) {},
      );
    }
    return w.settled.future;
  }

  @override
  void purge() {
    if (_closing || _purgePending) return;
    _purgePending = true;
    _ready.future.then(
      (_) => _commands!.send(['purge']),
      onError: (Object _) {},
    );
  }

  @override
  Future<void> close() {
    if (!_closing) {
      _closing = true;
      _commands?.send(['close']);
    }
    return _closed.future;
  }
}

class _HostWrite {
  _HostWrite(this.id);
  final int id;
  final result = Completer<SerialWriteResult>();
  final settled = Completer<void>();
  bool cancelRequested = false;
}

void _serialWorker(
  (SendPort, SerialPortConfig, SerialNativeDriverFactory) args,
) {
  final (host, config, factory) = args;
  SerialNativeDriver? driver;
  try {
    driver = factory();
    driver.open(config);
  } catch (error) {
    // 打开失败也由同一 worker 回收；失败时保留所有权并重试关闭。
    void cleanup() {
      try {
        driver?.close();
        host.send(['openError', '$error']);
      } catch (_) {
        Timer(const Duration(milliseconds: 20), cleanup);
      }
    }

    cleanup();
    return;
  }
  _SerialWorker(host, driver).start();
}

class _SerialWorker {
  _SerialWorker(this.host, this.driver);
  final SendPort host;
  final SerialNativeDriver driver;
  final commands = ReceivePort();
  final clock = Stopwatch()..start();
  Timer? timer, _fastWritePoll;
  _WorkerWrite? write;
  _WorkerLoop? loop;
  SerialReadCompletionSignals? _readSignals;
  Uint8List? _receivePrefix;
  int _receiveOverrun = 0;
  bool reading = false, _readWatching = false, _purgeAfterRead = false;
  bool readCancel = false;
  bool credit = true;
  bool closing = false;
  bool faulted = false;
  bool closed = false;
  void start() {
    commands.listen((dynamic raw) {
      final m = raw as List;
      try {
        switch (m[0]) {
          case 'write':
            final id = m[1] as int;
            if (closing || write != null || loop != null) {
              host.send(['result', id, false, 0, '串口不可写', true]);
              return;
            }
            beginWrite(id, m[2] as Uint8List, m[3] as int);
          case 'loopStart':
            final id = m[1] as int;
            if (closing || write != null || loop != null) {
              host.send(['loopStopped', id, '串口不可写', false]);
              return;
            }
            final run = loop = _WorkerLoop(
              this,
              id,
              m[2] as Uint8List,
              m[3] as int,
              m[4] as int,
            );
            run.start(immediate: m[5] as bool);
          case 'loopUpdate':
            final run = loop;
            if (run != null && run.id == m[1]) run.update(m[2] as Uint8List);
          case 'loopStop':
            final run = loop;
            if (run != null && run.id == m[1]) {
              run.stop(cancelInFlight: m[2] as bool);
            }
          case 'loopCredit':
            final run = loop;
            if (run != null && run.id == m[1]) run.acknowledge();
          case 'cancel':
            final w = write;
            if (w != null && w.id == m[1]) cancel(w, '串口写入已取消');
          case 'credit':
            credit = true;
          case 'close':
            beginClose();
          case 'purge':
            if (_readSignals != null && reading && !closing) {
              _purgeAfterRead = true;
              if (!readCancel) {
                readCancel = true;
                driver.cancelRead();
              }
            } else {
              _purge();
            }
        }
      } catch (error) {
        fault(error);
      }
      pump();
    });
    final source = driver;
    if (source is SerialReadCompletionSignals) {
      final signals = source as SerialReadCompletionSignals;
      if (signals.enableReadCompletion(_receiveReady)) _readSignals = signals;
    }
    host.send([
      'ready',
      commands.sendPort,
      driver is Win32SerialDriver && NativeSerialLoop.available,
    ]);
    if (_readSignals != null) pump();
    timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      pump(queryPendingRead: true);
      loop?.collectAndPublishRounds();
    });
  }

  void beginWrite(
    int id,
    Uint8List bytes,
    int timeoutMs, {
    _WorkerLoop? owner,
  }) {
    final startedAt = clock.elapsedMilliseconds;
    final pending = _WorkerWrite(
      id,
      bytes.length,
      startedAt + math.max(0, timeoutMs),
      startedAt + 4,
      owner == null ? null : (owner, bytes),
    );
    write = pending;
    try {
      driver.startWrite(bytes);
    } catch (error) {
      write = null;
      finishWrite(pending, null, error.toString());
      fault(error);
    }
  }

  void finishWrite(_WorkerWrite pending, int? count, String? reason) {
    if (pending.loop case (final owner, final bytes)) {
      owner.onRound(
        bytes,
        count,
        pending.cancelReason ?? reason,
        cancelled: pending.cancelRequested,
      );
    } else {
      result(pending, reason == null, count, reason, settled: true);
    }
  }

  void result(
    _WorkerWrite w,
    bool succeeded,
    int? count,
    String? reason, {
    bool settled = false,
  }) {
    if (w.resultSent) {
      if (settled) host.send(['settled', w.id]);
      return;
    }
    w.resultSent = true;
    host.send(['result', w.id, succeeded, count, reason, settled]);
  }

  void cancel(_WorkerWrite w, String reason) {
    if (w.cancelRequested) return;
    w.cancelRequested = true;
    w.cancelReason = reason;
    if (w.loop == null) result(w, false, null, reason);
    driver.cancelWrite();
  }

  void beginClose() {
    closing = true;
    loop?.stop(cancelInFlight: true, reason: '串口正在关闭');
    final w = write;
    if (w != null) cancel(w, '串口正在关闭');
    if (reading && !readCancel) {
      readCancel = true;
      driver.cancelRead();
    }
  }

  void fault(Object error) {
    if (!faulted) {
      faulted = true;
      host.send(['fault', '$error']);
    }
    try {
      beginClose();
    } catch (_) {
      /* 取消失败仍保留资源并继续查询终态。 */
    }
  }

  void pump({bool pollReceive = true, bool queryPendingRead = false}) {
    if (closed) return;
    try {
      final w = write;
      if (w != null) {
        final done = driver.pollWrite();
        if (!done.pending) {
          write = null;
          final timedOut =
              w.loop != null &&
              !w.cancelRequested &&
              clock.elapsedMilliseconds >= w.deadline;
          finishWrite(
            w,
            done.count,
            done.error ??
                (timedOut
                    ? '串口写入超时'
                    : done.count == w.length
                    ? null
                    : '串口短写'),
          );
          if (done.error != null && !w.cancelRequested) {
            fault(StateError(done.error!));
          }
        } else if (!w.cancelRequested &&
            clock.elapsedMilliseconds >= w.deadline) {
          if (w.loop case (final owner, _)) {
            owner.stop(cancelInFlight: true, reason: '串口写入超时');
          } else {
            cancel(w, '串口写入超时');
          }
        } else if (!w.cancelRequested && !w.watchingCompletion) {
          final source = driver;
          if (source is SerialWriteCompletionSignals) {
            w.watchingCompletion = true;
            (source as SerialWriteCompletionSignals).watchWriteCompletion(() {
              if (identical(write, w)) pump(pollReceive: false);
            });
          }
        }
      }
    } catch (error) {
      fault(error);
    }
    _scheduleFastWritePoll();
    if (pollReceive) _pumpReceive(queryPending: queryPendingRead || closing);
    if (closing && !reading && write == null && loop == null) {
      try {
        driver.close();
        closed = true;
        timer?.cancel();
        _fastWritePoll?.cancel();
        commands.close();
        host.send(['closed']);
      } catch (error) {
        fault(error);
      }
    }
  }

  void _scheduleFastWritePoll() {
    final pending = write;
    // 短写入优先收集完成回执；持续在途的写入回到常规轮询。
    if (closing ||
        pending == null ||
        pending.cancelRequested ||
        clock.elapsedMilliseconds >= pending.fastPollUntil) {
      _fastWritePoll?.cancel();
      _fastWritePoll = null;
      return;
    }
    _fastWritePoll ??= Timer(const Duration(milliseconds: 1), () {
      _fastWritePoll = null;
      pump(pollReceive: false);
    });
  }

  void _receiveReady() {
    _readWatching = false;
    pump(queryPendingRead: true);
    // 空闲读取正常返回零字节后，继续预投递下一次读取。
    if (!closing && !reading && credit) _pumpReceive(queryPending: false);
  }

  void _purge() {
    _purgeAfterRead = false;
    if (!closing) driver.purge();
    host.send(['purged']);
  }

  void _pumpReceive({required bool queryPending}) {
    try {
      final signals = _readSignals;
      // 每轮最多 16 KiB，缓冲未被宿主消费时不发起下一笔读取。
      if (!closing && !reading && credit) {
        final available = signals == null
            ? math.min(_availableBytes(), Win32SerialTransport.readBatchBytes)
            : Win32SerialTransport.readBatchBytes;
        if (available > 0) {
          driver.startRead(available);
          reading = true;
        } else {
          _publishRead(null);
        }
      }
      if (!reading || (_readWatching && !queryPending)) return;
      final done = driver.pollRead();
      if (done.pending) {
        if (signals != null && !_readWatching && !closing) {
          signals.watchReadCompletion();
          _readWatching = true;
        }
        return;
      }

      reading = false;
      _readWatching = false;
      final cancelled = readCancel;
      readCancel = false;
      final prefix = _receivePrefix;
      _receivePrefix = null;
      if (done.error != null) {
        if (!cancelled) {
          if (!closing) _publishRead(prefix);
          fault(StateError(done.error!));
        }
      } else {
        final source = driver;
        final combined =
            prefix != null &&
            !closing &&
            !cancelled &&
            source is Win32SerialDriver;
        final bytes = combined
            ? source.takeReadBytes(done.count!, prefix: prefix)
            : source.takeReadBytes(done.count!);
        if (!closing && !cancelled) {
          // 到达首字节时读操作可以结束。只追加一次此刻已在驱动内的字节，
          // 避免把同一批到达的数据拆成两条，同时不引入等待窗口。
          final buffered = signals == null ? 0 : _availableBytes();
          if (_receiveOverrun == 0 &&
              prefix == null &&
              bytes.length == 1 &&
              buffered > 0) {
            _receivePrefix = bytes;
            driver.startRead(
              math.min(buffered, Win32SerialTransport.readBatchBytes - 1),
            );
            reading = true;
            _pumpReceive(queryPending: true);
            return;
          }
          if (prefix != null && !combined) {
            final merged = Uint8List(prefix.length + bytes.length)
              ..setAll(0, prefix)
              ..setAll(prefix.length, bytes);
            _publishRead(merged);
          } else {
            _publishRead(bytes.isEmpty ? null : bytes);
          }
        }
      }
      if (_purgeAfterRead) _purge();
    } catch (error) {
      fault(error);
    }
  }

  int _availableBytes() {
    final count = driver.availableBytes;
    if (driver case final SerialReceiveOverrunSignals source) {
      _receiveOverrun |= source.takeReceiveOverrun();
    }
    return count;
  }

  void _publishRead(Uint8List? bytes) {
    if (bytes == null && _receiveOverrun == 0) return;
    credit = false;
    // 普通批次直接交付字节。缺口和该批数据共用一个 credit，按检测顺序交付。
    host.send(_receiveOverrun == 0 ? bytes! : ['rx', bytes, _receiveOverrun]);
    _receiveOverrun = 0;
  }
}

class _WorkerWrite {
  _WorkerWrite(
    this.id,
    this.length,
    this.deadline,
    this.fastPollUntil,
    this.loop,
  );
  final int id;
  final int length;
  final int deadline, fastPollUntil;
  final (_WorkerLoop, Uint8List)? loop;
  String? cancelReason;
  bool resultSent = false;
  bool cancelRequested = false;
  bool watchingCompletion = false;
}
