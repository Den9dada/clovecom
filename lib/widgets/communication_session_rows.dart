import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../src/application/session_history.dart';

const _bytesPerRow = 1024;
const _maxCachedSendBytes = 16 * _bytesPerRow;
const _hexDigits = '0123456789ABCDEF';
final _hexTriplets = Uint32List.fromList([
  for (var byte = 0; byte < 256; byte++)
    _hexDigits.codeUnitAt(byte >> 4) |
        (_hexDigits.codeUnitAt(byte & 15) << 8) |
        0x200000,
]);

/// 会话视图复用同一秒内的本地时分秒，只对每条记录补齐毫秒。
class SessionTimestampLabel {
  int? _second;
  String _prefix = '', _wholeSecond = '';

  String format(DateTime value, {required bool milliseconds}) {
    final micros = value.microsecondsSinceEpoch;
    final fraction = micros % Duration.microsecondsPerSecond;
    final second = micros - fraction;
    if (second != _second) {
      final local = value.toLocal();
      String two(int number) => number.toString().padLeft(2, '0');
      _prefix = '[${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
      _wholeSecond = '$_prefix]';
      _second = second;
    }
    if (!milliseconds) return _wholeSecond;
    final millis = fraction ~/ Duration.microsecondsPerMillisecond;
    return '$_prefix.${millis.toString().padLeft(3, '0')}]';
  }
}

/// 记录窗口的惰性行索引。只为可见行及 Flutter 预建行生成格式化文本。
class SessionDisplayRows {
  List<SessionRecord>? _records;
  bool _hideReceive = false, _liveTail = false;
  List<SessionRecord> _visible = const [];
  ListQueue<int>? _rowEnds;
  int _rowsBeforeWindow = 0;
  int _nearRecord = -1, _nearStart = 0, _nearEnd = 0;
  final _cache = <(int, int), SessionDisplayRow>{};
  (int, int)? _cachedSequences;

  final _longHexKeys = Uint64List(32);
  final _longHex = List<({Uint8List bytes, int start, String text})?>.filled(
    32,
    null,
  );
  List<int>? _lastSentPayload;
  String? _lastSentHex, _lastSentText;
  Map<(int, bool), String>? _lastSentSplitText;

  int get length => (_rowEnds?.last ?? _visible.length) - _rowsBeforeWindow;
  bool get hasSplitRecords => _rowEnds != null;

  String textFor(SessionDisplayRow row, {required bool hex}) {
    final record = row.record;
    final packet = record.packet;
    if (packet == null ||
        packet.peer != null ||
        record.notice != null ||
        record.textPrefix.isNotEmpty) {
      return row.text(hex: hex);
    }
    final bytes = packet.bytes;
    if (!record.sent) return _formatRow(row, bytes, hex);
    if (bytes.length > _maxCachedSendBytes ||
        (row.start != 0 &&
            (row.start < 0 ||
                row.start >= bytes.length ||
                row.start % _bytesPerRow != 0))) {
      return row.text(hex: hex);
    }
    // 原生循环回执可共享同一不可变负载，行号、时间戳仍由各行独立处理。
    if (!identical(_lastSentPayload, bytes)) {
      _lastSentPayload = bytes;
      _lastSentHex = _lastSentText = null;
      _lastSentSplitText = null;
    }
    if (bytes.length > _bytesPerRow) {
      return (_lastSentSplitText ??= {}).putIfAbsent((
        row.start,
        hex,
      ), () => _formatRow(row, bytes, hex));
    }
    return hex
        ? _lastSentHex ??= row.text(hex: true)
        : _lastSentText ??= row.text(hex: false);
  }

  String _formatRow(SessionDisplayRow row, List<int> bytes, bool hex) {
    const native = !bool.fromEnvironment('dart.library.js_interop');
    final start = row.start;
    final end = math.min(start + _bytesPerRow, bytes.length);
    if (!native ||
        !hex ||
        bytes is! Uint8List ||
        bytes.length > _maxCachedSendBytes ||
        start < 0 ||
        end - start < 192) {
      return row.text(hex: hex);
    }
    return row._hex ??= _cachedHex(bytes, start, end, row);
  }

