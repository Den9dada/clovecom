import '../../models/toolbox/crc_params.dart';

/// CRC 计算深模块：对外只暴露 calculate(data, params) 一个小接口。
///
/// width>=8 走缓存查表实现（每字节一次查表，约 8x 于逐位循环），
/// width<8 退回逐位循环。两条路径在反射/非反射、空数据、refout/xorout
/// 后处理上完全等价，由 21 个预设已知向量与查表/逐位对拍测试验证。
/// 查表按 (width, poly, refin) 缓存，重复计算同一预设只建表一次。
class CrcCalculator {
  CrcCalculator._();

  // 查表缓存：键为 (width, poly, refin)，值为 256 项表。
  static final Map<({int width, int poly, bool refin}), List<int>> _tables = {};

  static int calculate(List<int> data, CrcParams params) {
    final mask = (1 << params.width) - 1;

    // 空数据：init 经 refout 反射后再 xorout（与逐位实现保持一致）。
    if (data.isEmpty) {
      var crc = params.init & mask;
      if (params.refout) {
        crc = _reflect(crc, params.width);
      }
      return (crc ^ params.xorout) & mask;
    }

    var crc = params.width >= 8
        ? _tableDriven(data, params, mask)
        : _bitwise(data, params, mask);

    // 非空数据：仅当 refout 与 refin 不一致时反射，再 xorout。
    if (params.refout != params.refin) {
      crc = _reflect(crc, params.width);
    }
    return (crc ^ params.xorout) & mask;
  }

  /// 逐位实现：width<8 的唯一路径，也作为查表的语义基准。
  static int _bitwise(List<int> data, CrcParams params, int mask) {
    var crc = params.init & mask;
    if (params.refin) {
      final reflectedPoly = _reflect(params.poly, params.width);
      for (final byte in data) {
        crc ^= (byte & 0xFF);
        for (int i = 0; i < 8; i++) {
          if ((crc & 1) != 0) {
            crc = (crc >> 1) ^ reflectedPoly;
          } else {
            crc = crc >> 1;
          }
        }
      }
      crc &= mask;
    } else {
      final poly = params.poly | (1 << params.width);
      final topBit = 1 << (params.width - 1);
      for (final byte in data) {
        if (params.width > 8) {
          crc ^= ((byte & 0xFF) << (params.width - 8));
        } else {
          crc ^= (byte & 0xFF);
        }
        for (int i = 0; i < 8; i++) {
          if ((crc & topBit) != 0) {
            crc = ((crc << 1) ^ poly) & mask;
          } else {
            crc = (crc << 1) & mask;
          }
        }
      }
    }
    return crc;
  }

  /// 查表实现：仅用于 width>=8，结果与 _bitwise 完全一致。
  static int _tableDriven(List<int> data, CrcParams params, int mask) {
    final key = (width: params.width, poly: params.poly, refin: params.refin);
    final table = _tables.putIfAbsent(key, () => _buildTable(params, mask));
    var crc = params.init & mask;
    if (params.refin) {
      for (final byte in data) {
        crc = ((crc >> 8) ^ table[(crc ^ byte) & 0xFF]) & mask;
      }
    } else {
      final shift = params.width - 8;
      for (final byte in data) {
        final index = ((crc >> shift) ^ byte) & 0xFF;
        crc = ((crc << 8) ^ table[index]) & mask;
      }
    }
    return crc;
  }

  static List<int> _buildTable(CrcParams params, int mask) {
    final table = List<int>.filled(256, 0);
    if (params.refin) {
      final reflectedPoly = _reflect(params.poly, params.width);
      for (var i = 0; i < 256; i++) {
        var c = i;
        for (var k = 0; k < 8; k++) {
          c = (c & 1) != 0 ? (c >> 1) ^ reflectedPoly : c >> 1;
        }
        table[i] = c & mask;
      }
    } else {
      final poly = params.poly | (1 << params.width);
      final topBit = 1 << (params.width - 1);
      final shift = params.width - 8;
      for (var i = 0; i < 256; i++) {
        var c = (i << shift) & mask;
        for (var k = 0; k < 8; k++) {
          c = (c & topBit) != 0 ? ((c << 1) ^ poly) & mask : (c << 1) & mask;
        }
        table[i] = c;
      }
    }
    return table;
  }

  static int _reflect(int value, int bitWidth) {
    var result = 0;
    for (int i = 0; i < bitWidth; i++) {
      if ((value & (1 << i)) != 0) {
        result |= (1 << (bitWidth - 1 - i));
      }
    }
    return result;
  }
}