import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clovecom/main.dart';

void main() {
  testWidgets('应用启动后显示通信模块导航', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('通信助手'), findsNothing);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('终端'), findsOneWidget);
    expect(find.text('串口通信'), findsWidgets);
    expect(find.text('USB通信'), findsOneWidget);
    expect(find.text('网络通信'), findsOneWidget);
    expect(find.text('工具箱'), findsOneWidget);
  });
}
