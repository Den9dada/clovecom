import 'dart:async';
import 'dart:typed_data';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'transfer_protocol.dart';

/// Ymodem-1K 传输协议
///
/// 基于 Ymodem-1K 协议的文件传输，支持 CRC-16 校验。
/// 适用于支持 Ymodem 协议的嵌入式设备固件升级。
///
/// 协议流程：
///   1. 等待接收端发送 'C' 进入 CRC 模式
///   2. 发送文件名包 (SOH, seq=0)
///   3. 分包发送数据 (STX, 1024B/包)
///   4. 发送 EOT 结束
///   5. 发送空结束包
class YmodemProtocol implements TransferProtocol {
  static const int _soh = 0x01;
  static const int _stx = 0x02;
  static const int _eot = 0x04;
  static const int _ack = 0x06;
  static const int _crc = 0x43; // 'C'

  static const int _sohSize = 128;
  static const int _stxSize = 1024;

  /// CRC-16/XMODEM 查找表
  static const List<int> _crc16Table = [
    0, 4129, 8258, 12387, 16516, 20645, 24774, 28903,
    33032, 37161, 41290, 45419, 49548, 53677, 57806, 61935,
    4657, 528, 12915, 8786, 21173, 17044, 29431, 25302,
    37689, 33560, 45947, 41818, 54205, 50076, 62463, 58334,
    9314, 13379, 1056, 5121, 25830, 29895, 17572, 21637,
    42346, 46411, 34088, 38153, 58862, 62927, 50604, 54669,
    13907, 9842, 5649, 1584, 30423, 26358, 22165, 18100,
    46939, 42874, 38681, 34616, 63455, 59390, 55197, 51132,
    18532, 22597, 26662, 30727, 2272, 6337, 10402, 14499,
    51532, 55661, 59662, 63791, 35272, 39401, 43402, 47531,
    23157, 19028, 31287, 27158, 6897, 2768, 15027, 10898,
    56189, 52060, 64319, 60190, 39929, 35800, 48059, 43930,
    27814, 31879, 19684, 23749, 11298, 15363, 3168, 7233,
    60846, 64911, 52716, 56781, 44330, 48395, 36200, 40265,
    32407, 28342, 24277, 20212, 15891, 11826, 7761, 3696,
    65439, 61374, 57309, 53244, 48923, 44858, 40793, 36728,
    37256, 33193, 45514, 41451, 53516, 49453, 61774, 57711,
    4224, 161, 12482, 8419, 20484, 16421, 28742, 24679,
    33721, 37784, 41979, 46042, 49981, 54044, 58239, 62302,
    689, 4752, 8947, 13010, 16949, 21012, 25207, 29270,
    46570, 42443, 38312, 34185, 62830, 58703, 54572, 50445,
    13538, 9411, 5280, 1153, 29798, 25671, 21540, 17413,
    42971, 47098, 34713, 38840, 59231, 63358, 50973, 55100,
    9939, 14066, 1681, 5808, 26199, 30326, 17941, 22068,
    55628, 51565, 63758, 59695, 39368, 35305, 47498, 43435,
    22596, 18533, 30726, 26663, 6336, 2273, 14466, 10403,
    52093, 56156, 60223, 64286, 35833, 39896, 43963, 48026,
    19061, 23124, 27191, 31254, 2801, 6864, 10931, 14994,
    64814, 60687, 56684, 52557, 48554, 44427, 40424, 36297,
    31782, 27655, 23652, 19525, 15522, 11395, 7392, 3265,
    61215, 65342, 53085, 57212, 44955, 49082, 36825, 40952,
    28183, 32310, 20053, 24180, 11923, 16050, 3793, 7920,
  ];

  @override
  String get name => 'Ymodem-1K';

  @override
  String get description => 'Ymodem-1K 协议，支持 CRC-16 校验，适用于嵌入式固件升级';

