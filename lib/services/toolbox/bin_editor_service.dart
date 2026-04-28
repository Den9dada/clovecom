class BinEditorService {
  const BinEditorService._();

  static List<int> insertBytes(List<int> source, int address, List<int> bytes) {
    _checkInsertRange(source, address);
    return <int>[
      ...source.take(address),
      ...bytes,
      ...source.skip(address),
    ];
  }

  static List<int> replaceBytes(List<int> source, int address, List<int> bytes) {
    _checkRange(source, address, bytes.length);
    return <int>[
      ...source.take(address),
      ...bytes,
      ...source.skip(address + bytes.length),
    ];
  }

  static List<int> deleteBytes(List<int> source, int address, int length) {
    if (length <= 0) {
      throw RangeError.value(length, 'length', '删除长度必须大于 0');
    }
    _checkRange(source, address, length);
    return <int>[
      ...source.take(address),
      ...source.skip(address + length),
    ];
  }

  static void _checkInsertRange(List<int> source, int address) {
    if (address < 0 || address > source.length) {
      throw RangeError.range(address, 0, source.length, 'address');
    }
  }

  static void _checkRange(List<int> source, int address, int length) {
    if (address < 0 || address > source.length) {
      throw RangeError.range(address, 0, source.length, 'address');
    }
    if (address + length > source.length) {
      throw RangeError.range(address + length, 0, source.length, 'endAddress');
    }
  }
}
