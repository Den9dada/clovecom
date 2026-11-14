// CH341 操作结果模型

/// I2C 操作结果
class Ch341OperationResult {
  /// 是否成功
  final bool success;

  /// 错误信息
  final String? errorMessage;

  /// 读取到的数据（I2C 读取操作时有效）
  final List<int>? data;

  /// 操作耗时
  final Duration duration;

  /// 时间戳
  final DateTime timestamp;

  /// 操作描述（如 "RD 0x10"）
  final String description;

  const Ch341OperationResult({
    required this.success,
    this.errorMessage,
    this.data,
    required this.duration,
    required this.timestamp,
    required this.description,
  });

  /// 创建成功结果
  factory Ch341OperationResult.ok({
    required List<int>? data,
    required Duration duration,
    required String description,
  }) {
    return Ch341OperationResult(
      success: true,
      data: data,
      duration: duration,
      timestamp: DateTime.now(),
      description: description,
    );
  }

  /// 创建失败结果
  factory Ch341OperationResult.fail({
    required String errorMessage,
    required Duration duration,
    required String description,
  }) {
    return Ch341OperationResult(
      success: false,
      errorMessage: errorMessage,
      duration: duration,
      timestamp: DateTime.now(),
      description: description,
    );
  }

  /// 十六进制数据字符串
  String get hexData {
    if (data == null || data!.isEmpty) return '';
    return data!.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }
}
