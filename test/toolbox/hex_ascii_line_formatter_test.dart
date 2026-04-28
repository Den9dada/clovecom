import 'package:clovecom/services/toolbox/hex_ascii_line_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats offset hex and printable ascii without slicing input', () {
    final line = HexAsciiLineFormatter.formatLine(
      bytes: [0x41, 0x00, 0x7A],
      start: 0,
      end: 3,
      address: 0x1000,
    );

    expect(line.offset, '00001000');
    expect(line.hex, '41 00 7A');
    expect(line.ascii, 'A.z');
  });

  test('formats partial lines from a larger byte list', () {
    final line = HexAsciiLineFormatter.formatLine(
      bytes: [0x00, 0x01, 0x20, 0x7E, 0xFF],
      start: 2,
      end: 5,
      address: 0x2002,
    );

    expect(line.offset, '00002002');
    expect(line.hex, '20 7E FF');
    expect(line.ascii, ' ~.');
  });
}
