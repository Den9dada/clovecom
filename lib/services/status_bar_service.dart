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
/// 工具箱四个子工具各自使用独立槽位（subIndex 0-3），
/// 只有当前活跃子工具的状态才映射到 tab 3 供 HomeView 读取。
class StatusBarService {
  static final StatusBarService _instance = StatusBarService._();
  factory StatusBarService() => _instance;
  StatusBarService._();

  final Map<int, StatusBarInfo> _statuses = {};
  final Map<int, StatusBarInfo> _toolboxStatuses = {};
  int _activeToolboxSubTab = 0;
  final ValueNotifier<int> version = ValueNotifier(0);

  // ─── 普通 Tab 模块 ──────────────────────────────────────────

  void update(int tabIndex, StatusBarInfo info) {
    final old = _statuses[tabIndex];
    if (old != null && old.text == info.text && old.icon == info.icon) return;
    _statuses[tabIndex] = info;
    version.value++;
  }

  // ─── 工具箱子工具 ────────────────────────────────────────────

  /// 子工具调用，写入自身槽位；若恰好是当前活跃子工具则同步刷新
  void updateToolboxStatus(int subIndex, StatusBarInfo info) {
    final old = _toolboxStatuses[subIndex];
    if (old != null && old.text == info.text && old.icon == info.icon) return;
    _toolboxStatuses[subIndex] = info;
    if (subIndex == _activeToolboxSubTab) {
      _statuses[3] = info;
      version.value++;
    }
  }

  /// ToolboxView 切子 Tab 时调用，切换到对应子工具的已缓存状态
  void setActiveToolboxSubTab(int subIndex) {
    _activeToolboxSubTab = subIndex;
    final info = _toolboxStatuses[subIndex];
    if (info != null) {
      _statuses[3] = info;
      version.value++;
    }
  }

  // ─── 查询 ────────────────────────────────────────────────────

  StatusBarInfo statusFor(int tabIndex) =>
      _statuses[tabIndex] ?? StatusBarInfo.empty;
}
