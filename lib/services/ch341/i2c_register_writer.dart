// Excel 寄存器映射生成器（反向导出）
//
// 将当前 I2cRegisterMap（含从芯片读取的 currentValue）导出为 xlsx 文件，
// 保持与导入格式完全一致的结构，仅更新 F 列 Value(hex) 为当前读取值。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../../models/i2c_register_map.dart';

class I2cRegisterWriter {
  /// 导出寄存器映射到 xlsx 文件
  Future<void> writeToFile(I2cRegisterMap map, String outputPath) async {
    final bytes = buildXlsx(map);
    final file = File(outputPath);
    await file.writeAsBytes(bytes);
  }

  /// 构建 xlsx 字节数据
  Uint8List buildXlsx(I2cRegisterMap map) {
    final archive = Archive();

    // ─── 1. [Content_Types].xml ──────────────────
    archive.addFile(_fileBytes('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>'''));

    // ─── 2. _rels/.rels ──────────────────────────
    archive.addFile(_fileBytes('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>'''));

    // ─── 3. xl/_rels/workbook.xml.rels ───────────
    archive.addFile(_fileBytes('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>'''));

    // ─── 4. xl/styles.xml ────────────────────────
    archive.addFile(_fileBytes('xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0"/></numFmts>
  <fonts count="2">
    <font><sz val="11"/><name val="Microsoft YaHei"/></font>
    <font><sz val="11"/><name val="Microsoft YaHei"/><b/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>
  </cellXfs>
</styleSheet>'''));

    // ─── 5. xl/workbook.xml ──────────────────────
    archive.addFile(_fileBytes('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Module" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>'''));

    // ─── 6. xl/sharedStrings.xml + sheet1.xml ────

    final sharedStrings = <String>[];
    final cells = _buildCells(map, sharedStrings);

    // Shared strings XML
    final ssb = StringBuffer();
    ssb.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    ssb.writeln(
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${sharedStrings.length}" uniqueCount="${sharedStrings.length}">');
    for (final s in sharedStrings) {
      ssb.writeln('<si><t>${_xmlEscape(s)}</t></si>');
    }
    ssb.writeln('</sst>');
    archive.addFile(_fileBytes('xl/sharedStrings.xml', ssb.toString()));

    // Sheet XML
    final sheet = StringBuffer();
    sheet.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sheet.writeln(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    sheet.writeln('<sheetData>');
    for (final entry in cells.entries) {
      final row = entry.key;
      final rowCells = entry.value as List<_CellData>;
      sheet.writeln('<row r="$row">');
      for (final cell in rowCells) {
        if (cell.isString) {
          sheet.writeln(
              '<c r="${cell.ref}" t="s"><v>${cell.value}</v></c>');
        } else {
          sheet.writeln('<c r="${cell.ref}"><v>${cell.value}</v></c>');
        }
      }
      sheet.writeln('</row>');
    }
    sheet.writeln('</sheetData>');
    sheet.writeln('</worksheet>');
    archive.addFile(_fileBytes('xl/worksheets/sheet1.xml', sheet.toString()));

    // ─── 7. Zip 压缩 ─────────────────────────────
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded!);
  }

  // ─── 构建单元格数据 ──────────────────────────────────────

  /// {row: [CellData, ...]}
  Map<int, List<_CellData>> _buildCells(
      I2cRegisterMap map, List<String> sharedStrings) {
    final config = map.chipConfig;
    final cells = <int, List<_CellData>>{};

    void addString(int row, String col, String text) {
      final idx = sharedStrings.indexOf(text);
      if (idx >= 0) {
        cells.putIfAbsent(row, () => []).add(_CellData('$col$row', idx, true));
      } else {
        sharedStrings.add(text);
        cells.putIfAbsent(row, () => [])
            .add(_CellData('$col$row', sharedStrings.length - 1, true));
      }
    }

    void addStringRows(int row, Map<String, String> rowData) {
      for (final entry in rowData.entries) {
        addString(row, entry.key, entry.value);
      }
    }

    // 行 1: 标题
    addString(1, 'A', config.moduleName);

    // 行 2-11: 元数据
    addStringRows(2, {'A': 'Version', 'C': config.version});
    addStringRows(3, {'A': 'Interface', 'C': config.interfaceType});
    addStringRows(4, {'A': 'Speed', 'C': config.speed.toString()});
    addStringRows(
        5, {'A': 'Device Address', 'C': config.deviceAddressHex});
    addStringRows(6, {
      'A': 'Base Address',
      'C': '0x${config.baseAddress.toRadixString(16).padLeft(8, '0').toUpperCase()}'
    });
    addStringRows(7,
        {'A': 'Byte Order', 'C': config.littleEndian ? 'little-endian' : 'big-endian'});
    if (config.multiModule) {
      addString(8, 'A', 'Multi Module');
    }
    if (config.registerSetOffset != null) {
      addStringRows(9, {
        'A': 'Register Set Offset',
        'C': '0x${config.registerSetOffset!.toRadixString(16).toUpperCase()}'
      });
    }
    if (config.registerClearOffset != null) {
      addStringRows(10, {
        'A': 'Register Clear Offset',
        'C': '0x${config.registerClearOffset!.toRadixString(16).toUpperCase()}'
      });
    }
    addStringRows(11, {'A': 'Option'});

    // 行 12: 表头
    addStringRows(12, {
      'A': 'Register Name',
      'B': 'Offset',
      'C': 'Bit Field',
      'D': 'Field Name',
      'E': 'Access',
      'F': 'Value(hex)',
      'G': 'Description',
    });

    // 行 13+: 寄存器数据
    int row = 13;
    for (final reg in map.registers) {
      // 寄存器名称 + 偏移
      addString(row, 'A', reg.name);
      final offsetKey = 'B$row';
      cells.putIfAbsent(row, () => []).add(
          _CellData(offsetKey, reg.offset, false)); // 数字格式
      // 位域表头 "Bits"
      addString(row, 'C', 'Bits');
      addString(row, 'D', 'Field Name');
      addString(row, 'E', 'Access');
      addString(row, 'F', 'Value(hex)');
      addString(row, 'G', 'Description');
      row++;

      // 各位域
      for (final bf in reg.bitFields) {
        final bitStr = bf.msb == bf.lsb ? '${bf.msb}' : '${bf.msb}:${bf.lsb}';
        addString(row, 'C', bitStr);
        addString(row, 'D', bf.fieldName);
        addString(row, 'E', bf.access);

        // F 列：优先使用 currentValue 解码后的位域值
        int displayValue;
        if (reg.currentValue != null) {
          displayValue = bf.extract(reg.currentValue!);
        } else if (reg.editingValue != null) {
          displayValue = bf.extract(reg.editingValue!);
        } else {
          displayValue = bf.defaultValue;
        }
        final hexVal =
            '0x${displayValue.toRadixString(16).toUpperCase().padLeft(((bf.width + 3) ~/ 4).clamp(1, 2), '0')}';
        addString(row, 'F', hexVal);

        // G 列：描述（含 gain/offset 参数）
        addString(row, 'G', bf.description);
        row++;
      }
    }

    return cells;
  }

  // ─── 辅助 ────────────────────────────────────────────────

  ArchiveFile _fileBytes(String path, String content) {
    final data = utf8.encode(content);
    final file = ArchiveFile(path, data.length, data);
    // xlsx 文件内容必须使用 UTF-8 且在 zip 中标记
    return file;
  }

  String _dateString() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;')
        .replaceAll('\n', '&#10;');
  }
}

/// 单元格数据
class _CellData {
  final String ref; // 如 "A13"
  final dynamic value; // int（数字）或 int（共享字符串索引）
  final bool isString; // true = 共享字符串引用

  _CellData(this.ref, this.value, this.isString);
}
