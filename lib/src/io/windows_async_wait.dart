import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _WaitCallback = Void Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
);

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createWait = _kernel32
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<NativeFunction<_WaitCallback>>,
        Pointer<Void>,
        Pointer<Void>,
      ),
      Pointer<Void> Function(
        Pointer<NativeFunction<_WaitCallback>>,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('CreateThreadpoolWait');
final _setWait = _kernel32
    .lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
    >('SetThreadpoolWait');
final _drainWait = _kernel32
    .lookupFunction<
      Void Function(Pointer<Void>, Int32),
      void Function(Pointer<Void>, int)
    >('WaitForThreadpoolWaitCallbacks');
final _closeWait = _kernel32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CloseThreadpoolWait',
    );

/// 将 Windows 对象的单次信号投递到创建它的 isolate。
class WindowsEventWait {
  WindowsEventWait(void Function() signal) {
    void onSignal(
      Pointer<Void> _,
      Pointer<Void> _,
      Pointer<Void> _,
      int result,
    ) {
      if (!_closed && result == 0) signal();
    }

    _callback = NativeCallable<_WaitCallback>.listener(onSignal);
    try {
      _wait = _createWait(_callback.nativeFunction, nullptr, nullptr);
      if (_wait == nullptr) throw StateError('创建 Windows 线程池等待失败');
    } catch (_) {
      _callback.close();
      rethrow;
    }
  }

  late final NativeCallable<_WaitCallback> _callback;
  late final Pointer<Void> _wait;
  bool _closed = false;

  void watch(Pointer<Void> handle) => _setWait(_wait, handle, nullptr);

  void close() {
    if (_closed) return;
    _closed = true;
    // 先撤销注册并等原生回调结束，才允许释放回调和被等对象。
    _setWait(_wait, nullptr, nullptr);
    _drainWait(_wait, 1);
    _closeWait(_wait);
    _callback.close();
  }
}

final _createTimer = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Uint32, Uint32),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, int)
    >('CreateWaitableTimerExW');
final _setTimer = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Int64>,
        Int32,
        Pointer<Void>,
        Pointer<Void>,
        Int32,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Int64>,
        int,
        Pointer<Void>,
        Pointer<Void>,
        int,
      )
    >('SetWaitableTimer');
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'CloseHandle',
    );

/// 复用原生定时器，每次只安排一个到期事件。
class WindowsHighResolutionTimer {
  factory WindowsHighResolutionTimer(void Function() signal) {
    const highResolution = 0x2;
    const synchronizeAndModify = 0x00100002;
    final timer = _createTimer(
      nullptr,
      nullptr,
      highResolution,
      synchronizeAndModify,
    );
    if (timer == nullptr) throw StateError('创建 Windows 高分辨率定时器失败');
    try {
      return WindowsHighResolutionTimer._(timer, WindowsEventWait(signal));
    } catch (_) {
      _closeHandle(timer);
      rethrow;
    }
  }

  WindowsHighResolutionTimer._(this._timer, this._wait);
  final Pointer<Void> _timer;
  final WindowsEventWait _wait;
  final _due = calloc<Int64>();
  bool _closed = false;

  void arm(int microseconds) {
    if (_closed) throw StateError('Windows 定时器已关闭');
    // 相对时间为负值，Windows 单位为 100ns。
    _due.value = microseconds > 0 ? -microseconds * 10 : -1;
    _wait.watch(_timer);
    if (_setTimer(_timer, _due, 0, nullptr, nullptr, 0) == 0) {
      throw StateError('设置 Windows 高分辨率定时器失败');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _wait.close();
    _closeHandle(_timer);
    calloc.free(_due);
  }
}
