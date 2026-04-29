class IntelHexParseResult {
  const IntelHexParseResult({required this.baseAddress, required this.bytes});

  final int baseAddress;
  final List<int> bytes;
}

class IntelHexParser {
  const IntelHexParser._();

  static IntelHexParseResult parse(String content) {
    final memory = <int, int>{};
    var extendedBase = 0;
    var sawEof = false;

    final lines = content.split(RegExp(r'\r?\n'));
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final lineNumber = lineIndex + 1;
      final line = lines[lineIndex].trim();
      if (line.isEmpty) {
        continue;
      }
      if (sawEof) {
        throw FormatException('EOF 后存在数据', line, lineNumber);
      }
      if (!line.startsWith(':')) {
        throw FormatException('HEX 行必须以冒号开头', line, lineNumber);
      }

      final raw = line.substring(1);
      if (raw.length < 10 || raw.length.isOdd) {
        throw FormatException('HEX 行长度不完整', line, lineNumber);
      }
      if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(raw)) {
        throw FormatException('HEX 行包含非法字符', line, lineNumber);
      }

      final recordBytes = <int>[];
      for (var index = 0; index < raw.length; index += 2) {
        recordBytes.add(int.parse(raw.substring(index, index + 2), radix: 16));
      }

      final byteCount = recordBytes[0];
      final expectedLength = 5 + byteCount;
      if (recordBytes.length != expectedLength) {
        throw FormatException('HEX 行数据长度与字节数不一致', line, lineNumber);
      }

      final checksum = recordBytes.fold<int>(0, (sum, byte) => sum + byte);
      if ((checksum & 0xFF) != 0) {
        throw FormatException('HEX 校验和错误', line, lineNumber);
      }

      final address = (recordBytes[1] << 8) | recordBytes[2];
      final recordType = recordBytes[3];
      final data = recordBytes.sublist(4, 4 + byteCount);

      switch (recordType) {
        case 0x00:
          final absoluteAddress = extendedBase + address;
          for (var index = 0; index < data.length; index++) {
            memory[absoluteAddress + index] = data[index];
          }
        case 0x01:
          if (byteCount != 0) {
            throw FormatException('EOF 记录不应包含数据', line, lineNumber);
          }
          sawEof = true;
        case 0x02:
          if (byteCount != 2) {
            throw FormatException('扩展段地址记录长度错误', line, lineNumber);
          }
          extendedBase = ((data[0] << 8) | data[1]) << 4;
        case 0x04:
          if (byteCount != 2) {
            throw FormatException('扩展线性地址记录长度错误', line, lineNumber);
          }
          extendedBase = ((data[0] << 8) | data[1]) << 16;
        case 0x05:
          if (byteCount != 4) {
            throw FormatException('起始线性地址记录长度错误', line, lineNumber);
          }
        default:
          throw FormatException('不支持的 HEX 记录类型', line, lineNumber);
      }
    }

    if (!sawEof) {
      throw const FormatException('缺少 EOF 记录');
    }
    if (memory.isEmpty) {
      return const IntelHexParseResult(baseAddress: 0, bytes: <int>[]);
    }

    final addresses = memory.keys.toList()..sort();
    final minAddress = addresses.first;
    final maxAddress = addresses.last;
    final bytes = List<int>.generate(
      maxAddress - minAddress + 1,
      (index) => memory[minAddress + index] ?? 0xFF,
    );

    return IntelHexParseResult(baseAddress: minAddress, bytes: bytes);
  }
}
