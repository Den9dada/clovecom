# Toolbox Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows-first Toolbox module with HEX-to-BIN conversion, BIN editing, BIN linking, shared HEX/ASCII preview, drag-and-drop import, and registration-based extensibility.

**Architecture:** Add a fourth top-level Toolbox tab that hosts a registered set of tool pages. Keep file parsing/editing/linking in pure Dart services with unit tests; keep UI in focused widgets and `ChangeNotifier` view models that follow the existing Provider pattern.

**Tech Stack:** Flutter, Dart, Material 3, Provider, `file_picker`, `desktop_drop`, `cross_file`, `flutter_test`.

---

## File Structure

- Modify `pubspec.yaml`: add `desktop_drop` and direct `cross_file` dependencies for Windows drag-and-drop file handling.
- Modify `lib/views/home/home_view.dart`: add the top-level Toolbox tab and keep `IndexedStack` state retention.
- Create `lib/views/toolbox/toolbox_view.dart`: toolbox shell, internal tabs, responsive workbench layout.
- Create `lib/views/toolbox/toolbox_tool_registry.dart`: tool definition model and registry list.
- Create `lib/views/toolbox/widgets/file_drop_zone.dart`: shared drag/click import surface.
- Create `lib/views/toolbox/widgets/hex_ascii_viewer.dart`: shared hex/address/ascii viewer.
- Create `lib/views/toolbox/widgets/tool_status_panel.dart`: shared status/error display.
- Create `lib/views/toolbox/tools/hex_to_bin_tool.dart`: HEX-to-BIN tool UI.
- Create `lib/views/toolbox/tools/bin_editor_tool.dart`: BIN editor tool UI.
- Create `lib/views/toolbox/tools/bin_link_tool.dart`: BIN link tool UI.
- Create `lib/models/toolbox/toolbox_file_entry.dart`: imported file entry and status model.
- Create `lib/models/toolbox/bin_edit_operation.dart`: edit operation model.
- Create `lib/models/toolbox/bin_link_segment.dart`: link segment model.
- Create `lib/services/toolbox/hex_text_parser.dart`: user HEX text and address parsing.
- Create `lib/services/toolbox/hex_parser.dart`: Intel HEX parser.
- Create `lib/services/toolbox/bin_editor_service.dart`: insert/replace/delete pure byte operations.
- Create `lib/services/toolbox/bin_link_service.dart`: address-based link/merge pure logic.
- Create `lib/viewmodels/toolbox/hex_to_bin_viewmodel.dart`: import, parse, selection, export state for HEX-to-BIN.
- Create `lib/viewmodels/toolbox/bin_editor_viewmodel.dart`: single-file edit, history, undo, export state.
- Create `lib/viewmodels/toolbox/bin_link_viewmodel.dart`: segment list, preview, conflict state, export state.
- Modify `test/widget_test.dart`: add top-level Toolbox navigation coverage.
- Create `test/toolbox/hex_text_parser_test.dart`: HEX text/address parser tests.
- Create `test/toolbox/hex_parser_test.dart`: Intel HEX tests.
- Create `test/toolbox/bin_editor_service_test.dart`: insert/replace/delete tests.
- Create `test/toolbox/bin_link_service_test.dart`: link/fill/overlap tests.
- Create `test/toolbox/toolbox_widget_test.dart`: toolbox UI and viewer tests.

---

### Task 1: Add Drag-And-Drop Dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependency declarations**

Add these entries under existing dependencies:

```yaml
  # 桌面文件拖拽
  desktop_drop: ^0.7.0
  cross_file: ^0.3.5+2
```

- [ ] **Step 2: Fetch dependencies**

Run: `flutter pub get`

Expected: exit code 0 and `pubspec.lock` updated with `desktop_drop` and `cross_file`.

