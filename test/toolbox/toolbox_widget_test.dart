import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

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

  testWidgets('hex ascii viewer shows offsets hex bytes and printable ascii', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HexAsciiViewer(bytes: Uint8List.fromList([0x41, 0x00, 0x7A])),
        ),
      ),
    );

    expect(find.text('00000000'), findsOneWidget);
    expect(find.textContaining('41 00 7A'), findsOneWidget);
    expect(find.textContaining('A.z'), findsOneWidget);
  });

  testWidgets('hex ascii viewer edits a byte when editing is enabled', (
    tester,
  ) async {
    var editedIndex = -1;
    var editedValue = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HexAsciiViewer(
            bytes: const [0x01, 0x02],
            onByteChanged: (index, value) {
              editedIndex = index;
              editedValue = value;
            },
          ),
        ),
      ),
    );

    final rowStart = tester.getTopLeft(find.textContaining('01 02'));
    await tester.tapAt(rowStart + const Offset(34, 10));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'AA');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(editedIndex, 1);
    expect(editedValue, 0xAA);
  });

  testWidgets('hex ascii viewer highlights hovered editable byte', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HexAsciiViewer(
            bytes: const [0x01, 0x02],
            onByteChanged: (_, _) {},
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    final rowStart = tester.getTopLeft(find.textContaining('01 02'));
    await gesture.moveTo(rowStart + const Offset(34, 10));
    await tester.pump();

    expect(find.byKey(const ValueKey('hex-byte-1-hovered')), findsOneWidget);

    await gesture.removePointer();
  });

  testWidgets('editable hex ascii viewer keeps inactive rows lightweight', (
    tester,
  ) async {
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

    expect(find.textContaining('00 01 02 03'), findsOneWidget);
    expect(find.byKey(const ValueKey('hex-byte-0-normal')), findsNothing);
  });

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
