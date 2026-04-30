import 'dart:typed_data';

import 'package:clovecom/views/toolbox/toolbox_view.dart';
import 'package:clovecom/views/toolbox/widgets/hex_ascii_viewer.dart';
import 'package:clovecom/views/toolbox/widgets/tool_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toolbox shows registered tool tabs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ToolboxView()));
    await tester.pump();

    expect(find.text('HEX转BIN'), findsWidgets);
    expect(find.text('BIN编辑'), findsWidgets);
    expect(find.text('BIN拼接'), findsWidgets);
    expect(find.text('文件转换、编辑与拼接'), findsNothing);
  });

  testWidgets('hex ascii viewer shows offset header and renders without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HexAsciiViewer(bytes: Uint8List.fromList([0x41, 0x00, 0x7A])),
        ),
      ),
    );

    expect(find.textContaining('offset'), findsOneWidget);
    expect(find.text('ASCII'), findsOneWidget);
    expect(find.byType(HexAsciiViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hex ascii viewer accepts tap and renders without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HexAsciiViewer(
            bytes: const [0x41, 0x42, 0x43],
            onByteChanged: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.byType(HexAsciiViewer), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(110, 50));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hex ascii viewer with more rows renders without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HexAsciiViewer(
            bytes: List<int>.generate(64, (i) => i),
            onByteChanged: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.byType(HexAsciiViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editable hex ascii viewer renders custom paint without overflow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HexAsciiViewer(
              bytes: List<int>.generate(32, (index) => index),
              onByteChanged: (_, _) {},
            ),
          ),
        ),
      );

      expect(find.textContaining('offset'), findsOneWidget);
      expect(find.byType(HexAsciiViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toolbox keeps tool state when switching tabs', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ToolboxView()));
    await tester.pump();

    await tester.tap(find.text('BIN拼接').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '0x1000');
    await tester.enterText(find.byType(TextField).at(2), '01 02');
    await tester.tap(find.text('新增HEX片段'));
    await tester.pumpAndSettle();

    expect(find.text('手动HEX 1'), findsOneWidget);

    await tester.tap(find.text('HEX转BIN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('BIN拼接').last);
    await tester.pumpAndSettle();

    expect(find.text('手动HEX 1'), findsOneWidget);
  });

  testWidgets('tool status panel exposes dismiss button for errors', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolStatusPanel(
            title: '错误',
            message: '正常',
            error: '失败',
            onDismissError: () => dismissed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('关闭错误提示'));
    await tester.pump();

    expect(dismissed, isTrue);
  });
}
