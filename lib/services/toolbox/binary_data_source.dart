
import 'dart:typed_data';

abstract class BinaryDataSource {
  int get length;
  Future<Uint8List> read(int offset, int length);
  Future<void> write(int offset, Uint8List data);
  Future<void> dispose();
}

class MemoryDataSource implements BinaryDataSource {
  final Uint8List _data;

  MemoryDataSource(Uint8List data) : _data = data;

  factory MemoryDataSource.fromList(List<int> bytes) =>
      MemoryDataSource(Uint8List.fromList(bytes));

  @override
  int get length => _data.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final end = (offset + length).clamp(0, _data.length);
    return Uint8List.sublistView(_data, offset, end);
  }

  @override
  Future<void> write(int offset, Uint8List data) async {
    _data.setRange(offset, (offset + data.length).clamp(0, _data.length), data);
  }

  @override
  Future<void> dispose() async {}

  Uint8List get rawData => _data;
}

class EditBuffer {
  final BinaryDataSource _source;
  final Map<int, int> _modifiedBytes = {};
  final Map<int, int> _originalBytes = {};

  EditBuffer(this._source);

  int get length => _source.length;
  bool get hasModifications => _modifiedBytes.isNotEmpty;
  int get modificationCount => _modifiedBytes.length;

  int getByte(int offset) {
    return _modifiedBytes[offset] ?? _source.rawData[offset];
  }

  void setByte(int offset, int value) {
    if (offset < 0 || offset >= length) {
      throw RangeError(offset);
    }
    if ((value & 0xFF) == (_source.rawData[offset] & 0xFF)) {
      _modifiedBytes.remove(offset);
      _originalBytes.remove(offset);
      return;
    }
    _originalBytes.putIfAbsent(offset, () => _source.rawData[offset]);
    _modifiedBytes[offset] = value & 0xFF;
  }

  void setBytes(int offset, List<int> values) {
    for (var i = 0; i < values.length; i++) {
      setByte(offset + i, values[i]);
    }
  }

  int getOriginalByte(int offset) {
    return _originalBytes[offset] ?? _source.rawData[offset];
  }

  void undoByte(int offset) {
    if (!_modifiedBytes.containsKey(offset)) return;
    _modifiedBytes.remove(offset);
    if (_originalBytes.containsKey(offset)) {
      _originalBytes.remove(offset);
    }
  }

  void clear() {
    _modifiedBytes.clear();
    _originalBytes.clear();
  }

  Uint8List buildOutput() {
    final result = Uint8List(length);
    result.setRange(0, length, _source.rawData);
    for (final entry in _modifiedBytes.entries) {
      result[entry.key] = entry.value;
    }
    return result;
  }

  Map<int, int> get modifiedBytes => Map.unmodifiable(_modifiedBytes);
  Map<int, int> get originalBytes => Map.unmodifiable(_originalBytes);
}

extension BinaryDataSourceRaw on BinaryDataSource {
  Uint8List get rawData {
    if (this is MemoryDataSource) {
      return (this as MemoryDataSource).rawData;
    }
    throw UnsupportedError('rawData is only available for MemoryDataSource');
  }
}
