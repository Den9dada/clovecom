# UI 优化实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不破坏通信功能的前提下，将应用调整为浅色专业工作台风格，并突出深色串口日志区。

**Architecture:** 只修改 View 层和主题层。`SerialPortViewModel`、模型、协议和串口通信逻辑保持不变；必要的逻辑整理只限于 UI 状态表达、布局约束和控件组合。

**Tech Stack:** Flutter、Material 3、Provider、现有 `flutter_test` widget 测试。

---

## 文件结构

- 修改 `lib/main.dart`：统一浅色专业工具主题、字体层级、控件尺寸、配色。
- 修改 `lib/views/home/home_view.dart`：让 AppBar/TabBar 更像桌面工具外壳。
- 修改 `lib/views/serial_port/serial_port_view.dart`：调整为日志优先的工作台布局，深色日志区，配置侧栏和发送区视觉优化。
- 修改 `lib/views/usb/usb_view.dart`：同步占位页视觉。
- 修改 `lib/views/network/network_view.dart`：同步占位页视觉。
- 修改 `test/widget_test.dart`：把模板计数器测试改成应用启动和模块导航烟雾测试。

## 任务 1：修正 UI 烟雾测试

**Files:**
- Modify: `test/widget_test.dart`

- [ ] **Step 1: 写入失败测试**

将模板计数器测试替换为：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:clovecom/main.dart';

void main() {
  testWidgets('应用启动后显示通信模块导航', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('通信助手'), findsOneWidget);
    expect(find.text('串口通信'), findsWidgets);
    expect(find.text('USB通信'), findsOneWidget);
    expect(find.text('网络通信'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认当前基线**

Run: `flutter test test/widget_test.dart`

Expected: 当前模板测试会失败；替换后的烟雾测试应在 UI 可构建时通过，若 Flutter 环境不可用则记录错误。

## 任务 2：更新全局主题

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 调整主题为浅色工作台**

用浅灰背景、蓝/绿/红功能色、小圆角控件、系统 UI 字体替换当前偏默认的 Material 主题。保留 `useMaterial3: true` 和 `home: const HomeView()`。

- [ ] **Step 2: 运行静态检查**

Run: `flutter analyze`

Expected: 无新增 Dart 分析错误。

## 任务 3：优化应用外壳和占位页

**Files:**
- Modify: `lib/views/home/home_view.dart`
- Modify: `lib/views/usb/usb_view.dart`
- Modify: `lib/views/network/network_view.dart`

- [ ] **Step 1: 优化 HomeView**

保留 `TabController` 和 `IndexedStack`，只调整 AppBar/TabBar 样式。Tab 文案和模块顺序保持：串口通信、USB通信、网络通信。

- [ ] **Step 2: 优化占位页**

USB 和网络页面使用相同的浅色背景、白色面板、轻量边框、图标块和中文文案，不新增任何交互。

- [ ] **Step 3: 运行烟雾测试**

Run: `flutter test test/widget_test.dart`

Expected: 应用能构建，三个模块导航文本存在。

## 任务 4：调整串口工作台布局

**Files:**
- Modify: `lib/views/serial_port/serial_port_view.dart`

- [ ] **Step 1: 改为日志优先布局**

顶部连接栏保持全宽；主体区域将数据面板放在左侧/主区域，配置面板放到右侧辅助栏。保留所有现有控件和 ViewModel 调用。

- [ ] **Step 2: 强化深色日志区**

`_buildLogArea` 使用深色背景、浅色数据文字、低对比时间戳、彩色 RX/TX 标签，并保留自动滚动逻辑。

- [ ] **Step 3: 优化发送区和配置区**

发送区贴近日志底部，输入框和按钮尺寸更统一；配置卡片使用一致边框、标题、开关布局，不删除任何选项。

- [ ] **Step 4: 运行分析和测试**

Run: `flutter analyze`

Expected: 无新增 Dart 分析错误。

Run: `flutter test test/widget_test.dart`

Expected: 烟雾测试通过，或记录 Flutter 环境错误。

## 任务 5：最终验证

**Files:**
- Review: `lib/main.dart`
- Review: `lib/views/home/home_view.dart`
- Review: `lib/views/serial_port/serial_port_view.dart`
- Review: `lib/views/usb/usb_view.dart`
- Review: `lib/views/network/network_view.dart`
- Review: `test/widget_test.dart`

- [ ] **Step 1: 检查功能入口完整性**

确认以下入口仍存在：打开串口、断开连接、刷新串口、清空接收区、HEX 显示、日志模式、自动换行、隐藏接收、保存文件、自动滚动、HEX 发送、循环发送、追加回车、追加新行、文本发送、文件发送、固件升级。

- [ ] **Step 2: 检查 Git diff**

Run: `git diff --stat`

Expected: 只包含 UI、主题、占位页、测试和计划相关改动。
