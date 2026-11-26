import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../io/recording.dart';

part 'session_history_codec.dart';
part 'session_history_reader.dart';

/// TX 只包含传输层确认接受的字节。缺口记录单独表示丢失的范围。
class SessionRecord {
  const SessionRecord(
    this.packet, {
    this.sent = false,
    this.notice,
    this.sequence = 0,
    this.textPrefix = const [],
  });
  final int sequence;
  final RawPacket? packet;
  final bool sent;
  final String? notice;
  final List<int> textPrefix;

  SessionRecord _withPrefix(List<int> prefix) => SessionRecord(
    packet,
    sent: sent,
    notice: notice,
    sequence: sequence,
    textPrefix: prefix,
  );
  int get cost => _costOf(packet);

  static int _costOf(RawPacket? packet) => (packet?.bytes.length ?? 0) + 160;

  Map<String, Object?> toJson() {
    final packet = this.packet;
    final json = packet?.toJson() ?? <String, Object?>{};
    if (packet != null) json['direction'] = sent ? 'tx' : 'rx';
    if (notice != null) json['gap'] = notice;
    if (sequence != 0) json['recordSequence'] = sequence;
    return json;
  }

  factory SessionRecord.fromJson(Map<String, dynamic> json) =>
      switch (json['gap']) {
        final String notice => SessionRecord(
          null,
          notice: notice,
          sequence: json['recordSequence'] as int? ?? 0,
        ),
        _ => SessionRecord(
          RawPacket.fromJson(json),
          sent: json['direction'] == 'tx',
          sequence: json['recordSequence'] as int? ?? 0,
        ),
      };
}

/// 返回区间内未收齐的 UTF-8 后缀起点，完整时返回 end。
int incompleteSessionUtf8Start(List<int> bytes, int start, int end) {
  if (end <= start || (bytes[end - 1] & 0x80) == 0) return end;
  // UTF-8 字符最多 4 字节，未收齐时最多留下 3 字节。
  final limit = max(start, end - 3);
  for (var index = end - 1; index >= limit; index--) {
    final lead = bytes[index];
    if ((lead & 0xc0) == 0x80) continue;
    final expected = switch (lead) {
      >= 0xc2 && <= 0xdf => 2,
      >= 0xe0 && <= 0xef => 3,
      >= 0xf0 && <= 0xf4 => 4,
      _ => 1,
    };
    return expected > end - index ? index : end;
  }
  return end;
}

/// 进程锁避免多个应用实例之间误删正在使用的文件。
class SessionHistoryDirectory {
  static Future<Directory>? _current;
  static RandomAccessFile? _lock;

  static Future<Directory> open() async {
    return _current ??= _prepare().then(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        unawaited(_lock?.close());
        _lock = null;
        _current = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  static Future<Directory> _prepare() async {
    final root = await Directory(
      path.join(Directory.systemTemp.path, 'clovecom-session-history'),
    ).create(recursive: true);
    final guard = await File(path.join(root.path, '.maintenance'))
        .open(mode: FileMode.append);
    try {
      await guard.lock(FileLock.blockingExclusive);
      return await _prepareRun(root);
    } finally {
      await guard.close();
    }
  }

  static Future<Directory> _prepareRun(Directory root) async {
    final current = await root.createTemp('run-');
    final lock = await File(path.join(current.path, '.lock'))
        .open(mode: FileMode.append);
    await lock.lock();
    _lock = lock;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          entity.path == current.path ||
          !path.basename(entity.path).startsWith('run-')) {
        continue;
      }
      // 仅清理初始化完成且进程锁已释放的目录。
      final oldLock = File(path.join(entity.path, '.lock'));
      if (!await oldLock.exists()) continue;
      try {
        final handle = await oldLock.open(mode: FileMode.append);
        try {
          await handle.lock(FileLock.exclusive);
        } finally {
          await handle.close();
        }
        await entity.delete(recursive: true);
      } on FileSystemException {
        // 仍有实例正在记录，或目录已由另一个实例清理。
      }
    }
    return current;
  }
}

class SessionHistoryPage {
  const SessionHistoryPage(this.before, this.after, this.records);
  final int before, after;
  final List<SessionRecord> records;
}

class SessionHistoryCursorPage {
  const SessionHistoryCursorPage(this.records, this.oldest);
  final List<SessionRecord> records;
  final int? oldest;
}

class _Segment {
  _Segment(this.file, this.start);
  final File file;
  final int start;
  final ends = <int>[];
  final sequences = <int>[];
  final sentOrNotice = <int>[];
  final prefixes = <int, List<int>>{};
  int readers = 0;
  bool sealed = false;
  int get bytes => ends.lastOrNull ?? 0;
  int get count => ends.length;
  int get end => start + count;

