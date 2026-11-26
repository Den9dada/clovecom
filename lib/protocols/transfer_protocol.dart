import 'dart:typed_data';

/// 文件传输协议回调接口
class TransferCallbacks {
  final void Function(double progress) onProgress;
  final void Function(String message) onLog;
  final void Function(String message) onError;
  final void Function(int totalBytes) onComplete;
  final Future<int?> Function(int timeoutMs) onWaitByte;
  final Future<Uint8List?> Function(int timeoutMs) onWaitData;
  final bool Function() isCancelled;
  final Future<bool> Function(Uint8List data, int timeoutMs) onWrite;
  final String fileName;
  final void Function(String fileName, int fileSize)? onFileInfo;

  const TransferCallbacks({
    required this.onProgress,
    required this.onLog,
    required this.onError,
    required this.onComplete,
    required this.onWaitByte,
    required this.onWaitData,
    required this.isCancelled,
    required this.onWrite,
    this.fileName = '',
    this.onFileInfo,
  });
}

/// 文件传输协议抽象基类
///
/// 实现此接口以添加新的传输协议。
/// 实现：
///   - YmodemProtocol: Ymodem-1K
abstract class TransferProtocol {
  /// 协议显示名称
  String get name;

  /// 协议接收模式下的显示名称（默认为发送名称，接收方可覆盖）
  String get receiveName => '$name 接收';

  /// 协议简要描述
  String get description;

  /// 执行文件发送
  ///
  /// 串口字节通道由 callbacks 提供。
  /// [data] 要发送的文件数据
  /// [packetSize] 每包大小（字节），由用户在 UI 中配置
  /// [intervalMs] 每包发送间隔（毫秒），由用户在 UI 中配置
  /// [callbacks] 回调接口
  Future<void> send(
    Uint8List data, {
    required int packetSize,
    required int intervalMs,
    required TransferCallbacks callbacks,
  });

  /// 执行文件接收
  ///
  /// 串口字节通道由 callbacks 提供。
  /// [savePath] 文件保存路径
  /// [callbacks] 回调接口
  /// 成功通知必须在文件关闭之后发出。
  Future<void> receive({
    required String savePath,
    required TransferCallbacks callbacks,
  });
}
