/// 桌面端横向滚动辅助：补齐 Flutter 默认缺失的鼠标交互。
///
/// Flutter 在桌面平台默认不将 [PointerDeviceKind.mouse] 加入拖拽设备，
/// 且滚轮事件只作用于垂直轴，导致"内容超宽但拖不动、滚不动"。
/// [DesktopHScroll] 为横向滚动容器补上三种操作：
/// - 鼠标按住直接拖动；
/// - 滚轮（可选修饰键 Shift/Ctrl）映射为横向滚动；
/// - 底部可拖拽的横向滚动条滑块。
library;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// 允许触发拖拽滚动的全部指针设备（含鼠标/触控板/触屏）。
const Set<PointerDeviceKind> kDragDevicesAll = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

/// 把任意（通常超宽的）子件包进可横向滚动的视口。
class DesktopHScroll extends StatefulWidget {
  const DesktopHScroll({
    super.key,
    required this.child,
    this.controller,
    this.physics,
    this.wheelRequiresModifier = true,
    this.showScrollbar = true,
  });

  final Widget child;

  /// 外部滚动控制器；缺省时内部自建，供 [DesktopHScrollControllerScope] 使用。
  final ScrollController? controller;

  final ScrollPhysics? physics;

  /// true：按住 Shift/Ctrl 时滚轮才做横向滚动（区域内地含垂直列表）；
  /// false：滚轮直接横向滚动（纯横向区域，如筛选栏）。
  final bool wheelRequiresModifier;

  /// 可隐藏滚动条，并由调用方提供溢出提示。
  final bool showScrollbar;

  @override
  State<DesktopHScroll> createState() => DesktopHScrollState();
}

class DesktopHScrollState extends State<DesktopHScroll> {
  late final ScrollController _own = ScrollController();

  ScrollController get _controller => widget.controller ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    final mods = HardwareKeyboard.instance;
    final modifier = mods.isShiftPressed || mods.isControlPressed;
    if (widget.wheelRequiresModifier && !modifier) return;
    if (!widget.wheelRequiresModifier && modifier) return;
    final position =
        (_controller.hasClients ? _controller.position.pixels : 0.0) + delta;
    _controller.jumpTo(
      position.clamp(
        _controller.position.minScrollExtent,
        _controller.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 该 SDK 的 SingleChildScrollView 没有 dragDevices 参数，
    // 拖拽设备需通过 ScrollBehavior 沿子树继承下发。
    final inherited = ScrollConfiguration.of(
      context,
    ).copyWith(dragDevices: kDragDevicesAll);
    final behavior = widget.showScrollbar
        ? inherited
        : inherited.copyWith(scrollbars: false);
    final viewport = Listener(
      onPointerSignal: _onPointerSignal,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: widget.physics,
        child: widget.child,
      ),
    );
    return DesktopHScrollControllerScope(
      controller: _controller,
      child: ScrollConfiguration(
        behavior: behavior,
        child: widget.showScrollbar
            ? Scrollbar(
                controller: _controller,
                notificationPredicate: (notification) =>
                    notification.depth == 0,
                child: viewport,
              )
            : viewport,
      ),
    );
  }
}

/// 向子树暴露所属横向滚动视口的控制器，供页面底部提示条判断
/// "是否还有未显示的列"。
class DesktopHScrollControllerScope extends InheritedWidget {
  const DesktopHScrollControllerScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopHScrollControllerScope>()
      ?.controller;

  @override
  bool updateShouldNotify(DesktopHScrollControllerScope oldWidget) =>
      oldWidget.controller != controller;
}
