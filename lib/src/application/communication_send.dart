import '../../services/serial/serial_write_result.dart';
import 'dart:async';

/// 普通发送只报告本地传输接受情况，不代表对端协议完成。
enum SendOutcome { pending, succeeded, failed, notExecuted, partial, unknown }

/// 普通发送和循环共用同一结果口径；调度、日志及结束证明由调用方持有。
SendOutcome classifySendResult(
  SerialWriteResult result, {
  required bool started,
  required int requestedBytes,
}) {
  if (!started) return SendOutcome.notExecuted;
  if (result.succeeded) return SendOutcome.succeeded;
  final count = result.acceptedBytes;
  if (count == null) return SendOutcome.unknown;
  if (count > 0 && count < requestedBytes) return SendOutcome.partial;
  return SendOutcome.failed;
}

class SendTargetResult {
  SendTargetResult({
    required this.connectionId,
    required this.name,
    required this.epoch,
    required this.requestedBytes,
    required this.outcome,
    this.acceptedBytes,
    this.reason,
    Future<void>? settled,
  }) : settled = settled ?? Future<void>.value();
  final String connectionId, name;
  final int epoch, requestedBytes;
  final SendOutcome outcome;
  final int? acceptedBytes;
  final String? reason;

  /// 结果可先到达；原生结束证明用于资格交接与兼容业务清理。
  final Future<void> settled;
  String get completionLayer => 'localTransport';
}

class SendTarget {
  SendTarget(
    this.connectionId,
    this.name,
    this.epoch,
    this.requestedBytes,
    this.result,
  );
  final String connectionId, name;
  final int epoch, requestedBytes;
  final Future<SendTargetResult> result;
}

class SendOperation {
  SendOperation(Iterable<SendTarget> targets)
    : targets = List.unmodifiable(targets);
  final List<SendTarget> targets;
  late final Future<SendSummary> summary = completed.then(SendSummary.new);
  late final Future<List<SendTargetResult>> completed = Future.wait(
    targets.map((target) => target.result),
  ).then(List.unmodifiable);
}

class SendSummary {
  SendSummary(Iterable<SendTargetResult> results)
    : total = results.length,
      succeeded = results
          .where((r) => r.outcome == SendOutcome.succeeded)
          .length,
      pending = results.where((r) => r.outcome == SendOutcome.pending).length,
      failed = results.where((r) => r.outcome == SendOutcome.failed).length,
      notExecuted = results
          .where((r) => r.outcome == SendOutcome.notExecuted)
          .length,
      partial = results.where((r) => r.outcome == SendOutcome.partial).length,
      unknown = results.where((r) => r.outcome == SendOutcome.unknown).length;
  final int total, succeeded, pending, failed, notExecuted, partial, unknown;
  bool get allSucceeded => total > 0 && succeeded == total;
}