- [ ] **Step 3: Commit dependency update**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add toolbox drag drop dependencies"
```

---

### Task 2: Implement HEX Text Parsing With TDD

**Files:**
- Create: `test/toolbox/hex_text_parser_test.dart`
- Create: `lib/services/toolbox/hex_text_parser.dart`

- [ ] **Step 1: Write failing parser tests**

```dart
import 'package:clovecom/services/toolbox/hex_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HexTextParser.parseBytes', () {
    test('parses bytes separated by spaces commas and newlines', () {
      final bytes = HexTextParser.parseBytes('01 02,AA\nff');

      expect(bytes, [0x01, 0x02, 0xAA, 0xFF]);
    });

    test('rejects odd-length compact hex text', () {
      expect(
        () => HexTextParser.parseBytes('ABC'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-hex characters', () {
      expect(
        () => HexTextParser.parseBytes('01 ZZ'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HexTextParser.parseNumber', () {
    test('parses decimal and 0x-prefixed values', () {
      expect(HexTextParser.parseNumber('32'), 32);
      expect(HexTextParser.parseNumber('0x20'), 32);
      expect(HexTextParser.parseNumber('0X20'), 32);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/toolbox/hex_text_parser_test.dart`

Expected: FAIL because `package:clovecom/services/toolbox/hex_text_parser.dart` does not exist.

- [ ] **Step 3: Implement parser**

```dart
class HexTextParser {
  const HexTextParser._();

  static List<int> parseBytes(String input) {
    final normalized = input.replaceAll(RegExp(r'[\s,]+'), '');
    if (normalized.isEmpty) {
      return <int>[];
    }
    if (normalized.length.isOdd) {
      throw const FormatException('HEX 数据必须由完整字节组成');
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
      throw const FormatException('HEX 数据包含非法字符');
    }

    final bytes = <int>[];
    for (var index = 0; index < normalized.length; index += 2) {
      bytes.add(int.parse(normalized.substring(index, index + 2), radix: 16));
    }
    return bytes;
  }

  static int parseNumber(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('地址不能为空');
    }
    if (value.startsWith('0x') || value.startsWith('0X')) {
      return int.parse(value.substring(2), radix: 16);
    }
    return int.parse(value, radix: 10);
  }

  static String formatHexByte(int value) {
    if (value < 0 || value > 0xFF) {
      throw const FormatException('填充值必须是单字节');
    }
    return value.toRadixString(16).padLeft(2, '0').toUpperCase();
  }
}
```

- [ ] **Step 4: Run tests to verify GREEN**

Run: `flutter test test/toolbox/hex_text_parser_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/toolbox/hex_text_parser.dart test/toolbox/hex_text_parser_test.dart
git commit -m "feat: add toolbox hex text parser"
```

---

### Task 3: Implement Intel HEX Parsing With TDD

**Files:**
- Create: `test/toolbox/hex_parser_test.dart`
- Create: `lib/services/toolbox/hex_parser.dart`

- [ ] **Step 1: Write failing parser tests**

```dart
import 'package:clovecom/services/toolbox/hex_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses data records into continuous bytes', () {
    final result = IntelHexParser.parse('''
:10010000214601360121470136007EFE09D2190140
:00000001FF
''');

    expect(result.baseAddress, 0x0100);
    expect(result.bytes.length, 16);
    expect(result.bytes.take(4), [0x21, 0x46, 0x01, 0x36]);
  });

  test('fills gaps with FF', () {
    final result = IntelHexParser.parse('''
:020000000102FB
:020004000506EF
:00000001FF
''');

    expect(result.baseAddress, 0x0000);
    expect(result.bytes, [0x01, 0x02, 0xFF, 0xFF, 0x05, 0x06]);
  });

  test('supports extended linear addresses', () {
    final result = IntelHexParser.parse('''
:020000040001F9
:02001000AABB89
:00000001FF
''');

    expect(result.baseAddress, 0x10010);
    expect(result.bytes, [0xAA, 0xBB]);
  });

  test('rejects checksum errors', () {
    expect(
      () => IntelHexParser.parse(':020000000102FC\n:00000001FF'),
      throwsA(isA<FormatException>()),
    );
  });
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/toolbox/hex_parser_test.dart`

Expected: FAIL because `hex_parser.dart` does not exist.

- [ ] **Step 3: Implement Intel HEX parser**

Create `IntelHexParseResult` with `baseAddress` and `bytes`, and `IntelHexParser.parse(String content)`. The parser must:

```dart
class IntelHexParseResult {
  const IntelHexParseResult({
    required this.baseAddress,
    required this.bytes,
  });

  final int baseAddress;
  final List<int> bytes;
}
```

Implementation rules:

```dart
// For every non-empty line:
// 1. Require ':' prefix.
// 2. Decode byte count, 16-bit address, record type, data bytes, checksum.
// 3. Verify ((sum(all decoded bytes including checksum) & 0xFF) == 0).
// 4. Record 00 writes data to current extended base + address.
// 5. Record 01 marks EOF.
// 6. Record 02 sets base to segment << 4.
// 7. Record 04 sets base to linear << 16.
// 8. Reject other record types.
// 9. Reject data after EOF and missing EOF.
// 10. Return continuous bytes from min to max address, filling gaps with 0xFF.
```

- [ ] **Step 4: Run tests to verify GREEN**

Run: `flutter test test/toolbox/hex_parser_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/toolbox/hex_parser.dart test/toolbox/hex_parser_test.dart
git commit -m "feat: add intel hex parser"
```

---

### Task 4: Implement BIN Edit And Link Services With TDD

**Files:**
- Create: `test/toolbox/bin_editor_service_test.dart`
- Create: `test/toolbox/bin_link_service_test.dart`
- Create: `lib/services/toolbox/bin_editor_service.dart`
- Create: `lib/services/toolbox/bin_link_service.dart`
- Create: `lib/models/toolbox/bin_link_segment.dart`

- [ ] **Step 1: Write failing BIN editor tests**

```dart
import 'package:clovecom/services/toolbox/bin_editor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inserts bytes at an address', () {
    expect(
      BinEditorService.insertBytes([0x01, 0x04], 1, [0x02, 0x03]),
      [0x01, 0x02, 0x03, 0x04],
    );
  });

  test('replaces bytes without changing file length', () {
    expect(
      BinEditorService.replaceBytes([0x01, 0x02, 0x03], 1, [0xAA, 0xBB]),
      [0x01, 0xAA, 0xBB],
    );
  });

  test('deletes bytes at an address', () {
    expect(
      BinEditorService.deleteBytes([0x01, 0x02, 0x03, 0x04], 1, 2),
      [0x01, 0x04],
    );
  });

  test('rejects out of range replacement', () {
    expect(
      () => BinEditorService.replaceBytes([0x01], 1, [0xAA]),
      throwsA(isA<RangeError>()),
    );
  });
}
```

- [ ] **Step 2: Write failing BIN link tests**

```dart
import 'package:clovecom/models/toolbox/bin_link_segment.dart';
import 'package:clovecom/services/toolbox/bin_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links segments by address and fills gaps', () {
    final result = BinLinkService.link(
      [
        BinLinkSegment(name: 'a.bin', address: 0x1000, bytes: [0x01, 0x02]),
        BinLinkSegment(name: 'manual', address: 0x1004, bytes: [0xAA]),
      ],
      fillByte: 0xFF,
    );

    expect(result.baseAddress, 0x1000);
    expect(result.bytes, [0x01, 0x02, 0xFF, 0xFF, 0xAA]);
  });

  test('rejects overlapping segments', () {
    expect(
      () => BinLinkService.link(
        [
          BinLinkSegment(name: 'a.bin', address: 0, bytes: [0x01, 0x02]),
          BinLinkSegment(name: 'b.bin', address: 1, bytes: [0xAA]),
        ],
        fillByte: 0xFF,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
```

- [ ] **Step 3: Run tests to verify RED**

Run: `flutter test test/toolbox/bin_editor_service_test.dart test/toolbox/bin_link_service_test.dart`

Expected: FAIL because services and models do not exist.

- [ ] **Step 4: Implement services and segment model**

Use these public APIs:

```dart
class BinEditorService {
  const BinEditorService._();

  static List<int> insertBytes(List<int> source, int address, List<int> bytes);
  static List<int> replaceBytes(List<int> source, int address, List<int> bytes);
  static List<int> deleteBytes(List<int> source, int address, int length);
}
```

```dart
class BinLinkSegment {
  const BinLinkSegment({
    required this.name,
    required this.address,
    required this.bytes,
    this.isManual = false,
  });

  final String name;
  final int address;
  final List<int> bytes;
  final bool isManual;
  int get endAddress => address + bytes.length;
}
```

```dart
class BinLinkResult {
  const BinLinkResult({
    required this.baseAddress,
    required this.bytes,
  });

  final int baseAddress;
  final List<int> bytes;
}

class BinLinkService {
  const BinLinkService._();

  static BinLinkResult link(List<BinLinkSegment> segments, {required int fillByte});
}
```

- [ ] **Step 5: Run tests to verify GREEN**

Run: `flutter test test/toolbox/bin_editor_service_test.dart test/toolbox/bin_link_service_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/toolbox/bin_link_segment.dart lib/services/toolbox/bin_editor_service.dart lib/services/toolbox/bin_link_service.dart test/toolbox/bin_editor_service_test.dart test/toolbox/bin_link_service_test.dart
git commit -m "feat: add toolbox bin services"
```

---

### Task 5: Add Toolbox Navigation And Shared Widgets

**Files:**
- Modify: `lib/views/home/home_view.dart`
- Create: `lib/views/toolbox/toolbox_view.dart`
- Create: `lib/views/toolbox/toolbox_tool_registry.dart`
- Create: `lib/views/toolbox/widgets/hex_ascii_viewer.dart`
- Create: `lib/views/toolbox/widgets/file_drop_zone.dart`
- Create: `lib/views/toolbox/widgets/tool_status_panel.dart`
- Modify: `test/widget_test.dart`
- Create: `test/toolbox/toolbox_widget_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add to `test/widget_test.dart`:

```dart
expect(find.text('工具箱'), findsOneWidget);
```

Create `test/toolbox/toolbox_widget_test.dart`:

```dart
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

  testWidgets('hex ascii viewer shows offsets hex bytes and printable ascii', (tester) async {
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
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/widget_test.dart test/toolbox/toolbox_widget_test.dart`

Expected: FAIL because Toolbox UI files and the top-level tab do not exist.

- [ ] **Step 3: Implement navigation and shared widgets**

Update `HomeView`:

```dart
_tabController = TabController(length: 4, vsync: this);
```

Add a Toolbox `Tab` and `ToolboxView()` as the fourth `IndexedStack` child.

Create `ToolboxToolDefinition`:

```dart
class ToolboxToolDefinition {
  const ToolboxToolDefinition({
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final WidgetBuilder builder;
}
```

Create `ToolboxView` with a `DefaultTabController`, internal `TabBar`, and registered tool pages. Shared widgets should compile even before full tool view models exist by rendering static first-pass controls.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `flutter test test/widget_test.dart test/toolbox/toolbox_widget_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/views/home/home_view.dart lib/views/toolbox test/widget_test.dart test/toolbox/toolbox_widget_test.dart
git commit -m "feat: add toolbox shell"
```

---

### Task 6: Implement Tool ViewModels And Tool Pages

**Files:**
- Create: `lib/models/toolbox/toolbox_file_entry.dart`
- Create: `lib/models/toolbox/bin_edit_operation.dart`
- Create: `lib/viewmodels/toolbox/hex_to_bin_viewmodel.dart`
- Create: `lib/viewmodels/toolbox/bin_editor_viewmodel.dart`
- Create: `lib/viewmodels/toolbox/bin_link_viewmodel.dart`
- Modify: `lib/views/toolbox/tools/hex_to_bin_tool.dart`
- Modify: `lib/views/toolbox/tools/bin_editor_tool.dart`
- Modify: `lib/views/toolbox/tools/bin_link_tool.dart`
- Modify: `test/toolbox/toolbox_widget_test.dart`

- [ ] **Step 1: Add failing UI expectations**

Extend `test/toolbox/toolbox_widget_test.dart`:

```dart
testWidgets('bin editor exposes insert replace and delete controls', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: ToolboxView()));
  await tester.tap(find.text('BIN编辑').last);
  await tester.pumpAndSettle();

  expect(find.text('插入'), findsWidgets);
  expect(find.text('修改'), findsWidgets);
  expect(find.text('删除'), findsWidgets);
  expect(find.text('导出BIN'), findsOneWidget);
});

testWidgets('bin link exposes segment list and fill byte input', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: ToolboxView()));
  await tester.tap(find.text('BIN拼接').last);
  await tester.pumpAndSettle();

  expect(find.text('片段列表'), findsOneWidget);
  expect(find.text('填充值'), findsOneWidget);
  expect(find.text('导出拼接BIN'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/toolbox/toolbox_widget_test.dart`

Expected: FAIL because full tool controls are not implemented.

- [ ] **Step 3: Implement models and view models**

Use these state boundaries:

```dart
enum ToolboxFileStatus { idle, parsed, failed, exported }

class ToolboxFileEntry {
  const ToolboxFileEntry({
    required this.name,
    required this.path,
    required this.extension,
    required this.size,
    required this.status,
    this.bytes,
    this.error,
  });

  final String name;
  final String path;
  final String extension;
  final int size;
  final ToolboxFileStatus status;
  final List<int>? bytes;
  final String? error;
}
```

```dart
enum BinEditOperationType { insert, replace, delete }

class BinEditOperation {
  const BinEditOperation({
    required this.type,
    required this.address,
    required this.length,
  });

  final BinEditOperationType type;
  final int address;
  final int length;
}
```

Each ViewModel should expose synchronous methods for applying already-read bytes, and async file methods for UI import/export:

```dart
void loadBinBytes(String name, String path, List<int> bytes);
void applyInsert(String addressText, String hexText);
void applyReplace(String addressText, String hexText);
void applyDelete(String addressText, String lengthText);
void undoLast();
```

- [ ] **Step 4: Implement tool pages**

Each page should use `ChangeNotifierProvider`, `FileDropZone`, `ToolStatusPanel`, and `HexAsciiViewer`. The first implementation must make these controls visible:

```text
HEX转BIN: 导入HEX/BIN, 转换当前, 批量导出, 文件列表
BIN编辑: 导入BIN, 插入, 修改, 删除, 撤销, 导出BIN
BIN拼接: 导入BIN片段, 新增HEX片段, 片段列表, 填充值, 预览拼接, 导出拼接BIN
```

- [ ] **Step 5: Run tests to verify GREEN**

Run: `flutter test test/toolbox/toolbox_widget_test.dart test/widget_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/toolbox lib/viewmodels/toolbox lib/views/toolbox test/toolbox/toolbox_widget_test.dart test/widget_test.dart
git commit -m "feat: add toolbox tool pages"
```

---

### Task 7: Wire File Import, Drag Drop, Export, And Verification

**Files:**
- Modify: `lib/views/toolbox/widgets/file_drop_zone.dart`
- Modify: `lib/viewmodels/toolbox/hex_to_bin_viewmodel.dart`
- Modify: `lib/viewmodels/toolbox/bin_editor_viewmodel.dart`
- Modify: `lib/viewmodels/toolbox/bin_link_viewmodel.dart`
- Modify: `lib/views/toolbox/tools/hex_to_bin_tool.dart`
- Modify: `lib/views/toolbox/tools/bin_editor_tool.dart`
- Modify: `lib/views/toolbox/tools/bin_link_tool.dart`

- [ ] **Step 1: Implement drag/drop and picker callbacks**

`FileDropZone` should expose:

```dart
class FileDropZone extends StatefulWidget {
  const FileDropZone({
    super.key,
    required this.title,
    required this.subtitle,
    required this.allowedExtensions,
    required this.allowMultiple,
    required this.onFilesSelected,
  });

  final String title;
  final String subtitle;
  final List<String> allowedExtensions;
  final bool allowMultiple;
  final Future<void> Function(List<String> paths) onFilesSelected;
}
```

Use `desktop_drop.DropTarget` for drop events and `FilePicker.platform.pickFiles` for the button path. Normalize extensions to lowercase before filtering.

- [ ] **Step 2: Implement export methods**

Use `FilePicker.platform.saveFile` for single-file export and `FilePicker.platform.getDirectoryPath` for batch export. For all exported data, write via `File(path).writeAsBytes(bytes)`.

Required behavior:

```text
HEX转BIN 当前导出: suggested name = original basename + .bin
HEX转BIN 批量导出: each valid .hex writes basename.bin into selected directory
BIN编辑导出: suggested name = original basename + _edited.bin
BIN拼接导出: suggested name = linked.bin
```

- [ ] **Step 3: Run all toolbox tests**

Run: `flutter test test/toolbox`

Expected: PASS.

- [ ] **Step 4: Run full tests**

Run: `flutter test`

Expected: PASS.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`

Expected: exit code 0 with no errors.

- [ ] **Step 6: Format changed Dart files**

Run: `dart format lib test`

Expected: all changed Dart files formatted.

- [ ] **Step 7: Final verification**

Run again:

```bash
flutter test
flutter analyze
```

Expected: both exit code 0.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib test
git commit -m "feat: add toolbox binary tools"
```

---

## Self-Review

- Spec coverage: covered top-level Toolbox tab, internal tool tabs, three required tools, HEX/ASCII viewer, batch HEX export, BIN edit insert/replace/delete, BIN link with manual HEX segments, drag/drop import, button import/export, error reporting, extensible registry, and test coverage.
- Placeholder scan: this plan contains no placeholder markers or fill-in instructions. Each task has exact files, commands, and expected results.
- Type consistency: model and service names are consistent across tasks: `HexTextParser`, `IntelHexParser`, `BinEditorService`, `BinLinkService`, `ToolboxFileEntry`, `BinEditOperation`, `BinLinkSegment`, and `ToolboxToolDefinition`.
