class HexTextParser {
  const HexTextParser._();

  static List<int> parseBytes(String input) {
    final normalized = input.replaceAll(RegExp(r'[\s,]+'), '');
    if (normalized.isEmpty) {
      return <int>[];
    }
    if (normalized.length.isOdd) {
      throw const FormatException('HEX 数据必须由完整字节组成');
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
      throw const FormatException('HEX 数据包含非法字符');
    }

    final bytes = <int>[];
    for (var index = 0; index < normalized.length; index += 2) {
      bytes.add(int.parse(normalized.substring(index, index + 2), radix: 16));
    }
    return bytes;
  }

  static int parseNumber(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('地址不能为空');
    }
    if (value.startsWith('0x') || value.startsWith('0X')) {
      return int.parse(value.substring(2), radix: 16);
    }
    return int.parse(value, radix: 10);
  }

  static String formatHexByte(int value) {
    if (value < 0 || value > 0xFF) {
      throw const FormatException('填充值必须是单字节');
    }
    return value.toRadixString(16).padLeft(2, '0').toUpperCase();
  }
}
