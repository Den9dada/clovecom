import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clovecom/main.dart';
import 'package:clovecom/ui/layout/responsive.dart';

void main() {
  testWidgets('导航完全收起，内容占满宽度并可在紧凑窗口展开', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('接口通信'), findsOneWidget);
    expect(find.text('工具箱'), findsOneWidget);
    expect(find.text('CH34x调试'), findsOneWidget);
    await tester.tap(find.text('工具箱'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final content = find.byKey(const ValueKey('home-content'));
    final stack = find
        .descendant(of: content, matching: find.byType(IndexedStack))
        .first;
    final contentElement = tester.element(content);
    expect(tester.getTopLeft(content).dx, AppWindowMetrics.navWidth);
    expect(tester.widget<IndexedStack>(stack).index, 1);

    await tester.tap(find.byTooltip('收起导航'));
    await tester.pump();
    expect(find.text('接口通信'), findsNothing);
    expect(find.byTooltip('接口通信'), findsNothing);
    expect(tester.getTopLeft(content).dx, 0);
    expect(tester.getSize(content).width, 1280);
    expect(tester.element(content), same(contentElement));
    expect(tester.widget<IndexedStack>(stack).index, 1);

    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();
    expect(tester.getSize(content).width, 800);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = AppWindowMetrics.minimumSize;
    await tester.pump();
    await tester.tap(find.byTooltip('展开导航'));
    await tester.pump();
    expect(find.text('接口通信'), findsOneWidget);
    expect(tester.getTopLeft(content).dx, AppWindowMetrics.navWidth);
    expect(tester.widget<IndexedStack>(stack).index, 1);
    await tester.tap(find.text('接口通信'));
    await tester.pump();
    expect(tester.widget<IndexedStack>(stack).index, 0);
    expect(tester.takeException(), isNull);
  });
}