  String _cachedHex(
    Uint8List bytes,
    int start,
    int end,
    SessionDisplayRow row,
  ) {
    final length = end - start;
    final key =
        (length << 24) |
        (bytes[start] << 16) |
        (bytes[start + length ~/ 2] << 8) |
        bytes[end - 1];
    final slot = (key ^ (key >> 9) ^ (key >> 17)) & 31;
    // 样本重复后才保留报文和字符串，随机负载只记一个整数。
    if (_longHexKeys[slot] != key) {
      _longHexKeys[slot] = key;
      _longHex[slot] = null;
      return row._formatHex(bytes, end);
    }
    final previous = _longHex[slot];
    if (previous != null) {
      if (identical(previous.bytes, bytes) && previous.start == start) {
        return previous.text;
      }
      final view = ByteData.sublistView(bytes, start, end);
      final other = ByteData.sublistView(
        previous.bytes,
        previous.start,
        previous.start + length,
      );
      var offset = 0;
      for (; offset + 8 <= length; offset += 8) {
        if (view.getUint64(offset, Endian.host) !=
            other.getUint64(offset, Endian.host)) {
          break;
        }
      }
      while (offset < length &&
          view.getUint8(offset) == other.getUint8(offset)) {
        offset++;
      }
      if (offset == length) return previous.text;
    }
    // 样本仅用于查找，复用前核对完整字节。
    final text = row._formatHex(bytes, end);
    _longHex[slot] = (bytes: bytes, start: start, text: text);
    return text;
  }

  /// 窗口更新影响可见记录时返回 true。
  bool replace(
    List<SessionRecord> records, {
    required bool hideReceive,
    bool liveTail = false,
  }) {
    final filterChanged = hideReceive != _hideReceive;
    final previousLiveTail = _liveTail;
    _liveTail = liveTail;
    if (identical(_records, records) && !filterChanged) return false;
    var firstUnindexed = 0, expired = 0;
    // 实时尾部只追加和淘汰。核对重叠区两端的记录身份后再复用索引。
    final previous = _records;
    if (liveTail &&
        previousLiveTail &&
        !filterChanged &&
        previous != null &&
        previous.isNotEmpty &&
        records.isNotEmpty) {
      final first = records.first;
      final firstKept = first.sequence - previous.first.sequence;
      final overlapEnd = previous.last.sequence - first.sequence;
      if (firstKept >= 0 &&
          firstKept < previous.length &&
          overlapEnd >= 0 &&
          overlapEnd < records.length &&
          identical(previous[firstKept], first) &&
          identical(records[overlapEnd], previous.last)) {
        expired = firstKept;
        firstUnindexed = overlapEnd + 1;
      }
    }
    final visible = hideReceive
        ? _filterReceive(records, firstUnindexed)
        : records;
    _records = records;
    _hideReceive = hideReceive;
    if (records.isEmpty) {
      _longHexKeys.fillRange(0, _longHexKeys.length, 0);
      _longHex.fillRange(0, _longHex.length, null);
      _lastSentPayload = null;
      _lastSentHex = _lastSentText = null;
      _lastSentSplitText = null;
    }
    if (hideReceive) {
      if (!filterChanged && identical(_visible, visible)) return false;
      firstUnindexed = 0;
    }
    _visible = visible;
    _indexRows(visible, firstUnindexed, expired);

    if (filterChanged || visible.isEmpty) {
      _cache.clear();
      _cachedSequences = null;
    } else if (_cachedSequences case (final firstCached, final lastCached)) {
      final first = visible.first.sequence, last = visible.last.sequence;
      if (firstCached < first || lastCached > last) {
        _cache.removeWhere((id, _) => id.$1 < first || id.$1 > last);
        // 淘汰前的边界可以更宽；清理后收紧，以免下一次追加时再次扫描。
        _cachedSequences = _cache.isEmpty
            ? null
            : (math.max(firstCached, first), math.min(lastCached, last));
      }
    }
    return true;
  }

  List<SessionRecord> _filterReceive(List<SessionRecord> records, int overlap) {
    if (overlap == 0) {
      List<SessionRecord>? visible;
      for (final record in records) {
        if (record.sent || record.packet == null) (visible ??= []).add(record);
      }
      return visible ?? (_visible.isEmpty ? _visible : const []);
    }

    final first = records.first.sequence;
    var expired = 0;
    while (expired < _visible.length && _visible[expired].sequence < first) {
      expired++;
    }
    List<SessionRecord>? updated;
    for (var index = overlap; index < records.length; index++) {
      final record = records[index];
      if (record.sent || record.packet == null) {
        (updated ??= _visible.sublist(expired)).add(record);
      }
    }
    return updated ?? (expired == 0 ? _visible : _visible.sublist(expired));
  }

