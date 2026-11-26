import 'dart:convert';
import 'dart:typed_data';

import 'package:clovecom/src/application/session_history.dart';
import 'package:clovecom/src/io/recording.dart';
import 'package:clovecom/widgets/communication_session_rows.dart';
import 'package:flutter_test/flutter_test.dart';

SessionRecord _record(int sequence, List<int> bytes, {bool sent = false}) =>
    SessionRecord(
      RawPacket(connectionId: 'a', receivedAt: DateTime(2026), bytes: bytes),
      sequence: sequence,
      sent: sent,
    );

void main() {
  test('重复发送复用文本时仍按方向、对端和前缀显示', () {
    final rows = SessionDisplayRows();
    final input = TransportInput([0x41, 0x42]);
    final packet = RawPacket.fromInput(
      input,
      connectionId: 'a',
      receivedAt: DateTime.utc(2026),
      epoch: 1,
      sequence: 0,
    );
    SessionDisplayRow sent(int sequence) => SessionDisplayRow(
      SessionRecord(packet, sequence: sequence, sent: true),
      0,
    );
    final first = sent(1);
    final second = sent(2);
    expect(rows.textFor(first, hex: false), 'AB');
    expect(
      rows.textFor(second, hex: false),
      same(rows.textFor(first, hex: false)),
    );
    expect(rows.textFor(second, hex: true), '41 42');
    expect(rows.textFor(first, hex: true), '41 42');

    final peerPacket = RawPacket.fromInput(
      input,
      connectionId: 'a',
      receivedAt: DateTime.utc(2026),
      epoch: 1,
      sequence: 0,
      peer: '对端',
    );
    final peer = SessionDisplayRow(SessionRecord(peerPacket, sent: true), 0);
    final prefixed = SessionDisplayRow(
      SessionRecord(packet, sent: true, textPrefix: const [0x43]),
      0,
    );
    expect(rows.textFor(peer, hex: false), '对端 AB');
    expect(rows.textFor(prefixed, hex: false), 'CAB');

    final incomplete = RawPacket(
      connectionId: 'a',
      receivedAt: DateTime.utc(2026),
      bytes: [0xe4],
    );
    final rx = SessionDisplayRow(SessionRecord(incomplete), 0);
    final tx = SessionDisplayRow(SessionRecord(incomplete, sent: true), 0);
    expect(rows.textFor(tx, hex: false), '�');
    expect(rows.textFor(rx, hex: false), isEmpty);
    expect(rows.textFor(second, hex: false), 'AB');
  });

  test('同一不可变长报文按分行复用 HEX 和文本，区分偏移和新草稿', () {
    final rows = SessionDisplayRows();
    RawPacket packet(int last) => RawPacket.fromInput(
      TransportInput.takeOwned(
        Uint8List(2051)
          ..[1023] = 0xe4
          ..[1024] = 0xb8
          ..[1025] = 0xad
          ..[2050] = last,
      ),
      connectionId: 'a',
      receivedAt: DateTime.utc(2026),
      epoch: 1,
      sequence: 0,
    );
    final first = packet(0x41);
    SessionDisplayRow row(RawPacket value, int sequence, int offset) =>
        SessionDisplayRow(
          SessionRecord(value, sequence: sequence, sent: true),
          offset,
        );
    final middle = row(first, 1, 1024);
    final tail = row(first, 1, 2048);
    final middleText = rows.textFor(middle, hex: false);
    expect(middleText.startsWith('中'), isTrue);
    expect(rows.textFor(row(first, 2, 1024), hex: false), same(middleText));
    final middleHex = rows.textFor(middle, hex: true);
    expect(middleHex.startsWith('B8 AD '), isTrue);
    expect(rows.textFor(row(first, 2, 1024), hex: true), same(middleHex));
    final tailHex = rows.textFor(tail, hex: true);
    expect(tailHex, '00 00 41');
    expect(rows.textFor(row(first, 2, 2048), hex: true), same(tailHex));
    expect(rows.textFor(row(packet(0x42), 3, 2048), hex: true), '00 00 42');
  });

  test('HEX 批量格式化保留边界字节、空格及奇数尾部', () {
    String expected(List<int> bytes) => bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    for (final length in [0, 1, 31, 32, 33, 1023, 1024, 1025, 1057]) {
      final bytes = Uint8List.fromList(
        List.generate(length, (index) => (index * 137 + 0xe7) & 0xff),
      );
      final record = _record(1, bytes);
      expect(
        SessionDisplayRow(record, 0).text(hex: true),
        expected(bytes.take(1024).toList()),
      );
      if (length > 1024) {
        expect(
          SessionDisplayRow(record, 1024).text(hex: true),
          expected(bytes.sublist(1024)),
        );
      }
    }
  });

  for (final (length, offset) in [(256, 0), (2048, 1024)]) {
    test('HEX 跨记录复用前核对全部字节（报文长度 $length）', () {
      final rows = SessionDisplayRows();
      SessionDisplayRow row(int sequence, int byte, {bool sent = false}) {
        final data = Uint8List(length)..[offset + 73] = byte;
        return SessionDisplayRow(_record(sequence, data, sent: sent), offset);
      }

      final first = row(1, 0x41);
      final second = row(2, 0x41);
      expect(rows.textFor(first, hex: true), first.text(hex: true));
      final repeated = rows.textFor(second, hex: true);
      expect(
        rows.textFor(row(3, 0x41, sent: offset != 0), hex: true),
        same(repeated),
      );

      final changed = row(4, 0x42);
      final actual = rows.textFor(changed, hex: true);
      expect(actual, changed.text(hex: true));
      expect(actual, isNot(repeated));
      expect(actual, contains(' 42 '));
      expect(rows.textFor(row(5, 0x42), hex: true), same(actual));
    });
  }

  test('时间戳使用本地时区，跨秒、倒序和负时间戳的毫秒准确', () {
    final labels = SessionTimestampLabel();
    final start = DateTime.utc(2026, 12, 31, 23, 59, 59);
    final samples = [
      start,
      start.add(const Duration(milliseconds: 7)),
      start.add(const Duration(microseconds: 999999)),
      start.add(const Duration(seconds: 1)),
      start.add(const Duration(milliseconds: 32)).toLocal(),
      DateTime.fromMicrosecondsSinceEpoch(-1, isUtc: true),
      DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
    ];
    for (final value in samples) {
      final local = value.toLocal().toIso8601String().split('T').last;
      expect(
        labels.format(value, milliseconds: true),
        '[${local.substring(0, 12)}]',
      );
      expect(
        labels.format(value, milliseconds: false),
        '[${local.substring(0, 8)}]',
      );
    }
  });

  test('短包窗口滑动及同序号回读能定位并更新缓存', () {
    final first = _record(2, [0x31], sent: true);
    final original = _record(5, [0x32]);
    final notice = SessionRecord(null, sequence: 8, notice: '历史缺口');
    final last = _record(12, [0x33], sent: true);
    final rows = SessionDisplayRows()
      ..replace([first, original, notice], hideReceive: false);
    final cached = rows[1];
    expect(rows.length, 3);
    expect(rows.indexOf((5, 0)), 1);
    expect(rows.indexOf((5, 1024)), isNull);
    expect(rows.lowerBound((4, 0)), 1);
    expect(rows.lowerBound((5, 1)), 2);
    expect(rows.lowerBound((10, 0)), 3);

    rows.replace([original, notice, last], hideReceive: false);
    expect(rows.firstOrNull, same(cached));
    expect(rows.indexOf((2, 0)), isNull);
    final reloaded = _record(5, List.filled(1025, 0x41));
    rows.replace([reloaded, notice, last], hideReceive: false);
    expect(rows.firstOrNull, isNot(same(cached)));
    expect(rows.length, 4);
    expect(rows[1].text(hex: false), 'A');
    expect(rows.indexOf((5, 1024)), 1);
    expect(rows.lowerBound((5, 1025)), 2);

    rows.replace([reloaded, notice, last], hideReceive: true);
    expect(rows.length, 2);
    expect(rows.lowerBound((5, 1024)), 0);
    expect(rows.firstOrNull?.text(hex: false), '历史缺口');
    expect(rows.lastOrNull?.id, (12, 0));
  });

  test('跨行字符保持完整，流式和独立报文的尾部行为不变', () {
    final bytes = [...List.filled(1021, 0x41), ...utf8.encode('😀'), 0xe4];
    final rx = _record(1, bytes);
    final tx = _record(2, bytes, sent: true);
    expect(SessionDisplayRow(rx, 0).text(hex: false), 'A' * 1021);
    expect(SessionDisplayRow(rx, 1024).text(hex: false), '😀');
    expect(SessionDisplayRow(tx, 1024).text(hex: false), '😀�');
    expect(SessionDisplayRow(rx, 1024).text(hex: true), '80 E4');
    expect(SessionDisplayRow(_record(3, []), 0).text(hex: true), '');
    expect(
      SessionDisplayRow(_record(4, [0, 0xff, 0x100, -1]), 0).text(hex: true),
      '00 FF 100 -1',
    );
  });

  test('十六进制字节缓冲按行输出，保留对端标签和末行边界', () {
    final record = SessionRecord(
      RawPacket(
        connectionId: 'a',
        receivedAt: DateTime(2026),
        bytes: Uint8List(1025)
          ..[1023] = 0x80
          ..[1024] = 0xff,
        peer: '对端',
      ),
      sequence: 1,
    );
    final rows = SessionDisplayRows()..replace([record], hideReceive: false);
    expect(rows.length, 2);
    expect(rows[0].text(hex: true), '对端 ${'00 ' * 1023}80');
    expect(rows[1].text(hex: true), 'FF');
  });

  test('分页追加保留已有行缓存，过滤与分片仍可按原始序号定位', () {
    final first = _record(3, utf8.encode('中文'));
    final bytes = [...List.filled(1023, 0x41), ...utf8.encode('中')];
    final second = _record(5, bytes, sent: true);
    final rows = SessionDisplayRows()
      ..replace([first, second], hideReceive: false);
    final cached = rows[0];
    expect(rows.length, 3);
    expect(rows.indexOf((5, 1024)), 2);
    expect(rows[1].text(hex: false), 'A' * 1023);
    expect(rows[2].text(hex: false), '中');
    expect(rows[2].text(hex: true), 'B8 AD');
    final third = _record(9, [0xab], sent: true);
    rows.replace([first, second, third], hideReceive: false);
    expect(identical(rows[0], cached), isTrue);
    rows.replace([first, second, third], hideReceive: true);
    expect(rows.lowerBound((3, 0)), 0);
    expect(rows.firstOrNull!.id, (5, 0));
    expect(rows.lastOrNull!.text(hex: true), 'AB');
  });

  test('隐藏接收时复用可见行，保留缺口和新增发送并淘汰过期记录', () {
    final rx1 = _record(1, [1]);
    final tx2 = _record(2, [2], sent: true);
    final rx3 = _record(3, [3]);
    final rx4 = _record(4, [4]);
    final gap = SessionRecord(null, sequence: 5, notice: '历史缺口');
    final tx6 = _record(6, List.filled(1025, 0x41), sent: true);
    final rows = SessionDisplayRows();
    expect(
      rows.replace([rx1, tx2, rx3], hideReceive: true, liveTail: true),
      isTrue,
    );
    final cached = rows[0];

    expect(
      rows.replace([tx2, rx3, rx4], hideReceive: true, liveTail: true),
      isFalse,
    );
    expect(rows[0], same(cached));
    expect(
      rows.replace([rx3, rx4, gap, tx6], hideReceive: true, liveTail: true),
      isTrue,
    );
    expect(rows.length, 3);
    expect(rows.indexOf((2, 0)), isNull);
    expect(rows[0].text(hex: false), '历史缺口');
    expect(rows[2].id, (6, 1024));

    final rx7 = _record(7, [7]);
    final cachedTail = rows[2];
    expect(
      rows.replace([rx4, gap, tx6, rx7], hideReceive: true, liveTail: true),
      isFalse,
    );
    expect(rows[2], same(cachedTail));
  });

  test('实时窗口复用短记录索引，追加长记录后保留分片定位', () {
    final first = _record(1, [1]);
    final second = _record(2, [2]);
    final third = _record(3, [3]);
    final long = _record(4, List.filled(2050, 0x41));
    final rows = SessionDisplayRows()
      ..replace([first, second, third], hideReceive: false, liveTail: true);
    final cached = rows[1];

    rows.replace([second, third, long], hideReceive: false, liveTail: true);
    expect(rows.length, 5);
    expect(rows[0], same(cached));
    expect(rows.indexOf((4, 1024)), 3);
    expect(rows[4].id, (4, 2048));

    const visibleIds = [(2, 0), (3, 0), (4, 0), (4, 1024), (4, 2048)];
    for (final index in [0, 1, 2, 3, 4, 3, 2, 1, 0, 3, 0, 4]) {
      expect(rows[index].id, visibleIds[index]);
    }

    final fourth = _record(4, [4]);
    rows.replace([second, third, fourth], hideReceive: false);
    expect(rows.length, 3);
    expect(rows.indexOf((4, 1024)), isNull);

    final next = _record(5, List.filled(1025, 0x42));
    final sixth = _record(6, [0x43]);
    rows.replace([third, fourth, next], hideReceive: false, liveTail: true);
    expect(rows.indexOf((5, 1024)), 3);
    rows.replace([next, sixth], hideReceive: false, liveTail: true);
    expect(rows.length, 3);
    expect(rows[1].id, (5, 1024));
    expect(rows.lowerBound((6, 0)), 2);

    final seventh = _record(7, [0x44]);
    rows.replace([sixth, seventh], hideReceive: false, liveTail: true);
    expect(rows.hasSplitRecords, isFalse);
    expect(rows.length, 2);
    expect(rows.firstOrNull!.id, (6, 0));
    expect(rows.lastOrNull!.id, (7, 0));
  });
}
