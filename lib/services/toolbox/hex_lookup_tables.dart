class HexLookupTables {
  HexLookupTables._();

  static final List<String> hexTable = List<String>.generate(256, (i) {
    return i.toRadixString(16).padLeft(2, '0').toUpperCase();
  });

  static final List<String> asciiTable = List<String>.generate(256, (i) {
    if (i >= 0x20 && i <= 0x7E) return String.fromCharCode(i);
    return '.';
  });

  static String hexByte(int byte) => hexTable[byte & 0xFF];
  static String asciiChar(int byte) => asciiTable[byte & 0xFF];

  static String hexLine(List<int> bytes, int start, int end) {
    final buf = StringBuffer();
    for (var i = start; i < end; i++) {
      if (i > start) buf.write(' ');
      buf.write(hexTable[bytes[i] & 0xFF]);
    }
    return buf.toString();
  }

  static String asciiLine(List<int> bytes, int start, int end) {
    final buf = StringBuffer();
    for (var i = start; i < end; i++) {
      buf.write(asciiTable[bytes[i] & 0xFF]);
    }
    return buf.toString();
  }

  static String offsetText(int address) {
    return address.toRadixString(16).padLeft(8, '0').toUpperCase();
  }
}
