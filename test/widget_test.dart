import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clovecom/main.dart';

void main() {
  testWidgets('应用启动后显示通信模块导航', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('串口通信'), findsOneWidget);
    expect(find.text('USB通信'), findsOneWidget);
    expect(find.text('网络通信'), findsOneWidget);
    expect(find.text('工具箱'), findsOneWidget);
    expect(find.text('CH34x调试'), findsOneWidget);
    await tester.tap(find.text('工具箱'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('收起导航'));
    await tester.pump();
    expect(find.byTooltip('串口通信'), findsOneWidget);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();
    await tester.tap(find.byTooltip('串口通信'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
