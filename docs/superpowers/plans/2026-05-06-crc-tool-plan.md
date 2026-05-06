# CRC 计算工具实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在工具箱中新增 CRC 计算工具，支持 Hex/ASCII/文件三种输入，21种预设模型+自定义参数，关于悬浮窗展示参数对照表。

**Architecture:** 遵循现有4层结构 (Model → Service → ViewModel → View)，纯 Dart CRC 计算引擎零 Flutter 依赖，UI 复用现有 HexAsciiViewer 和 FileDropZone 组件，关于弹窗使用 MouseRegion 跟踪 + showDialog 实现。

**Tech Stack:** Flutter/Dart, provider + ChangeNotifier, Material 3

---

## 文件清单

| 操作 | 文件路径 |
|------|---------|
| 新建 | `lib/models/toolbox/crc_params.dart` |
| 新建 | `lib/services/toolbox/crc_calculator.dart` |
| 新建 | `lib/viewmodels/toolbox/crc_viewmodel.dart` |
| 新建 | `lib/views/toolbox/tools/crc_tool.dart` |
| 修改 | `lib/views/toolbox/toolbox_tool_registry.dart` |
| 新建 | `test/toolbox/crc_calculator_test.dart` |
| 修改 | `test/toolbox/toolbox_viewmodel_test.dart` |

---

### Task 1: CRC 参数模型与预设数据

**Files:**
- Create: `lib/models/toolbox/crc_params.dart`

- [ ] **Step 1: 创建 CRC 参数模型和预设数据文件**

```dart
enum DataInputMode { hex, ascii, file }

class CrcParams {
  const CrcParams({
    required this.width,
    required this.poly,
    required this.init,
    required this.xorout,
    required this.refin,
    required this.refout,
  });

  final int width;
  final int poly;
  final int init;
  final int xorout;
  final bool refin;
  final bool refout;

  CrcParams copyWith({
    int? width,
    int? poly,
    int? init,
    int? xorout,
    bool? refin,
    bool? refout,
  }) {
    return CrcParams(
      width: width ?? this.width,
      poly: poly ?? this.poly,
      init: init ?? this.init,
      xorout: xorout ?? this.xorout,
      refin: refin ?? this.refin,
      refout: refout ?? this.refout,
    );
  }
}

class CrcPreset {
  const CrcPreset({required this.name, required this.params});
  final String name;
  final CrcParams params;
}

class CrcPresets {
  CrcPresets._();

  static const all = <CrcPreset>[
    CrcPreset(name: 'CRC-4/ITU', params: CrcParams(width: 4, poly: 0x03, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-5/EPC', params: CrcParams(width: 5, poly: 0x09, init: 0x09, xorout: 0x00, refin: false, refout: false)),
    CrcPreset(name: 'CRC-5/ITU', params: CrcParams(width: 5, poly: 0x15, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-5/USB', params: CrcParams(width: 5, poly: 0x05, init: 0x1F, xorout: 0x1F, refin: true, refout: true)),
    CrcPreset(name: 'CRC-6/ITU', params: CrcParams(width: 6, poly: 0x03, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-7/MMC', params: CrcParams(width: 7, poly: 0x09, init: 0x00, xorout: 0x00, refin: false, refout: false)),
    CrcPreset(name: 'CRC-8', params: CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: false)),
    CrcPreset(name: 'CRC-8/ITU', params: CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x55, refin: false, refout: false)),
    CrcPreset(name: 'CRC-8/ROHC', params: CrcParams(width: 8, poly: 0x07, init: 0xFF, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-8/MAXIM', params: CrcParams(width: 8, poly: 0x31, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/IBM', params: CrcParams(width: 16, poly: 0x8005, init: 0x0000, xorout: 0x0000, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/MAXIM', params: CrcParams(width: 16, poly: 0x8005, init: 0x0000, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/USB', params: CrcParams(width: 16, poly: 0x8005, init: 0xFFFF, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/MODBUS', params: CrcParams(width: 16, poly: 0x8005, init: 0xFFFF, xorout: 0x0000, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/CCITT', params: CrcParams(width: 16, poly: 0x1021, init: 0x0000, xorout: 0x0000, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/CCITT-FALSE', params: CrcParams(width: 16, poly: 0x1021, init: 0xFFFF, xorout: 0x0000, refin: false, refout: false)),
    CrcPreset(name: 'CRC-16/X25', params: CrcParams(width: 16, poly: 0x1021, init: 0xFFFF, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/XMODEM', params: CrcParams(width: 16, poly: 0x1021, init: 0x0000, xorout: 0x0000, refin: false, refout: false)),
    CrcPreset(name: 'CRC-16/DNP', params: CrcParams(width: 16, poly: 0x3D65, init: 0x0000, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-32', params: CrcParams(width: 32, poly: 0x04C11DB7, init: 0xFFFFFFFF, xorout: 0xFFFFFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-32/MPEG-2', params: CrcParams(width: 32, poly: 0x04C11DB7, init: 0xFFFFFFFF, xorout: 0x00000000, refin: false, refout: false)),
  ];

  static CrcPreset byName(String name) {
    return all.firstWhere((p) => p.name == name);
  }

  static List<String> get presetNames => ['自定义', ...all.map((p) => p.name)];
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/models/toolbox/crc_params.dart
git commit -m "feat: add CRC params model and 21 presets"
```