  void _indexRows(
    List<SessionRecord> records,
    int firstUnindexed,
    int expired,
  ) {
    var ends = firstUnindexed == 0 ? null : _rowEnds;
    var end = firstUnindexed;
    if (ends == null) {
      _rowsBeforeWindow = 0;
    } else {
      // 用绝对行尾记录窗口移动，移除旧记录时无需重写重叠区。
      for (var i = 0; i < expired; i++) {
        _rowsBeforeWindow = ends.removeFirst();
      }
      end = ends.last;
    }
    for (var index = firstUnindexed; index < records.length; index++) {
      final bytes = records[index].packet?.bytes.length ?? 0;
      if (bytes > _bytesPerRow) {
        if (ends == null) {
          ends = ListQueue<int>(records.length);
          // 第一条长记录之前，每条记录都正好占一行。
          for (var previous = 0; previous < index; previous++) {
            ends.addLast(previous + 1);
          }
        }
        end += (bytes + _bytesPerRow - 1) ~/ _bytesPerRow;
      } else {
        end++;
      }
      ends?.addLast(end);
    }
    if (end - _rowsBeforeWindow == records.length) {
      _rowsBeforeWindow = 0;
      ends = null;
    }
    _rowEnds = ends;
    _nearRecord = -1;
  }

  SessionDisplayRow? get firstOrNull => length == 0 ? null : this[0];
  SessionDisplayRow? get lastOrNull => length == 0 ? null : this[length - 1];

  int _firstRow(int recordIndex) =>
      recordIndex == 0 ? 0 : _endRow(recordIndex - 1);

  int _endRow(int recordIndex) =>
      (_rowEnds?.elementAt(recordIndex) ?? recordIndex + 1) - _rowsBeforeWindow;

  int _findRecord(int sequence) {
    var first = 0;
    var end = _visible.length;
    if (end != 0) {
      // 连续序号可直接定位，历史缺口和隐藏接收的窗口按序号二分。
      final offset = sequence - _visible.first.sequence;
      if (offset >= 0 &&
          offset < end &&
          _visible[offset].sequence == sequence) {
        return offset;
      }
    }
    while (first < end) {
      final middle = (first + end) ~/ 2;
      if (_visible[middle].sequence < sequence) {
        first = middle + 1;
      } else {
        end = middle;
      }
    }
    return first;
  }

  int? indexOf((int, int) id) {
    final record = _findRecord(id.$1);
    if (record == _visible.length || _visible[record].sequence != id.$1) {
      return null;
    }
    final row = _firstRow(record) + id.$2 ~/ _bytesPerRow;
    return row < _endRow(record) ? row : null;
  }

  int lowerBound((int, int) id) {
    final record = _findRecord(id.$1);
    if (record == _visible.length) return length;
    final first = _firstRow(record);
    if (_visible[record].sequence != id.$1) return first;
    return math.min(
      _endRow(record),
      first + (id.$2 + _bytesPerRow - 1) ~/ _bytesPerRow,
    );
  }

  void _locateSplitRow(int index, ListQueue<int> ends) {
    if (_nearRecord >= 0) {
      if (index >= _nearStart && index < _nearEnd) return;
      // Sliver 通常正向或反向连续取行，跨一个报文时可直接更新边界。
      if (index == _nearEnd) {
        _nearRecord++;
        _nearStart = _nearEnd;
        _nearEnd = _endRow(_nearRecord);
        return;
      }
      if (index == _nearStart - 1) {
        _nearRecord--;
        _nearEnd = _nearStart;
        _nearStart = _firstRow(_nearRecord);
        return;
      }
    }
    var first = 0;
    var end = ends.length;
    final absoluteIndex = index + _rowsBeforeWindow;
    while (first < end) {
      final middle = (first + end) ~/ 2;
      if (ends.elementAt(middle) <= absoluteIndex) {
        first = middle + 1;
      } else {
        end = middle;
      }
    }
    _nearRecord = first;
    _nearStart = _firstRow(first);
    _nearEnd = _endRow(first);
  }

