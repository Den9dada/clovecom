import '../../models/toolbox/bin_link_segment.dart';
import '../../models/toolbox/crc_params.dart';
import 'crc_calculator.dart';

/// 同一次规划的布局、诊断、统计与输出，冲突时没有旧输出。
class BinLinkResult {
  const BinLinkResult({
    required this.baseAddress,
    required this.bytes,
    this.outputCrc32,
    this.paddingBytes = 0,
    this.enabledCount = 0,
    this.originalSize = 0,
    this.layoutEndAddress = 0,
    this.overlappingPairs = const [],
    this.error,
  });
  final int baseAddress;
  final List<int> bytes;
  final int? outputCrc32;
  final int paddingBytes;
  final int enabledCount;
  final int originalSize;
  final int layoutEndAddress;
  final List<({int i, int j})> overlappingPairs;
  final String? error;
  bool get canExport => enabledCount > 0 && error == null;
}

class BinLinkService {
  const BinLinkService._();
  static final _crc32Params = CrcPresets.byName('CRC-32').params;
  static int computeSegmentCrc(List<int> bytes) =>
      bytes.isEmpty ? 0 : CrcCalculator.calculate(bytes, _crc32Params);
  static int computeOutputCrc(List<int> bytes) => computeSegmentCrc(bytes);

  static int alignAddress(int address, int alignment) {
    if (alignment <= 0) return address;
    final remainder = address % alignment;
    return remainder == 0 ? address : address + alignment - remainder;
  }

  static List<({int i, int j})> findOverlaps(List<BinLinkSegment> segments) {
    final sorted =
        segments.asMap().entries.where((e) => e.value.enabled).toList()
          ..sort((a, b) => a.value.address.compareTo(b.value.address));
    return _conflicts(sorted);
  }

  static List<({int i, int j})> _conflicts(
    List<MapEntry<int, BinLinkSegment>> sorted,
  ) {
    final pairs = <({int i, int j})>[];
    for (var i = 0; i < sorted.length; i++) {
      final a = sorted[i];
      if (a.value.alignedEndAddress <= a.value.address) continue;
      for (var j = i + 1; j < sorted.length; j++) {
        final b = sorted[j];
        if (b.value.address >= a.value.alignedEndAddress) break;
        if (b.value.alignedEndAddress > b.value.address) {
          pairs.add((i: a.key, j: b.key));
        }
      }
    }
    return List.unmodifiable(pairs);
  }

  static BinLinkResult plan(
    List<BinLinkSegment> segments, {
    required int fillByte,
  }) {
    final sorted =
        segments.asMap().entries.where((e) => e.value.enabled).toList()
          ..sort((a, b) => a.value.address.compareTo(b.value.address));
    final conflicts = _conflicts(sorted);
    final originalSize = sorted.fold<int>(
      0,
      (total, e) => total + e.value.bytes.length,
    );
    final end = sorted.fold<int>(
      0,
      (max, e) =>
          e.value.alignedEndAddress > max ? e.value.alignedEndAddress : max,
    );
    String? error;
    if (fillByte < 0 || fillByte > 0xFF) {
      error = '填充值必须是单字节';
    } else if (sorted.any((e) => e.value.address < 0)) {
      error = '地址不能为负数';
    } else if (conflicts.isNotEmpty) {
      error =
          '片段地址重叠: ${conflicts.map((p) => '${segments[p.i].name} 与 ${segments[p.j].name}').join('；')}';
    }
    if (error != null || sorted.isEmpty) {
      return BinLinkResult(
        baseAddress: 0,
        bytes: const [],
        enabledCount: sorted.length,
        originalSize: originalSize,
        layoutEndAddress: end,
        overlappingPairs: conflicts,
        error: error,
      );
    }
    final bytes = List<int>.filled(end, fillByte);
    for (final entry in sorted) {
      bytes.setRange(
        entry.value.address,
        entry.value.address + entry.value.bytes.length,
        entry.value.bytes,
      );
    }
    return BinLinkResult(
      baseAddress: 0,
      bytes: List.unmodifiable(bytes),
      outputCrc32: computeOutputCrc(bytes),
      paddingBytes: end - originalSize,
      enabledCount: sorted.length,
      originalSize: originalSize,
      layoutEndAddress: end,
    );
  }

  /// 保留原有算法入口，所有规则由规划统一决定。
  static BinLinkResult link(
    List<BinLinkSegment> segments, {
    required int fillByte,
  }) {
    final result = plan(segments, fillByte: fillByte);
    if (result.error != null) {
      if (fillByte < 0 ||
          fillByte > 0xFF ||
          segments.any((s) => s.enabled && s.address < 0)) {
        throw RangeError(result.error);
      }
      throw StateError(result.error!);
    }
    return result;
  }
}
