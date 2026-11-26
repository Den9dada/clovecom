part of 'session_history.dart';

typedef _EncodedBatch = ({Uint8List bytes, List<int> ends});
typedef _PageRead = ({
  String path,
  int offset,
  int length,
  int count,
  String? connectionId,
});

// 临时分段只在当前进程读写。首字节指明用哪种记录头，随机读页无需扫描前文。
const _flags = 0;
const _sequence = 1;
const _compactLayout = (
  headerSize: 29,
  time: 5,
  packetSequence: 13,
  epoch: 17,
  payloadLength: 21,
  connectionLength: 25,
  peerLength: 27,
);
const _wideLayout = (
  headerSize: 45,
  time: 9,
  packetSequence: 17,
  epoch: 25,
  payloadLength: 33,
  connectionLength: 37,
  peerLength: 41,
);
const _sent = 1;
const _datagram = 2;
const _notice = 4;
const _compact = 8;
// 一份会话只有一个常用连接标识，临时文件可引用它而不重复写入。
const _sessionConnection = 16;
// 无对端的会话短包直接接在 16 位负载长度之后，省去两个标签长度。
const _shortSessionPacket = 32;
const _shortSessionHeaderSize = 23;
// 发送回执的包序号通常为 0，可由标志恢复。历史记录序号始终独立保存。
const _zeroPacketSequence = 64;
const _compactPacketSequenceBytes = 4;
const _nullCompactPeer = 0xffff;

_EncodedBatch? _encodeUniformCompact(
  List<SessionRecord> records,
  String? connectionId,
) {
  if (records.length < 2) return null;
  final first = records.first.packet;
  if (first == null) return null;
  final usesSessionConnection = first.connectionId == connectionId;
  final connection = usesSessionConnection
      ? null
      : utf8.encode(first.connectionId);
  final connectionLength = connection?.length ?? 0;
  final peerName = first.peer;
  final peer = peerName == null ? null : utf8.encode(peerName);
  if (connectionLength > 0xffff || (peer?.length ?? 0) >= _nullCompactPeer) {
    return null;
  }

  const layout = _compactLayout;
  final short = usesSessionConnection && peerName == null;
  final headerSize = short ? _shortSessionHeaderSize : layout.headerSize;
  final labelBytes = connectionLength + (peer?.length ?? 0);
  final ends = List<int>.filled(records.length, 0);
  var size = 0;
  for (var i = 0; i < records.length; i++) {
    final row = records[i];
    final packet = row.packet;
    if (row.notice != null ||
        packet == null ||
        packet.connectionId != first.connectionId ||
        packet.peer != peerName ||
        (short && packet.bytes.length > 0xffff) ||
        ((row.sequence | packet.sequence | packet.epoch) >>> 32) != 0) {
      return null;
    }
    final omitted = short && row.sent && packet.sequence == 0
        ? _compactPacketSequenceBytes
        : 0;
    size += headerSize - omitted + labelBytes + packet.bytes.length;
    ends[i] = size;
  }
  final output = Uint8List(size);
  final data = ByteData.sublistView(output);
  final lengths = (connectionLength << 16) | (peer?.length ?? _nullCompactPeer);
  final baseFlags =
      _compact |
      (usesSessionConnection ? _sessionConnection : 0) |
      (short ? _shortSessionPacket : 0);
  var offset = 0;
  for (var i = 0; i < records.length; i++) {
    final row = records[i];
    final packet = row.packet!;
    final end = ends[i];
    final zeroSequence = short && row.sent && packet.sequence == 0;
    final omitted = zeroSequence ? _compactPacketSequenceBytes : 0;
    data
      ..setUint8(
        offset + _flags,
        baseFlags |
            (row.sent ? _sent : 0) |
            (packet.datagram ? _datagram : 0) |
            (zeroSequence ? _zeroPacketSequence : 0),
      )
      ..setUint32(offset + _sequence, row.sequence)
      ..setInt64(
        offset + layout.time,
        packet.receivedAt.microsecondsSinceEpoch,
      );
    if (!zeroSequence) {
      data.setUint32(offset + layout.packetSequence, packet.sequence);
    }
    data.setUint32(offset + layout.epoch - omitted, packet.epoch);
    if (short) {
      data.setUint16(
        offset + layout.payloadLength - omitted,
        packet.bytes.length,
      );
    } else {
      data
        ..setUint32(offset + layout.payloadLength, packet.bytes.length)
        ..setUint32(offset + layout.connectionLength, lengths);
    }
    final start = offset + headerSize - omitted;
    if (connection != null) output.setAll(start, connection);
    if (peer != null) output.setAll(start + connectionLength, peer);
    output.setRange(start + labelBytes, end, packet.bytes);
    offset = end;
  }
  return (bytes: output, ends: ends);
}