  int offset(int index) => index == 0 ? 0 : ends[index - 1];

  int fitPage(int edge, int count, int budget, bool forward) {
    final origin = offset(edge);
    int size(int records) => forward
        ? offset(edge + records) - origin
        : origin - offset(edge - records);
    if (size(count) <= budget) return count;
    // 累计字节偏移单调递增，直接找预算内最远的记录边界。
    var low = 0, high = count;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (size(middle) <= budget) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static int _boundary(List<int> ordered, int sequence, {bool after = false}) {
    var left = 0;
    var right = ordered.length;
    while (left < right) {
      final middle = (left + right) ~/ 2;
      final current = ordered[middle];
      if (current < sequence || (after && current == sequence)) {
        left = middle + 1;
      } else {
        right = middle;
      }
    }
    return left;
  }
}

typedef _HistorySlice = ({
  _Segment segment,
  int from,
  int to,
  int start,
  int end,
});

typedef _CachedPage = ({List<SessionRecord> records, int cost});

typedef _CachedSpan = ({
  int from,
  int to,
  int pageStart,
  List<SessionRecord> records,
});

/// 每个打开的会话独立拥有队列、分段文件和游标。
class SessionHistory {
  static const defaultMaxBytes = 16 * 1024 * 1024;

  SessionHistory(
    this.root,
    this.changed, {
    this.connectionId,
    this.maxBytes = defaultMaxBytes,
    this.segmentBytes = 256 * 1024,
    this.pendingLimit = 2 * 1024 * 1024,
  });

  final Future<Directory> Function() root;
  final void Function() changed;
  final String? connectionId;
  final int maxBytes, segmentBytes, pendingLimit;
  final _segments = ListQueue<_Segment>();
  // 尚未成功写入的分段只由文件清理队列持有。
  final _published = ListQueue<_Segment>();
  final _visibleSegments = ListQueue<_Segment>();
  final _pending = ListQueue<SessionRecord>();
  // 少量最近访问的页用于滚动方向变化及重复定位，独立于磁盘历史容量。
  static const _pageCacheLimit = 4;
  static const _minimumByteReuse = 64 * 1024;
  static const _pageCacheByteLimit = 1024 * 1024;
  final _cachedPages = <(int, int), _CachedPage>{};
  int _cachedPageBytes = 0;
  final _pageReader = _HistoryPageReader();
  final _pendingPages = <(int, int), Future<List<SessionRecord>>>{};
  final _retired = <_Segment>{};
  final _retiredFolders = <Directory>{};
  final _carry = <String?, ({List<int> bytes, int firstSequence})>{};
  int _diskGapSequence = 0;
  int? _carryEpoch;
  int _generation = 0, _clearing = 0;
  int get generation => _generation;
  bool _exporting = false;
  int? get oldestPublishedSequence => _clearing != 0 || _published.isEmpty
      ? null
      : _published.first.sequences.first;

  int get publishedSequence =>
      _clearing != 0 || _published.isEmpty ? 0 : _published.last.sequences.last;

  bool get hasPending => _pending.isNotEmpty || _writing;
  Future<void> _cleanup = Future.value();
  int _pendingBytes = 0, _storedBytes = 0, _next = 0, _serial = 0;
  int _lost = 0, _sequence = 0;
  bool _closed = false;
  bool truncated = false;
  String? error;
  Directory? _folder;
  Timer? _timer, _appendIdle;
  bool _flushSoonScheduled = false;
  static const _maxBatchBytes = 128 * 1024;
  late final _flushWatermark = max(1, min(_maxBatchBytes, pendingLimit ~/ 2));
  RandomAccessFile? _appendHandle;
  _Segment? _appendSegment;
  Future<void> _tail = Future.value();
  bool _writing = false;
  bool get hasHistory =>
      _segments.isNotEmpty || _pending.isNotEmpty || _writing;

  /// 让实时记录与从磁盘读出的同一记录使用同一个序号。
  SessionRecord append(SessionRecord record) => _closed
      ? record
      : _append(record.packet, sent: record.sent, notice: record.notice);

  SessionRecord appendPacket(RawPacket packet, {bool sent = false}) =>
      _closed ? SessionRecord(packet, sent: sent) : _append(packet, sent: sent);

