import 'package:flutter/material.dart';

import '../theme/traework_theme.dart';

/// 弹窗异步动作的唯一入口：防重入、清除旧错误、失败后保留表单。
class DsDialogAction extends ChangeNotifier {
  bool _disposed = false;
  bool _busy = false;
  String? _error;
  bool get busy => _busy;
  String? get error => _error;

  Future<bool> run(Future<void> Function() operation) async {
    if (busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    var succeeded = false;
    try {
      await operation();
      succeeded = true;
    } catch (failure) {
      _error = failure.toString();
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
    return succeeded;
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
