class HexWriter {
  HexWriter._();

  static const _maxDataLen = 16;

  /// 将字节数组转换为 Intel HEX 格式文本
  static String bytesToHex(List<int> bytes, {int baseAddress = 0}) {
    if (bytes.isEmpty) return ':00000001FF\n';

    final buf = StringBuffer();
    final hi = (baseAddress >> 16) & 0xFFFF;
    if (hi != 0) {
      buf.write(_extendedLinearAddressRecord(hi));
    }

    for (var offset = 0; offset < bytes.length; offset += _maxDataLen) {
      final end = (offset + _maxDataLen).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      buf.write(_dataRecord(baseAddress + offset, chunk));
    }

    buf.write(':00000001FF\n');
    return buf.toString();
  }

  /// 数据记录 (类型 00)
  static String _dataRecord(int address, List<int> data) {
    final addrLow = address & 0xFFFF;
    final buf = StringBuffer();
    buf.write(':');
    buf.write(data.length.toRadixString(16).padLeft(2, '0').toUpperCase());
    buf.write(
        addrLow.toRadixString(16).padLeft(4, '0').toUpperCase());
    buf.write('00');
    for (final b in data) {
      buf.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    final checksum = _computeChecksum(data.length, addrLow, 0x00, data);
    buf.write(
        checksum.toRadixString(16).padLeft(2, '0').toUpperCase());
    buf.write('\n');
    return buf.toString();
  }

  /// 扩展线性地址记录 (类型 04)
  static String _extendedLinearAddressRecord(int hiAddr) {
    final data = [hiAddr >> 8, hiAddr & 0xFF];
    final buf = StringBuffer();
    buf.write(':02000004');
    for (final b in data) {
      buf.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    final checksum = _computeChecksum(2, 0, 0x04, data);
    buf.write(
        checksum.toRadixString(16).padLeft(2, '0').toUpperCase());
    buf.write('\n');
    return buf.toString();
  }

  /// 每行校验和：取所有字节和的低8位的二进制补码
  static int _computeChecksum(
      int byteCount, int address, int recordType, List<int> data) {
    var sum = byteCount + (address >> 8) + (address & 0xFF) + recordType;
    for (final b in data) {
      sum += b;
    }
    return (0x100 - (sum & 0xFF)) & 0xFF;
  }
}