  SessionRecord _append(
    RawPacket? packet, {
    bool sent = false,
    String? notice,
  }) {
    final cost = SessionRecord._costOf(packet);
    final canQueue = error == null && _pendingBytes + cost <= pendingLimit;
    if (canQueue) _queueGap();
    final sequence = ++_sequence;
    if (notice != null ||
        (packet != null && !sent && packet.epoch != _carryEpoch)) {
      _carry.clear();
      _carryEpoch = packet?.epoch;
    }
    var prefix = const <int>[];
    int? prefixSequence;
    if (packet != null &&
        !sent &&
        !packet.datagram &&
        packet.bytes.isNotEmpty) {
      final carry = _carry.isEmpty ? null : _carry.remove(packet.peer);
      if (carry != null) {
        prefix = carry.bytes;
        prefixSequence = carry.firstSequence;
      }
      final bytes = packet.bytes;
      final tail = prefix.isNotEmpty && bytes.length < 3
          ? [...prefix, ...bytes]
          : bytes;
      final incomplete = incompleteSessionUtf8Start(tail, 0, tail.length);
      if (incomplete < tail.length) {
        if (_carry.length >= 32) _carry.remove(_carry.keys.first);
        _carry[packet.peer] = (
          bytes: List.unmodifiable(tail.sublist(incomplete)),
          firstSequence: !identical(tail, bytes) && incomplete < prefix.length
              ? prefixSequence!
              : sequence,
        );
      }
    }
    final numbered = SessionRecord(
      packet,
      sent: sent,
      notice: notice,
      sequence: sequence,
      textPrefix: prefix,
    );
    if (!canQueue) {
      _lost++;
      if (!truncated) {
        truncated = true;
        changed();
      }
      return numbered;
    }
    // 落盘缺口不影响实时流。回放只能使用缺口之后收到的前缀。
    final saved = prefixSequence != null && prefixSequence <= _diskGapSequence
        ? numbered._withPrefix(const [])
        : numbered;
    _pending.add(saved);
    _pendingBytes += cost;
    _schedule();
    return numbered;
  }

  void _queueGap() {
    if (_lost == 0) return;
    final gap = SessionRecord(
      null,
      notice: '历史缺口：$_lost 条记录未能保存',
      sequence: ++_sequence,
    );
    _diskGapSequence = gap.sequence;
    _pending.add(gap);
    _pendingBytes += gap.cost;
    _lost = 0;
  }

  void _schedule() {
    if (_closed || error != null || _writing || _pending.isEmpty) return;
    final flushSoon = _pendingBytes >= _flushWatermark;
    if (_timer != null && (_flushSoonScheduled || !flushSoon)) return;
    _timer?.cancel();
    _flushSoonScheduled = flushSoon;
    // 低流量合批，积压到高水位时让出当前事件轮后立即写盘。
    _timer = Timer(
      flushSoon ? Duration.zero : const Duration(milliseconds: 40),
      () {
        _timer = null;
        unawaited(flush());
      },
    );
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _flushSoonScheduled = false;
    if (_closed || error != null) return _tail;
    if (_writing) return _tail.then((_) => flush());
    _queueGap();
    var remaining = _pending.length;
    if (remaining == 0) return _tail;
    _appendIdle?.cancel();
    _appendIdle = null;
    _writing = true;
    final generation = _generation;
    final batchLimit = min(segmentBytes ~/ 2, _maxBatchBytes);
    return _serialize(() async {
      try {
        while (!_closed &&
            generation == _generation &&
            remaining > 0 &&
            _pending.isNotEmpty) {
          final batch = <SessionRecord>[];
          var cost = 0;
          while (remaining > 0 && _pending.isNotEmpty) {
            final nextCost = _pending.first.cost;
            if (batch.isNotEmpty && cost + nextCost > batchLimit) break;
            batch.add(_pending.removeFirst());
            cost += nextCost;
            remaining--;
          }
          try {
            await _write(batch, cost, generation);
          } catch (_) {
            if (generation == _generation) _lost += batch.length;
            rethrow;
          } finally {
            _pendingBytes -= cost;
          }
          // 文件等待期间，实时显示仍可刷新。
        }
      } catch (failure) {
        if (generation != _generation) return;
        _lost += _pending.length;
        _pending.clear();
        _pendingBytes = 0;
        error = '历史写入失败：$failure';
        truncated = true;
        changed();
      } finally {
        _writing = false;
        if (generation == _generation) {
          _queueGapIfPaused();
          _scheduleAppendIdle();
        }
        _schedule();
      }
    });
  }

  void _queueGapIfPaused() {
    if (!_closed && error == null && _pending.isEmpty) _queueGap();
  }

