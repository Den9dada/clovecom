class BinLinkSegment {
  const BinLinkSegment({
    required this.name,
    required this.address,
    required this.bytes,
    this.isManual = false,
    this.enabled = true,
    this.alignment = 0,
    this.crc,
  });

  final String name;
  final int address;
  final List<int> bytes;
  final bool isManual;
  final bool enabled;
  final int alignment;
  final int? crc;

  int get endAddress => address + bytes.length;

  int get alignedEndAddress {
    if (alignment <= 0) return endAddress;
    final remainder = endAddress % alignment;
    if (remainder == 0) return endAddress;
    return endAddress + alignment - remainder;
  }

  String get sizeFormatted {
    final len = bytes.length;
    if (len >= 1024) {
      final kb = len / 1024;
      if (kb >= 1024) {
        return '${(kb / 1024).toStringAsFixed(1)} MB';
      }
      return '${kb.toStringAsFixed(kb == kb.roundToDouble() ? 0 : 1)} KB';
    }
    return '$len B';
  }

  String get crcHex => crc != null
      ? '0x${crc!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
      : '--';

  BinLinkSegment copyWith({
    String? name,
    int? address,
    List<int>? bytes,
    bool? isManual,
    bool? enabled,
    int? alignment,
    int? crc,
  }) {
    return BinLinkSegment(
      name: name ?? this.name,
      address: address ?? this.address,
      bytes: bytes ?? this.bytes,
      isManual: isManual ?? this.isManual,
      enabled: enabled ?? this.enabled,
      alignment: alignment ?? this.alignment,
      crc: crc ?? this.crc,
    );
  }
}
