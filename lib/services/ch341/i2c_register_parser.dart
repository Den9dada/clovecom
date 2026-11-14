// Excel 寄存器映射解析器
//
// 解析符合 SC7061 格式的 .xlsx 寄存器定义文件。
// 格式：元数据区（行 1-11）+ 表头（行 12）+ 寄存器数据区（行 13+）
// 支持多 Sheet（每个 Sheet 为一个模块）。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../../models/i2c_register_map.dart';

class I2cRegisterParser {
  /// 解析 xlsx 文件，返回寄存器映射
  Future<I2cRegisterMap> parse(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return parseBytes(bytes, filePath);
  }

  /// 从字节数据解析
  I2cRegisterMap parseBytes(Uint8List bytes, String filePath) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final errors = <String>[];

    // 1. 读取共享字符串表
    final sharedStrings = _readSharedStrings(archive);

    // 2. 读取第一个工作表
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
    if (sheetFile == null) {
      return I2cRegisterMap(
        filePath: filePath,
        chipConfig: const I2cChipConfig(),
        parseErrors: ['未找到工作表 sheet1.xml'],
      );
    }

    final sheetXml = utf8.decode(sheetFile.content as List<int>);
    final cells = _parseSheetCells(sheetXml, sharedStrings);

    // 3. 提取元数据（行 1-11）
    final chipConfig = _parseMetadata(cells);

    // 4. 提取寄存器定义（行 13+）
    final registers = _parseRegisters(cells, errors);

