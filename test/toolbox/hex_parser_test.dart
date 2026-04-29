import 'package:clovecom/services/toolbox/hex_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses data records into continuous bytes', () {
    final result = IntelHexParser.parse('''
:10010000214601360121470136007EFE09D2190140
:00000001FF
''');

    expect(result.baseAddress, 0x0100);
    expect(result.bytes.length, 16);
    expect(result.bytes.take(4), [0x21, 0x46, 0x01, 0x36]);
  });

  test('fills gaps with FF', () {
    final result = IntelHexParser.parse('''
:020000000102FB
:020004000506EF
:00000001FF
''');

    expect(result.baseAddress, 0x0000);
    expect(result.bytes, [0x01, 0x02, 0xFF, 0xFF, 0x05, 0x06]);
  });

  test('supports extended linear addresses', () {
    final result = IntelHexParser.parse('''
:020000040001F9
:02001000AABB89
:00000001FF
''');

    expect(result.baseAddress, 0x10010);
    expect(result.bytes, [0xAA, 0xBB]);
  });

  test('ignores start linear address records', () {
    final result = IntelHexParser.parse('''
:020000040800F2
:02000000AABB99
:040000050800019559
:00000001FF
''');

    expect(result.baseAddress, 0x08000000);
    expect(result.bytes, [0xAA, 0xBB]);
  });

  test('rejects checksum errors', () {
    expect(
      () => IntelHexParser.parse(':020000000102FC\n:00000001FF'),
      throwsA(isA<FormatException>()),
    );
  });
}
