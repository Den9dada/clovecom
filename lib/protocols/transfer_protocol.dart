import 'dart:typed_data';
import 'package:serial_port_win32/serial_port_win32.dart';

/// 文件传输协议回调接口
class TransferCallbacks {
  /// 更新进度 (0.0 ~ 1.0)
  final void Function(double progress) onProgress;

  /// 输出日志
  final void Function(String message) onLog;

  /// 报告错误
  final void Function(String message) onError;

  /// 传输完成
  final void Function(int totalBytes) onComplete;

  /// 读取串口收到的数据（同步轮询，返回 null 表示超时）
  final Future<int?> Function(int timeoutMs) onWaitByte;

  /// 检查是否已取消传输（协议应在每次迭代时调用）
  final bool Function() isCancelled;

  const TransferCallbacks({
    required this.onProgress,
    required this.onLog,
    required this.onError,
    required this.onComplete,
    required this.onWaitByte,
    required this.isCancelled,
  });
}

/// 文件传输协议抽象基类
///
/// 实现此接口以添加新的传输协议。
/// 已内置实现：
///   - RawPacketProtocol: 分包发送（默认）
///   - YmodemProtocol: Ymodem-1K
abstract class TransferProtocol {
  /// 协议显示名称
  String get name;

  /// 协议简要描述
  String get description;

  /// 执行文件传输
  ///
  /// [port] 已打开的串口实例
  /// [data] 要发送的文件数据
  /// [packetSize] 每包大小（字节），由用户在 UI 中配置
  /// [intervalMs] 每包发送间隔（毫秒），由用户在 UI 中配置
  /// [callbacks] 回调接口
  Future<void> send(
    SerialPort port,
    Uint8List data, {
    required int packetSize,
    required int intervalMs,
    required TransferCallbacks callbacks,
  });
}
