import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/toolbox/bin_edit_operation.dart';
import '../../services/toolbox/bin_editor_service.dart';
import '../../services/toolbox/hex_text_parser.dart';

class BinEditorViewModel extends ChangeNotifier {
  String _fileName = '';
  String _filePath = '';
  List<int> _bytes = [];
  bool _hasUnsavedChanges = false;
  String? _lastError;
  final List<BinEditOperation> _history = [];

  String get fileName => _fileName;
  String get filePath => _filePath;
  List<int> get bytes => _bytes;
  bool get hasFile => _fileName.isNotEmpty;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  String? get lastError => _lastError;
  List<BinEditOperation> get history => List.unmodifiable(_history);

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  void loadBinBytes({
    required String name,
    required String path,
    required List<int> bytes,
  }) {
    _fileName = name;
    _filePath = path;
    _bytes = [...bytes];
    _hasUnsavedChanges = false;
    _history.clear();
    _lastError = null;
    notifyListeners();
  }

  Future<void> importPaths(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    final path = paths.first;
    try {
      loadBinBytes(
        name: _fileNameFromPath(path),
        path: path,
        bytes: await File(path).readAsBytes(),
      );
    } catch (error) {
      _lastError = '读取 BIN 文件失败: $error';
      notifyListeners();
    }
  }

  void applyInsert(String addressText, String hexText) {
    _applyEdit(() {
      final address = HexTextParser.parseNumber(addressText);
      final insertBytes = HexTextParser.parseBytes(hexText);
      _bytes = BinEditorService.insertBytes(_bytes, address, insertBytes);
      _history.add(
        BinEditOperation(
          type: BinEditOperationType.insert,
          address: address,
          length: insertBytes.length,
          deltaBytes: insertBytes,
        ),
      );
    });
  }

  void applyReplace(String addressText, String hexText) {
    _applyEdit(() {
      final address = HexTextParser.parseNumber(addressText);
      final replaceBytes = HexTextParser.parseBytes(hexText);
      final oldBytes = _bytes.sublist(
        address,
        (address + replaceBytes.length).clamp(0, _bytes.length),
      );
      _bytes = BinEditorService.replaceBytes(_bytes, address, replaceBytes);
      _history.add(
        BinEditOperation(
          type: BinEditOperationType.replace,
          address: address,
          length: replaceBytes.length,
          deltaBytes: oldBytes,
        ),
      );
    });
  }

  void applyDelete(String addressText, String lengthText) {
    _applyEdit(() {
      final address = HexTextParser.parseNumber(addressText);
      final length = HexTextParser.parseNumber(lengthText);
      final end = (address + length).clamp(0, _bytes.length);
      final deletedBytes = _bytes.sublist(address, end);
      _bytes = BinEditorService.deleteBytes(_bytes, address, length);
      _history.add(
        BinEditOperation(
          type: BinEditOperationType.delete,
          address: address,
          length: length,
          deltaBytes: deletedBytes,
        ),
      );
    });
  }

  void replaceByte(int index, String hexText) {
    _applyEdit(() {
      final bytes = HexTextParser.parseBytes(hexText);
      if (bytes.length != 1) {
        throw const FormatException('请输入 1 个字节');
      }
      final oldByte = _bytes[index];
      _bytes = BinEditorService.replaceBytes(_bytes, index, bytes);
      _history.add(
        BinEditOperation(
          type: BinEditOperationType.replace,
          address: index,
          length: 1,
          deltaBytes: [oldByte],
        ),
      );
    });
  }

  void undoLast() {
    if (_history.isEmpty) {
      return;
    }
    final operation = _history.removeLast();
    switch (operation.type) {
      case BinEditOperationType.insert:
        _bytes = BinEditorService.deleteBytes(
          _bytes,
          operation.address,
          operation.length,
        );
      case BinEditOperationType.replace:
        _bytes = BinEditorService.replaceBytes(
          _bytes,
          operation.address,
          operation.deltaBytes,
        );
      case BinEditOperationType.delete:
        _bytes = BinEditorService.insertBytes(
          _bytes,
          operation.address,
          operation.deltaBytes,
        );
    }
    _hasUnsavedChanges = _history.isNotEmpty;
    _lastError = null;
    notifyListeners();
  }

  Future<void> exportEdited() async {
    if (!hasFile) {
      _lastError = '请先导入 BIN 文件';
      notifyListeners();
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出编辑后的BIN文件',
      fileName: '${_baseName(_fileName)}_edited.bin',
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (path == null) {
      return;
    }
    await File(path).writeAsBytes(_bytes);
    _hasUnsavedChanges = false;
    _lastError = null;
    notifyListeners();
  }

  void _applyEdit(VoidCallback edit) {
    if (!hasFile) {
      _lastError = '请先导入 BIN 文件';
      notifyListeners();
      return;
    }
    try {
      edit();
      _hasUnsavedChanges = true;
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
