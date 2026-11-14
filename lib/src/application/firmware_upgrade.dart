import 'dart:async';

enum UpgradeTerminal { done, failed, cancelled }

/// 适配器运行事件：进度 0–100，或终态（[terminal] 非空即结束）。
/// 契约固定为 progress + done/failed（ADR 0008）：满格不等于成功终态。
class UpgradeRunEvent {
  const UpgradeRunEvent.progress(this.percent)
    : terminal = null,
      error = null,
      message = null;
  const UpgradeRunEvent.finished(this.terminal, {this.error})
    : percent = null,
      message = null;
  const UpgradeRunEvent.log(this.message)
    : percent = null,
      terminal = null,
      error = null;
  final int? percent;
  final UpgradeTerminal? terminal;
  final String? error;
  final String? message;
}

/// 一次传输运行句柄。
abstract interface class UpgradeRun {
  Stream<UpgradeRunEvent> get events;

  /// 计时器、入向订阅和在途下行全部停止；终态不等于释放完成。
  Future<void> get released;

  /// 幂等停止后续发送，并等待资源释放；不能提前宣布链路空闲。
  Future<void> cancel();
}
