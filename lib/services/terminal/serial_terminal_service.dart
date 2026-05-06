import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:win32/win32.dart';
import 'package:xterm/xterm.dart';

import '../../models/terminal/serial_connection_params.dart';

class SerialTerminalService {
  SerialPort? _port;
  Timer? _readTimer;
  Terminal? _terminal;

  Pointer<DWORD>? _readBytesRead;
  Pointer<COMSTAT>? _readComStat;
  Pointer<DWORD>? _readErrors;
  Pointer<OVERLAPPED>? _readOver;

  bool get isConnected => _port != null;

  void connect(SerialConnectionParams params, Terminal terminal) {
    _terminal = terminal;

    _port = SerialPort(params.port, openNow: false);
    _port!.openWithSettings(
      BaudRate: params.baudRate,
      ByteSize: params.dataBits,
      StopBits: params.stopBits == 1 ? 0 : 2,
      Parity: _parityValue(params.parity),
    );

    _startReading();

    terminal.onOutput = (data) {
      if (_port != null) {
        _port!.writeBytesFromUint8List(Uint8List.fromList(utf8.encode(data)));
      }
    };
  }

  void _startReading() {
    _readBytesRead = calloc<DWORD>();
    _readComStat = calloc<COMSTAT>();
    _readErrors = calloc<DWORD>();
    _readOver = calloc<OVERLAPPED>();
    _readOver!.ref.hEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);

    _readTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _readLoop();
    });
  }

  void _readLoop() {
    if (_port == null || _terminal == null) return;
    final handler = _port!.handler!;

    ClearCommError(handler, _readErrors!, _readComStat!);
    final available = _readComStat!.ref.cbInQue;
    if (available == 0) return;

    final bytesToRead = available < 1024 ? available : 1024;
    final buffer = calloc<Uint8>(bytesToRead);
    try {
      ResetEvent(_readOver!.ref.hEvent);
      final result = ReadFile(
        handler,
        buffer,
        bytesToRead,
        _readBytesRead!,
        _readOver!,
      );

      int bytesRead = 0;
      if (result != FALSE) {
        bytesRead = _readBytesRead!.value;
      } else if (GetLastError() == ERROR_IO_PENDING) {
        if (WaitForSingleObject(_readOver!.ref.hEvent, 50) == 0) {
          GetOverlappedResult(
            handler,
            _readOver!,
            _readBytesRead!,
            FALSE,
          );
          bytesRead = _readBytesRead!.value;
        }
      }

      if (bytesRead > 0) {
        _terminal!.write(
          utf8.decode(buffer.asTypedList(bytesRead), allowMalformed: true),
        );
      }
    } finally {
      free(buffer);
    }
  }

  void disconnect() {
    _readTimer?.cancel();
    _readTimer = null;

    if (_readOver != null) {
      CloseHandle(_readOver!.ref.hEvent);
      free(_readOver!);
      _readOver = null;
    }
    free(_readBytesRead!);
    _readBytesRead = null;
    free(_readComStat!);
    _readComStat = null;
    free(_readErrors!);
    _readErrors = null;

    try {
      _port?.close();
    } catch (_) {}
    _port = null;
  }

  void dispose() => disconnect();

  static int _parityValue(String parity) {
    switch (parity) {
      case 'Odd':
        return 1;
      case 'Even':
        return 2;
      case 'Mark':
        return 3;
      case 'Space':
        return 4;
      default:
        return 0;
    }
  }

  static List<String> getAvailablePorts() {
    try {
      return SerialPort.getAvailablePorts();
    } catch (_) {
      return [];
    }
  }
}
