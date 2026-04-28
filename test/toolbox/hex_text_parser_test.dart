import 'package:clovecom/services/toolbox/hex_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HexTextParser.parseBytes', () {
    test('parses bytes separated by spaces commas and newlines', () {
      final bytes = HexTextParser.parseBytes('01 02,AA\nff');

      expect(bytes, [0x01, 0x02, 0xAA, 0xFF]);
    });

    test('rejects odd-length compact hex text', () {
      expect(
        () => HexTextParser.parseBytes('ABC'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-hex characters', () {
      expect(
        () => HexTextParser.parseBytes('01 ZZ'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HexTextParser.parseNumber', () {
    test('parses decimal and 0x-prefixed values', () {
      expect(HexTextParser.parseNumber('32'), 32);
      expect(HexTextParser.parseNumber('0x20'), 32);
      expect(HexTextParser.parseNumber('0X20'), 32);
    });
  });
}
