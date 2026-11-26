import 'dart:ffi';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../models/serial_port_model.dart';
import '../../src/io/windows_async_wait.dart';
import 'native_serial_loop.dart';
import 'serial_native_driver.dart';

SerialNativeDriver createWin32SerialDriver() => Win32SerialDriver();

/// 所有同步 FFI 发起都位于 worker；绝不调用 Wait 或 wait=true。
class Win32SerialDriver
    implements
        SerialNativeDriver,
        SerialWriteCompletionSignals,
        SerialReadCompletionSignals,
        SerialReceiveOverrunSignals {
  HANDLE? _handle;
  _NativeOperation? _rx;
  _NativeOperation? _tx;
  NativeSerialLoop? _nativeLoop;
  _NativeOperation? _readStorage, _writeStorage;
  WindowsEventWait? _writeWait, _readWait;
  void Function()? _writeSignal;
  bool _writeWaitUnavailable = false;
  Pointer<COMSTAT>? _stat;
  Pointer<DWORD>? _errors;
  int _receiveOverrun = 0;
  @override
  void open(SerialPortConfig config) {
    final path = '\\\\.\\${config.portName}'.toNativeUtf16();
    final dcb = calloc<DCB>();
    final timeouts = calloc<COMMTIMEOUTS>();
    try {
      final opened = CreateFile(
        PCWSTR(path),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_MODE(0),
        null,
        OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED,
        null,
      );
      if (opened.value == INVALID_HANDLE_VALUE) {
        throw StateError('打开串口失败：${opened.error}');
      }
      _handle = opened.value;
      _receiveOverrun = 0;
      _prepareQueues(opened.value, config);
      dcb.ref.DCBlength = sizeOf<DCB>();
      _check(GetCommState(_handle!, dcb), '读取串口配置');
      dcb.ref.BaudRate = config.baudRate;
      dcb.ref.ByteSize = config.dataBits;
      dcb.ref.StopBits = config.stopBits == 1 ? ONESTOPBIT : TWOSTOPBITS;
      dcb.ref.Parity = switch (config.parity) {
        'Odd' => ODDPARITY,
        'Even' => EVENPARITY,
        'Mark' => MARKPARITY,
        'Space' => SPACEPARITY,
        _ => NOPARITY,
      };
      // 不继承驱动缓存中的字节丢弃、替换、DSR 门控或错误中止策略。
      var bits = 1 | (config.parity == 'None' ? 0 : 1 << 1);
      if (config.flowControl == 'RTS/CTS') bits |= (1 << 2) | (2 << 12);
      if (config.flowControl == 'DTR/DSR') bits |= (1 << 3) | (2 << 4);
      if (config.flowControl == 'XON/XOFF') bits |= (1 << 8) | (1 << 9);
      dcb.ref.bitfield = bits;
      dcb.ref.XonChar = const CHAR(0x11);
      dcb.ref.XoffChar = const CHAR(0x13);
      dcb.ref.XonLim = 128;
      dcb.ref.XoffLim = 128;
      _check(SetCommState(_handle!, dcb), '设置串口配置');
      timeouts.ref.ReadIntervalTimeout = 0xffffffff;
      timeouts.ref.ReadTotalTimeoutMultiplier = 0;
      timeouts.ref.ReadTotalTimeoutConstant = 0;
      timeouts.ref.WriteTotalTimeoutMultiplier = 0;
      timeouts.ref.WriteTotalTimeoutConstant = 0;
      _check(SetCommTimeouts(_handle!, timeouts), '设置串口超时');
      _stat = calloc<COMSTAT>();
      _errors = calloc<DWORD>();
    } catch (_) {
      close();
      rethrow;
    } finally {
      calloc.free(path);
      calloc.free(dcb);
      calloc.free(timeouts);
    }
  }

  void _prepareQueues(HANDLE handle, SerialPortConfig config) {
    final frameBits =
        1 +
        config.dataBits +
        config.stopBits +
        (config.parity == 'None' ? 0 : 1);
    // 按线速预留约一秒的接收空间，并限制高波特率下单连接的驱动内存。
    final receive = max(
      64 * 1024,
      min(256 * 1024, config.baudRate ~/ frameBits),
    );
    const transmit = 16 * 1024;
    final properties = calloc<COMMPROP>();
    try {
      final known = GetCommProperties(handle, properties).value;
      final input = known ? properties.ref.dwCurrentRxQueue : 0;
      final output = known ? properties.ref.dwCurrentTxQueue : 0;
      if (input < receive || output < transmit) {
        // 让驱动缓存多个接收批次，实际可用容量仍由驱动决定。
        SetupComm(handle, max(receive, input), max(transmit, output));
      }
    } finally {
      calloc.free(properties);
    }
  }

  void _check(Win32Result<bool> result, String action) {
    if (!result.value) throw StateError('$action 失败：${result.error}');
  }

  @override
  int get availableBytes {
    _checkReceiveQueue();
    return _stat!.ref.cbInQue;
  }

  void _checkReceiveQueue() {
    _check(ClearCommError(_handle!, _errors!, _stat!), '查询串口输入');
    final errors = _errors!.value;
    final overrun = CE_RXOVER | CE_OVERRUN;
    if ((errors & overrun) != errors) {
      throw StateError('串口接收数据不完整：$errors');
    }
    _receiveOverrun |= errors;
  }

  @override
  int takeReceiveOverrun() {
    final flags = _receiveOverrun;
    _receiveOverrun = 0;
    return flags;
  }

  NativeSerialLoop? startNativeLoop(
    Uint8List bytes,
    int periodMicros,
    int timeoutMs, {
    required bool immediate,
  }) {
    final handle = _handle;
    if (handle == null || _tx != null || _nativeLoop != null) return null;
    return _nativeLoop = NativeSerialLoop.start(
      Pointer<Void>.fromAddress(handle.address),
      bytes,
      periodMicros,
      timeoutMs,
      immediate: immediate,
    );
  }

  void releaseNativeLoop() {
    _nativeLoop!.release();
    _nativeLoop = null;
  }

  @override
  void startWrite(Uint8List bytes) {
    if (_tx != null || _nativeLoop != null) throw StateError('原生写仍在途');
    final op = (_writeStorage ??= _NativeOperation())..prepare(bytes.length);
    _tx = op;
    op.buffer.asTypedList(bytes.length).setAll(0, bytes);
    final started = WriteFile(_handle!, op.buffer, bytes.length, null, op.over);
    // FALSE 和错误码 0 无法证明操作是否提交，仍须查询这一笔 I/O。
    if (!started.value &&
        started.error != ERROR_IO_PENDING &&
        started.error != ERROR_SUCCESS) {
      op.immediateError = '串口写入发起失败：${started.error}';
    }
  }

  @override
  void watchWriteCompletion(void Function() signal) {
    final op = _tx;
    if (op == null || _writeSignal != null || _writeWaitUnavailable) return;
    try {
      // 唤醒只用于查询当前在途写，迟到的唤醒也不能代替原生终结证明。
      final wait = _writeWait ??= WindowsEventWait(() => _writeSignal?.call());
      _writeSignal = signal;
      wait.watch(Pointer<Void>.fromAddress(op.over.ref.hEvent.address));
    } catch (_) {
      _writeSignal = null;
      _writeWait?.close();
      _writeWait = null;
      // 无法注册时，worker 继续通过定时查询收集完成结果。
      _writeWaitUnavailable = true;
    }
  }

  @override
  SerialNativeCompletion pollWrite() {
    final op = _tx!;
    final result = _poll(op);
    if (!result.pending) {
      _writeSignal = null;
      _tx = null;
    }
    return result;
  }

  @override
  bool enableReadCompletion(void Function() signal) {
    final timeouts = calloc<COMMTIMEOUTS>();
    WindowsEventWait? wait;
    try {
      wait = WindowsEventWait(signal);
      // 已缓冲的数据立即返回。空缓冲等待首字节或正常空闲超时。
      timeouts.ref
        ..ReadIntervalTimeout = 0xffffffff
        ..ReadTotalTimeoutMultiplier = 0xffffffff
        ..ReadTotalTimeoutConstant = 250;
      if (!SetCommTimeouts(_handle!, timeouts).value) return false;
      _readWait = wait;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!identical(wait, _readWait)) wait?.close();
      calloc.free(timeouts);
    }
  }

  @override
  void watchReadCompletion() {
    final pending = _rx;
    if (pending == null) return;
    _readWait?.watch(
      Pointer<Void>.fromAddress(pending.over.ref.hEvent.address),
    );
  }

  @override
  void startRead(int maxBytes) {
    if (_rx != null) throw StateError('原生读仍在途');
    final op = (_readStorage ??= _NativeOperation())..prepare(maxBytes);
    _rx = op;
    final started = ReadFile(_handle!, op.buffer, maxBytes, null, op.over);
    if (!started.value &&
        started.error != ERROR_IO_PENDING &&
        started.error != ERROR_SUCCESS) {
      op.immediateError = '串口读取发起失败：${started.error}';
    }
  }

  @override
  SerialNativeCompletion pollRead() {
    final op = _rx!;
    final result = _poll(op);
    if (!result.pending) {
      if (result.error != null) {
        _rx = null;
      } else {
        op.received = result.count!;
      }
    }
    return result;
  }

  SerialNativeCompletion _poll(_NativeOperation op) {
    if (op.immediateError != null) {
      return SerialNativeCompletion.failed(op.immediateError!);
    }
    var done = GetOverlappedResult(_handle!, op.over, op.count, false);
    if (!done.value && done.error == ERROR_SUCCESS) {
      // 出现 FALSE + 0 时，再查询同一个 OVERLAPPED，不重新提交读写。
      done = GetOverlappedResultEx(_handle!, op.over, op.count, 0, false);
    }
    return interpretSerialOverlappedResult(done, op.count.value, op.length);
  }

  @override
  Uint8List takeReadBytes(int count, {Uint8List? prefix}) {
    final op = _rx!;
    final received = op.received;
    if (received == null) throw StateError('串口读取尚未结束');
    RangeError.checkValueInInterval(count, 0, received);
    final view = op.buffer.asTypedList(count);
    final bytes = prefix == null
        ? Uint8List.fromList(view)
        : (Uint8List(prefix.length + count)
            ..setAll(0, prefix)
            ..setAll(prefix.length, view));
    _rx = null;
    return bytes;
  }

  void _cancel(_NativeOperation? op) {
    if (op == null || op.received != null || op.immediateError != null) return;
    final result = CancelIoEx(_handle!, op.over);
    if (!result.value && result.error != ERROR_NOT_FOUND) {
      _check(result, '取消串口 I/O');
    }
  }

  @override
  void cancelWrite() => _cancel(_tx);
  @override
  void cancelRead() => _cancel(_rx);
  @override
  void purge() =>
      _check(PurgeComm(_handle!, PURGE_TXCLEAR | PURGE_RXCLEAR), '清空串口缓冲');
  @override
  void close() {
    if (_tx != null || _rx != null || _nativeLoop != null) {
      throw StateError('原生 I/O 未结束，保留串口资源');
    }
    _writeSignal = null;
    _writeWait?.close();
    _writeWait = null;
    _readWait?.close();
    _readWait = null;
    _writeWaitUnavailable = false;
    _writeStorage?.dispose();
    _writeStorage = null;
    _readStorage?.dispose();
    _readStorage = null;
    if (_handle != null) {
      _check(CloseHandle(_handle!), '关闭串口句柄');
      _handle = null;
    }
    if (_stat != null) {
      calloc.free(_stat!);
      _stat = null;
    }
    if (_errors != null) {
      calloc.free(_errors!);
      _errors = null;
    }
  }
}

