import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'transfer_protocol.dart';
import '../models/toolbox/crc_params.dart';
import '../services/toolbox/crc_calculator.dart';

/// Ymodem-1K 传输协议
///
/// 严格遵循 YModem 标准：接收端每次 ACK 后发 'C' 驱动下一块传输。
class YmodemProtocol implements TransferProtocol {
  // ── 常量 ──
  static const int _soh = 0x01;
  static const int _stx = 0x02;
  static const int _eot = 0x04;
  static const int _ack = 0x06;
  static const int _nak = 0x15;
  static const int _can = 0x18;
  static const int _crc = 0x43;

  static const int _sohSize = 128;
  static const int _stxSize = 1024;

  // ── 超时 (ms) ──
  static const int _tShort = 3000;
  static const int _tNormal = 10000;
  static const int _tLong = 60000;

  final List<int> _rxBuf = [];

  @override
  String get name => 'Ymodem-1K';
  @override
  String get receiveName => 'Ymodem-1K 接收';
  @override
  String get description => 'Ymodem-1K 协议，CRC-16 校验';

  // ═══════════════════════════════════════════════════════════════
  // CRC / 包构建
  // ═══════════════════════════════════════════════════════════════

  static final _crcParams = CrcPresets.byName('CRC-16/XMODEM').params;
  static int _crc16(List<int> bytes) =>
      CrcCalculator.calculate(bytes, _crcParams);
  static Uint8List _pkt(int type, int seq, int sz, List<int> data) {
    final pad = List<int>.filled(sz, 0x1A);
    for (int i = 0; i < data.length && i < sz; i++) {
      pad[i] = data[i];
    }
    final crc = _crc16(pad);
    final p = Uint8List(3 + sz + 2);
    p[0] = type;
    p[1] = seq & 0xFF;
    p[2] = (0xFF - seq) & 0xFF;
    p.setRange(3, 3 + sz, pad);
    p[3 + sz] = (crc >> 8) & 0xFF;
    p[3 + sz + 1] = crc & 0xFF;
    return p;
  }

  // ═══════════════════════════════════════════════════════════════
  // I/O 辅助
  // ═══════════════════════════════════════════════════════════════