    return I2cRegisterMap(
      filePath: filePath,
      chipConfig: chipConfig,
      registers: registers,
      parseErrors: errors,
      sheetNames: _readSheetNames(archive),
    );
  }

  // ─── 共享字符串 ──────────────────────────────────────────

  List<String> _readSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return [];
    final xml = utf8.decode(file.content as List<int>);

    final strings = <String>[];
    // 解析 <si>...</si> 块，提取 <t> 内容
    final siRegex = RegExp(r'<si>(.*?)</si>', dotAll: true);
    for (final siMatch in siRegex.allMatches(xml)) {
      final siContent = siMatch.group(1)!;
      final texts = <String>[];
      // 简单文本格式：<t>text</t>
      final simpleTRegex = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
      for (final tMatch in simpleTRegex.allMatches(siContent)) {
        texts.add(tMatch.group(1)!);
      }
      strings.add(_xmlUnescape(texts.join()));
    }
    return strings;
  }

  // ─── Sheet 单元格 ────────────────────────────────────────

  /// 解析工作表 XML，返回 {cellRef → value} 映射
  /// value 可以是 String（共享字符串）或 int（数字）
  Map<String, dynamic> _parseSheetCells(
      String xml, List<String> sharedStrings) {
    final cells = <String, dynamic>{};

    // 匹配单元格: <c r="A1" t="s"><v>0</v></c> 或 <c r="B1" s="15"/>
    // 同时处理自闭合格式和完整格式
    final cellRegex = RegExp(
        r'<c r="([A-Z]+)(\d+)"([^>/]*)(?:/>|>(.*?)</c>)',
        dotAll: true);
    final vRegex = RegExp(r'<v>(.*?)</v>');

    for (final match in cellRegex.allMatches(xml)) {
      final col = match.group(1)!;
      final row = int.parse(match.group(2)!);
      final attrs = match.group(3)!;  // 所有属性
      final cellContent = match.group(4);  // null for self-closing

      if (cellContent == null) continue; // 自闭合单元格，无值

      final vMatch = vRegex.firstMatch(cellContent);
      if (vMatch == null) continue;

      // 判断是否为共享字符串引用
      final isString = attrs.contains('t="s"');

      final rawValue = vMatch.group(1)!;
      final key = '$col$row';

      if (isString) {
        // 共享字符串引用
        final idx = int.tryParse(rawValue);
        if (idx != null && idx < sharedStrings.length) {
          cells[key] = sharedStrings[idx];
        }
      } else {
        // 数字或布尔值
        final numValue = int.tryParse(rawValue);
        if (numValue != null) {
          cells[key] = numValue;
        }
        // 也尝试解析十六进制
        if (numValue == null && rawValue.startsWith('0x', 0)) {
          cells[key] = rawValue;
        }
      }
    }
    return cells;
  }

  // ─── 元数据解析（行 1-11）─────────────────────────────────

  I2cChipConfig _parseMetadata(Map<String, dynamic> cells) {
    String? getValue(String col, int row) => cells['$col$row']?.toString();

    return I2cChipConfig(
      moduleName: getValue('A', 1) ?? 'Module Registers',
      version: getValue('C', 2) ?? '',
      interfaceType: getValue('C', 3) ?? 'I2C',
      speed: int.tryParse(getValue('C', 4) ?? '') ?? 400,
      deviceAddress: _parseHexOrInt(getValue('C', 5) ?? '0x00'),
      baseAddress: _parseHexOrInt(getValue('C', 6) ?? '0x00'),
      littleEndian:
          (getValue('C', 7) ?? '').toLowerCase().contains('little'),
      multiModule: getValue('A', 8) != null,
      registerSetOffset: _parseHexOrIntNullable(getValue('C', 9)),
      registerClearOffset: _parseHexOrIntNullable(getValue('C', 10)),
    );
  }

  // ─── 寄存器解析（行 13+）──────────────────────────────────

  List<I2cRegister> _parseRegisters(
      Map<String, dynamic> cells, List<String> errors) {
    final registers = <I2cRegister>[];
    I2cRegister? currentReg;
    List<I2cRegisterBitField> currentFields = [];

    // 从行 13 开始扫描
    for (int row = 13; row < 300; row++) {
      final aVal = cells['A$row']?.toString();
      final bVal = cells['B$row'];

      if (aVal != null && aVal.isNotEmpty && bVal != null) {
        // 新寄存器：先保存上一个
        if (currentReg != null) {
          registers.add(I2cRegister(
            name: currentReg.name,
            offset: currentReg.offset,
            bitFields: List.from(currentFields),
          ));
        }

        final offset = _extractNumber(bVal);
        if (offset != null) {
          currentReg = I2cRegister(
            name: aVal,
            offset: offset,
            bitFields: [],
          );
          currentFields = [];
        } else {
          // 不是有效的偏移地址，可能解析错误
          currentReg = null;
          currentFields = [];
        }
        continue;
      }

      // 解析位域行：C 列格式 "M:N" 或 "M"
      final cVal = cells['C$row']?.toString();
      if (cVal == null || cVal == 'Bits' || cVal.isEmpty) continue;

      if (currentReg == null) continue;

      final parts = cVal.split(':');
      if (parts.length == 2) {
        final msb = int.tryParse(parts[0]);
        final lsb = int.tryParse(parts[1]);
        if (msb == null || lsb == null) continue;

        final dVal = cells['D$row']?.toString() ?? '';
        final eVal = cells['E$row']?.toString() ?? 'RW';
        final fVal = cells['F$row']?.toString();
        final gVal = cells['G$row']?.toString() ?? '';

        final defaultValue = _parseHexOrInt(fVal ?? '0');
        final gain = _extractParam(gVal, 'gain');
        final offsetVal = _extractParam(gVal, 'offset')?.toInt();

        currentFields.add(I2cRegisterBitField(
          msb: msb,
          lsb: lsb,
          fieldName: dVal,
          access: eVal,
          defaultValue: defaultValue,
          description: gVal,
          gain: gain,
          offsetValue: offsetVal,
        ));
      } else if (parts.length == 1) {
        // 单个位
        final bit = int.tryParse(parts[0]);
        if (bit == null) continue;

        final dVal = cells['D$row']?.toString() ?? '';
        final eVal = cells['E$row']?.toString() ?? 'RW';
        final fVal = cells['F$row']?.toString();
        final gVal = cells['G$row']?.toString() ?? '';

        final defaultValue = _parseHexOrInt(fVal ?? '0');

        currentFields.add(I2cRegisterBitField(
          msb: bit,
          lsb: bit,
          fieldName: dVal,
          access: eVal,
          defaultValue: defaultValue,
          description: gVal,
        ));
      }
    }

    // 保存最后一个寄存器
    if (currentReg != null) {
      registers.add(I2cRegister(
        name: currentReg.name,
        offset: currentReg.offset,
        bitFields: List.from(currentFields),
      ));
    }

    return registers;
  }

  // ─── Sheet 列表 ──────────────────────────────────────────

  List<String> _readSheetNames(Archive archive) {
    final workbookFile = archive.findFile('xl/workbook.xml');
    if (workbookFile == null) return ['Sheet1'];
    final xml = utf8.decode(workbookFile.content as List<int>);
    final nameRegex = RegExp(r'name="([^"]*)"');
    return nameRegex.allMatches(xml).map((m) => m.group(1)!).toList();
  }

  // ─── 辅助 ────────────────────────────────────────────────

  /// 从单元格值提取数字（可能是 int 或 String）
  int? _extractNumber(dynamic val) {
    if (val is int) return val;
    if (val is String) return _parseHexOrIntNullable(val);
    return null;
  }

  int _parseHexOrInt(String s) => _parseHexOrIntNullable(s) ?? 0;

  int? _parseHexOrIntNullable(String? s) {
    if (s == null || s.isEmpty) return null;
    s = s.trim().toLowerCase();
    if (s.startsWith('0x')) {
      return int.tryParse(s.substring(2), radix: 16);
    }
    return int.tryParse(s);
  }

  /// 从描述文本中提取 <param> 值
  double? _extractParam(String text, String param) {
    // 格式：<VALUE:gain> 或 <VALUE:offset>（VALUE 在前，param 在后）
    final regex = RegExp('<([\\d.]+):$param>', caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// XML 实体解码
  String _xmlUnescape(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#10;', '\n')
        .replaceAll('&#13;', '\r');
  }
}
