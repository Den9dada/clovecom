import 'dart:typed_data';

import 'package:clovecom/src/application/session_history.dart';
import 'package:clovecom/src/io/recording.dart';
import 'package:clovecom/widgets/communication_history_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<SessionRecord> records(int first, int count, {int payloadBytes = 0}) {
    final data = TransportInput(Uint8List(payloadBytes));
    final stamp = DateTime.utc(2026);
    return [
      for (var sequence = first; sequence < first + count; sequence++)
        SessionRecord(
          RawPacket.fromInput(
            data,
            connectionId: 'a',
            receivedAt: stamp,
            epoch: 1,
            sequence: sequence,
          ),
          sequence: sequence,
        ),
    ];
  }

  test('跨页按滚动方向裁剪，锚点在临界位置时保留原窗口', () {
    final retained = records(101, 800);
    final window = SessionHistoryWindow()..replace(retained);
    final older = records(1, 100);
    window.extend(older, older: true, anchorSequence: 900);
    expect(window.records, same(retained));
    window.extend(older, older: true, anchorSequence: 120);
    expect(window.records.length, 800);
    expect(window.records.first, same(older.first));
    expect(window.records.last.sequence, 800);
    expect(window.containsSequence(120), isTrue);
    expect(window.containsSequence(900), isFalse);

    window.replace(retained);
    final newer = records(901, 100);
    window.extend(newer, older: false, anchorSequence: 101);
    expect(window.records, same(retained));
    window.extend(newer, older: false, anchorSequence: 400);
    expect(window.records.first.sequence, 201);
    expect(window.records.last, same(newer.last));
  });

  test('连续跨页的字节预算准确，并保留超过预算的单条锚点', () {
    const byteLimit = 4 * 1024 * 1024;
    const packetSize = 10000;
    final first = records(1, 400, payloadBytes: packetSize);
    final window = SessionHistoryWindow()..replace(first);
    final second = records(401, 100, payloadBytes: packetSize);
    window.extend(second, older: false, anchorSequence: 350);
    final expectedLength = byteLimit ~/ second.first.cost;
    expect(window.records.length, expectedLength);
    expect(window.records.first.sequence, 501 - expectedLength);
    expect(window.records.last.sequence, 500);

    final third = records(501, 100, payloadBytes: packetSize);
    window.extend(third, older: false, anchorSequence: 480);
    expect(window.records.length, expectedLength);
    expect(window.records.first.sequence, 601 - expectedLength);
    expect(window.records.last.sequence, 600);

    final oversized = records(601, 1, payloadBytes: byteLimit + 1);
    window.extend(oversized, older: false, anchorSequence: 601);
    expect(window.records.single, same(oversized.single));
  });
}