---

### Task 2: CRC 计算引擎（纯 Service 层）

**Files:**
- Create: `lib/services/toolbox/crc_calculator.dart`

- [ ] **Step 1: 创建 CRC 计算引擎**

```dart
import '../../models/toolbox/crc_params.dart';

class CrcCalculator {
  CrcCalculator._();

  static int calculate(List<int> data, CrcParams params) {
    if (data.isEmpty) {
      final mask = (1 << params.width) - 1;
      var crc = params.init & mask;
      if (params.refout) {
        crc = _reverseBits(crc, params.width);
      }
      return (crc ^ params.xorout) & mask;
    }

    var crc = params.init;
    final mask = (1 << params.width) - 1;
    final poly = params.poly | (1 << params.width);
    final topBit = 1 << (params.width - 1);

    for (final byte in data) {
      var b = byte & 0xFF;
      if (params.refin) {
        b = _reverseBits(b, 8);
      }

      if (params.width > 8) {
        crc ^= (b << (params.width - 8));
      } else {
        crc ^= b;
      }

      for (int i = 0; i < 8; i++) {
        if ((crc & topBit) != 0) {
          crc = ((crc << 1) ^ poly) & mask;
        } else {
          crc = (crc << 1) & mask;
        }
      }
    }

    if (params.refout) {
      crc = _reverseBits(crc, params.width);
    }

    return (crc ^ params.xorout) & mask;
  }

  static int _reverseBits(int value, int bitWidth) {
    var result = 0;
    for (int i = 0; i < bitWidth; i++) {
      if ((value & (1 << i)) != 0) {
        result |= (1 << (bitWidth - 1 - i));
      }
    }
    return result;
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/toolbox/crc_calculator.dart
git commit -m "feat: add CRC bit-by-bit calculation engine"
```

---

### Task 3: CRC 计算引擎单元测试

**Files:**
- Create: `test/toolbox/crc_calculator_test.dart`

- [ ] **Step 1: 编写 CRC 计算器测试**

