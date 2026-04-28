class HexAsciiLine {
  const HexAsciiLine({
    required this.offset,
    required this.hex,
    required this.ascii,
  });

  final String offset;
  final String hex;
  final String ascii;
}

class HexAsciiLineFormatter {
  const HexAsciiLineFormatter._();

  static const _hexChars = '0123456789ABCDEF';

  static HexAsciiLine formatLine({
    required List<int> bytes,
    required int start,
    required int end,
    required int address,
  }) {
    final hex = StringBuffer();
    final ascii = StringBuffer();

    for (var index = start; index < end; index++) {
      if (index > start) {
        hex.write(' ');
      }
      final byte = bytes[index] & 0xFF;
      hex
        ..write(_hexChars[byte >> 4])
        ..write(_hexChars[byte & 0x0F]);
      ascii.writeCharCode(byte >= 0x20 && byte <= 0x7E ? byte : 0x2E);
    }

    return HexAsciiLine(
      offset: address.toRadixString(16).padLeft(8, '0').toUpperCase(),
      hex: hex.toString(),
      ascii: ascii.toString(),
    );
  }
}
