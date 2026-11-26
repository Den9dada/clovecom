import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/toolbox/toolbox_file_entry.dart';
import '../../services/toolbox/hex_parser.dart';
import '../../services/toolbox/hex_writer.dart';

class HexToBinViewModel extends ChangeNotifier {
  final List<ToolboxFileEntry> _entries = [];
  int _selectedIndex = -1;
  String? _lastError;

  List<ToolboxFileEntry> get entries => List.unmodifiable(_entries);
  int get selectedIndex => _selectedIndex;
  String? get lastError => _lastError;

  ToolboxFileEntry? get selectedEntry {
    if (_selectedIndex < 0 || _selectedIndex >= _entries.length) {
      return null;
    }
    return _entries[_selectedIndex];
  }

  // 空态返回规范化 const 空列表：保证 selectedBytes 身份仅随选中条目变化，
  // 供查看器域的 Selector 做廉价相等判定。
  List<int> get selectedBytes => selectedEntry?.bytes ?? const <int>[];
  int get selectedBaseAddress => selectedEntry?.baseAddress ?? 0;
  bool get canExportCurrent => selectedEntry?.canExport ?? false;
  bool get canExportCurrentBin => selectedEntry?.canExportBin ?? false;
  bool get canExportCurrentHex => selectedEntry?.canExportHex ?? false;
  bool get canExportBatch => _entries.any((entry) => entry.canExport);
  bool get canExportBatchBin => _entries.any((entry) => entry.canExportBin);
  bool get canExportBatchHex => _entries.any((entry) => entry.canExportHex);

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  void selectEntry(int index) {
    if (index < 0 || index >= _entries.length) {
      return;
    }
    _selectedIndex = index;
    notifyListeners();
  }

  void removeEntry(int index) {
    if (index < 0 || index >= _entries.length) {
      return;
    }
    _entries.removeAt(index);
    if (_entries.isEmpty) {
      _selectedIndex = -1;
    } else if (_selectedIndex >= _entries.length) {
      _selectedIndex = _entries.length - 1;
    } else if (index < _selectedIndex) {
      _selectedIndex--;
    }
    _lastError = null;
    notifyListeners();
  }

  void loadHexContent({
    required String name,
    required String path,
    required String content,
    bool notify = true,
  }) {
    if (_isDuplicatePath(path)) {
      _lastError = '文件已导入: $name';
      if (notify) notifyListeners();
      return;
    }
    try {
      final parsed = IntelHexParser.parse(content);
      _entries.add(
        ToolboxFileEntry(
          name: name,
          path: path,
          extension: 'hex',
          size: content.length,
          status: ToolboxFileStatus.parsed,
          bytes: parsed.bytes,
          baseAddress: parsed.baseAddress,
        ),
      );
      _selectedIndex = _entries.length - 1;
      _lastError = null;
    } catch (error) {
      _entries.add(
        ToolboxFileEntry(
          name: name,
          path: path,
          extension: 'hex',
          size: content.length,
          status: ToolboxFileStatus.failed,
          error: error.toString(),
        ),
      );
      _selectedIndex = _entries.length - 1;
      _lastError = '解析 $name 失败: $error';
    }
    if (notify) notifyListeners();
  }

  void loadBinBytes({
    required String name,
    required String path,
    required List<int> bytes,
    bool notify = true,
  }) {
    if (_isDuplicatePath(path)) {
      _lastError = '文件已导入: $name';
      if (notify) notifyListeners();
      return;
    }
    _entries.add(
      ToolboxFileEntry(
        name: name,
        path: path,
        extension: 'bin',
        size: bytes.length,
        status: ToolboxFileStatus.parsed,
        bytes: bytes,
      ),
    );
    _selectedIndex = _entries.length - 1;
    _lastError = null;
    if (notify) notifyListeners();
  }

