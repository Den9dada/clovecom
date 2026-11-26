import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/toolbox/bin_edit_operation.dart';
import '../../models/toolbox/bin_file_entry.dart';

import '../../services/toolbox/hex_text_parser.dart';

class BinEditorViewModel extends ChangeNotifier {
  final List<BinFileEntry> _files = [];
  int? _activeFileIndex;

  List<BinFileEntry> get files => List.unmodifiable(_files);
  int? get activeFileIndex => _activeFileIndex;
  BinFileEntry? get activeFile {
    if (_activeFileIndex == null || _activeFileIndex! >= _files.length) {
      return null;
    }
    return _files[_activeFileIndex!];
  }

  String? get lastError => _lastError;
  String? _lastError;

  bool get hasFile => activeFile != null;
  String get fileName => activeFile?.name ?? '';
  String get filePath => activeFile?.path ?? '';
  // 空态返回规范化 const 空列表：保证 bytes 身份仅在内容真正变化时改变，
  // 供查看器域的 Selector 做廉价相等判定。
  List<int> get bytes => activeFile?.currentBytes ?? const <int>[];
  bool get hasUnsavedChanges =>
      _files.any((f) => f.hasUnsavedChanges) ||
      (activeFile?.hasUnsavedChanges ?? false);
  List<BinEditOperation> get history =>
      List.unmodifiable(activeFile?.history ?? []);

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> importPaths(List<String> paths) async {
    for (final path in paths) {
      try {
        final name = _fileNameFromPath(path);
        final bytes = await File(path).readAsBytes();
        _files.add(BinFileEntry(name: name, path: path, bytes: bytes));
      } catch (error) {
        _lastError = '读取 BIN 文件失败: $error';
      }
    }
    if (_activeFileIndex == null && _files.isNotEmpty) {
      _activeFileIndex = 0;
    }
    notifyListeners();
  }

  void switchToFile(int index) {
    if (index < 0 || index >= _files.length) return;
    _activeFileIndex = index;
    notifyListeners();
  }

  void removeFile(int index) {
    if (index < 0 || index >= _files.length) return;
    _files.removeAt(index);
    if (_activeFileIndex != null && index < _activeFileIndex!) {
      _activeFileIndex = _activeFileIndex! - 1;
    }
    if (_files.isEmpty) {
      _activeFileIndex = null;
    } else if (_activeFileIndex != null && _activeFileIndex! >= _files.length) {
      _activeFileIndex = _files.length - 1;
    }
    notifyListeners();
  }

  void applyInsert(String addressText, String hexText) {
    _applyEdit(
      () => activeFile!.insert(
        HexTextParser.parseNumber(addressText),
        HexTextParser.parseBytes(hexText),
      ),
    );
  }

  void applyReplace(String addressText, String hexText) {
    _applyEdit(
      () => activeFile!.replace(
        HexTextParser.parseNumber(addressText),
        HexTextParser.parseBytes(hexText),
      ),
    );
  }

  void applyDelete(String addressText, String lengthText) {
    _applyEdit(
      () => activeFile!.delete(
        HexTextParser.parseNumber(addressText),
        HexTextParser.parseNumber(lengthText),
      ),
    );
  }

  void replaceByte(int index, String hexText) {
    _applyEdit(() {
      final bytes = HexTextParser.parseBytes(hexText);
      if (bytes.length != 1) throw const FormatException('请输入 1 个字节');
      activeFile!.replace(index, bytes);
    });
  }

  void undoLast() {
    if (activeFile == null || activeFile!.history.isEmpty) return;
    _applyEdit(() => activeFile!.undo());
  }

  Future<void> exportEdited() async {
    final f = activeFile;
    if (f == null) {
      _lastError = '请先导入 BIN 文件';
      notifyListeners();
      return;
    }
    final path = await FilePickerCompat.saveFile(
      dialogTitle: '导出编辑后的BIN文件',
      fileName: '${_baseName(f.name)}_edited.bin',
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (path == null) return;
    final snapshot = f.currentBytes;
    await File(path).writeAsBytes(snapshot);
    f.markSaved(snapshot);
    _lastError = null;
    notifyListeners();
  }

  void _applyEdit(VoidCallback edit) {
    if (activeFile == null) {
      _lastError = '请先导入 BIN 文件';
      notifyListeners();
      return;
    }
    try {
      edit();
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
    notifyListeners();
  }

  String _fileNameFromPath(String path) => path.split(RegExp(r'[\\/]')).last;

  String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }
}
