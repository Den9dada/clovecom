import 'package:clovecom/models/toolbox/crc_params.dart';
import 'package:clovecom/services/toolbox/crc_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CRC Calculator', () {
    test('CRC-16/MODBUS with [0x31, 0x32, 0x33, 0x34]', () {
      final params = CrcPresets.byName('CRC-16/MODBUS').params;
      final result = CrcCalculator.calculate([0x31, 0x32, 0x33, 0x34], params);
      expect(result, 0x30BA);
    });

    test('CRC-32 with "123456789" -> 0xCBF43926', () {
      final bytes = '123456789'.codeUnits;
      final params = CrcPresets.byName('CRC-32').params;
      final result = CrcCalculator.calculate(bytes, params);
      expect(result, 0xCBF43926);
    });

    test('CRC-32/MPEG-2 with "123456789"', () {
      final bytes = '123456789'.codeUnits;
      final params = CrcPresets.byName('CRC-32/MPEG-2').params;
      final result = CrcCalculator.calculate(bytes, params);
      expect(result, 0x0376E6E7);
    });

    test('CRC-8 with single byte [0x31]', () {
      final params = CrcPresets.byName('CRC-8').params;
      final result = CrcCalculator.calculate([0x31], params);
      expect(result, 0x97);
    });

    test('CRC-8/MAXIM with [0x31, 0x32]', () {
      final params = CrcPresets.byName('CRC-8/MAXIM').params;
      final result = CrcCalculator.calculate([0x31, 0x32], params);
      expect(result, 0xEB);
    });

    test('CRC-16/CCITT-FALSE with [0x31, 0x32, 0x33, 0x34]', () {
      final params = CrcPresets.byName('CRC-16/CCITT-FALSE').params;
      final result = CrcCalculator.calculate([0x31, 0x32, 0x33, 0x34], params);
      expect(result, 0x5349);
    });

    test('CRC-16/XMODEM with [0x31, 0x32, 0x33, 0x34]', () {
      final params = CrcPresets.byName('CRC-16/XMODEM').params;
      final result = CrcCalculator.calculate([0x31, 0x32, 0x33, 0x34], params);
      expect(result, 0xD789);
    });

    test('empty data returns init processed through refout and xorout', () {
      final params = CrcPresets.byName('CRC-16/MODBUS').params;
      final result = CrcCalculator.calculate([], params);
      expect(result, 0xFFFF);
    });

    test('all 21 presets calculate without error on [0x31, 0x32, 0x33, 0x34]', () {
      final testData = [0x31, 0x32, 0x33, 0x34];
      for (final preset in CrcPresets.all) {
        final result = CrcCalculator.calculate(testData, preset.params);
        final mask = (1 << preset.params.width) - 1;
        expect(result, lessThanOrEqualTo(mask),
            reason: '${preset.name} result $result exceeds width mask');
        expect(result, greaterThanOrEqualTo(0),
            reason: '${preset.name} result $result is negative');
      }
    });

    test('REFIN true vs false produces different results', () {
      final data = [0x31, 0x32];
      final paramsTrue = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: true, refout: false);
      final paramsFalse = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: false);
      expect(CrcCalculator.calculate(data, paramsTrue), isNot(CrcCalculator.calculate(data, paramsFalse)));
    });

    test('REFOUT true vs false produces different results', () {
      final data = [0x31, 0x32];
      final paramsTrue = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: true);
      final paramsFalse = CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: false);
      expect(CrcCalculator.calculate(data, paramsTrue), isNot(CrcCalculator.calculate(data, paramsFalse)));
    });

    test('WIDTH=1 boundary', () {
      final params = CrcParams(width: 1, poly: 0x01, init: 0x00, xorout: 0x00, refin: false, refout: false);
      final result = CrcCalculator.calculate([0x31], params);
      expect(result, lessThanOrEqualTo(1));
    });

    test('WIDTH=32 with 256 bytes', () {
      final data = List.generate(256, (i) => i);
      final params = CrcPresets.byName('CRC-32').params;
      final result = CrcCalculator.calculate(data, params);
      expect(result, lessThanOrEqualTo(0xFFFFFFFF));
    });
  });
}
