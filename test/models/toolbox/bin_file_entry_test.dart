import 'package:clovecom/models/toolbox/bin_file_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BinFileEntry document() =>
      BinFileEntry(name: 'data.bin', path: '', bytes: [1, 2, 3]);
  test('编辑与撤销统一恢复字节及未保存状态', () {
    final doc = document();
    doc.insert(1, [9]);
    doc.replace(0, [8]);
    doc.delete(2, 1);
    expect(doc.currentBytes, [8, 9, 3]);
    doc.undo();
    doc.undo();
    doc.undo();
    expect(doc.currentBytes, [1, 2, 3]);
    expect(doc.hasUnsavedChanges, isFalse);
  });
  test('保存后撤销按保存基线判断修改', () {
    final doc = document();
    doc.replace(1, [9]);
    doc.markSaved(doc.currentBytes);
    expect(doc.hasUnsavedChanges, isFalse);
    doc.undo();
    expect(doc.hasUnsavedChanges, isTrue);
    doc.replace(1, [9]);
    expect(doc.hasUnsavedChanges, isFalse);
  });
  test('保存旧快照不会吞掉异步导出期间的新编辑', () {
    final doc = document();
    doc.replace(1, [9]);
    final snapshot = doc.currentBytes;
    doc.replace(2, [8]);
    doc.markSaved(snapshot);
    expect(snapshot, [1, 9, 3]);
    expect(doc.hasUnsavedChanges, isTrue);
    doc.undo();
    expect(doc.hasUnsavedChanges, isFalse);
  });
  test('无效编辑不改变字节、历史和版本', () {
    final doc = document();
    expect(() => doc.delete(2, 3), throwsRangeError);
    expect(doc.currentBytes, [1, 2, 3]);
    expect(doc.history, isEmpty);
    expect(doc.revision, 0);
    expect(() => doc.currentBytes[0] = 4, throwsUnsupportedError);
  });
}