  SessionDisplayRow operator [](int index) {
    RangeError.checkValueInInterval(index, 0, length - 1);
    final ends = _rowEnds;
    var recordIndex = index, rowStart = index;
    if (ends != null) {
      _locateSplitRow(index, ends);
      recordIndex = _nearRecord;
      rowStart = _nearStart;
    }
    final record = _visible[recordIndex];
    final start = (index - rowStart) * _bytesPerRow;
    final id = (record.sequence, start);
    final cached = _cache.remove(id);
    final row = cached != null && identical(cached.record, record)
        ? cached
        : SessionDisplayRow(record, start);
    _cache[id] = row;
    if (cached == null) {
      final sequence = record.sequence;
      final (first, last) = _cachedSequences ?? (sequence, sequence);
      _cachedSequences = (math.min(first, sequence), math.max(last, sequence));
    }
    if (_cache.length > 192) _cache.remove(_cache.keys.first);
    return row;
  }
}

class SessionDisplayRow {
  SessionDisplayRow(this.record, this.start);

  final SessionRecord record;
  final int start;
  (int, int) get id => (record.sequence, start);
  String? _hex, _utf8;

  String text({required bool hex}) {
    if (record.notice case final notice?) return notice;
    return hex ? _hex ??= _format(true) : _utf8 ??= _format(false);
  }

  String _format(bool hex) {
    final packet = record.packet;
    if (packet == null) return '';
    final bytes = packet.bytes;
    final end = math.min(start + _bytesPerRow, bytes.length);
    final String content;
    if (hex) {
      content = _formatHex(bytes, end);
    } else {
      final prefixStart = incompleteSessionUtf8Start(bytes, 0, start);
      final prefix = start == 0
          ? record.textPrefix
          : prefixStart == start
          ? const <int>[]
          : bytes.sublist(prefixStart, start);
      final continues =
          end < bytes.length || (!packet.datagram && !record.sent);
      const decoder = Utf8Decoder(allowMalformed: true);
      if (prefix.isEmpty) {
        final textEnd = continues
            ? incompleteSessionUtf8Start(bytes, start, end)
            : end;
        content = decoder.convert(bytes, start, textEnd);
      } else {
        final input = [...prefix, ...bytes.getRange(start, end)];
        final textEnd = continues
            ? incompleteSessionUtf8Start(input, 0, input.length)
            : input.length;
        content = decoder.convert(input, 0, textEnd);
      }
    }
    final peer = start == 0 ? packet.peer : null;
    return peer == null ? content : '$peer $content';
  }

  String _formatHex(List<int> bytes, int end) {
    if (start == end) return '';
    if (bytes is Uint8List) {
      final length = (end - start) * 3;
      const native = !bool.fromEnvironment('dart.library.js_interop');
      final packed = native && end - start >= 32;
      final chars = Uint8List(length + (packed ? 2 : 1));
      final output = ByteData.sublistView(chars);
      var index = start, offset = 0;
      if (packed) {
        // 两个输入字节组成六个字符，下一次写入覆盖本次的填充。
        for (; index + 1 < end; index += 2, offset += 6) {
          final low = _hexTriplets[bytes[index]];
          final high = _hexTriplets[bytes[index + 1]];
          output.setUint64(offset, low | (high << 24), Endian.little);
        }
      }
      for (; index < end; index++, offset += 3) {
        output.setUint32(offset, _hexTriplets[bytes[index]], Endian.little);
      }
      return String.fromCharCodes(chars, 0, length - 1);
    }
    final chars = Uint8List((end - start) * 3 - 1);
    var offset = 0;
    for (var index = start; index < end; index++) {
      final byte = bytes[index];
      if (byte < 0 || byte > 255) {
        // 保留普通列表中非字节值原有的显示方式。
        return bytes
            .getRange(start, end)
            .map(
              (value) => value.toRadixString(16).padLeft(2, '0').toUpperCase(),
            )
            .join(' ');
      }
      if (index != start) chars[offset++] = 0x20;
      chars[offset++] = _hexDigits.codeUnitAt(byte >> 4);
      chars[offset++] = _hexDigits.codeUnitAt(byte & 15);
    }
    return String.fromCharCodes(chars);
  }
}
