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
    expect(find.text('串口通信'), findsWidgets);
    expect(find.text('USB通信'), findsOneWidget);
    expect(find.text('网络通信'), findsOneWidget);
  });

  testWidgets('较矮窗口下数据发送区不会发生布局溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('数据发送'), findsWidgets);
    expect(find.text('文件发送'), findsOneWidget);
    expect(find.text('固件升级'), findsOneWidget);
  });

  testWidgets('最小窗口尺寸下主界面完整显示', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1240, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('串口参数'), findsOneWidget);
    expect(find.text('接收配置'), findsOneWidget);
    expect(find.text('发送配置'), findsOneWidget);
    expect(find.text('数据日志'), findsOneWidget);
    expect(find.text('数据发送'), findsOneWidget);
    expect(find.text('文件发送'), findsOneWidget);
    expect(find.text('固件升级'), findsOneWidget);
    expect(find.text('清空接收区'), findsOneWidget);
    expect(find.text('清空发送区'), findsOneWidget);
    expect(find.text('打开串口'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶部使用文字菜单并用复选框呈现收发配置', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1240, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('文件'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.byType(Checkbox), findsAtLeastNWidgets(10));
  });

  testWidgets('收发配置选项保持两列排列', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1240, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final receiveFirst = tester.getTopLeft(find.text('HEX显示'));
    final receiveSecond = tester.getTopLeft(find.text('日志模式'));
    final sendFirst = tester.getTopLeft(find.text('HEX发送'));
    final sendSecond = tester.getTopLeft(find.text('循环发送'));

    expect((receiveFirst.dy - receiveSecond.dy).abs(), lessThan(2));
    expect(receiveSecond.dx, greaterThan(receiveFirst.dx));
    expect((sendFirst.dy - sendSecond.dy).abs(), lessThan(2));
    expect(sendSecond.dx, greaterThan(sendFirst.dx));
  });

  testWidgets('清空按钮放在日志计数右侧和发送输入右侧', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1240, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final tx = tester.getRect(find.textContaining('TX:'));
    final logTitle = tester.getRect(find.text('数据日志'));
    final rx = tester.getRect(find.textContaining('RX:'));
    final clearReceive = tester.getRect(find.text('清空接收区'));
    final sendTab = tester.getRect(find.text('数据发送'));
    final clearSend = tester.getRect(find.text('清空发送区'));
    final sendButton = tester.getRect(find.text('发送').last);

    expect(rx.left - logTitle.right, greaterThan(500));
    expect(1240 - clearReceive.right, lessThan(48));
    expect(clearReceive.left, greaterThan(tx.right));
    expect((clearReceive.center.dy - tx.center.dy).abs(), lessThan(8));
    expect(clearSend.left, greaterThan(sendTab.left));
    expect(clearSend.left, greaterThan(sendTab.right));
    expect((clearSend.center.dx - sendButton.center.dx).abs(), lessThan(24));
    expect(clearSend.top, lessThan(sendButton.top));
  });

  testWidgets('最小窗口下日志区大于发送区且配置栏收窄', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1240, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final config = tester.getRect(find.text('串口参数'));
    final log = tester.getRect(find.text('数据日志'));
    final send = tester.getRect(find.text('文件发送'));
    final textSend = tester.getRect(find.text('数据发送'));

    expect(log.left - config.left, lessThan(290));
    expect(send.top - log.top, greaterThan(380));
    expect(textSend.top - send.top, lessThan(60));
  });

  testWidgets('桌面布局下配置栏显示在数据日志左侧', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final configLeft = tester.getTopLeft(find.text('串口参数')).dx;
    final logLeft = tester.getTopLeft(find.text('数据日志')).dx;

    expect(configLeft, lessThan(logLeft));
  });
}
