import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import '../../models/serial_port_model.dart';
import 'win32_serial_writer.dart';

/// 单次物理连接的字节通道；关闭后禁止复用。
abstract interface class SerialByteTransport {
  Stream<Uint8List> get chunks;
  bool send(Uint8List bytes, int timeoutMs);
  void purge();
  void close();
}

class Win32SerialTransport implements SerialByteTransport {
  Win32SerialTransport(SerialPortConfig config) {
    try {
      _serialPort = SerialPort(config.portName, openNow: false);
      _serialPort!.openWithSettings(
        BaudRate: config.baudRate,
        ByteSize: config.dataBits,
        StopBits: config.stopBits == 1 ? ONESTOPBIT : TWOSTOPBITS,
        Parity: _getParityValue(config.parity),
      );
      _configureFlowControl(config.flowControl);
      _startListening();
    } catch (_) {
      close();
      rethrow;
    }
  }
  SerialPort? _serialPort;
  final _chunks = StreamController<Uint8List>();
  final _writer = const Win32SerialWriter();
  bool _closed = false;
  Timer? _readTimer;
  Pointer<OVERLAPPED>? _readOver;
  Pointer<DWORD>? _readBytesRead;
  Pointer<COMSTAT>? _readComStat;
  Pointer<DWORD>? _readErrors;
  @override
  Stream<Uint8List> get chunks => _chunks.stream;

  void _configureFlowControl(String flow) {
    final dcb = calloc<DCB>();
    try {
      dcb.ref.DCBlength = sizeOf<DCB>();
      if (!GetCommState(_serialPort!.handler, dcb).value) {
        throw StateError('读取串口流控配置失败');
      }
      // 清除缓存端口中残留的 CTS/DSR、DTR/RTS、软件流控位。
      const mask =
          (1 << 2) |
          (1 << 3) |
          (3 << 4) |
          (1 << 6) |
          (1 << 8) |
          (1 << 9) |
          (3 << 12);
      var bits = dcb.ref.bitfield & ~mask;
      bits |= 1;
      if (flow == 'RTS/CTS') bits |= (1 << 2) | (2 << 12);
      if (flow == 'DTR/DSR') bits |= (1 << 3) | (2 << 4);
      if (flow == 'XON/XOFF') {
        bits |= (1 << 8) | (1 << 9);
        dcb.ref.XonChar = const CHAR(0x11);
        dcb.ref.XoffChar = const CHAR(0x13);
      }
      dcb.ref.bitfield = bits;
      if (!SetCommState(_serialPort!.handler, dcb).value) {
        throw StateError('应用串口流控配置失败');
      }
    } finally {
      free(dcb);
    }
  }

  DCB_PARITY _getParityValue(String parity) {
    switch (parity) {
      case 'Odd':
        return ODDPARITY;
      case 'Even':
        return EVENPARITY;
      case 'Mark':
        return MARKPARITY;
      case 'Space':
        return SPACEPARITY;
      default:
        return NOPARITY;
    }
  }

  void _startListening() {
    _readTimer?.cancel();
    _disposeReadResources();

    _readOver = calloc<OVERLAPPED>();
    _readOver!.ref.hEvent = CreateEvent(null, true, false, null).value;
    if (_readOver!.ref.hEvent.address == 0) {
      free(_readOver!);
      _readOver = null;
      throw StateError('创建串口读取事件失败');
    }
    _readOver!.ref.Internal = 0;
    _readOver!.ref.InternalHigh = 0;
    _readBytesRead = calloc<DWORD>();
    _readComStat = calloc<COMSTAT>();
    _readErrors = calloc<DWORD>();

    _readTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_closed || _serialPort == null) {
        _readTimer?.cancel();
        return;
      }

      final handler = _serialPort!.handler;

      // 查询接收缓冲区中的可用字节数
      if (!ClearCommError(handler, _readErrors!, _readComStat!).value) {
        _fail(StateError('串口读取失败或设备已移除'));
        return;
      }
      final bytesAvailable = _readComStat!.ref.cbInQue;
      if (bytesAvailable == 0) return;

      final bytesToRead = bytesAvailable < 1024 ? bytesAvailable : 1024;
      final lpBuffer = calloc<Uint8>(bytesToRead);

      try {
        _readBytesRead!.value = 0;
        ResetEvent(_readOver!.ref.hEvent);

        final result = ReadFile(
          handler,
          lpBuffer,
          bytesToRead,
          _readBytesRead!,
          _readOver!,
        );

        int bytesRead = 0;
        if (result.value) {
          // 同步完成：ReadFile 立即读取了数据
          bytesRead = _readBytesRead!.value;
        } else if (result.error == ERROR_IO_PENDING) {
          // 异步操作：等待 OVERLAPPED 事件完成（最多 100ms）
          if (WaitForSingleObject(_readOver!.ref.hEvent, 100).value ==
              WAIT_OBJECT_0) {
            if (!GetOverlappedResult(
              handler,
              _readOver!,
              _readBytesRead!,
              false,
            ).value) {
              _fail(StateError('串口异步读取失败'));
              return;
            }
            bytesRead = _readBytesRead!.value;
          } else {
            CancelIoEx(handler, _readOver!);
            GetOverlappedResult(handler, _readOver!, _readBytesRead!, true);
          }
        } else {
          _fail(StateError('串口读取失败：${result.error}'));
          return;
        }

        if (bytesRead > 0) {
          final data = Uint8List.fromList(lpBuffer.asTypedList(bytesRead));
          _chunks.add(data);
        }
      } finally {
        free(lpBuffer);
      }
    });
  }

  void _disposeReadResources() {
    if (_readOver != null) {
      CloseHandle(_readOver!.ref.hEvent);
      free(_readOver!);
      _readOver = null;
    }
    if (_readBytesRead != null) {
      free(_readBytesRead!);
      _readBytesRead = null;
    }
    if (_readComStat != null) {
      free(_readComStat!);
      _readComStat = null;
    }
    if (_readErrors != null) {
      free(_readErrors!);
      _readErrors = null;
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    _chunks.addError(error);
    close();
  }

  @override
  bool send(Uint8List bytes, int timeoutMs) =>
      !_closed &&
      _serialPort != null &&
      _writer.write(_serialPort!.handler, bytes, timeoutMs);
  @override
  void purge() {
    if (!_closed && _serialPort != null) {
      PurgeComm(_serialPort!.handler, PURGE_TXCLEAR | PURGE_RXCLEAR);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _readTimer?.cancel();
    _readTimer = null;
    _disposeReadResources();
    try {
      _serialPort?.close();
    } catch (_) {
      /* 设备可能已拔出。 */
    }
    _serialPort = null;
    unawaited(_chunks.close());
  }
}