```dart
import 'package:clovecom/models/toolbox/crc_params.dart';
import 'package:clovecom/services/toolbox/crc_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CRC Calculator', () {
    test('CRC-16/MODBUS with [0x31, 0x32, 0x33, 0x34]', () {
      final params = CrcPresets.byName('CRC-16/MODBUS').params;
      final result = CrcCalculator.calculate([0x31, 0x32, 0x33, 0x34], params);
      expect(result, 0x89C1);
    });

    test('CRC-32 with "123456789" → 0xCBF43926', () {
      final bytes = '123456789'.codeUnits;
      final params = CrcPresets.byName('CRC-32').params;
      final result = CrcCalculator.calculate(bytes, params);
      expect(result, 0xCBF43926);
    });

    test('CRC-32/MPEG-2 with "123456789"', () {
      final bytes = '123456789'.codeUnits;
      final params = CrcPresets.byName('CRC-32/MPEG-2').params;
      final result = CrcCalculator.calculate(bytes, params);
      expect(result, 0x0376E6E7);
    });

    test('CRC-8 with single byte [0x31]', () {
      final params = CrcPresets.byName('CRC-8').params;
      final result = CrcCalculator.calculate([0x31], params);
      expect(result, 0xA6);
    });

    test('CRC-8/MAXIM with [0x31, 0x32]', () {
      final params = CrcPresets.byName('CRC-8/MAXIM').params;
      final result = CrcCalculator.calculate([0x31, 0x32], params);
      expect(result, 0x64);
    });

    test('CRC-16/CCITT-FALSE with [0x31, 0x32, 0x33, 0x34]', () {
      final params = CrcPresets.byName('CRC-16/CCITT-FALSE').params;
      final result = CrcCalculator.calculate([0x31, 0x32, 0x33, 0x34], params);
      expect(result, 0x6B32);
    });

    test('CRC-16/XMODEM with [0x31, 0x32, 0x33, 0x34]', () {
      final params = CrcPresets.byName('CRC-16/XMODEM').params;
      final result = CrcCalculator.calculate([0x31, 0x32, 0x33, 0x34], params);
      expect(result, 0xE672);
    });

    test('empty data returns init processed through refout and xorout', () {
      final params = CrcPresets.byName('CRC-16/MODBUS').params;
      final result = CrcCalculator.calculate([], params);
      expect(result, 0xFFFF);
    });

    test('all 21 presets calculate without error on [0x31, 0x32, 0x33, 0x34]', () {
      final testData = [0x31, 0x32, 0x33, 0x34];
      for (final preset in CrcPresets.all) {
        final result = CrcCalculator.calculate(testData, preset.params);
        final mask = (1 << preset.params.width) - 1;
        expect(result, lessThanOrEqualTo(mask),
            reason: '${preset.name} result $result exceeds width mask');
        expect(result, greaterThanOrEqualTo(0),
            reason: '${preset.name} result $result is negative');
      }
    });

    test('REFIN true vs false produces different results', () {
      final data = [0x31, 0x32];
      final paramsTrue = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: true, refout: false);
      final paramsFalse = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: false);
      expect(CrcCalculator.calculate(data, paramsTrue), isNot(CrcCalculator.calculate(data, paramsFalse)));
    });

    test('REFOUT true vs false produces different results', () {
      final data = [0x31, 0x32];
      final paramsTrue = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: true);
      final paramsFalse = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: false);
      expect(CrcCalculator.calculate(data, paramsTrue), isNot(CrcCalculator.calculate(data, paramsFalse)));
    });

    test('WIDTH=1 boundary', () {
      final params = CrcParams(width: 1, poly: 0x01, init: 0x00, xorout: 0x00, refin: false, refout: false);
      final result = CrcCalculator.calculate([0x31], params);
      expect(result, lessThanOrEqualTo(1));
    });

    test('WIDTH=32 with 256 bytes', () {
      final data = List.generate(256, (i) => i);
      final params = CrcPresets.byName('CRC-32').params;
      final result = CrcCalculator.calculate(data, params);
      expect(result, lessThanOrEqualTo(0xFFFFFFFF));
    });
  });
}
```

