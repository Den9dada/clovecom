import 'dart:typed_data';

import 'package:clovecom/views/toolbox/toolbox_view.dart';
import 'package:clovecom/views/toolbox/widgets/hex_ascii_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toolbox shows registered tool tabs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ToolboxView()));
    await tester.pump();

    expect(find.text('HEX转BIN'), findsWidgets);
    expect(find.text('BIN编辑'), findsWidgets);
    expect(find.text('BIN拼接'), findsWidgets);
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
}