  Future<void> _write(
    List<SessionRecord> batch,
    int cost,
    int generation,
  ) async {
    final folder = _folder ??= await (await root()).createTemp('session-');
    final rawPayload =
        batch.length == 1 &&
            cost > _maxBatchBytes &&
            batch.single.notice == null
        ? batch.single.packet?.bytes
        : null;
    final payload = rawPayload is Uint8List ? rawPayload : null;
    final small = batch.length <= 256 && cost <= _maxBatchBytes;
    final contents = small || payload != null
        ? _encodeRecords(
            batch,
            connectionId: connectionId,
            omitSinglePayload: payload != null,
          )
        : await _encodeInBackground(batch, connectionId);
    final encodedLength = contents.ends.last;
    if (generation != _generation) return;
    if (encodedLength > maxBytes) {
      _lost += batch.length;
      truncated = true;
      changed();
      return;
    }
    // 已退役且无人读取的分段可用作新分段，避免每次轮换删除并新建文件。
    final last = _segments.lastOrNull;
    final needsSegment =
        last == null ||
        last.sealed ||
        last.bytes + encodedLength > segmentBytes;
    _Segment? reusable;
    var rotated = false;
    try {
      while (_segments.isNotEmpty && _storedBytes + encodedLength > maxBytes) {
        final removed = _segments.first;
        if (identical(_appendSegment, removed)) await _closeAppend();
        if (generation != _generation) return;
        _segments.removeFirst();
        if (removed.count != 0) _published.removeFirst();
        if (removed.sentOrNotice.isNotEmpty) _visibleSegments.removeFirst();
        _discardCachedPagesBefore(removed.end);
        _storedBytes -= removed.bytes;
        if (needsSegment && reusable == null && removed.readers == 0) {
          reusable = removed;
          // 回收可能已排队，重用前先占住这条已移出索引的路径。
          removed.readers++;
        }
        _retired.add(removed);
        rotated = true;
      }
      if (rotated) {
        if (_retired.length > (reusable == null ? 0 : 1)) await _cleanRetired();
        if (!truncated && generation == _generation) {
          truncated = true;
          changed();
        }
        if (generation != _generation) return;
        if (reusable != null) _retired.remove(reusable);
      }
    } finally {
      if (reusable != null) reusable.readers--;
    }
    var segment = _segments.isEmpty ? null : _segments.last;
    if (segment == null ||
        segment.sealed ||
        segment.bytes + encodedLength > segmentBytes) {
      segment = _Segment(
        reusable?.file ?? File(path.join(folder.path, '${_serial++}.bin')),
        _next,
      );
      _segments.add(segment);
    }
    try {
      if (!identical(_appendSegment, segment)) {
        await _closeAppend();
        _appendHandle = await segment.file.open(
          mode: reusable == null ? FileMode.append : FileMode.write,
        );
        _appendSegment = segment;
      }
      final handle = _appendHandle!;
      await handle.writeFrom(contents.bytes);
      if (payload != null) await handle.writeFrom(payload);
    } catch (_) {
      // 文件系统可能已接受本批的一部分，恢复前回退到已知边界。
      try {
        await _closeAppend();
        final file = await segment.file.open(mode: FileMode.append);
        try {
          await file.truncate(segment.bytes);
        } finally {
          await file.close();
        }
      } on FileSystemException {
        // 回退失败时封存本段，后续批次写入新文件。
        segment.sealed = true;
      }
      rethrow;
    }
    if (segment.count == 0) _published.addLast(segment);
    final base = segment.bytes;
    for (var i = 0; i < batch.length; i++) {
      final record = batch[i];
      if (record.textPrefix.isNotEmpty) {
        segment.prefixes[segment.count] = record.textPrefix;
      }
      segment.ends.add(base + contents.ends[i]);
      segment.sequences.add(record.sequence);
      if (record.sent || record.packet == null) {
        if (segment.sentOrNotice.isEmpty) _visibleSegments.addLast(segment);
        segment.sentOrNotice.add(record.sequence);
      }
    }
    _storedBytes += encodedLength;
    _next += batch.length;
    changed();
  }

  Future<void> _closeAppend() async {
    final handle = _appendHandle;
    _appendHandle = null;
    _appendSegment = null;
    await handle?.close();
  }

  void _scheduleAppendIdle() {
    if (_closed || _appendHandle == null) return;
    final generation = _generation;
    _appendIdle = Timer(const Duration(milliseconds: 750), () {
      _appendIdle = null;
      if (_writing || _closed || generation != _generation) return;
      unawaited(
        _serialize(() async {
          if (_writing || _closed || generation != _generation) return;
          try {
            await _closeAppend();
          } on FileSystemException catch (failure) {
            if (generation != _generation) return;
            error = '关闭历史写入文件失败：$failure';
            changed();
          }
        }),
      );
    });
  }