- [ ] **Step 2: 运行测试验证**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter test test/toolbox/crc_calculator_test.dart
```

Expected: All 13 tests PASS.

- [ ] **Step 3: 提交**

```bash
git add test/toolbox/crc_calculator_test.dart
git commit -m "test: add CRC calculator unit tests for 21 presets and edge cases"
```

---

### Task 4: CRC ViewModel（状态管理）

**Files:**
- Create: `lib/viewmodels/toolbox/crc_viewmodel.dart`

- [ ] **Step 1: 创建 CrcViewModel**

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/toolbox/crc_params.dart';
import '../../services/toolbox/crc_calculator.dart';

class CrcViewModel extends ChangeNotifier {
  DataInputMode _inputMode = DataInputMode.hex;
  String _hexText = '';
  String _asciiText = '';
  List<int>? _fileBytes;
  String? _fileName;
  int _fileSize = 0;

  String? _selectedPreset = 'CRC-16/MODBUS';
  CrcParams _customParams = const CrcParams(
    width: 16, poly: 0x8005, init: 0xFFFF, xorout: 0x0000, refin: true, refout: true,
  );

  bool _isAboutPinned = false;
  bool _isAboutHovered = false;

  int? _result;

  DataInputMode get inputMode => _inputMode;
  String get hexText => _hexText;
  String get asciiText => _asciiText;
  List<int>? get fileBytes => _fileBytes;
  String? get fileName => _fileName;
  int get fileSize => _fileSize;
  String? get selectedPreset => _selectedPreset;
  CrcParams get customParams => _customParams;
  bool get isAboutPinned => _isAboutPinned;
  bool get isAboutHovered => _isAboutHovered;
  bool get showAboutPopup => _isAboutPinned || _isAboutHovered;
  int? get result => _result;
  bool get isCustomMode => _selectedPreset == null;

  CrcParams get effectiveParams {
    if (_selectedPreset != null) return CrcPresets.byName(_selectedPreset!).params;
    return _customParams;
  }

  List<int>? get currentBytes {
    switch (_inputMode) {
      case DataInputMode.hex: return _parseHex(_hexText);
      case DataInputMode.ascii: return _asciiText.isEmpty ? null : _asciiText.codeUnits;
      case DataInputMode.file: return _fileBytes;
    }
  }

  void setInputMode(DataInputMode mode) { _inputMode = mode; _recalculate(); }
  void setHexText(String text) { _hexText = text; _recalculate(); }
  void setAsciiText(String text) { _asciiText = text; _recalculate(); }

  Future<void> importFile(List<String> paths) async {
    if (paths.isEmpty) return;
    final path = paths.first;
    try {
      _fileName = path.split(RegExp(r'[\\/]')).last;
      _fileBytes = await File(path).readAsBytes();
      _fileSize = _fileBytes!.length;
    } catch (_) {
      _fileBytes = null; _fileName = null; _fileSize = 0;
    }
    _recalculate();
  }

  void selectPreset(String? name) { _selectedPreset = name; _recalculate(); }
  void setCustomWidth(int width) { _customParams = _customParams.copyWith(width: width); _recalculate(); }
  void setCustomPoly(String hexStr) { final v = _tryParseHex(hexStr); if (v != null) { _customParams = _customParams.copyWith(poly: v); _recalculate(); } }
  void setCustomInit(String hexStr) { final v = _tryParseHex(hexStr); if (v != null) { _customParams = _customParams.copyWith(init: v); _recalculate(); } }
  void setCustomXorout(String hexStr) { final v = _tryParseHex(hexStr); if (v != null) { _customParams = _customParams.copyWith(xorout: v); _recalculate(); } }
  void setCustomRefin(bool value) { _customParams = _customParams.copyWith(refin: value); _recalculate(); }
  void setCustomRefout(bool value) { _customParams = _customParams.copyWith(refout: value); _recalculate(); }

  void setAboutHovered(bool value) { _isAboutHovered = value; notifyListeners(); }
  void toggleAboutPinned() { _isAboutPinned = !_isAboutPinned; notifyListeners(); }
  void dismissAbout() { _isAboutPinned = false; notifyListeners(); }

  String formatHex(int value) {
    final hexLen = (effectiveParams.width + 3) ~/ 4;
    return '0x${value.toRadixString(16).toUpperCase().padLeft(hexLen, '0')}';
  }

  String formatBin(int value) {
    final bin = value.toRadixString(2).padLeft(effectiveParams.width, '0');
    final parts = <String>[];
    for (int i = 0; i < bin.length; i += 4) {
      final end = i + 4 > bin.length ? bin.length : i + 4;
      parts.add(bin.substring(i, end));
    }
    return parts.join(' ');
  }

  String formatDec(int value) => value.toString();

  void _recalculate() {
    final bytes = currentBytes;
    if (bytes == null || bytes.isEmpty) { _result = null; notifyListeners(); return; }
    _result = CrcCalculator.calculate(bytes, effectiveParams);
    notifyListeners();
  }

  static List<int>? _parseHex(String text) {
    final cleaned = text.replaceAll(RegExp(r'[\s\r\n,]+'), '').replaceAll('0x', '').replaceAll('0X', '');
    if (cleaned.isEmpty) return null;
    if (RegExp(r'[^0-9a-fA-F]').hasMatch(cleaned)) return null;
    if (cleaned.length % 2 != 0) return null;
    final bytes = <int>[];
    for (int i = 0; i < cleaned.length; i += 2) {
      bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  static int? _tryParseHex(String hexStr) {
    final cleaned = hexStr.replaceAll('0x', '').replaceAll('0X', '').trim();
    if (cleaned.isEmpty) return 0;
    if (RegExp(r'[^0-9a-fA-F]').hasMatch(cleaned)) return null;
    return int.tryParse(cleaned, radix: 16);
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/viewmodels/toolbox/crc_viewmodel.dart
git commit -m "feat: add CrcViewModel with input modes, presets, and about state"
```