  /// 计算 CRC-16/XMODEM
  static int _crc16(List<int> data) {
    int crc = 0;
    for (final byte in data) {
      final idx = ((crc >> 8) & 0xFF) ^ byte;
      crc = ((crc << 8) & 0xFFFF) ^ _crc16Table[idx];
    }
    return crc;
  }

  /// 构建 128 字节数据包 (SOH)
  static Uint8List _buildSohPacket(int seq, List<int> data) {
    final padded = List<int>.filled(_sohSize, 0x1A);
    for (int i = 0; i < data.length && i < _sohSize; i++) {
      padded[i] = data[i];
    }
    final crc = _crc16(padded);
    final pkt = Uint8List(3 + _sohSize + 2);
    pkt[0] = _soh;
    pkt[1] = seq;
    pkt[2] = 0xFF - seq;
    pkt.setRange(3, 3 + _sohSize, padded);
    pkt[3 + _sohSize] = (crc >> 8) & 0xFF;
    pkt[3 + _sohSize + 1] = crc & 0xFF;
    return pkt;
  }

  /// 构建 1024 字节数据包 (STX)
  static Uint8List _buildStxPacket(int seq, List<int> data) {
    final padded = List<int>.filled(_stxSize, 0x1A);
    for (int i = 0; i < data.length && i < _stxSize; i++) {
      padded[i] = data[i];
    }
    final crc = _crc16(padded);
    final pkt = Uint8List(3 + _stxSize + 2);
    pkt[0] = _stx;
    pkt[1] = seq;
    pkt[2] = 0xFF - seq;
    pkt.setRange(3, 3 + _stxSize, padded);
    pkt[3 + _stxSize] = (crc >> 8) & 0xFF;
    pkt[3 + _stxSize + 1] = crc & 0xFF;
    return pkt;
  }

