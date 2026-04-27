import 'dart:async';
import 'dart:typed_data';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'transfer_protocol.dart';

/// 分包发送协议（默认）
///
/// 将文件数据按指定包大小分包，逐包发送，无握手应答。
/// 适用于简单的串口透传场景。
class RawPacketProtocol implements TransferProtocol {
  @override
  String get name => '分包发送';

  @override
  String get description => '按固定包大小逐包发送，无应答校验';

  @override
  Future<void> send(
    SerialPort port,
    Uint8List data, {
    required int packetSize,
    required int intervalMs,
    required TransferCallbacks callbacks,
  }) async {
    int offset = 0;

    final completer = Completer<void>();
    Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      // 检查是否已取消
      if (callbacks.isCancelled()) {
        timer.cancel();
        callbacks.onLog('传输已取消');
        completer.complete();
        return;
      }

      if (offset >= data.length) {
        timer.cancel();
        callbacks.onComplete(data.length);
        completer.complete();
        return;
      }

      int end = offset + packetSize;
      if (end > data.length) end = data.length;

      final packet = Uint8List.fromList(data.sublist(offset, end));
      try {
        port.writeBytesFromUint8List(packet);
        offset = end;
        callbacks.onProgress(offset / data.length);
      } catch (e) {
        timer.cancel();
        callbacks.onError('发送失败: $e');
        completer.completeError(e);
      }
    });

    return completer.future;
  }
}