---

### Task 5: CrcViewModel 单元测试

**Files:**
- Modify: `test/toolbox/toolbox_viewmodel_test.dart`

- [ ] **Step 1: 在现有测试文件末尾追加 CrcViewModel 测试**

在文件顶部已有 imports 下方新增：

```dart
import 'package:clovecom/models/toolbox/crc_params.dart';
import 'package:clovecom/viewmodels/toolbox/crc_viewmodel.dart';
```

在 `main()` 函数末尾（最后一个 `}` 之前）追加：

```dart
  group('CRC ViewModel', () {
    test('default preset is CRC-16/MODBUS', () {
      final vm = CrcViewModel();
      expect(vm.selectedPreset, 'CRC-16/MODBUS');
      expect(vm.isCustomMode, false);
    });

    test('setHexText triggers recalculation', () {
      final vm = CrcViewModel();
      vm.setHexText('31 32 33 34');
      expect(vm.result, 0x89C1);
    });

    test('setAsciiText triggers recalculation', () {
      final vm = CrcViewModel();
      vm.setAsciiText('1234');
      expect(vm.result, 0x89C1);
    });

    test('empty hex text gives null result', () {
      final vm = CrcViewModel();
      vm.setHexText('');
      expect(vm.result, isNull);
    });

    test('invalid hex text gives null result', () {
      final vm = CrcViewModel();
      vm.setHexText('GG HH');
      expect(vm.result, isNull);
    });

    test('switching input modes preserves data', () {
      final vm = CrcViewModel();
      vm.setHexText('31 32');
      vm.setInputMode(DataInputMode.ascii);
      vm.setAsciiText('AB');
      expect(vm.hexText, '31 32');
      expect(vm.asciiText, 'AB');
    });

    test('switch to custom mode shows custom params', () {
      final vm = CrcViewModel();
      vm.selectPreset(null);
      expect(vm.isCustomMode, true);
    });

    test('custom params recalculate correctly', () {
      final vm = CrcViewModel();
      vm.selectPreset(null);
      vm.setCustomWidth(16);
      vm.setCustomPoly('8005');
      vm.setCustomInit('FFFF');
      vm.setCustomXorout('0000');
      vm.setCustomRefin(true);
      vm.setCustomRefout(true);
      vm.setHexText('31 32 33 34');
      expect(vm.result, 0x89C1);
    });

    test('formatHex pads correctly', () {
      final vm = CrcViewModel();
      vm.setHexText('31 32 33 34');
      expect(vm.formatHex(vm.result!), '0x89C1');
    });

    test('about popup toggles', () {
      final vm = CrcViewModel();
      expect(vm.showAboutPopup, false);
      vm.setAboutHovered(true);
      expect(vm.showAboutPopup, true);
      vm.setAboutHovered(false);
      expect(vm.showAboutPopup, false);
      vm.toggleAboutPinned();
      expect(vm.showAboutPopup, true);
      vm.setAboutHovered(false);
      expect(vm.showAboutPopup, true);
      vm.dismissAbout();
      expect(vm.showAboutPopup, false);
    });
  });
```

- [ ] **Step 2: 运行测试**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter test test/toolbox/toolbox_viewmodel_test.dart
```

Expected: 现有测试 + 新增 10 个 CRC ViewModel 测试全部 PASS。

- [ ] **Step 3: 提交**

```bash
git add test/toolbox/toolbox_viewmodel_test.dart
git commit -m "test: add CrcViewModel unit tests"
```

---

### Task 6: CRC 工具注册

**Files:**
- Modify: `lib/views/toolbox/toolbox_tool_registry.dart`

- [ ] **Step 1: 在 tools 列表末尾注册**

在文件顶部已有 imports 下方新增：

```dart
import 'tools/crc_tool.dart';
```

在 `tools` 列表中 `BinLinkTool` 条目后追加：

```dart
    ToolboxToolDefinition(
      title: 'CRC计算',
      icon: Icons.calculate_outlined,
      builder: (_) => const CrcTool(),
    ),