  Future<void> recover() async {
    if (_closed) return;
    error = null;
    changed();
    await flush();
  }

  Future<SessionHistoryPage?> read({
    int? before,
    int? from,
    int limit = 160,
  }) async {
    await flush();
    if (_closed || _clearing != 0 || _published.isEmpty) return null;
    final first = _published.first.start;
    final end = (before ?? (from == null ? _next : from + limit)).clamp(
      first,
      _next,
    );
    final start = (from ?? end - limit).clamp(first, end);
    if (start >= end) return null;
    final slices = <_HistorySlice>[];
    final firstSegment = _findSegment(
      _published,
      (segment) => segment.end <= start,
    );
    for (var index = firstSegment; index < _published.length; index++) {
      final segment = _published.elementAt(index);
      if (segment.start >= end) break;
      slices.add(
        _slice(
          segment,
          (start - segment.start).clamp(0, segment.count),
          (end - segment.start).clamp(0, segment.count),
        ),
      );
    }
    return SessionHistoryPage(start, end, await _readSlices(slices));
  }

  int _findSegment(
    ListQueue<_Segment> segments,
    bool Function(_Segment) precedes,
  ) {
    var left = 0, right = segments.length;
    while (left < right) {
      final middle = (left + right) ~/ 2;
      if (precedes(segments.elementAt(middle))) {
        left = middle + 1;
      } else {
        right = middle;
      }
    }
    return left;
  }

  /// 在已发布的记录中查找发送或缺口，跳过纯接收分段，无需读取文件。
  int? firstSentOrNoticeAtOrAfter(int sequence) {
    if (_closed || _clearing != 0) return null;
    final first = _findSegment(
      _visibleSegments,
      (segment) => segment.sentOrNotice.last < sequence,
    );
    if (first == _visibleSegments.length) return null;
    final candidates = _visibleSegments.elementAt(first).sentOrNotice;
    return candidates[_Segment._boundary(candidates, sequence)];
  }

  int? _lastSentOrNoticeBefore(int? sequence) {
    if (sequence == null) return _visibleSegments.lastOrNull?.sentOrNotice.last;
    final index =
        _findSegment(
          _visibleSegments,
          (segment) => segment.sentOrNotice.first < sequence,
        ) -
        1;
    if (index < 0) return null;
    final candidates = _visibleSegments.elementAt(index).sentOrNotice;
    return candidates[_Segment._boundary(candidates, sequence) - 1];
  }

  _HistorySlice _slice(_Segment segment, int from, int to) => (
    segment: segment,
    from: from,
    to: to,
    start: segment.offset(from),
    end: segment.offset(to),
  );

  _PageRead _pageRead(_HistorySlice slice) => (
    path: slice.segment.file.path,
    offset: slice.start,
    length: slice.end - slice.start,
    count: slice.to - slice.from,
    connectionId: connectionId,
  );

  /// 只读取调用时已经发布的完整记录，写入队列独立推进。
  Future<SessionHistoryCursorPage> readPage({
    int? before,
    int? after,
    int limit = 160,
    int byteLimit = 512 * 1024,
    bool skipReceiveEdge = false,
  }) async {
    assert(before == null || after == null);
    assert(limit > 0 && byteLimit > 0);
    if (_closed || _clearing != 0) {
      return const SessionHistoryCursorPage([], null);
    }
    final oldest = oldestPublishedSequence;
    final forward = after != null;
    if (skipReceiveEdge) {
      // 只跳过游标旁不可见的连续接收记录，命中后按普通页读取。
      if (after case final cursor?) {
        final next = cursor >= publishedSequence
            ? null
            : firstSentOrNoticeAtOrAfter(cursor + 1);
        if (next == null) return SessionHistoryCursorPage([], oldest);
        after = next - 1;
      } else {
        final previous = _lastSentOrNoticeBefore(before);
        if (previous == null) return SessionHistoryCursorPage([], oldest);
        before = previous + 1;
      }
    }
    final firstSegment = forward
        ? _findSegment(
            _published,
            (segment) => segment.sequences.last <= after!,
          )
        : before == null
        ? _published.length - 1
        : _findSegment(
                _published,
                (segment) => segment.sequences.first < before!,
              ) -
              1;
    final slices = <_HistorySlice>[];
    var count = 0;
    var bytes = 0;
    for (
      var index = firstSegment;
      index >= 0 && index < _published.length;
      index += forward ? 1 : -1
    ) {
      final segment = _published.elementAt(index);
      final from = after != null && index == firstSegment
          ? _Segment._boundary(segment.sequences, after, after: true)
          : 0;
      final to = before != null && index == firstSegment
          ? _Segment._boundary(segment.sequences, before)
          : segment.count;
      final span = to - from;
      final edge = forward ? from : to;
      final requested = min(span, limit - count);
      var take = segment.fitPage(edge, requested, byteLimit - bytes, forward);
      if (take == 0 && span > 0 && count == 0) take = 1;
      if (take > 0) {
        final start = forward ? from : to - take;
        final end = forward ? from + take : to;
        final slice = _slice(segment, start, end);
        slices.add(slice);
        bytes += slice.end - slice.start;
        count += take;
      }
      if (count == limit || bytes >= byteLimit || take < span) break;
    }
    return SessionHistoryCursorPage(
      await _readSlices(slices, reverse: !forward),
      oldest,
    );
  }

