import 'dart:math';

import 'package:clovecom/models/toolbox/bin_link_segment.dart';
import 'package:clovecom/models/toolbox/crc_params.dart';
import 'package:clovecom/services/toolbox/bin_link_service.dart';
import 'package:clovecom/services/toolbox/crc32_combine.dart';
import 'package:clovecom/services/toolbox/crc_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// C6 crc32_combine/填充闭式合成的 oracle 对拍：
/// 合成结果必须与“物化完整输出后全量扫描”的标准 CRC-32 逐位一致。
void main() {
  final params = CrcPresets.byName('CRC-32').params;
  int fullCrc(List<int> bytes) =>
      bytes.isEmpty ? 0 : CrcCalculator.calculate(bytes, params);

  test('空游程返回 0', () {
    expect(synthesizeCrc32([]), 0);
  });

  test('单数据游程等于其 CRC', () {
    final bytes = [0x01, 0x02, 0x03];
    final crc = fullCrc(bytes);
    expect(synthesizeCrc32([Crc32DataRun(crc: crc, length: 3)]), crc);
  });

  test('填充游程闭式等于全量扫描', () {
    for (final byte in [0x00, 0xFF, 0xA5]) {
      for (final n in [1, 2, 3, 7, 16, 255, 1024, 65537]) {
        final full = fullCrc(List<int>.filled(n, byte));
        expect(
          synthesizeCrc32([Crc32FillRun(byte: byte, length: n)]),
          full,
          reason: 'byte=$byte n=$n',
        );
      }
    }
  });

  test('随机布局合成等于全量扫描（200 组 oracle 对拍）', () {
    final rng = Random(42);
    for (var trial = 0; trial < 200; trial++) {
      final segCount = rng.nextInt(5) + 1;
      final segs = <({int addr, List<int> bytes})>[];
      var cursor = rng.nextInt(8);
      for (var i = 0; i < segCount; i++) {
        final addr = cursor + rng.nextInt(16);
        final len = rng.nextInt(32) + 1;
        final bytes = List<int>.generate(len, (_) => rng.nextInt(256));
        segs.add((addr: addr, bytes: bytes));
        cursor = addr + len + rng.nextInt(4);
      }
      final end = cursor + rng.nextInt(16);
      final fill = rng.nextInt(256);
      final full = List<int>.filled(end, fill);
      final runs = <Crc32Run>[];
      var c = 0;
      for (final s in segs) {
        if (s.addr > c) runs.add(Crc32FillRun(byte: fill, length: s.addr - c));
        full.setRange(s.addr, s.addr + s.bytes.length, s.bytes);
        runs.add(Crc32DataRun(crc: fullCrc(s.bytes), length: s.bytes.length));
        c = s.addr + s.bytes.length;
      }
      if (end > c) runs.add(Crc32FillRun(byte: fill, length: end - c));
      expect(synthesizeCrc32(runs), fullCrc(full), reason: 'trial $trial');
    }
  });

  test('高地址稀疏镜像合成等于全量扫描', () {
    final bytes = [0xDE, 0xAD, 0xBE, 0xEF];
    const addr = 0x10000;
    final end = addr + bytes.length + 16;
    const fill = 0xFF;
    final full = List<int>.filled(end, fill);
    full.setRange(addr, addr + bytes.length, bytes);
    final runs = <Crc32Run>[
      Crc32FillRun(byte: fill, length: addr),
      Crc32DataRun(crc: fullCrc(bytes), length: bytes.length),
      Crc32FillRun(byte: fill, length: end - addr - bytes.length),
    ];
    expect(synthesizeCrc32(runs), fullCrc(full));
  });

  test('plan 合成路径与全量扫描一致（50 组集成对拍）', () {
    final rng = Random(7);
    for (var trial = 0; trial < 50; trial++) {
      final segs = <BinLinkSegment>[];
      var cursor = rng.nextInt(8);
      final count = rng.nextInt(4) + 1;
      for (var i = 0; i < count; i++) {
        final addr = cursor + rng.nextInt(8);
        final bytes = List<int>.generate(
          rng.nextInt(24) + 1,
          (_) => rng.nextInt(256),
        );
        segs.add(BinLinkSegment(name: 's$i', address: addr, bytes: bytes));
        cursor = addr + bytes.length;
      }
      final fill = rng.nextInt(256);
      final result = BinLinkService.plan(segs, fillByte: fill);
      expect(result.error, isNull, reason: 'trial $trial');
      expect(
        result.outputCrc32,
        fullCrc(result.bytes),
        reason: 'trial $trial',
      );
    }
  });
}