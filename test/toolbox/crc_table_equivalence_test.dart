import 'dart:math';

import 'package:clovecom/models/toolbox/crc_params.dart';
import 'package:clovecom/services/toolbox/crc_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 独立逐位 oracle：复刻查表优化前的原始算法，用于对拍验证
/// 查表路径（width>=8）与逐位路径在所有预设上结果完全一致。
int _referenceCrc(List<int> data, CrcParams p) {
  final mask = (1 << p.width) - 1;
  if (data.isEmpty) {
    var crc = p.init & mask;
    if (p.refout) crc = _reflect(crc, p.width);
    return (crc ^ p.xorout) & mask;
  }
  var crc = p.init & mask;
  if (p.refin) {
    final rp = _reflect(p.poly, p.width);
    for (final b in data) {
      crc ^= b & 0xFF;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ rp : crc >> 1;
      }
    }
    crc &= mask;
  } else {
    final poly = p.poly | (1 << p.width);
    final top = 1 << (p.width - 1);
    for (final b in data) {
      crc ^= p.width > 8 ? (b & 0xFF) << (p.width - 8) : (b & 0xFF);
      for (var i = 0; i < 8; i++) {
        crc = (crc & top) != 0 ? ((crc << 1) ^ poly) & mask : (crc << 1) & mask;
      }
    }
  }
  if (p.refout != p.refin) crc = _reflect(crc, p.width);
  return (crc ^ p.xorout) & mask;
}

int _reflect(int value, int width) {
  var result = 0;
  for (var i = 0; i < width; i++) {
    if ((value & (1 << i)) != 0) result |= 1 << (width - 1 - i);
  }
  return result;
}

void main() {
  final patterns = <String, List<int>>{
    'empty': const [],
    'single': const [0x31],
    'check': '123456789'.codeUnits,
    'ramp256': List.generate(256, (i) => i),
    'zeros64': List.filled(64, 0),
    'ff64': List.filled(64, 0xFF),
  };
  final random = Random(20261115);
  patterns['random512'] = List.generate(512, (_) => random.nextInt(256));

  group('查表 CRC 与逐位 oracle 对拍', () {
    for (final preset in CrcPresets.all) {
      test('${preset.name} 在所有数据模式上一致', () {
        for (final entry in patterns.entries) {
          final actual = CrcCalculator.calculate(entry.value, preset.params);
          final expected = _referenceCrc(entry.value, preset.params);
          expect(actual, expected,
              reason: '${preset.name} / ${entry.key} 查表与逐位不一致');
        }
      });
    }

    test('自定义 width>=8 反射/非反射参数对拍', () {
      final customs = <CrcParams>[
        const CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: true, refout: false),
        const CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: true),
        const CrcParams(width: 16, poly: 0x1021, init: 0x1D0F, xorout: 0x0000, refin: false, refout: false),
        const CrcParams(width: 32, poly: 0x04C11DB7, init: 0xFFFFFFFF, xorout: 0xFFFFFFFF, refin: true, refout: true),
        const CrcParams(width: 24, poly: 0x864CFB, init: 0xB704CE, xorout: 0x000000, refin: false, refout: false),
      ];
      for (final p in customs) {
        for (final entry in patterns.entries) {
          expect(CrcCalculator.calculate(entry.value, p), _referenceCrc(entry.value, p),
              reason: 'width=${p.width} refin=${p.refin} / ${entry.key}');
        }
      }
    });

    test('重复调用同一预设结果稳定（缓存表不污染）', () {
      final p = CrcPresets.byName('CRC-32').params;
      final data = '123456789'.codeUnits;
      final first = CrcCalculator.calculate(data, p);
      for (var i = 0; i < 5; i++) {
        expect(CrcCalculator.calculate(data, p), first);
      }
      expect(first, 0xCBF43926);
    });
  });
}