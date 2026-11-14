import 'package:flutter/material.dart';

import '../theme/traework_theme.dart';

/// 异步反馈深模块：每个异步动作一个实例，内化防重入、清除旧错误、失败保留错误、
/// 忙碌复位与销毁守卫；呈现经 [run] 的 `onFailed` 适配器注入（缝）：
/// - 缺省：错误仅保留在 [error]，由绑定的 [DsDialog] 呈现（确认/输入弹窗）；
/// - 注入 `showDsToast`：瞬态错误轻提示；
/// - 注入 ViewModel 的错误 setter：持久错误内联面板。
/// 领域校验仍由调用方负责；本模块只管反馈生命周期。
class DsDialogAction extends ChangeNotifier {
  bool _disposed = false;
  bool _busy = false;
  String? _error;
  bool get busy => _busy;
  String? get error => _error;

  /// 执行异步动作。忙碌或已销毁时直接返回 false（防重入）。
  /// 成功返回 true；失败保留错误到 [error] 并经 `onFailed` 分发呈现，返回 false。
  Future<bool> run(
    Future<void> Function() operation, {
    void Function(Object error)? onFailed,
  }) async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    var succeeded = false;
    try {
      await operation();
      succeeded = true;
    } catch (failure) {
      _error = '$failure';
      if (!_disposed) onFailed?.call(failure);
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
    return succeeded;
  }

  /// 清除保留的错误（例如弹窗重新打开时）。
  void clearError() {
    if (_error == null) return;
    _error = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 弹窗统一布局与执行中关闭策略；领域校验由调用方保留。
class DsDialog extends StatelessWidget {
  const DsDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.busy = false,
    this.error,
    this.contentPadding,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 24,
    ),
  });
  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final bool busy;
  final String? error;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: title,
      insetPadding: insetPadding,
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      contentPadding:
          contentPadding ?? const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actionsOverflowButtonSpacing: 8,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: AbsorbPointer(
              absorbing: busy,
              child: ExcludeFocus(excluding: busy, child: content),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            DsErrorMessage(error!),
          ],
        ],
      ),
      actions: actions,
    ),
  );
}

class DsErrorMessage extends StatelessWidget {
  const DsErrorMessage(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: traeworkText(color: TraeWorkColors.statusError),
    ),
  );
}
