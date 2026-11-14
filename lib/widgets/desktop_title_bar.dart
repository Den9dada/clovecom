import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 无 logo 标题栏：菜单与窗口按钮独立于拖动区域。
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({
    super.key,
    required this.navigationExpanded,
    required this.onMenu,
  });

  final bool navigationExpanded;
  final VoidCallback onMenu;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _maximized = false;
  bool get _desktop =>
      !kIsWeb &&
      {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    if (_desktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Widget _windowButton(
    String tooltip,
    IconData icon,
    VoidCallback onPressed, {
    bool close = false,
  }) {
    return SizedBox(
      width: 44,
      height: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => close && states.contains(WidgetState.hovered)
                ? const Color(0xFFE8463A)
                : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => close && states.contains(WidgetState.hovered)
                ? Colors.white
                : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          IconButton(
            tooltip: widget.navigationExpanded ? '收起导航' : '展开导航',
            icon: const Icon(Icons.menu, size: 18),
            onPressed: widget.onMenu,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: _desktop
                  ? (_) => windowManager.startDragging()
                  : null,
              onDoubleTap: _desktop ? _toggleMaximize : null,
              child: const SizedBox.expand(),
            ),
          ),
          if (_desktop) ...[
            _windowButton(
              '最小化',
              Icons.horizontal_rule,
              () => windowManager.minimize(),
            ),
            _windowButton(
              _maximized ? '还原' : '最大化',
              _maximized ? Icons.filter_none : Icons.crop_square,
              _toggleMaximize,
            ),
            _windowButton(
              '关闭',
              Icons.close,
              () => windowManager.close(),
              close: true,
            ),
          ],
        ],
      ),
    );
  }
}
