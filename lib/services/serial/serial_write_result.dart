/// 本地传输接受结果，不代表对端协议已经成功。
class SerialWriteResult {
  SerialWriteResult({
    required this.succeeded,
    this.acceptedBytes,
    this.reason,
    this._settled,
  });
  factory SerialWriteResult.success(int bytes) =>
      SerialWriteResult(succeeded: true, acceptedBytes: bytes);
  factory SerialWriteResult.failure(
    String reason, {
    int? acceptedBytes,
    Future<void>? settled,
  }) => SerialWriteResult(
    succeeded: false,
    acceptedBytes: acceptedBytes,
    reason: reason,
    settled: settled,
  );
  final bool succeeded;

  /// null 表示实际接受字节数未知，失败不能解释为零字节送出。
  final int? acceptedBytes;
  final String? reason;

  static final _alreadySettled = Future<void>.value();
  final Future<void>? _settled;

  /// 返回结果时是否还需要检查单独的终结证明。
  bool get needsSettlement => _settled != null;

  /// 即使结果已超时，仍须等此证明才能释放资源或交接写入资格。
  Future<void> get settled => _settled ?? _alreadySettled;
}
