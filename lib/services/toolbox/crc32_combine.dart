/// CRC-32 拼接合成深模块。
///
/// 接口：按输出顺序排列的游程列表 → 整图标准 CRC-32。
/// 实现：GF(2) 矩阵幂（zlib crc32_combine 同款）＋填充游程闭式倍增，
/// 无需物化或扫描完整输出。复杂度 O(游程数 × log 游程长)。
///
/// 数学依据（init == xorout == 0xFFFFFFFF 时成立）：
///   crc(A||B) = T^|B|(crc(A)) ^ crc(B)
/// 其中 T 是“输入一个零字节”的 GF(2) 线性算子（反射多项式 0xEDB88320）。
/// 因此可直接对最终 CRC 值做合成，无需还原 init/xorout。
library;

import '../../models/toolbox/crc_params.dart';
import 'crc_calculator.dart';

/// 输出游程：一段数据（最终 CRC-32＋长度）或一段填充（字节＋长度）。
sealed class Crc32Run {
  const Crc32Run();

  /// 游程字节数。
  int get length;
}

/// 数据游程：[crc] 是该段 bytes 的标准 CRC-32 最终值。
final class Crc32DataRun extends Crc32Run {
  const Crc32DataRun({required this.crc, required this.length});

  final int crc;
  @override
  final int length;
}

/// 填充游程：[length] 个重复的 [byte]。
final class Crc32FillRun extends Crc32Run {
  const Crc32FillRun({required this.byte, required this.length});

  final int byte;
  @override
  final int length;
}

final _params = CrcPresets.byName('CRC-32').params;

/// 反射 CRC-32 多项式（zlib 表示）。
const _poly = 0xEDB88320;

/// 从按输出顺序排列的游程合成整图标准 CRC-32。
/// 空游程列表返回 0（与空数据 CRC-32 一致）。
int synthesizeCrc32(List<Crc32Run> runs) {
  var acc = 0; // 空前缀的 CRC-32
  for (final run in runs) {
    if (run.length == 0) continue;
    final runCrc = switch (run) {
      Crc32DataRun() => run.crc,
      Crc32FillRun() => _fillCrc(run.byte, run.length),
    };
    // combine(acc, runCrc, len) = T^len(acc) ^ runCrc；
    // 首个游程时 acc=0，T^len(0)=0，结果即 runCrc。
    acc = _shiftZeros(acc, run.length) ^ runCrc;
  }
  return acc & 0xFFFFFFFF;
}

/// n 个重复字节 [byte] 的标准 CRC-32，闭式倍增 O(log n)。
int _fillCrc(int byte, int n) {
  // pow[i] = crc(byte^(2^i))，由 crc(f^(2k)) = T^k(crc(f^k)) ^ crc(f^k) 倍增。
  final powCrc = <int>[CrcCalculator.calculate([byte], _params)];
  final powLen = <int>[1];
  while (powLen.last < n) {
    final prev = powCrc.last;
    final len = powLen.last;
    powCrc.add(_shiftZeros(prev, len) ^ prev);
    powLen.add(len * 2);
  }
  // 按 n 的二进制位拼接对应幂次（同字节游程，拼接顺序不影响结果）。
  var result = 0;
  var remaining = n;
  var i = 0;
  while (remaining > 0) {
    if (remaining & 1 != 0) {
      result = _shiftZeros(result, powLen[i]) ^ powCrc[i];
    }
    remaining >>= 1;
    i++;
  }
  return result & 0xFFFFFFFF;
}

/// 对 [crc] 施加“输入 n 个零字节”的 GF(2) 线性算子 T^n。
/// zlib crc32_combine 的矩阵幂循环：odd/even交替平方，按 n 的位施加。
int _shiftZeros(int crc, int n) {
  if (n <= 0) return crc;
  // odd = 一个零位的算子矩阵。
  var odd = List<int>.filled(32, 0);
  odd[0] = _poly;
  var row = 1;
  for (var i = 1; i < 32; i++) {
    odd[i] = row;
    row <<= 1;
  }
  var even = _square(odd); // 两个零位
  odd = _square(even); // 四个零位
  var len = n;
  do {
    // 首次平方得到“一个零字节（八位）”算子。
    even = _square(odd);
    if (len & 1 != 0) crc = _times(even, crc);
    len >>= 1;
    if (len == 0) break;
    odd = _square(even);
    if (len & 1 != 0) crc = _times(odd, crc);
    len >>= 1;
  } while (len != 0);
  return crc & 0xFFFFFFFF;
}

/// GF(2) 矩阵平方：out[i] = mat 作用于 mat[i]。
List<int> _square(List<int> mat) {
  final out = List<int>.filled(32, 0);
  for (var i = 0; i < 32; i++) {
    out[i] = _times(mat, mat[i]);
  }
  return out;
}

/// GF(2) 矩阵乘向量：vec 各置位对应行的 XOR。
int _times(List<int> mat, int vec) {
  var sum = 0;
  var i = 0;
  while (vec != 0) {
    if (vec & 1 != 0) sum ^= mat[i];
    vec >>= 1;
    i++;
  }
  return sum;
}