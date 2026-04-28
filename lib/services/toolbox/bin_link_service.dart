import '../../models/toolbox/bin_link_segment.dart';

class BinLinkResult {
  const BinLinkResult({required this.baseAddress, required this.bytes});

  final int baseAddress;
  final List<int> bytes;
}

class BinLinkService {
  const BinLinkService._();

  static BinLinkResult link(
    List<BinLinkSegment> segments, {
    required int fillByte,
  }) {
    if (fillByte < 0 || fillByte > 0xFF) {
      throw RangeError.value(fillByte, 'fillByte', '填充值必须是单字节');
    }
    if (segments.isEmpty) {
      return const BinLinkResult(baseAddress: 0, bytes: <int>[]);
    }

    final sorted = [...segments]
      ..sort((a, b) => a.address.compareTo(b.address));
    for (final segment in sorted) {
      if (segment.address < 0) {
        throw RangeError.value(segment.address, 'address', '地址不能为负数');
      }
    }

    for (var index = 1; index < sorted.length; index++) {
      final previous = sorted[index - 1];
      final current = sorted[index];
      if (current.address < previous.endAddress) {
        throw StateError('片段地址重叠: ${previous.name} 与 ${current.name}');
      }
    }

    final baseAddress = sorted.first.address;
    final endAddress = sorted
        .map((segment) => segment.endAddress)
        .reduce((previous, current) => previous > current ? previous : current);
    final output = List<int>.filled(endAddress - baseAddress, fillByte);

    for (final segment in sorted) {
      final start = segment.address - baseAddress;
      for (var index = 0; index < segment.bytes.length; index++) {
        output[start + index] = segment.bytes[index];
      }
    }

    return BinLinkResult(baseAddress: baseAddress, bytes: output);
  }
}
