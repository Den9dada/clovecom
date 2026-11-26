import 'dart:math' as math;

import '../src/application/session_history.dart';

/// 保留按序号排列、受条数和字节限制的会话查看窗口。
class SessionHistoryWindow {
  static const _recordLimit = 800;
  static const _byteLimit = 4 * 1024 * 1024;

  List<SessionRecord> _records = const [];
  int? _bytes;

  List<SessionRecord> get records => _records;

  void replace(List<SessionRecord> records) {
    _records = records;
    _bytes = null;
  }

  void extend(
    List<SessionRecord> page, {
    required bool older,
    required int? anchorSequence,
  }) {
    final leading = older ? page : _records;
    final trailing = older ? _records : page;
    final pivot = leading.length;
    final length = pivot + trailing.length;
    SessionRecord at(int index) =>
        index < pivot ? leading[index] : trailing[index - pivot];

    var bytes = (_bytes ?? _cost(_records)) + _cost(page);
    var first = 0, end = length;
    // 优先淘汰滚动方向相反的一端。临界记录是可见锚点时，改从另一端裁剪。
    while (end - first > 1 &&
        (end - first > _recordLimit || bytes > _byteLimit)) {
      final trimFront = older
          ? at(end - 1).sequence == anchorSequence
          : at(first).sequence != anchorSequence;
      bytes -= trimFront ? at(first++).cost : at(--end).cost;
    }

    if (first == 0 && end == pivot) {
      _records = leading;
    } else if (first == pivot && end == length) {
      _records = trailing;
    } else {
      // 分别从两侧复制保留区间，避免构造随后会被丢弃的完整拼接列表。
      final kept = List<SessionRecord>.filled(end - first, at(first));
      if (first < pivot) {
        kept.setRange(0, math.min(end, pivot) - first, leading, first);
      }
      if (end > pivot) {
        final start = math.max(first, pivot);
        kept.setRange(start - first, end - first, trailing, start - pivot);
      }
      _records = kept;
    }
    _bytes = bytes;
  }

  bool containsSequence(int sequence) {
    var first = 0, end = _records.length;
    while (first < end) {
      final middle = (first + end) ~/ 2;
      final candidate = _records[middle].sequence;
      if (candidate == sequence) return true;
      if (candidate < sequence) {
        first = middle + 1;
      } else {
        end = middle;
      }
    }
    return false;
  }

  int _cost(List<SessionRecord> records) {
    var bytes = 0;
    for (final record in records) {
      bytes += record.cost;
    }
    return bytes;
  }
}
