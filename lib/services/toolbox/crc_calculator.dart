import '../../models/toolbox/crc_params.dart';

class CrcCalculator {
  CrcCalculator._();

  static int calculate(List<int> data, CrcParams params) {
    final mask = (1 << params.width) - 1;

    if (data.isEmpty) {
      var crc = params.init & mask;
      if (params.refout) {
        crc = _reflect(crc, params.width);
      }
      return (crc ^ params.xorout) & mask;
    }

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

    if (params.refout != params.refin) {
      crc = _reflect(crc, params.width);
    }

    return (crc ^ params.xorout) & mask;
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