_EncodedBatch _encodeRecords(
  List<SessionRecord> records, {
  required String? connectionId,
  bool omitSinglePayload = false,
}) {
  // 常见单连接批次共用已编码标签，混合批次按各记录选择布局。
  if (_encodeUniformCompact(records, connectionId) case final uniform?) {
    return uniform;
  }
  final ends = List<int>.filled(records.length, 0);
  final commonConnection = records.firstOrNull?.packet?.connectionId;
  final commonLabel =
      commonConnection == null || commonConnection == connectionId
      ? null
      : utf8.encode(commonConnection);
  final labels = <String, Uint8List>{};
  Uint8List label(String text) =>
      (text == commonConnection ? commonLabel : null) ??
      labels.putIfAbsent(text, () => utf8.encode(text));

  final headers = Uint8List(records.length);
  var size = 0;
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    final packet = record.packet;
    var fields = record.sequence;
    var flags = 0;
    var remaining = 0;
    var fitsLabels = true;
    if (record.notice != null || packet == null) {
      flags = _notice;
      remaining = label(record.notice ?? '').length;
    } else {
      fields |= packet.sequence | packet.epoch;
      flags = (record.sent ? _sent : 0) | (packet.datagram ? _datagram : 0);
      final usesSessionConnection = packet.connectionId == connectionId;
      if (usesSessionConnection) flags |= _sessionConnection;
      final connection = usesSessionConnection
          ? 0
          : label(packet.connectionId).length;
      final peer = packet.peer == null ? 0 : label(packet.peer!).length;
      fitsLabels = connection <= 0xffff && peer < _nullCompactPeer;
      remaining = packet.bytes.length + connection + peer;
    }
    final compact = fields >= 0 && fields <= 0xffffffff && fitsLabels;
    final short =
        compact &&
        (flags & _sessionConnection) != 0 &&
        packet!.peer == null &&
        packet.bytes.length <= 0xffff;
    if (compact) flags |= _compact;
    if (short) flags |= _shortSessionPacket;
    final zeroSequence = short && record.sent && packet.sequence == 0;
    if (zeroSequence) flags |= _zeroPacketSequence;
    headers[index] = flags;
    final headerSize = short
        ? _shortSessionHeaderSize -
              (zeroSequence ? _compactPacketSequenceBytes : 0)
        : (compact ? _compactLayout : _wideLayout).headerSize;
    size += headerSize + remaining;
    ends[index] = size;
  }

  // 单条大记录的原始负载独立写入，记录末尾仍按完整编码长度计算。
  final omitted = omitSinglePayload ? records.single.packet!.bytes.length : 0;
  final output = Uint8List(size - omitted);
  final data = ByteData.sublistView(output);
  var offset = 0;
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    final packet = record.packet;
    final end = ends[index];
    final flags = headers[index];
    final compact = (flags & _compact) != 0;
    final layout = compact ? _compactLayout : _wideLayout;
    data.setUint8(offset + _flags, flags);
    if (compact) {
      data.setUint32(offset + _sequence, record.sequence);
    } else {
      data.setInt64(offset + _sequence, record.sequence);
    }
    final short = (flags & _shortSessionPacket) != 0;
    final zeroSequence = (flags & _zeroPacketSequence) != 0;
    final omittedSequence = zeroSequence ? _compactPacketSequenceBytes : 0;
    var start =
        offset +
        (short ? _shortSessionHeaderSize : layout.headerSize) -
        omittedSequence;
    if ((flags & _notice) != 0) {
      final notice = label(record.notice ?? '');
      data.setUint32(offset + layout.payloadLength, notice.length);
      output.setRange(start, end, notice);
    } else {
      final connection = (flags & _sessionConnection) == 0
          ? label(packet!.connectionId)
          : null;
      final connectionLength = connection?.length ?? 0;
      final peerName = packet!.peer;
      final peer = peerName == null ? null : label(peerName);
      data.setInt64(
        offset + layout.time,
        packet.receivedAt.microsecondsSinceEpoch,
      );
      if (short) {
        data.setUint16(
          offset + layout.payloadLength - omittedSequence,
          packet.bytes.length,
        );
      } else {
        data.setUint32(offset + layout.payloadLength, packet.bytes.length);
      }
      if (compact) {
        if (!zeroSequence) {
          data.setUint32(offset + layout.packetSequence, packet.sequence);
        }
        data.setUint32(offset + layout.epoch - omittedSequence, packet.epoch);
        if (!short) {
          data.setUint32(
            offset + layout.connectionLength,
            (connectionLength << 16) | (peer?.length ?? _nullCompactPeer),
          );
        }
      } else {
        data
          ..setInt64(offset + layout.packetSequence, packet.sequence)
          ..setInt64(offset + layout.epoch, packet.epoch)
          ..setUint32(offset + layout.connectionLength, connectionLength)
          ..setInt32(offset + layout.peerLength, peer?.length ?? -1);
      }
      if (connection != null) {
        output.setAll(start, connection);
        start += connectionLength;
      }
      if (peer != null) {
        output.setAll(start, peer);
        start += peer.length;
      }
      if (!omitSinglePayload) output.setRange(start, end, packet.bytes);
    }
    offset = end;
  }
  return (bytes: output, ends: ends);
}