  /// 等待接收一个字节
  Future<int?> _waitByte(TransferCallbacks callbacks, int timeoutMs) async {
    // 在等待期间也检查取消状态
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (callbacks.isCancelled()) return null;
      final byte = await callbacks.onWaitByte(100); // 每次只等100ms，以便检查取消
      if (byte != null) return byte;
    }
    return null;
  }

  /// 等待 ACK
  Future<bool> _waitAck(TransferCallbacks callbacks, int timeoutMs, {int retries = 0}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      final byte = await _waitByte(callbacks, timeoutMs);
      if (byte == null) {
        callbacks.onLog('等待应答超时');
      } else if (byte == _ack) {
        return true;
      } else {
        callbacks.onLog('收到应答: 0x${byte.toRadixString(16).padLeft(2, '0').toUpperCase()} (期望 ACK 0x06)');
      }
      if (attempt < retries) {
        callbacks.onLog('应答重试 ${attempt + 1}/${retries + 1}');
      }
    }
    return false;
  }

  @override
  Future<void> send(
    SerialPort port,
    Uint8List data, {
    required int packetSize,
    required int intervalMs,
    required TransferCallbacks callbacks,
  }) async {
    final fileSize = data.length;

    callbacks.onLog('Ymodem-1K 传输开始');
    callbacks.onLog('固件大小: $fileSize 字节');

    // 检查取消
    if (callbacks.isCancelled()) {
      callbacks.onLog('传输已取消');
      return;
    }

    // 阶段 0: 等待接收端发送 'C' 进入 CRC 模式
    callbacks.onLog('等待接收端发送 CRC 请求 (0x43)...');
    bool gotCrc = false;
    for (int attempt = 0; attempt < 10; attempt++) {
      if (callbacks.isCancelled()) {
        callbacks.onLog('传输已取消');
        return;
      }
      final b = await _waitByte(callbacks, 1000);
      if (b != null) {
        callbacks.onLog('收到: 0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
      if (b == _crc) {
        gotCrc = true;
        callbacks.onLog('收到 CRC 模式请求');
        break;
      }
    }
    if (!gotCrc) {
      callbacks.onError('接收端就绪（未收到 0x43 CRC 请求）');
      return;
    }

    // 检查取消
    if (callbacks.isCancelled()) {
      callbacks.onLog('传输已取消');
      return;
    }

    // 阶段 1: 发送文件名包 (SOH, seq=0)
    final nameBytes = <int>[];
    final nameStr = 'FW.BIN';
    for (int i = 0; i < nameStr.length; i++) {
      nameBytes.add(nameStr.codeUnitAt(i));
    }
    nameBytes.add(0); // 分隔符
    final sizeStr = fileSize.toString();
    for (int i = 0; i < sizeStr.length; i++) {
      nameBytes.add(sizeStr.codeUnitAt(i));
    }

    final filenamePkt = _buildSohPacket(0, nameBytes);
    callbacks.onLog('发送文件名包 (${filenamePkt.length} 字节)...');
    final writeOk = port.writeBytesFromUint8List(filenamePkt);
    if (!writeOk) {
      callbacks.onError('文件名包发送失败（串口写入超时）');
      return;
    }

    if (!await _waitAck(callbacks, 3000)) {
      if (callbacks.isCancelled()) {
        callbacks.onLog('传输已取消');
        return;
      }
      callbacks.onError('文件名包未被确认');
      return;
    }

    // 等待第二个 'C'
    final c2 = await _waitByte(callbacks, 3000);
    if (c2 != _crc) {
      callbacks.onLog('警告: 未收到第二个 CRC 请求，继续传输');
    }

    // 阶段 2: 分包发送数据 (STX, 1024B)
    final totalPackets = (fileSize / _stxSize).ceil();
    callbacks.onLog('共 $totalPackets 个数据包');

    int offset = 0;
    int packetSeq = 0;

    while (offset < fileSize) {
      // 检查取消
      if (callbacks.isCancelled()) {
        callbacks.onLog('传输已取消');
        return;
      }

      int end = offset + _stxSize;
      if (end > fileSize) end = fileSize;
      final chunk = data.sublist(offset, end).toList();

      packetSeq++;
      final dataPkt = _buildStxPacket(packetSeq & 0xFF, chunk);
      callbacks.onLog('发送包 #$packetSeq (${chunk.length}B, ${dataPkt.length}B)');
      final dataWriteOk = port.writeBytesFromUint8List(dataPkt);
      if (!dataWriteOk) {
        callbacks.onError('包 #$packetSeq 发送失败（串口写入超时）');
        return;
      }

      if (!await _waitAck(callbacks, 3000)) {
        if (callbacks.isCancelled()) {
          callbacks.onLog('传输已取消');
          return;
        }
        callbacks.onError('包 #$packetSeq 未被确认，传输中止');
        return;
      }

      offset = end;
      callbacks.onProgress(offset / fileSize);
    }

    // 检查取消
    if (callbacks.isCancelled()) {
      callbacks.onLog('传输已取消');
      return;
    }

    // 阶段 3: 发送 EOT
    callbacks.onLog('发送 EOT...');
    final eotOk = port.writeBytesFromUint8List(Uint8List.fromList([_eot]));
    if (!eotOk) {
      callbacks.onError('EOT 发送失败');
      return;
    }
    await _waitAck(callbacks, 3000);

    // 阶段 4: 发送结束包 (SOH, seq=0, 全零)
    final endWait = await _waitByte(callbacks, 3000);
    if (endWait == _crc) {
      callbacks.onLog('发送结束包...');
      final endPkt = _buildSohPacket(0, List.filled(_sohSize, 0));
      final endOk = port.writeBytesFromUint8List(endPkt);
      if (!endOk) {
        callbacks.onError('结束包发送失败');
        return;
      }
      await _waitAck(callbacks, 3000);
    }

    callbacks.onLog('Ymodem-1K 传输完成!');
    callbacks.onComplete(fileSize);
  }
}