  Future<List<SessionRecord>> _readSlices(
    List<_HistorySlice> slices, {
    bool reverse = false,
  }) async {
    if (slices.isEmpty) return [];
    final first = reverse ? slices.last : slices.first;
    final last = reverse ? slices.first : slices.last;
    final start = first.segment.start + first.from;
    final key = (start, last.segment.start + last.to);
    final cached = _cachedPages.remove(key);
    if (cached != null) {
      _cachedPages[key] = cached;
      return List.of(cached.records);
    }
    if (_pendingPages[key] case final pending?) {
      return List.of(await pending);
    }
    if (_readCachedRange(key.$1, key.$2) case final records?) return records;
    final requested = reverse ? slices.reversed.toList() : slices;
    final generation = _generation;
    for (final entry in _pendingPages.entries) {
      final range = entry.key;
      if (range.$1 <= key.$1 && range.$2 >= key.$2) {
        final offset = key.$1 - range.$1;
        final end = key.$2 - range.$1;
        final parent = entry.value;
        return _withSlices(requested, (snapshot) async {
          final List<SessionRecord> records;
          try {
            records = await parent;
          } catch (_) {
            // 父页可能在子区间之外读取失败。保留原快照并独立重读子页。
            return _loadSlices(snapshot, key, generation);
          }
          return records.sublist(offset, end);
        });
      }
    }
    final pending = _loadSlices(requested, key, generation);
    _pendingPages[key] = pending;
    try {
      return List.of(await pending);
    } finally {
      if (identical(_pendingPages[key], pending)) _pendingPages.remove(key);
    }
  }

  List<SessionRecord>? _readCachedRange(int start, int end) {
    if (_cachedPages.isEmpty) return null;
    // 先确认整段连续命中，再复制结果，避免为部分命中重复拼接。
    List<(int, int)>? pages;
    for (var cursor = start; cursor < end;) {
      (int, int)? best;
      var furthest = cursor;
      for (final key in _cachedPages.keys) {
        if (key.$1 <= cursor && key.$2 > furthest) {
          best = key;
          furthest = key.$2;
          if (furthest >= end) break;
        }
      }
      if (best == null) return null;
      if (cursor == start && furthest >= end) {
        final page = _cachedPages.remove(best)!;
        _cachedPages[best] = page;
        return page.records.sublist(start - best.$1, end - best.$1);
      }
      (pages ??= []).add(best);
      cursor = furthest;
    }

    final records = List<SessionRecord>.filled(
      end - start,
      _cachedPages[pages!.first]!.records.first,
      growable: true,
    );
    var cursor = start;
    for (final key in pages) {
      final page = _cachedPages.remove(key)!;
      _cachedPages[key] = page;
      final stop = min(end, key.$2);
      records.setRange(
        cursor - start,
        stop - start,
        page.records,
        cursor - key.$1,
      );
      cursor = stop;
    }
    return records;
  }

  int _encodedRangeBytes(List<_HistorySlice> slices, int start, int end) {
    var bytes = 0;
    for (final slice in slices) {
      final segment = slice.segment;
      final from = max(slice.from, start - segment.start);
      final to = min(slice.to, end - segment.start);
      if (from < to) bytes += segment.offset(to) - segment.offset(from);
    }
    return bytes;
  }

