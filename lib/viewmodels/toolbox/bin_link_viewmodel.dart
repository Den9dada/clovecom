import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/toolbox/bin_link_segment.dart';
import '../../services/toolbox/bin_link_service.dart';
import '../../services/toolbox/hex_text_parser.dart';

class BinLinkViewModel extends ChangeNotifier {
  final List<BinLinkSegment> _segments = [];
  int _fillByte = 0xFF;
  BinLinkResult _preview = const BinLinkResult(baseAddress: 0, bytes: <int>[]);
  String? _lastError;

  List<BinLinkSegment> get segments => List.unmodifiable(_segments);
  int get fillByte => _fillByte;
  String get fillByteHex => HexTextParser.formatHexByte(_fillByte);
  List<int> get previewBytes => _preview.bytes;
  int get previewBaseAddress => _preview.baseAddress;
  String? get lastError => _lastError;
  bool get canExport => _segments.isNotEmpty && _lastError == null;

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> importPaths(List<String> paths) async {
    for (final path in paths) {
      try {
        _segments.add(
          BinLinkSegment(
            name: _fileNameFromPath(path),
            address: _nextAddress(),
            bytes: await File(path).readAsBytes(),
          ),
        );
      } catch (error) {
        _lastError = '读取 BIN 片段失败: $error';
      }
    }
    _refreshPreview();
  }

  void addManualHex({required String addressText, required String hexText}) {
    try {
      final address = HexTextParser.parseNumber(addressText);
      final bytes = HexTextParser.parseBytes(hexText);
      if (bytes.isEmpty) {
        throw const FormatException('手动 HEX 数据不能为空');
      }
      if (!_replaceOverlappingSegment(address, bytes)) {
        _segments.add(
          BinLinkSegment(
            name: '手动HEX ${_segments.length + 1}',
            address: address,
            bytes: bytes,
            isManual: true,
          ),
        );
      }
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
      return;
    }
    _refreshPreview();
  }

  void updateSegmentAddress(int index, String addressText) {
    if (index < 0 || index >= _segments.length) {
      return;
    }
    try {
      final address = HexTextParser.parseNumber(addressText);
      _segments[index] = _segments[index].copyWith(address: address);
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
      return;
    }
    _refreshPreview();
  }

  void removeSegment(int index) {
    if (index < 0 || index >= _segments.length) {
      return;
    }
    _segments.removeAt(index);
    _refreshPreview();
  }

  void setFillByte(String text) {
    try {
      final bytes = HexTextParser.parseBytes(text);
      if (bytes.length != 1) {
        throw const FormatException('填充值必须是单字节');
      }
      _fillByte = bytes.single;
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
      return;
    }
    _refreshPreview();
  }

  Future<void> exportLinked() async {
    _refreshPreview();
    if (!canExport) {
      _lastError ??= '没有可导出的拼接结果';
      notifyListeners();
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出拼接BIN文件',
      fileName: 'linked.bin',
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (path == null) {
      return;
    }
    await File(path).writeAsBytes(_preview.bytes);
    _lastError = null;
    notifyListeners();
  }

  void _refreshPreview() {
    try {
      _preview = BinLinkService.link(_segments, fillByte: _fillByte);
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
    notifyListeners();
  }

  int _nextAddress() {
    if (_segments.isEmpty) {
      return 0;
    }
    return _segments
        .map((segment) => segment.endAddress)
        .reduce((previous, current) => previous > current ? previous : current);
  }

  String _fileNameFromPath(String path) => path.split(RegExp(r'[\\/]')).last;

  bool _replaceOverlappingSegment(int address, List<int> bytes) {
    final endAddress = address + bytes.length;
    for (var index = 0; index < _segments.length; index++) {
      final segment = _segments[index];
      final fullyInside =
          address >= segment.address && endAddress <= segment.endAddress;
      if (!fullyInside) {
        continue;
      }

      final updatedBytes = [...segment.bytes];
      final start = address - segment.address;
      for (var byteIndex = 0; byteIndex < bytes.length; byteIndex++) {
        updatedBytes[start + byteIndex] = bytes[byteIndex];
      }
      _segments[index] = segment.copyWith(bytes: updatedBytes);
      return true;
    }
    return false;
  }
}
