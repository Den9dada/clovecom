import 'dart:typed_data';

import '../../models/serial_port_model.dart';

/// 操作系统边界；实例只能在串口 worker 内创建和使用。
/// start 不等待完成；poll 的 pending 期间必须保留原生缓冲和 OVERLAPPED。
abstract interface class SerialNativeDriver {
  void open(SerialPortConfig config);
  int get availableBytes;
  void startWrite(Uint8List bytes);
  SerialNativeCompletion pollWrite();
  void startRead(int maxBytes);
  SerialNativeCompletion pollRead();
  Uint8List takeReadBytes(int count);
  void cancelWrite();
  void cancelRead();
  void purge();

  /// 调用前读写必须均已终结；失败时保留尚未释放的资源以便重试。
  void close();
}

/// 可选的原生唤醒，只触发完成查询，结束证明仍由 pollWrite 提供。
abstract interface class SerialWriteCompletionSignals {
  void watchWriteCompletion(void Function() signal);
}

/// 可选的到字节即返回读取模式，完成事件只用于唤醒。
abstract interface class SerialReadCompletionSignals {
  bool enableReadCompletion(void Function() signal);
  void watchReadCompletion();
}

/// 驱动报告丢字节，丢失数量和具体位置未知。
class SerialReceiveOverrun implements Exception {
  const SerialReceiveOverrun(this.flags);
  final int flags;

  @override
  String toString() => '串口接收溢出，丢失字节数未知（标志 0x${flags.toRadixString(16)}）';
}

abstract interface class SerialReceiveOverrunSignals {
  int takeReceiveOverrun();
}

typedef SerialNativeDriverFactory = SerialNativeDriver Function();

class SerialNativeCompletion {
  const SerialNativeCompletion.pending()
    : pending = true,
      count = null,
      error = null;
  const SerialNativeCompletion.completed(int bytes)
    : pending = false,
      count = bytes,
      error = null;
  const SerialNativeCompletion.failed(String reason)
    : pending = false,
      count = null,
      error = reason;
  final bool pending;
  final int? count;
  final String? error;
}
