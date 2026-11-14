import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:flutter/material.dart';

import '../../models/toolbox/bin_link_segment.dart';
import '../../services/toolbox/bin_link_service.dart';
import '../../services/toolbox/hex_text_parser.dart';

class BinLinkViewModel extends ChangeNotifier {
  final List<BinLinkSegment> _segments = [];
  int _fillByte = 0xFF;
  BinLinkResult _preview = const BinLinkResult(baseAddress: 0, bytes: <int>[]);
  String? _lastError;
  // 布局修订号：仅在规划真正变化（_refreshPreview）时自增。
  // painter 用它做 O(1) 重绘判定，取代脆弱的 List 身份比较；
  // 改名/清错误等不影响布局几何的通知不会触发布局重绘。
  int _layoutRevision = 0;

  List<BinLinkSegment> get segments => List.unmodifiable(_segments);
  int get layoutRevision => _layoutRevision;
  int get fillByte => _fillByte;
  String get fillByteHex => HexTextParser.formatHexByte(_fillByte);
  List<int> get previewBytes => _preview.bytes;
  int get previewBaseAddress => _preview.baseAddress;
  int get previewEndAddress => _preview.layoutEndAddress;
  String? get lastError => _lastError ?? _preview.error;
  bool get canExport => _preview.canExport && _lastError == null;

  int get enabledCount => _preview.enabledCount;
  int get totalOriginalSize => _preview.originalSize;
  int get totalPaddedSize => _preview.bytes.length;
  int get paddingBytes => _preview.paddingBytes;
  int? get outputCrc32 => _preview.outputCrc32;

  String get outputCrc32Hex => _preview.outputCrc32 != null
      ? '0x${_preview.outputCrc32!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
      : '--';

  String get totalUsedFormatted => _formatSize(totalOriginalSize);
  String get totalPaddedFormatted => _formatSize(totalPaddedSize);
  String get paddingFormatted => _formatSize(paddingBytes);

  bool get hasConflicts => _preview.overlappingPairs.isNotEmpty;
  String get conflictStatus => hasConflicts ? '检测到重叠' : '无冲突';

  List<({int i, int j})> get overlappingPairs => _preview.overlappingPairs;

  int getSegmentCrc(int index) {
    if (index < 0 || index >= _segments.length) return 0;
    return BinLinkService.computeSegmentCrc(_segments[index].bytes);
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> importPaths(List<String> paths) async {
    for (final path in paths) {
      try {
        final bytes = await File(path).readAsBytes();
        final crc = BinLinkService.computeSegmentCrc(bytes);
        _segments.add(
          BinLinkSegment(
            name: _fileNameFromPath(path),
            address: _nextAddress(),
            bytes: bytes,
            crc: crc,
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
      final crc = BinLinkService.computeSegmentCrc(bytes);
      if (!_replaceOverlappingSegment(address, bytes)) {
        _segments.add(
          BinLinkSegment(
            name: '手动HEX ${_segments.length + 1}',
            address: address,
            bytes: bytes,
            isManual: true,
            crc: crc,
          ),
        );
      } else {
        final idx = _segments.indexWhere(
          (s) =>
              address >= s.address && (address + bytes.length) <= s.endAddress,
        );
        if (idx >= 0) {
          final crc = BinLinkService.computeSegmentCrc(_segments[idx].bytes);
          _segments[idx] = _segments[idx].copyWith(crc: crc);
        }
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

  void updateSegmentName(int index, String name) {
    if (index < 0 || index >= _segments.length) return;
    _segments[index] = _segments[index].copyWith(name: name);
    notifyListeners();
  }

  void removeSegment(int index) {
    if (index < 0 || index >= _segments.length) {
      return;
    }
    _segments.removeAt(index);
    _refreshPreview();
  }

  void toggleSegmentEnabled(int index) {
    if (index < 0 || index >= _segments.length) return;
    _segments[index] = _segments[index].copyWith(
      enabled: !_segments[index].enabled,
    );
    _refreshPreview();
  }

  void updateSegmentAlignment(int index, int alignment) {
    if (index < 0 || index >= _segments.length) return;
    _segments[index] = _segments[index].copyWith(alignment: alignment);
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

  void setFillByteValue(int value) {
    if (value < 0 || value > 0xFF) return;
    _fillByte = value;
    _refreshPreview();
  }

  void autoArrange() {
    if (_segments.isEmpty) return;
    // 从地址 0 开始，按顺序延顺放置，消除所有重叠
    var nextAddress = 0;
    for (var i = 0; i < _segments.length; i++) {
      final alignedAddr = BinLinkService.alignAddress(
        nextAddress,
        _segments[i].alignment,
      );
      _segments[i] = _segments[i].copyWith(address: alignedAddr);
      nextAddress = alignedAddr + _segments[i].bytes.length;
    }
    _lastError = null;
    _refreshPreview();
  }

  String checkConflicts() {
    _refreshPreview();
    return _preview.error ?? '未检测到冲突';
  }

  Future<void> exportLinked() async {
    _refreshPreview();
    if (!canExport) {
      _lastError ??= '没有可导出的拼接结果';
      notifyListeners();
      return;
    }
    final snapshot = _preview.bytes;
    final path = await FilePickerCompat.saveFile(
      dialogTitle: '导出拼接BIN文件',
      fileName: 'linked.bin',
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (path == null) {
      return;
    }
    await File(path).writeAsBytes(snapshot);
    _lastError = null;
    notifyListeners();
  }

  void _refreshPreview() {
    _preview = BinLinkService.plan(_segments, fillByte: _fillByte);
    _lastError = null;
    _layoutRevision++;
    notifyListeners();
  }

  int _nextAddress() {
    if (_segments.isEmpty) {
      return 0;
    }
    return _segments
        .map((segment) => segment.alignedEndAddress)
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

  String _formatSize(int bytes) {
    if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(kb == kb.roundToDouble() ? 0 : 1)} KB';
    }
    return '$bytes B';
  }
}
