import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../src/io/windows_async_wait.dart';
import 'native_serial_loop.g.dart';

typedef NativeSerialRound = ({
  Uint8List bytes,
  int? accepted,
  int error,
  int timestampMicros,
});

class NativeSerialLoop {
  static const capacity = 128;
  static const maxPayloadBytes = nativeSerialLoopMaxPayloadBytes;

  static const _enabled = bool.fromEnvironment(
    'clovecom.native_serial_loop',
    defaultValue: true,
  );
  static final _api = _loadApi();
  static bool get available => _enabled && _api != null;
  static bool supportsPeriod(int microseconds) =>
      microseconds >= 1000 && microseconds <= 20000;

  static NativeSerialLoopApi? _loadApi() {
    final program = DynamicLibrary.executable();
    if (!program.providesSymbol('CloveSerialLoopDrainShared')) return null;
    return NativeSerialLoopApi(program);
  }

  static NativeSerialLoop? start(
    Pointer<Void> port,
    Uint8List bytes,
    int periodMicros,
    int timeoutMs, {
    required bool immediate,
  }) {
    if (!available ||
        !supportsPeriod(periodMicros) ||
        bytes.length > maxPayloadBytes ||
        timeoutMs < 0 ||
        timeoutMs > 0x7fffffff) {
      return null;
    }
    final api = _api!;
    final run = NativeSerialLoop._(api);
    run._draft.asTypedList(bytes.length).setAll(0, bytes);
    run._context = api.CloveSerialLoopStartTimed(
      port,
      run._draft.cast(),
      bytes.length,
      periodMicros,
      timeoutMs,
      immediate ? 1 : 0,
    );
    if (run._context != nullptr) return run;
    run._freeBuffers();
    return null;
  }

  NativeSerialLoop._(this._bindings);

  final NativeSerialLoopApi _bindings;
  final _draft = calloc<Uint8>(maxPayloadBytes);
  final _rounds = calloc<CloveSerialRound>(capacity);
  final _status = calloc<CloveSerialLoopStatus>();
  late final Pointer<Void> _context;
  Uint8List _lastBytes = Uint8List(0);
  int _lastDraftVersion = 0;
  WindowsEventWait? _roundWait;

  void watchRounds(void Function() signal) {
    try {
      final event = _bindings.CloveSerialLoopRoundsReady(_context);
      if (event == nullptr) return;
      final wait = WindowsEventWait(() {
        signal();
        _roundWait?.watch(event);
      });
      _roundWait = wait;
      wait.watch(event);
    } catch (_) {
      _roundWait?.close();
      _roundWait = null;
      // 事件不可用时，串口 worker 的定时查询仍会收集回执。
    }
  }

  void update(Uint8List bytes) {
    RangeError.checkValueInInterval(bytes.length, 0, maxPayloadBytes);
    _draft.asTypedList(bytes.length).setAll(0, bytes);
    _bindings.CloveSerialLoopUpdate(_context, _draft.cast(), bytes.length);
  }

  ({bool done, int error, int skipped}) drain(
    void Function(NativeSerialRound) accept, {
    required bool collect,
  }) {
    final count = _bindings.CloveSerialLoopDrainShared(
      _context,
      _rounds,
      collect ? capacity : 0,
      _status,
    );
    for (var index = 0; index < count; index++) {
      final round = (_rounds + index).ref;
      final version = round.draft_version;
      if (version != _lastDraftVersion) {
        // 回执中的指针只在本批有效。相同版本共享 Dart 侧不可变副本。
        _lastBytes = Uint8List.fromList(
          round.bytes.cast<Uint8>().asTypedList(round.length),
        ).asUnmodifiableView();
        _lastDraftVersion = version;
      }
      accept((
        bytes: _lastBytes,
        accepted: round.accepted < 0 ? null : round.accepted,
        error: round.error,
        timestampMicros: round.timestamp_micros,
      ));
    }
    final status = _status.ref;
    return (
      done: status.done != 0,
      error: status.error,
      skipped: status.skipped,
    );
  }

  void stop({required bool cancelInFlight}) =>
      _bindings.CloveSerialLoopStop(_context, cancelInFlight ? 1 : 0);

  void release() {
    _roundWait?.close();
    _roundWait = null;
    _bindings.CloveSerialLoopRelease(_context);
    _freeBuffers();
  }

  void _freeBuffers() {
    calloc.free(_status);
    calloc.free(_rounds);
    calloc.free(_draft);
  }
}