void _decodeRecords(
  Uint8List bytes,
  int count,
  String? connectionId,
  void Function(SessionRecord) consume, {
  bool consumeImmediately = false,
}) {
  final data = ByteData.sublistView(bytes);
  const decoder = Utf8Decoder();
  var offset = 0;
  for (var index = 0; index < count; index++) {
    final flags = data.getUint8(offset + _flags);
    final compact = (flags & _compact) != 0;
    final layout = compact ? _compactLayout : _wideLayout;
    final sequence = compact
        ? data.getUint32(offset + _sequence)
        : data.getInt64(offset + _sequence);
    final short = (flags & _shortSessionPacket) != 0;
    final zeroSequence = (flags & _zeroPacketSequence) != 0;
    if (zeroSequence && (!short || (flags & _sent) == 0)) {
      throw StateError('历史发送回执的记录头无效');
    }
    final omittedSequence = zeroSequence ? _compactPacketSequenceBytes : 0;
    final payloadLength = short
        ? data.getUint16(offset + layout.payloadLength - omittedSequence)
        : data.getUint32(offset + layout.payloadLength);
    var start =
        offset +
        (short ? _shortSessionHeaderSize : layout.headerSize) -
        omittedSequence;
    if ((flags & _notice) != 0) {
      if (short) throw StateError('历史缺口记录头无效');
      offset = start + payloadLength;
      consume(
        SessionRecord(
          null,
          sequence: sequence,
          notice: decoder.convert(bytes, start, offset),
        ),
      );
      continue;
    }
    final String connection;
    final String? peer;
    if (short) {
      if (!compact ||
          (flags & _sessionConnection) == 0 ||
          connectionId == null) {
        throw StateError('无对端的会话短包记录头无效');
      }
      connection = connectionId;
      peer = null;
    } else {
      final labelLengths = data.getUint32(offset + layout.connectionLength);
      final connectionLength = compact ? labelLengths >> 16 : labelLengths;
      final connectionEnd = start + connectionLength;
      if ((flags & _sessionConnection) != 0) {
        if (connectionId == null || connectionLength != 0) {
          throw StateError('历史记录的会话连接标识无效');
        }
        connection = connectionId;
      } else {
        connection = decoder.convert(bytes, start, connectionEnd);
      }
      start = connectionEnd;
      var peerLength = compact
          ? labelLengths & 0xffff
          : data.getInt32(offset + layout.peerLength);
      if (compact && peerLength == _nullCompactPeer) peerLength = -1;
      peer = peerLength < 0
          ? null
          : decoder.convert(bytes, start, start + peerLength);
      if (peerLength >= 0) start += peerLength;
    }
    final end = start + payloadLength;
    // 即时消费可以借用输入页。持久化到回看窗口的小包各自拷贝一次，
    // 避免裁剪窗口后单条记录继续持有整页。
    final sharePage =
        consumeImmediately ||
        (count == 1 &&
            payloadLength >= 128 * 1024 &&
            payloadLength >= bytes.length - payloadLength);
    final payload = sharePage
        ? Uint8List.sublistView(bytes, start, end)
        : bytes.sublist(start, end);
    final input = TransportInput.takeOwned(
      payload,
      peer: peer,
      datagram: (flags & _datagram) != 0,
    );
    consume(
      SessionRecord(
        RawPacket.fromInput(
          input,
          connectionId: connection,
          receivedAt: DateTime.fromMicrosecondsSinceEpoch(
            data.getInt64(offset + layout.time),
            isUtc: true,
          ),
          epoch: compact
              ? data.getUint32(offset + layout.epoch - omittedSequence)
              : data.getInt64(offset + layout.epoch),
          sequence: zeroSequence
              ? 0
              : compact
              ? data.getUint32(offset + layout.packetSequence)
              : data.getInt64(offset + layout.packetSequence),
        ),
        sent: (flags & _sent) != 0,
        sequence: sequence,
      ),
    );
    offset = end;
  }
  if (offset != bytes.length) throw StateError('历史索引与记录长度不一致');
}

