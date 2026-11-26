import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../models/toolbox/crc_file_entry.dart';
import '../../models/toolbox/crc_params.dart';
import '../../services/toolbox/crc_calculator.dart';

class CrcViewModel extends ChangeNotifier {
  DataInputMode _inputMode = DataInputMode.hex;
  String _hexText = '';
  String _asciiText = '';
  final List<CrcFileEntry> _files = [];

  String? _selectedPreset = 'CRC-16/MODBUS';
  CrcParams _customParams = const CrcParams(
    width: 16,
    poly: 0x8005,
    init: 0xFFFF,
    xorout: 0x0000,
    refin: true,
    refout: true,
  );

  bool _isAboutPinned = false;
  int _aboutHoverCount = 0;

  int? _result;

  DataInputMode get inputMode => _inputMode;
  String get hexText => _hexText;
  String get asciiText => _asciiText;
  List<CrcFileEntry> get files => List.unmodifiable(_files);
  bool get hasFiles => _files.isNotEmpty;
  String? get selectedPreset => _selectedPreset;
  CrcParams get customParams => _customParams;
  bool get isAboutPinned => _isAboutPinned;
  bool get showAboutPopup => _aboutHoverCount > 0 || _isAboutPinned;
  int? get result => _result;
  bool get isCustomMode => _selectedPreset == null;

  CrcParams get effectiveParams {
    if (_selectedPreset != null) {
      return CrcPresets.byName(_selectedPreset!).params;
    }
    return _customParams;
  }

  List<CrcFileEntry> get selectedFiles =>
      _files.where((f) => f.selected).toList();

  List<int>? get currentBytes {
    switch (_inputMode) {
      case DataInputMode.hex:
        return _parseHex(_hexText);
      case DataInputMode.ascii:
        return _asciiText.isEmpty ? null : _asciiText.codeUnits;
      case DataInputMode.file:
        final selected = selectedFiles;
        if (selected.isEmpty) return null;
        final all = <int>[];
        for (final f in selected) {
          all.addAll(f.bytes);
        }
        return all;
    }
  }

  int get selectedFileSize {
    var total = 0;
    for (final f in selectedFiles) {
      total += f.size;
    }
    return total;
  }

  void setInputMode(DataInputMode mode) {
    _inputMode = mode;
    _recalculate();
  }

  void setHexText(String text) {
    _hexText = text;
    _recalculate();
  }

  void setAsciiText(String text) {
    _asciiText = text;
    _recalculate();
  }

  Future<void> importFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final name = path.split(RegExp(r'[\\/]')).last;
        final bytes = await File(path).readAsBytes();
        _files.add(CrcFileEntry(
          name: name,
          path: path,
          bytes: bytes,
          size: bytes.length,
        ));
      } catch (_) {
        // 跳过无法读取的文件
      }
    }
    _recalculate();
  }

  void removeFile(int index) {
    if (index < 0 || index >= _files.length) return;
    _files.removeAt(index);
    _recalculate();
  }

  void toggleFileSelection(int index) {
    if (index < 0 || index >= _files.length) return;
    _files[index].selected = !_files[index].selected;
    _recalculate();
  }

  void selectPreset(String? name) {
    _selectedPreset = name;
    _recalculate();
  }

  void setCustomWidth(int width) {
    _customParams = _customParams.copyWith(width: width);
    _recalculate();
  }

  void setCustomPoly(String hexStr) {
    final v = _tryParseHex(hexStr);
    if (v != null) {
      _customParams = _customParams.copyWith(poly: v);
      _recalculate();
    }
  }

  void setCustomInit(String hexStr) {
    final v = _tryParseHex(hexStr);
    if (v != null) {
      _customParams = _customParams.copyWith(init: v);
      _recalculate();
    }
  }

  void setCustomXorout(String hexStr) {
    final v = _tryParseHex(hexStr);
    if (v != null) {
      _customParams = _customParams.copyWith(xorout: v);
      _recalculate();
    }
  }

  void setCustomRefin(bool value) {
    _customParams = _customParams.copyWith(refin: value);
    _recalculate();
  }

  void setCustomRefout(bool value) {
    _customParams = _customParams.copyWith(refout: value);
    _recalculate();
  }

  void enterAboutHover() {
    _aboutHoverCount++;
    notifyListeners();
  }

  void exitAboutHover() {
    if (_aboutHoverCount > 0) _aboutHoverCount--;
    notifyListeners();
  }

  void toggleAboutPinned() {
    _isAboutPinned = !_isAboutPinned;
    notifyListeners();
  }

  void dismissAbout() {
    _isAboutPinned = false;
    _aboutHoverCount = 0;
    notifyListeners();
  }

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

  String formatDec(int value) {
    return value.toString();
  }

  void _recalculate() {
    final bytes = currentBytes;
    if (bytes == null || bytes.isEmpty) {
      _result = null;
      notifyListeners();
      return;
    }
    _result = CrcCalculator.calculate(bytes, effectiveParams);
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }

  static List<int>? _parseHex(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[\s\r\n,]+'), '')
        .replaceAll('0x', '')
        .replaceAll('0X', '');
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
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
