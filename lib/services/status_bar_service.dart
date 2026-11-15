import 'package:flutter/material.dart';

/// 状态栏信息
class StatusBarInfo {
  final String text;
  final IconData? icon;
  final Color? color;

  const StatusBarInfo({required this.text, this.icon, this.color});

  static const empty = StatusBarInfo(text: '');
}

/// 跨模块状态栏服务（单例）
///
/// 各模块通过 [update] / [updateToolboxStatus] 上报状态。
/// HomeView 通过 [version] ValueNotifier + listener 驱动局部刷新。
///
/// 工具箱子工具按稳定入口 id 键控（见 ToolboxToolRegistry），
/// 只有当前活跃子工具的状态才映射到工具箱主 tab 供 HomeView 读取。
class StatusBarService {
  static final StatusBarService _instance = StatusBarService._();
  factory StatusBarService() => _instance;
  StatusBarService._();

  /// 工具箱在 HomeView 主导航中的固定 tab 槽位。
  static const int _toolboxTabIndex = 3;

  final Map<int, StatusBarInfo> _statuses = {};
  final Map<String, StatusBarInfo> _toolboxStatuses = {};
  String? _activeToolboxToolId;
  final ValueNotifier<int> version = ValueNotifier(0);

  // ─── 普通 Tab 模块 ──────────────────────────────────────────

  void update(int tabIndex, StatusBarInfo info) {
    final old = _statuses[tabIndex];
    if (old != null && old.text == info.text && old.icon == info.icon) return;
    _statuses[tabIndex] = info;
    version.value++;
  }

  // ─── 工具箱子工具（按入口 id 键控）─────────────────────────────

  /// 子工具调用，按自身入口 id 写入；若恰好是当前活跃子工具则同步刷新。
  void updateToolboxStatus(String toolId, StatusBarInfo info) {
    final old = _toolboxStatuses[toolId];
    if (old != null && old.text == info.text && old.icon == info.icon) return;
    _toolboxStatuses[toolId] = info;
    if (toolId == _activeToolboxToolId) {
      _statuses[_toolboxTabIndex] = info;
      version.value++;
    }
  }

  /// ToolboxView 切子 Tab 时调用，切换到对应入口 id 的已缓存状态。
  void setActiveToolboxTool(String toolId) {
    _activeToolboxToolId = toolId;
    final info = _toolboxStatuses[toolId];
    if (info != null) {
      _statuses[_toolboxTabIndex] = info;
      version.value++;
    }
  }

  // ─── 查询 ────────────────────────────────────────────────────

  StatusBarInfo statusFor(int tabIndex) =>
      _statuses[tabIndex] ?? StatusBarInfo.empty;
}
