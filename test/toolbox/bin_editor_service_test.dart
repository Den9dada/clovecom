import 'package:clovecom/services/toolbox/bin_editor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inserts bytes at an address', () {
    expect(BinEditorService.insertBytes([0x01, 0x04], 1, [0x02, 0x03]), [
      0x01,
      0x02,
      0x03,
      0x04,
    ]);
  });

  test('replaces bytes without changing file length', () {
    expect(BinEditorService.replaceBytes([0x01, 0x02, 0x03], 1, [0xAA, 0xBB]), [
      0x01,
      0xAA,
      0xBB,
    ]);
  });

  test('deletes bytes at an address', () {
    expect(BinEditorService.deleteBytes([0x01, 0x02, 0x03, 0x04], 1, 2), [
      0x01,
      0x04,
    ]);
  });

  test('rejects out of range replacement', () {
    expect(
      () => BinEditorService.replaceBytes([0x01], 1, [0xAA]),
      throwsA(isA<RangeError>()),
    );
  });
}