  List<_CachedSpan> _selectCachedOverlap(
    List<_HistorySlice> requested,
    int start,
    int end,
  ) {
    MapEntry<(int, int), _CachedPage>? firstPage;
    List<MapEntry<(int, int), _CachedPage>>? pages;
    for (final entry in _cachedPages.entries) {
      if (entry.key.$1 >= end || entry.key.$2 <= start) continue;
      final first = firstPage;
      if (first == null) {
        firstPage = entry;
      } else {
        (pages ??= [first]).add(entry);
      }
    }
    if (pages == null) {
      if (firstPage == null) return const [];
      final from = max(start, firstPage.key.$1);
      final to = min(end, firstPage.key.$2);
      if ((to - from) * 2 < end - start) {
        // 少数大报文可占大半页，节省的字节还要能抵消补读两端的开销。
        final bytes = _encodedRangeBytes(requested, from, to);
        if (bytes < _minimumByteReuse ||
            bytes * 2 < _encodedRangeBytes(requested, start, end)) {
          return const [];
        }
      }
      return [
        (
          from: from,
          to: to,
          pageStart: firstPage.key.$1,
          records: firstPage.value.records,
        ),
      ];
    }
    pages.sort((a, b) => a.key.$1.compareTo(b.key.$1));

    final spans = <_CachedSpan>[];
    var last = start;
    var covered = 0;
    for (final entry in pages) {
      final from = max(last, entry.key.$1);
      final to = min(end, entry.key.$2);
      if (from >= to) continue;
      spans.add((
        from: from,
        to: to,
        pageStart: entry.key.$1,
        records: entry.value.records,
      ));
      covered += to - from;
      last = to;
    }
    if (covered * 2 >= end - start) return spans;

    final savedBytes = spans.fold<int>(
      0,
      (total, span) =>
          total + _encodedRangeBytes(requested, span.from, span.to),
    );
    return savedBytes >= _minimumByteReuse &&
            savedBytes * 2 >= _encodedRangeBytes(requested, start, end)
        ? spans
        : const [];
  }

  Future<List<SessionRecord>> _loadSlices(
    List<_HistorySlice> requested,
    (int, int) key,
    int generation,
  ) async {
    final start = key.$1;
    // 合计命中足够的记录或字节时，只补读缓存区间之间的缺口。
    final overlaps = generation == _generation
        ? _selectCachedOverlap(requested, start, key.$2)
        : const <_CachedSpan>[];
    var missing = requested;
    if (overlaps.isNotEmpty) {
      missing = [];
      for (final slice in requested) {
        final base = slice.segment.start;
        var cursor = slice.from;
        for (final span in overlaps) {
          final from = span.from - base, to = span.to - base;
          if (to <= cursor) continue;
          if (from >= slice.to) break;
          if (cursor < from) missing.add(_slice(slice.segment, cursor, from));
          cursor = min(slice.to, to);
        }
        if (cursor == slice.from) {
          missing.add(slice);
        } else if (cursor < slice.to) {
          missing.add(_slice(slice.segment, cursor, slice.to));
        }
      }
    }

    var records = missing.isEmpty
        ? <SessionRecord>[]
        : await _withSlices(missing, (snapshot) async {
            // 一页只发起一次后台任务，跨分段时也不在界面 isolate 上解码。
            final records = await _pageReader.read(
              snapshot.map(_pageRead).toList(),
            );
            var offset = 0;
            for (final slice in snapshot) {
              final count = slice.to - slice.from;
              final prefixes = slice.segment.prefixes;
              if (prefixes.isNotEmpty) {
                for (var index = 0; index < count; index++) {
                  final prefix = prefixes[slice.from + index];
                  if (prefix != null) {
                    records[offset + index] = records[offset + index]
                        ._withPrefix(prefix);
                  }
                }
              }
              offset += count;
            }
            return records;
          });
    if (overlaps.isNotEmpty) {
      final merged = List<SessionRecord>.filled(
        key.$2 - start,
        overlaps.first.records.first,
        growable: true,
      );
      var cursor = 0, missingOffset = 0;
      for (final span in overlaps) {
        final from = span.from - start, to = span.to - start;
        if (cursor < from) {
          merged.setRange(cursor, from, records, missingOffset);
          missingOffset += from - cursor;
        }
        merged.setRange(from, to, span.records, span.from - span.pageStart);
        cursor = to;
      }
      merged.setRange(cursor, merged.length, records, missingOffset);
      records = merged;
    }
    if (generation == _generation &&
        _published.isNotEmpty &&
        start >= _published.first.start) {
      var cost = 0;
      for (final record in records) {
        cost += record.cost;
      }
      if (cost <= _pageCacheByteLimit && !_cachedPages.containsKey(key)) {
        while (_cachedPages.length >= _pageCacheLimit ||
            _cachedPageBytes + cost > _pageCacheByteLimit) {
          _removeCachedPage(_cachedPages.keys.first);
        }
        _cachedPages[key] = (records: records, cost: cost);
        _cachedPageBytes += cost;
      }
    }
    return records;
  }

  void _removeCachedPage((int, int) key) {
    _cachedPageBytes -= _cachedPages.remove(key)!.cost;
  }