Future<_EncodedBatch> _encodeInBackground(
  List<SessionRecord> records,
  String? connectionId,
) => Isolate.run(() => _encodeRecords(records, connectionId: connectionId));

Uint8List _readSliceBytes(
  _PageRead read, {
  RandomAccessFile? openFile,
  int position = 0,
}) {
  final input = openFile ?? File(read.path).openSync();
  try {
    if (read.offset != position) input.setPositionSync(read.offset);
    final bytes = input.readSync(read.length);
    if (bytes.length != read.length) {
      throw StateError('历史文件缺少已发布的字节');
    }
    return bytes;
  } finally {
    if (openFile == null) input.closeSync();
  }
}

List<SessionRecord> _readPageFromFiles(List<_PageRead> reads) {
  final records = <SessionRecord>[];
  RandomAccessFile? file;
  String? path;
  var position = 0;
  try {
    for (final read in reads) {
      // 部分命中的页可能要补读同一分段的两端。
      if (read.path != path) {
        final previous = file;
        file = null;
        previous?.closeSync();
        file = File(read.path).openSync();
        path = read.path;
        position = 0;
      }
      _decodeRecords(
        _readSliceBytes(read, openFile: file, position: position),
        read.count,
        read.connectionId,
        records.add,
      );
      position = read.offset + read.length;
    }
  } finally {
    file?.closeSync();
  }
  return records;
}

Future<Uint8List> _exportInBackground(_PageRead read) => Isolate.run(() {
  final output = BytesBuilder(copy: false);
  final encoder = JsonUtf8Encoder();
  _decodeRecords(_readSliceBytes(read), read.count, read.connectionId, (
    record,
  ) {
    output.add(encoder.convert(record.toJson()));
    output.addByte(0x0a);
  }, consumeImmediately: true);
  return output.takeBytes();
});
