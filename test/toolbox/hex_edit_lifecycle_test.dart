import 'package:clovecom/models/toolbox/bin_file_entry.dart';
import 'package:clovecom/views/toolbox/widgets/hex_ascii_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> selectFirstByte(WidgetTester tester) async {
  final paint = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is HexEditorPainter,
  );
  final rect = tester.getRect(paint);
  await tester.tapAt(Offset(rect.right - 130, rect.top + 13));
  await tester.pump();
}

void main() {
  testWidgets('半字节失焦丢弃，完整输入与撤销使用文档内容', (tester) async {
    final doc = BinFileEntry(name: 'a', path: '', bytes: [1, 2]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  onPressed: () => setState(doc.undo),
                  child: const Text('撤销'),
                ),
                Expanded(
                  child: HexAsciiViewer(
                    bytes: doc.currentBytes,
                    onByteChanged: (index, value) =>
                        setState(() => doc.replace(index, [value])),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await selectFirstByte(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(doc.currentBytes, [1, 2]);
    await tester.tap(find.text('撤销'));
    await tester.pump();
    await selectFirstByte(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(doc.currentBytes, [0xBC, 2]);
    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(doc.currentBytes, [1, 2]);
    await selectFirstByte(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(doc.currentBytes, [1, 2]);
    expect(doc.hasUnsavedChanges, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('同长度同首字节文件切换不会继承半字节草稿', (tester) async {
    final first = BinFileEntry(name: 'a', path: '', bytes: [1, 2]);
    final second = BinFileEntry(name: 'b', path: '', bytes: [1, 3]);
    var doc = first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => doc = second),
                  child: const Text('切换'),
                ),
                Expanded(
                  child: HexAsciiViewer(
                    key: ValueKey(doc),
                    bytes: doc.currentBytes,
                    onByteChanged: (index, value) =>
                        setState(() => doc.replace(index, [value])),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await selectFirstByte(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.tap(find.text('切换'));
    await tester.pump();
    await selectFirstByte(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pump();
    expect(second.currentBytes, [1, 3]);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(second.currentBytes, [1, 3]);
    expect(first.currentBytes, [1, 2]);
    expect(tester.takeException(), isNull);
  });
}