  Future<int?> _rd(TransferCallbacks cb, int ms) async {
    final dl = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(dl)) {
      if (cb.isCancelled()) return null;
      final b = await cb.onWaitByte(100);
      if (b != null) return b;
    }
    return null;
  }

  Future<bool> _wr(int b, TransferCallbacks cb) async {
    if (cb.isCancelled()) return false;
    final result = await cb.onWrite(Uint8List.fromList([b]), 500);
    return !cb.isCancelled() && result;
  }

  /// 发送数据包，失败时自动报告错误
  Future<bool> _wrPacket(
    Uint8List pkt,
    TransferCallbacks cb,
    int timeoutMs,
  ) async {
    if (cb.isCancelled()) return false;
    final result = await cb.onWrite(pkt, timeoutMs);
    if (cb.isCancelled()) return false;
    if (!result) {
      cb.onError('写入失败');
      return false;
    }
    return true;
  }

  /// 等待列表中任一字节，不在列表中的记录日志
  Future<int?> _wait(
    List<int> want,
    List<int> ign,
    TransferCallbacks cb,
    int ms,
  ) async {
    final dl = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(dl)) {
      if (cb.isCancelled()) return null;
      final b = await cb.onWaitByte(100);
      if (b == null) continue;
      if (want.contains(b)) return b;
      if (!ign.contains(b)) {
        cb.onLog('收: 0x${b.toRadixString(16).padLeft(2, '0')}');
      }
    }
    return null;
  }

  Future<Uint8List?> _readN(TransferCallbacks cb, int n, int ms) async {
    if (_rxBuf.length >= n) {
      final r = Uint8List.fromList(_rxBuf.sublist(0, n));
      _rxBuf.removeRange(0, n);
      return r;
    }
    final bytes = <int>[..._rxBuf];
    _rxBuf.clear();
    final dl = DateTime.now().add(Duration(milliseconds: ms));
    while (bytes.length < n && DateTime.now().isBefore(dl)) {
      if (cb.isCancelled()) {
        if (bytes.isNotEmpty) _rxBuf.addAll(bytes);
        return null;
      }
      final d = await cb.onWaitData(50);
      if (d != null) {
        if (bytes.length + d.length > 64 * 1024) {
          throw StateError('协议输入超出64 KiB预算，数据不完整');
        }
        bytes.addAll(d);
      }
    }
    if (bytes.length < n) {
      _rxBuf.addAll(bytes);
      return null;
    }
    if (bytes.length > n) _rxBuf.addAll(bytes.sublist(n));
    return Uint8List.fromList(bytes.sublist(0, n));
  }

  (int, int, List<int>)? _parse(Uint8List raw) {
    if (raw.length < 3) return null;
    final t = raw[0];
    if (t == _eot) return (_eot, 0, []);
    if (t != _soh && t != _stx) return null;
    final seq = raw[1], inv = raw[2];
    if ((seq + inv) & 0xFF != 0xFF) return null;
    final sz = t == _stx ? _stxSize : _sohSize;
    if (raw.length < 3 + sz + 2) return null;
    final data = raw.sublist(3, 3 + sz);
    final expectCrc = (raw[3 + sz] << 8) | raw[3 + sz + 1];
    return _crc16(data) == expectCrc ? (t, seq, data) : null;
  }

  // ═══════════════════════════════════════════════════════════════
  // 发送（标准 YModem：等 'C' → 发块 → 等 ACK → 等 'C' → ...）
  // ═══════════════════════════════════════════════════════════════

  @override
  Future<void> send(
    Uint8List data, {
    required int packetSize,
    required int intervalMs,
    required TransferCallbacks callbacks,
  }) async {
    final cb = callbacks;
    final fileSize = data.length;
    _rxBuf.clear();
    cb.onLog(
      'Ymodem-1K 发送: ${cb.fileName.isNotEmpty ? cb.fileName : "FW.BIN"} ($fileSize B)',
    );

    // Block 0
    final nb = <int>[
      ...utf8.encode(cb.fileName.isNotEmpty ? cb.fileName : 'FW.BIN'),
      0,
      ...utf8.encode('$fileSize'),
    ];
    if (nb.length > _sohSize) nb.length = _sohSize;
    final b0 = _pkt(_soh, 0, _sohSize, nb);

    int off = 0, seq = 0, pend = 0, nak = 0;
    List<int> chunk = [];
    bool awaitC = true, hsDone = false;

    while (true) {
      if (cb.isCancelled()) return;

      if (awaitC) {
        final c = await _wait([_crc], [_nak], cb, _tLong);
        if (c == null) {
          if (cb.isCancelled()) {
            cb.onLog('传输已取消');
            return;
          }
          cb.onError('未收到 CRC 请求');
          return;
        }

        if (!hsDone) {
          cb.onLog('发文件名包...');
          if (!await _wrPacket(b0, cb, _tNormal)) return;
          awaitC = false;
          continue;
        }
        if (off >= fileSize) {
          // EOT 交换：发 EOT → 等 NAK → 重发 EOT → 等 ACK → 发结束块
          cb.onLog('发 EOT...');
          var eotAcked = false;
          for (int e = 0; e < 2; e++) {
            if (!await _wrPacket(Uint8List.fromList([_eot]), cb, 500)) return;
            final r = await _rd(cb, _tShort);
            if (r == _ack) {
              eotAcked = true;
              break;
            }
            if (r == null && cb.isCancelled()) {
              cb.onLog('传输已取消');
              return;
            }
          }
          if (!eotAcked) {
            cb.onError('EOT 握手未完成');
            return;
          }
          cb.onLog('发结束块...');
          if (!await _wrPacket(
            _pkt(_soh, 0, _sohSize, List.filled(_sohSize, 0)),
            cb,
            _tNormal,
          )) {
            return;
          }
          awaitC = false;
          off = fileSize + 1;
          continue;
        }

        int end = off + _stxSize;
        if (end > fileSize) end = fileSize;
        chunk = data.sublist(off, end).toList();
        pend = end;
        seq = (seq + 1) & 0xFF;
        cb.onLog('发块 #$seq (${chunk.length}B)');
        if (!await _wrPacket(_pkt(_stx, seq, _stxSize, chunk), cb, _tNormal)) {
          return;
        }
        awaitC = false;
        nak = 0;
      } else {
        final r = await _wait([_ack, _nak, _can], [_crc], cb, _tNormal);
        if (r == null) {
          if (cb.isCancelled()) {
            cb.onLog('传输已取消');
            return;
          }
          cb.onError('传输超时');
          return;
        }
        if (r == _can) {
          cb.onError('传输中止');
          return;
        }
        if (r == _ack) {
          if (off > fileSize) {
            cb.onLog('结束块已确认');
            break;
          }
          if (!hsDone) {
            hsDone = true;
            cb.onLog('文件名包已确认');
          } else {
            off = pend;
            if (off > fileSize) off = fileSize;
            cb.onProgress(off / fileSize);
          }
          awaitC = true;
        } else {
          if (nak++ >= 3) {
            cb.onError('NAK 过多');
            return;
          }
          cb.onLog('NAK 重发 ($nak/3)');
          if (!hsDone) {
            if (!await _wrPacket(b0, cb, _tNormal)) return;
          } else if (off > fileSize) {
            if (!await _wrPacket(
              _pkt(_soh, 0, _sohSize, List.filled(_sohSize, 0)),
              cb,
              _tNormal,
            )) {
              return;
            }
          } else {
            if (!await _wrPacket(
              _pkt(_stx, seq, _stxSize, chunk),
              cb,
              _tNormal,
            )) {
              return;
            }
          }
        }
      }
    }
    cb.onLog('发送完成');
    cb.onComplete(fileSize);
  }

  // ═══════════════════════════════════════════════════════════════
  // 接收
  // ═══════════════════════════════════════════════════════════════

  @override
  Future<void> receive({
    required String savePath,
    required TransferCallbacks callbacks,
  }) async {
    final cb = callbacks;
    final sink = await File(savePath).open(mode: FileMode.write);
    _rxBuf.clear();
    var closed = false;
    Future<void> writeControl(int byte) async {
      if (!await _wr(byte, cb)) throw StateError('串口写入失败');
    }

    try {
      cb.onLog('Ymodem-1K 接收开始');
      (int, int, List<int>)? header;
      for (var attempt = 0; attempt < 10 && !cb.isCancelled(); attempt++) {
        await writeControl(_crc);
        final first = await _readN(cb, 1, _tShort);
        if (first == null) continue;
        if (first[0] == _can) throw StateError('发送端中止传输');
        if (first[0] != _soh) {
          await writeControl(_nak);
          continue;
        }
        final rest = await _readN(cb, 2 + _sohSize + 2, _tShort);
        if (rest == null) continue;
        final parsed = _parse(Uint8List.fromList([_soh, ...rest]));
        if (parsed != null && parsed.$2 == 0 && parsed.$3.first != 0) {
          header = parsed;
          break;
        }
        await writeControl(_nak);
      }
      if (cb.isCancelled()) return;
      if (header == null) throw StateError('未收到有效文件名包');
      final info = header.$3;
      final separator = info.indexOf(0);
      if (separator <= 0) throw StateError('文件名包格式错误');
      final name = utf8.decode(
        info.sublist(0, separator),
        allowMalformed: true,
      );
      final sizeText = utf8.decode(
        info
            .sublist(separator + 1)
            .takeWhile((byte) => byte != 0 && byte != 0x1A)
            .toList(),
        allowMalformed: true,
      );
      final expectedSize = int.tryParse(sizeText.split(' ').first);
      if (expectedSize != null && expectedSize < 0) throw StateError('文件大小无效');
      cb.onFileInfo?.call(name, expectedSize ?? 0);
      await writeControl(_ack);
      await writeControl(_crc);
      var sequence = 0;
      var failures = 0;
      var eotDone = false;
      var receivedBytes = 0;
      var writtenBytes = 0;
      var trailingPadding = 0;
      while (!cb.isCancelled() && failures < 10) {
        final first = await _readN(cb, 1, _tNormal);
        if (first == null) {
          failures++;
          await writeControl(_nak);
          continue;
        }
        final type = first[0];
        if (type == _can) throw StateError('发送端中止传输');
        if (type == _eot) {
          await writeControl(_nak);
          final second = await _readN(cb, 1, _tShort);
          if (second == null || second[0] != _eot) {
            throw StateError('EOT 握手未完成');
          }
          await writeControl(_ack);
          eotDone = true;
          break;
        }
        if (type != _soh && type != _stx) {
          failures++;
          await writeControl(_nak);
          continue;
        }
        final size = type == _stx ? _stxSize : _sohSize;
        final rest = await _readN(cb, 2 + size + 2, _tNormal);
        final packet = rest == null
            ? null
            : _parse(Uint8List.fromList([type, ...rest]));
        if (packet == null) {
          failures++;
          await writeControl(_nak);
          continue;
        }
        if (packet.$2 == (sequence & 0xFF)) {
          await writeControl(_ack);
          // 文件名包的重发也要继续请求数据块。
          if (sequence == 0) await writeControl(_crc);
          continue;
        }
        if (packet.$2 != ((sequence + 1) & 0xFF)) {
          failures++;
          await writeControl(_nak);
          continue;
        }
        final payload = packet.$3;
        receivedBytes += payload.length;
        if (expectedSize == null) {
          var padding = 0;
          for (var i = payload.length - 1; i >= 0 && payload[i] == 0x1A; i--) {
            padding++;
          }
          trailingPadding = padding == payload.length
              ? trailingPadding + padding
              : padding;
        }
        final length = expectedSize == null
            ? payload.length
            : (expectedSize - writtenBytes).clamp(0, payload.length);
        if (length > 0) {
          await sink.writeFrom(payload, 0, length);
          writtenBytes += length;
        }
        sequence = (sequence + 1) & 0xFF;
        failures = 0;
        await writeControl(_ack);
        await writeControl(_crc);
        if (expectedSize != null && expectedSize > 0) {
          cb.onProgress((writtenBytes / expectedSize).clamp(0, 1));
        }
      }
      if (cb.isCancelled()) return;
      if (!eotDone) throw StateError('接收超时，传输未完成');
      await writeControl(_crc);
      final ending = await _readN(cb, 3 + _sohSize + 2, _tShort);
      final parsedEnding = ending == null ? null : _parse(ending);
      if (parsedEnding == null ||
          parsedEnding.$1 != _soh ||
          parsedEnding.$2 != 0 ||
          parsedEnding.$3.first != 0) {
        throw StateError('未收到有效结束块');
      }
      await writeControl(_ack);
      if (expectedSize != null && receivedBytes < expectedSize) {
        throw StateError('接收文件被截断: $receivedBytes/$expectedSize');
      }
      final length = expectedSize ?? receivedBytes - trailingPadding;
      if (expectedSize == null && trailingPadding > 0) {
        await sink.truncate(length);
      }
      await sink.flush();
      await sink.close();
      closed = true;
      if (!cb.isCancelled()) {
        cb.onLog('接收完成 $length B');
        cb.onComplete(length);
      }
    } catch (error) {
      if (!cb.isCancelled()) cb.onError('接收失败: $error');
    } finally {
      _rxBuf.clear();
      if (!closed) await sink.close();
    }
  }
}
