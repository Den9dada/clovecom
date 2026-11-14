import 'bin_edit_operation.dart';
import '../../services/toolbox/bin_editor_service.dart';

/// 二进制编辑文档，统一维护内容、编辑历史和保存基线。
class BinFileEntry {
  final String name;
  final String path;
  final List<int> originalBytes;
  List<int> _currentBytes;
  List<int> _savedBytes;
  final List<BinEditOperation> _history = [];
  int _revision = 0;
  bool _dirty = false;

  List<int> get currentBytes => _currentBytes;
  List<BinEditOperation> get history => List.unmodifiable(_history);
  int get revision => _revision;
  bool get hasUnsavedChanges => _dirty;

  BinFileEntry({
    required this.name,
    required this.path,
    required List<int> bytes,
  }) : originalBytes = List.unmodifiable(bytes),
       _currentBytes = List.unmodifiable(bytes),
       _savedBytes = List.unmodifiable(bytes);

  void insert(int address, List<int> bytes) {
    final updated = BinEditorService.insertBytes(_currentBytes, address, bytes);
    _commit(
      updated,
      BinEditOperation(
        type: BinEditOperationType.insert,
        address: address,
        length: bytes.length,
        deltaBytes: List.unmodifiable(bytes),
      ),
    );
  }

  void replace(int address, List<int> bytes) {
    final updated = BinEditorService.replaceBytes(
      _currentBytes,
      address,
      bytes,
    );
    final previous = _currentBytes.sublist(address, address + bytes.length);
    _commit(
      updated,
      BinEditOperation(
        type: BinEditOperationType.replace,
        address: address,
        length: bytes.length,
        deltaBytes: List.unmodifiable(previous),
      ),
    );
  }

  void delete(int address, int length) {
    final updated = BinEditorService.deleteBytes(
      _currentBytes,
      address,
      length,
    );
    final previous = _currentBytes.sublist(address, address + length);
    _commit(
      updated,
      BinEditOperation(
        type: BinEditOperationType.delete,
        address: address,
        length: length,
        deltaBytes: List.unmodifiable(previous),
      ),
    );
  }

  void undo() {
    if (_history.isEmpty) return;
    final operation = _history.last;
    final updated = switch (operation.type) {
      BinEditOperationType.insert => BinEditorService.deleteBytes(
        _currentBytes,
        operation.address,
        operation.length,
      ),
      BinEditOperationType.replace => BinEditorService.replaceBytes(
        _currentBytes,
        operation.address,
        operation.deltaBytes,
      ),
      BinEditOperationType.delete => BinEditorService.insertBytes(
        _currentBytes,
        operation.address,
        operation.deltaBytes,
      ),
    };
    _history.removeLast();
    _currentBytes = List.unmodifiable(updated);
    _revision++;
    _dirty = !_sameBytes(_currentBytes, _savedBytes);
  }

  /// 保存导出时的快照；异步写入期间的新编辑仍属于未保存修改。
  void markSaved(List<int> exportedBytes) {
    _savedBytes = List.unmodifiable(exportedBytes);
    _dirty = !_sameBytes(_currentBytes, _savedBytes);
  }

  void _commit(List<int> updated, BinEditOperation operation) {
    if (_sameBytes(updated, _currentBytes)) return;
    _currentBytes = List.unmodifiable(updated);
    _history.add(operation);
    _revision++;
    _dirty = !_sameBytes(_currentBytes, _savedBytes);
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