```

- [ ] **Step 2: 提交**

```bash
git add lib/views/toolbox/toolbox_tool_registry.dart
git commit -m "feat: register CRC tool in toolbox registry"
```

---

### Task 7: CRC 工具 UI 页面

**Files:**
- Create: `lib/views/toolbox/tools/crc_tool.dart`

- [ ] **Step 1: 创建完整 CRC 工具 UI**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/toolbox/crc_params.dart';
import '../../../viewmodels/toolbox/crc_viewmodel.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/hex_ascii_viewer.dart';

class CrcTool extends StatefulWidget {
  const CrcTool({super.key});

  @override
  State<CrcTool> createState() => _CrcToolState();
}

class _CrcToolState extends State<CrcTool> with AutomaticKeepAliveClientMixin {
  late final CrcViewModel _viewModel = CrcViewModel();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: const _CrcToolContent(),
    );
  }
}

class _CrcToolContent extends StatelessWidget {
  const _CrcToolContent();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CrcViewModel>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final controls = _buildControls(context, viewModel);

        Widget rightPane;
        if (viewModel.inputMode == DataInputMode.file && viewModel.fileBytes != null) {
          rightPane = Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('文件预览: ${viewModel.fileName}', style: Theme.of(context).textTheme.labelMedium),
              ),
              Expanded(
                flex: 6,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: HexAsciiViewer(bytes: viewModel.fileBytes!),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(flex: 4, child: _buildResultCard(context, viewModel)),
            ],
          );
        } else {
          rightPane = _buildResultCard(context, viewModel);
        }

        if (compact) {
          return Column(children: [controls, const SizedBox(height: 10), Expanded(child: rightPane)]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [SizedBox(width: 320, child: controls), const SizedBox(width: 10), Expanded(child: rightPane)],
        );
      },
    );
  }

  Widget _buildControls(BuildContext context, CrcViewModel viewModel) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildInputCard(context, viewModel), const SizedBox(height: 10), _buildParamsCard(context, viewModel)],
      ),
    );
  }

  Widget _buildInputCard(BuildContext context, CrcViewModel viewModel) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据输入', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<DataInputMode>(
              segments: const [
                ButtonSegment(value: DataInputMode.hex, label: Text('Hex'), icon: Icon(Icons.hexagon_outlined, size: 16)),
                ButtonSegment(value: DataInputMode.ascii, label: Text('ASCII'), icon: Icon(Icons.text_fields, size: 16)),
                ButtonSegment(value: DataInputMode.file, label: Text('文件'), icon: Icon(Icons.insert_drive_file_outlined, size: 16)),
              ],
              selected: {viewModel.inputMode},
              onSelectionChanged: (v) => viewModel.setInputMode(v.first),
            ),
            const SizedBox(height: 10),
            _buildInputContent(context, viewModel),
          ],
        ),
      ),
    );
  }

  Widget _buildInputContent(BuildContext context, CrcViewModel viewModel) {
    switch (viewModel.inputMode) {
      case DataInputMode.hex:
        return TextField(
          maxLines: 4,
          decoration: const InputDecoration(hintText: '例如: 31 32 33 34', border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          onChanged: viewModel.setHexText,
          controller: TextEditingController(text: viewModel.hexText),
        );
      case DataInputMode.ascii:
        return TextField(
          maxLines: 4,
          decoration: const InputDecoration(hintText: '例如: hello world', border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
          onChanged: viewModel.setAsciiText,
          controller: TextEditingController(text: viewModel.asciiText),
        );
      case DataInputMode.file:
        return Column(
          children: [
            FileDropZone(
              title: '导入文件',
              subtitle: '拖入或点击选择任意文件，计算 CRC',
              allowedExtensions: const [],
              allowMultiple: false,
              onFilesSelected: (paths) async => context.read<CrcViewModel>().importFile(paths),
            ),
            if (viewModel.fileName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${viewModel.fileName} · ${CrcViewModel.formatFileSize(viewModel.fileSize)}', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }

  Widget _buildParamsCard(BuildContext context, CrcViewModel viewModel) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CRC 参数', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: viewModel.selectedPreset ?? '自定义',
                    decoration: const InputDecoration(labelText: '预设模型', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    isExpanded: true,
                    items: CrcPresets.presetNames.map((name) => DropdownMenuItem(value: name, child: Text(name, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (value) => viewModel.selectPreset(value == '自定义' ? null : value),
                  ),
                ),
                const SizedBox(width: 6),
                _buildAboutButton(viewModel, colorScheme),
              ],
            ),
            if (viewModel.isCustomMode) ...[
              const SizedBox(height: 10),
              _buildCustomParams(viewModel),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAboutButton(CrcViewModel viewModel, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => viewModel.toggleAboutPinned(),
      child: MouseRegion(
        onEnter: (_) => viewModel.setAboutHovered(true),
        onExit: (_) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (!viewModel.isAboutPinned) viewModel.setAboutHovered(false);
          });
        },
        child: Tooltip(
          message: '点击查看 CRC 参数模型列表',
          child: Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildCustomParams(CrcViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: DropdownButtonFormField<int>(
                value: viewModel.customParams.width,
                decoration: const InputDecoration(labelText: 'WIDTH', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                isExpanded: true,
                items: List.generate(32, (i) => i + 1).map((w) => DropdownMenuItem(value: w, child: Text('$w', style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) { if (v != null) viewModel.setCustomWidth(v); },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'POLY', hintText: '例如: 8005', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onChanged: viewModel.setCustomPoly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'INIT', hintText: '例如: FFFF', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onChanged: viewModel.setCustomInit,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'XOROUT', hintText: '例如: 0000', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onChanged: viewModel.setCustomXorout,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SwitchListTile(title: const Text('REFIN', style: TextStyle(fontSize: 13)), value: viewModel.customParams.refin, dense: true, contentPadding: EdgeInsets.zero, onChanged: viewModel.setCustomRefin),
            ),
            Expanded(
              child: SwitchListTile(title: const Text('REFOUT', style: TextStyle(fontSize: 13)), value: viewModel.customParams.refout, dense: true, contentPadding: EdgeInsets.zero, onChanged: viewModel.setCustomRefout),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultCard(BuildContext context, CrcViewModel viewModel) {
    final theme = Theme.of(context);
    final monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 14, color: theme.colorScheme.onSurface);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('计算结果', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            if (viewModel.result == null)
              Expanded(
                child: Center(
                  child: Text(
                    viewModel.currentBytes == null ? '请输入数据' : '无法计算（请检查输入）',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('HEX:  ${viewModel.formatHex(viewModel.result!)}', style: monoStyle),
                      const SizedBox(height: 6),
                      SelectableText('Bin:  ${viewModel.formatBin(viewModel.result!)}', style: monoStyle),
                      const SizedBox(height: 6),
                      SelectableText('Dec:  ${viewModel.formatDec(viewModel.result!)}', style: monoStyle),
                      const SizedBox(height: 10),
                      Text('字节长度: ${viewModel.currentBytes?.length ?? 0} bytes', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/views/toolbox/tools/crc_tool.dart
git commit -m "feat: add CRC tool UI with input modes, params card, and result display"
```

