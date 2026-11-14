/// 响应式布局契约：窗口尺寸阈值与布局密度断点的唯一事实来源。
///
/// - [AppWindowMetrics.minimumSize] 同时约束 Dart 侧 window_manager 与
///   Windows 原生宿主（windows/runner/flutter_window.cpp 的
///   WM_GETMINMAXINFO 处理），修改时两侧常量必须同步；
/// - [Responsive]/[ResponsiveScope] 负责把当前窗口尺寸换算成布局密度
///   并广播给整棵 Widget 树（含对话框），页面按需消费。
library;

import 'package:flutter/widgets.dart';

/// 应用窗口尺寸与布局阈值常量（逻辑像素）。
abstract final class AppWindowMetrics {
  /// 窗口不可继续缩小的最小宽度，与原生宿主 kMinWindowWidth 同步。
  /// 1120 = 折叠导航轨道 56 + 内容底线 960 + 窗框/DPI 取整余量，
  /// 保证最小窗口下不触发外壳横向滚动兜底。
  static const double minimumLogicalWidth = 1120;

  /// 窗口不可继续缩小的最小高度，与原生宿主 kMinWindowHeight 同步。
  static const double minimumLogicalHeight = 640;

  /// 最小窗口尺寸阈值。
  static const Size minimumSize = Size(
    minimumLogicalWidth,
    minimumLogicalHeight,
  );

  /// 启动时的默认窗口尺寸。
  static const Size preferredSize = Size(1440, 900);

  /// 内容区在自适应布局下仍须保证的最小宽度；
  /// 低于该值时退化为横向滚动，保证界面完整性。
  static const double minContentWidth = 960;

  /// 侧边导航常规宽度。
  static const double navWidth = 200;

  /// compact 密度下侧边导航折叠为图标轨道的宽度。
  static const double navRailWidth = 56;
}

/// 布局密度档位。
enum AppLayoutDensity {
  /// 紧凑：窗口接近最小阈值，导航折叠、面板收窄。
  compact,

  /// 常规：设计稿基准宽度附近。
  regular,

  /// 宽松：大窗口，留白与面板可以更舒展。
  expanded,
}

/// 根据窗口尺寸计算布局密度。
///
/// 宽 <1280 或高 <720 视为 compact（最小阈值 1120×640 之上的一档收窄
/// 布局）；宽 ≥1600 视为 expanded；其余为 regular。
AppLayoutDensity appDensityFor(Size size) {
  if (size.width < 1280 || size.height < 720) return AppLayoutDensity.compact;
  if (size.width >= 1600) return AppLayoutDensity.expanded;
  return AppLayoutDensity.regular;
}

/// 向子树广播当前窗口尺寸与布局密度的 InheritedWidget。
class Responsive extends InheritedWidget {
  const Responsive({
    super.key,
    required this.canvasSize,
    required this.density,
    required super.child,
  });

  /// 当前可用画布尺寸（逻辑像素）。
  final Size canvasSize;

  /// 当前布局密度。
  final AppLayoutDensity density;

  /// 读取当前密度；子树未包裹 [ResponsiveScope] 时按 regular 处理。
  static AppLayoutDensity densityOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Responsive>()?.density ??
      AppLayoutDensity.regular;

  /// 读取当前画布尺寸；无祖先时回退到 MediaQuery 尺寸。
  static Size sizeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Responsive>()?.canvasSize ??
      MediaQuery.sizeOf(context);

  @override
  bool updateShouldNotify(Responsive oldWidget) =>
      oldWidget.density != density || oldWidget.canvasSize != canvasSize;
}

/// 监听视口尺寸变化并刷新 [Responsive]，挂在应用根部。
class ResponsiveScope extends StatelessWidget {
  const ResponsiveScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallback = MediaQuery.sizeOf(context);
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : fallback.width,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : fallback.height,
        );
        return Responsive(
          canvasSize: size,
          density: appDensityFor(size),
          child: child,
        );
      },
    );
  }
}
