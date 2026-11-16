/// 统一提示弹窗（Toast）。
///
/// 规格：
/// - 位置固定于窗口左下角（16px 边距），多条时自下而上堆叠；
/// - 卡片 = 图标 + 文本主体 + 底部极薄进度条（3px），进度条指示 3 秒倒计时；
/// - 鼠标悬停 → 暂停倒计时；离开 → 从当前进度继续；
/// - 单击卡片 → 立即淡出消失；
/// - 三种语义：[DsToastKind.error] 红（禁止/错误行为）、
///   [DsToastKind.warning] 黄（警告行为）、[DsToastKind.success] 绿（成功行为）。
///
/// 使用方式：在 `MaterialApp.builder` 中挂载 [DsToastHost]（见 `main.dart`），
/// 任意位置调用顶层函数 [showDsToast] 触发，不需要 BuildContext。
library;

import 'package:flutter/material.dart';

import '../theme/traework_theme.dart';
import 'ds_interaction.dart';

/// Toast 语义类型：决定主色与图标。
enum DsToastKind {
  /// 禁止或错误行为：红色。
  error(TraeWorkColors.statusError, Icons.error_outline),

  /// 警告行为：黄色。
  warning(TraeWorkColors.statusWarning, Icons.warning_amber_rounded),

  /// 成功行为：绿色。
  success(TraeWorkColors.statusSuccess, Icons.check_circle_outline);

  const DsToastKind(this.color, this.icon);
  final Color color;
  final IconData icon;
}

/// 全局 Toast 宿主。挂在 `MaterialApp.builder` 层，位于 Navigator 之上，
/// 保证 Toast 覆盖对话框与页面内容。
class DsToastHost extends StatefulWidget {
  const DsToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<DsToastHost> createState() => DsToastHostState();
}

class DsToastHostState extends State<DsToastHost> {
  /// 单例访问键。`main.dart` 在 `MaterialApp.builder` 中用此键挂载 [DsToastHost]，
  /// 之后 [showDsToast] 就能在任意位置触发弹窗。
  static final GlobalKey<DsToastHostState> rootKey =
      GlobalKey<DsToastHostState>();

  /// 同时可见的最大条数。超过则从最早一条开始丢弃，避免堆满屏幕。
  static const int _maxVisible = 4;

  int _nextId = 0;
  final List<_ToastEntry> _toasts = [];

  /// 追加一条 Toast。
  void show(String message, DsToastKind kind) {
    // 应用状态和页面捕获可能分别传入异常字符串与正文，统一后去重。
    message = message.trim().replaceFirst(
      RegExp(r'^(?:FormatException:|Bad state:)\s*'),
      '',
    );
    if (!mounted ||
        message.isEmpty ||
        _toasts.any(
          (toast) => toast.message == message && toast.kind == kind,
        )) {
      return;
    }
    setState(() {
      _toasts.add(_ToastEntry(id: _nextId++, message: message, kind: kind));
      while (_toasts.length > _maxVisible) {
        _toasts.removeAt(0);
      }
    });
  }

  void _dismiss(int id) {
    if (!mounted) return;
    setState(() => _toasts.removeWhere((t) => t.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // 空列表时 Column 尺寸为零，不吃指针事件。
        Positioned(
          left: TraeWorkSpacers.s16,
          bottom: TraeWorkSpacers.s16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final toast in _toasts)
                _DsToastCard(
                  key: ValueKey(toast.id),
                  entry: toast,
                  onDismiss: () => _dismiss(toast.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToastEntry {
  _ToastEntry({required this.id, required this.message, required this.kind});
  final int id;
  final String message;
  final DsToastKind kind;
}

class _DsToastCard extends StatefulWidget {
  const _DsToastCard({super.key, required this.entry, required this.onDismiss});
  final _ToastEntry entry;
  final VoidCallback onDismiss;

  @override
  State<_DsToastCard> createState() => _DsToastCardState();
}

class _DsToastCardState extends State<_DsToastCard>
    with TickerProviderStateMixin {
  /// 倒计时总长（进度条从满格走到零）。
  static const Duration _lifetime = Duration(seconds: 3);

  /// 进出场淡入淡出时长。
  static const Duration _fade = Duration(milliseconds: 180);

  /// 卡片之间的间距。
  static const double _gap = 8;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _lifetime,
  );
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: _fade,
    value: 0,
  );
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _opacity.forward();
    _progress.addStatusListener(_onProgressStatus);
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.removeStatusListener(_onProgressStatus);
    _progress.dispose();
    _opacity.dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _dismiss();
  }

  /// 淡出后从宿主的列表中移除。多次调用只生效一次。
  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _progress.stop();
    _opacity.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.entry.kind;
    final accent = kind.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: FadeTransition(
        opacity: _opacity,
        child: MouseRegion(
          // 悬停暂停倒计时；离开时若未在淡出则从当前值继续。
          onEnter: (_) => _progress.stop(),
          onExit: (_) {
            if (!_dismissing) _progress.forward();
          },
          child: DsInteraction(
            onTap: _dismiss,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: TraeWorkColors.bgBaseDefault,
                borderRadius: BorderRadius.circular(TraeWorkRadius.r8),
                border: Border.all(color: _withAlpha(accent, 0.4)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TraeWorkRadius.r8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TraeWorkSpacers.s12,
                        vertical: TraeWorkSpacers.s10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(kind.icon, size: 16, color: accent),
                          const SizedBox(width: TraeWorkSpacers.s8),
                          Flexible(
                            child: Text(
                              widget.entry.message,
                              style: traeworkText(
                                size: TraeWorkFontSizes.bodyMd,
                                color: TraeWorkColors.textDefault,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 底部进度条：极薄，宽度 = 剩余时间占比。
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) {
                        final remaining = (1 - _progress.value).clamp(0.0, 1.0);
                        return Container(
                          height: 3,
                          color: _withAlpha(accent, 0.15),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: remaining,
                              child: Container(color: accent),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 兼容不同 Flutter 版本的透明度调整。
  static Color _withAlpha(Color color, double alpha) =>
      color.withValues(alpha: alpha);
}

/// 全局提示入口。宿主未挂载时静默丢弃（例如测试环境未包 [DsToastHost]）。
void showDsToast(String message, {DsToastKind kind = DsToastKind.error}) {
  DsToastHostState.rootKey.currentState?.show(message, kind);
}