  void _discardCachedPagesBefore(int position) {
    final discarded = _cachedPages.keys.where((key) => key.$1 < position);
    for (final key in discarded.toList()) {
      _removeCachedPage(key);
    }
  }

  Future<T> _withSlices<T>(
    List<_HistorySlice> snapshot,
    Future<T> Function(List<_HistorySlice>) action,
  ) async {
    for (final slice in snapshot) {
      slice.segment.readers++;
    }
    try {
      return await action(snapshot);
    } finally {
      if (_releaseSlices(snapshot)) await _cleanRetired();
    }
  }

  Future<List<SessionRecord>> readOlderThan(
    int? sequence, {
    int limit = 160,
  }) async {
    await flush();
    return (await readPage(
      before: sequence,
      limit: limit,
      byteLimit: maxBytes,
    )).records;
  }

  Future<void> exportTo(File destination) async {
    if (_exporting) throw StateError('会话历史正在导出');
    _exporting = true;
    final generation = _generation;
    try {
      await flush();
      if (_closed || _generation != generation || _clearing != 0) {
        throw StateError('会话历史不可导出');
      }
      final remaining = ListQueue<_HistorySlice>.of(
        _published.map((segment) => _slice(segment, 0, segment.count)),
      );
      for (final slice in remaining) {
        slice.segment.readers++;
      }
      try {
        final output = destination.openWrite();
        try {
          await output.addStream(_exportJsonLines(remaining));
        } finally {
          await output.close();
        }
      } finally {
        if (_releaseSlices(remaining)) await _cleanRetired();
      }
    } finally {
      _exporting = false;
    }
  }

  Stream<Uint8List> _exportJsonLines(
    ListQueue<_HistorySlice> remaining,
  ) async* {
    while (remaining.isNotEmpty) {
      final first = remaining.first;
      final second = remaining.length > 1 ? remaining.elementAt(1) : null;
      final batch =
          second != null &&
              first.end - first.start + second.end - second.start <= 512 * 1024
          // 两项都结束才交还分段。即使其中一个解码失败，另一个仍可能正在读。
          ? await Future.wait([
              _exportInBackground(_pageRead(first)),
              _exportInBackground(_pageRead(second)),
            ])
          : [await _exportInBackground(_pageRead(first))];
      for (final encoded in batch) {
        if (_releaseSlice(remaining.removeFirst())) await _cleanRetired();
        yield encoded;
      }
    }
  }

  bool _releaseSlice(_HistorySlice slice) {
    final segment = slice.segment;
    return --segment.readers == 0 && _retired.contains(segment);
  }

  bool _releaseSlices(Iterable<_HistorySlice> slices) {
    var releasedRetired = false;
    for (final slice in slices) {
      if (_releaseSlice(slice)) releasedRetired = true;
    }
    // 健康页无需加入其他分段的清理队列。
    return releasedRetired;
  }

  Future<void> _deleteRetired(FileSystemEntity entity) async {
    try {
      await entity.delete();
    } on PathNotFoundException {
      // 对已不存在的路径，清理已完成。
    }
  }

  Future<void> _cleanRetired() {
    final result = _cleanup.then((_) async {
      for (final segment in _retired.toList()) {
        if (segment.readers == 0 && _retired.contains(segment)) {
          await _deleteRetired(segment.file);
          _retired.remove(segment);
        }
      }
      for (final folder in _retiredFolders.toList()) {
        if (_retired.any(
          (segment) => segment.file.parent.path == folder.path,
        )) {
          continue;
        }
        await _deleteRetired(folder);
        _retiredFolders.remove(folder);
      }
    });
    _cleanup = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> clear() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _flushSoonScheduled = false;
    _cachedPages.clear();
    _pendingPages.clear();
    _cachedPageBytes = 0;
    _appendIdle?.cancel();
    _appendIdle = null;
    _clearing++;
    _pendingBytes -= _pending.fold<int>(0, (sum, record) => sum + record.cost);
    _pending.clear();
    _carry.clear();
    _diskGapSequence = 0;
    _lost = 0;
    truncated = false;
    error = null;
    changed();
    return _serialize(() async {
      try {
        try {
          await _closeAppend();
        } finally {
          if (_folder case final folder?) _retiredFolders.add(folder);
          _folder = null;
          _retired.addAll(_segments);
          _segments.clear();
          _published.clear();
          _visibleSegments.clear();
          _storedBytes = 0;
          _next = 0;
          await _cleanRetired();
        }
      } finally {
        _clearing--;
        changed();
        _schedule();
      }
    });
  }

  Future<void> close() {
    _closed = true;
    _pageReader.close();
    return clear();
  }
}