/// 将 Win32 完成查询结果转换为 worker 可使用的终态或等待状态。
SerialNativeCompletion interpretSerialOverlappedResult(
  Win32Result<bool> result,
  int count,
  int capacity,
) {
  if (result.value) {
    if (count > capacity) throw StateError('串口完成计数超出缓冲区');
    return SerialNativeCompletion.completed(count);
  }
  if (result.error == ERROR_IO_INCOMPLETE || result.error == ERROR_SUCCESS) {
    return const SerialNativeCompletion.pending();
  }
  // 不变量损坏时仍须保留原生资源，等待明确的结束证明。
  if (result.error == ERROR_INVALID_HANDLE ||
      result.error == ERROR_INVALID_PARAMETER) {
    throw StateError('串口原生结束无法确认：${result.error}');
  }
  return SerialNativeCompletion.failed('串口 I/O 失败：${result.error}');
}

/// 一个方向只保存一份原生存储；等上一笔 I/O 终结后才重新初始化。
class _NativeOperation {
  _NativeOperation() {
    final event = CreateEvent(null, true, false, null);
    if (event.value.address == 0) {
      throw StateError('创建串口事件失败：${event.error}');
    }
    try {
      over = calloc<OVERLAPPED>();
      over.ref.hEvent = event.value;
      try {
        count = calloc<DWORD>();
      } catch (_) {
        calloc.free(over);
        rethrow;
      }
    } catch (_) {
      CloseHandle(event.value);
      rethrow;
    }
  }

  late final Pointer<OVERLAPPED> over;
  late final Pointer<DWORD> count;
  Pointer<Uint8> buffer = nullptr;
  int _capacity = 0;
  int length = 0;
  int? received;
  String? immediateError;

  void prepare(int requested) {
    if (requested > _capacity || buffer == nullptr) {
      var capacity = _capacity == 0 ? 256 : _capacity;
      while (capacity < requested) {
        capacity *= 2;
      }
      final expanded = malloc<Uint8>(capacity);
      if (buffer != nullptr) malloc.free(buffer);
      buffer = expanded;
      _capacity = capacity;
    }
    length = requested;
    received = null;
    immediateError = null;
    count.value = 0;
    // ReadFile/WriteFile 在提交时重置手动复位事件。保留事件句柄，初始化其余字段。
    final state = over.ref;
    state
      ..Internal = 0
      ..InternalHigh = 0;
    state.Anonymous.Pointer$ = nullptr;
  }

  void dispose() {
    final closed = CloseHandle(over.ref.hEvent);
    if (!closed.value) {
      throw StateError('关闭串口事件失败：${closed.error}');
    }
    calloc.free(over);
    calloc.free(count);
    if (buffer != nullptr) malloc.free(buffer);
  }
}