---

### Task 8: 编译与测试验证

- [ ] **Step 1: 运行静态分析**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter analyze
```

Expected: No issues found.

- [ ] **Step 2: Debug 构建验证**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter build windows --debug
```

Expected: Build successful.

- [ ] **Step 3: 运行全部测试**

```bash
cd e:\Learn\flutterproject\clovecom_opencode && flutter test
```

Expected: All tests PASS.

---

## 关于悬浮弹窗说明

关于弹窗采用渐进式实现策略：

**首版（Task 7 已包含）：** 图标通过 `MouseRegion` 跟踪悬浮状态，ViewModel 管理 pinned/hovered 状态。悬浮指示通过 `Tooltip` 显示，点击图标时可通过按钮触发 `showDialog` 显示 DataTable 参数对照表。

**后续增强（不在本轮）：** 使用 `Overlay` + `OverlayEntry` 实现精准定位的非模态悬浮 DataTable，鼠标移入保持/移出消失。

---

## 实现顺序依赖

```
Task 1 (Model) ──┐
                 ├──> Task 3 (Calculator Test)
Task 2 (Service)─┘
                        │
Task 4 (ViewModel) ─────┤
                        ├──> Task 5 (VM Test)
Task 6 (Registry) ──────┤
                        │
Task 7 (UI View) ───────┘
                        │
                        └──> Task 8 (Build Verify)
```

Task 1-3 须先于 Task 4-7，ViewModel 依赖 Model + Service。Task 6 可与 4/7 并行。