  Future<void> importPaths(List<String> paths) async {
    for (final path in paths) {
      final extension = _extension(path);
      final name = _fileName(path);
      try {
        if (extension == 'hex') {
          loadHexContent(
            name: name,
            path: path,
            content: await File(path).readAsString(),
            notify: false,
          );
        } else if (extension == 'bin') {
          loadBinBytes(
            name: name,
            path: path,
            bytes: await File(path).readAsBytes(),
            notify: false,
          );
        } else {
          _lastError = '不支持的文件类型: $name';
        }
      } catch (error) {
        _entries.add(
          ToolboxFileEntry(
            name: name,
            path: path,
            extension: extension,
            size: 0,
            status: ToolboxFileStatus.failed,
            error: error.toString(),
          ),
        );
        _lastError = '读取 $name 失败: $error';
      }
    }
    notifyListeners();
  }

  Future<void> exportCurrent() async {
    final entry = selectedEntry;
    if (entry == null || !entry.canExport || entry.bytes == null) {
      _lastError = '没有可导出的 HEX 文件';
      notifyListeners();
      return;
    }

    final path = await FilePickerCompat.saveFile(
      dialogTitle: '导出BIN文件',
      fileName: '${_baseName(entry.name)}.bin',
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (path == null) {
      return;
    }
    await File(path).writeAsBytes(entry.bytes!);
    _entries[_selectedIndex] = entry.copyWith(
      status: ToolboxFileStatus.exported,
    );
    _lastError = null;
    notifyListeners();
  }

  Future<void> exportBatch() async {
    final validEntries = _entries.where((entry) => entry.canExport).toList();
    if (validEntries.isEmpty) {
      _lastError = '没有可批量导出的 HEX 文件';
      notifyListeners();
      return;
    }

    final directory = await FilePickerCompat.getDirectoryPath(
      dialogTitle: '选择批量导出目录',
    );
    if (directory == null) {
      return;
    }
    for (final entry in validEntries) {
      final output = File(
        '$directory${Platform.pathSeparator}${_baseName(entry.name)}.bin',
      );
      await output.writeAsBytes(entry.bytes!);
    }
    for (var index = 0; index < _entries.length; index++) {
      if (_entries[index].canExport) {
        _entries[index] = _entries[index].copyWith(
          status: ToolboxFileStatus.exported,
        );
      }
    }
    _lastError = null;
    notifyListeners();
  }

  Future<void> exportCurrentHex({int baseAddress = 0}) async {
    final entry = selectedEntry;
    if (entry == null || !entry.canExportHex || entry.bytes == null) {
      _lastError = '没有可导出为HEX的BIN文件';
      notifyListeners();
      return;
    }

    final path = await FilePickerCompat.saveFile(
      dialogTitle: '导出HEX文件',
      fileName: '${_baseName(entry.name)}.hex',
      type: FileType.custom,
      allowedExtensions: const ['hex'],
    );
    if (path == null) return;

    final hexContent = HexWriter.bytesToHex(entry.bytes!,
        baseAddress: baseAddress);
    await File(path).writeAsString(hexContent);
    _entries[_selectedIndex] = entry.copyWith(
      status: ToolboxFileStatus.exported,
    );
    _lastError = null;
    notifyListeners();
  }

  Future<void> exportBatchHex({int baseAddress = 0}) async {
    final validEntries =
        _entries.where((entry) => entry.canExportHex).toList();
    if (validEntries.isEmpty) {
      _lastError = '没有可批量导出为HEX的BIN文件';
      notifyListeners();
      return;
    }

    final directory = await FilePickerCompat.getDirectoryPath(
      dialogTitle: '选择批量导出目录',
    );
    if (directory == null) return;

    for (final entry in validEntries) {
      final hexContent = HexWriter.bytesToHex(entry.bytes!,
          baseAddress: baseAddress);
      final output = File(
        '$directory${Platform.pathSeparator}${_baseName(entry.name)}.hex',
      );
      await output.writeAsString(hexContent);
    }
    for (var index = 0; index < _entries.length; index++) {
      if (_entries[index].canExportHex) {
        _entries[index] = _entries[index].copyWith(
          status: ToolboxFileStatus.exported,
        );
      }
    }
    _lastError = null;
    notifyListeners();
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

  String _extension(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }

  bool _isDuplicatePath(String path) {
    final normalized = path.toLowerCase();
    return _entries.any((entry) => entry.path.toLowerCase() == normalized);
  }
}
