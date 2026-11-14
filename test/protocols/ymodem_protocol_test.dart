import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:clovecom/protocols/transfer_protocol.dart';
import 'package:clovecom/protocols/ymodem_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List packet(int sequence, List<int> content) {
  final payload = List<int>.filled(128, 0x1A);
  payload.setRange(0, content.length, content);
  var crc = 0;
  for (final byte in payload) {
    crc ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return Uint8List.fromList([
    1,
    sequence,
    255 - sequence,
    ...payload,
    crc >> 8,
    crc & 255,
  ]);
}

class Peer {
  final Queue<Uint8List> incoming = Queue();
  final List<Uint8List> writes = [];
  final List<String> errors = [];
  final List<int> completed = [];
  bool cancelled = false;
  bool writeSucceeds = true;
  void enqueue(List<int> data, {int fragmentSize = 99999}) {
    for (var i = 0; i < data.length; i += fragmentSize) {
      incoming.add(
        Uint8List.fromList(
          data.sublist(i, (i + fragmentSize).clamp(0, data.length)),
        ),
      );
    }
  }

  TransferCallbacks callbacks() => TransferCallbacks(
    onProgress: (_) {},
    onLog: (_) {},
    onError: errors.add,
    onComplete: completed.add,
    isCancelled: () => cancelled,
    onWrite: (data, timeout) {
      writes.add(Uint8List.fromList(data));
      return writeSucceeds;
    },
    onWaitByte: (timeout) async {
      if (incoming.isEmpty) {
        cancelled = true;
        return null;
      }
      final bytes = incoming.removeFirst();
      if (bytes.length > 1) incoming.addFirst(Uint8List.sublistView(bytes, 1));
      return bytes.first;
    },
    onWaitData: (timeout) async {
      if (incoming.isEmpty) {
        cancelled = true;
        return null;
      }
      return incoming.removeFirst();
    },
  );
}

void main() {
  late Directory temp;
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('clovecom_protocol_'),
  );
  tearDown(() async => temp.delete(recursive: true));
  List<int> stream({int size = 3}) => [
    ...packet(0, [...utf8.encode('test.bin'), 0, ...ascii.encode('$size'), 0]),
    ...packet(1, [1, 0xFF, 3]),
    4,
    4,
    ...packet(0, List.filled(128, 0)),
  ];
  for (final fragmentSize in [1, 17, 99999]) {
    test('Ymodem 接收拆包或粘包，$fragmentSize 字节分片', () async {
      final peer = Peer()..enqueue(stream(), fragmentSize: fragmentSize);
      final path = '${temp.path}/out.bin';
      await YmodemProtocol().receive(
        savePath: path,
        callbacks: peer.callbacks(),
      );
      expect(peer.errors, isEmpty);
      expect(peer.completed, [3]);
      expect(await File(path).readAsBytes(), [1, 0xFF, 3]);
    });
  }
  test('CRC 错误后重传，重复数据块不会重复写入', () async {
    final corrupt = packet(1, [1, 0xFF, 3]);
    corrupt[3] ^= 1;
    final peer = Peer()
      ..enqueue([
        ...packet(0, [...ascii.encode('test.bin'), 0, 0x33, 0]),
        ...corrupt,
        ...packet(1, [1, 0xFF, 3]),
        ...packet(1, [1, 0xFF, 3]),
        4,
        4,
        ...packet(0, List.filled(128, 0)),
      ]);
    final path = '${temp.path}/out.bin';
    await YmodemProtocol().receive(savePath: path, callbacks: peer.callbacks());
    expect(peer.errors, isEmpty);
    expect(peer.completed, [3]);
    expect(await File(path).readAsBytes(), [1, 0xFF, 3]);
    expect(
      peer.writes.any((bytes) => bytes.length == 1 && bytes.first == 0x15),
      isTrue,
    );
  });
  test('取消、发送端中止和无效结束块均不报告成功', () async {
    for (final bytes in <List<int>>[
      packet(0, [...ascii.encode('test.bin'), 0, 0x33, 0]),
      [0x18],
      [
        ...stream().take(133 + 133 + 2),
        ...packet(0, [1]),
      ],
    ]) {
      final peer = Peer()..enqueue(bytes);
      await YmodemProtocol().receive(
        savePath: '${temp.path}/out.bin',
        callbacks: peer.callbacks(),
      );
      expect(peer.completed, isEmpty);
      expect(peer.cancelled || peer.errors.isNotEmpty, isTrue);
    }
  });
  test('声明大小超过已收数据时拒绝截断文件', () async {
    final peer = Peer()..enqueue(stream(size: 300));
    await YmodemProtocol().receive(
      savePath: '${temp.path}/out.bin',
      callbacks: peer.callbacks(),
    );
    expect(peer.completed, isEmpty);
    expect(peer.errors.single, contains('截断'));
  });
  test('接收控制字节写入失败时结束并关闭文件', () async {
    final peer = Peer()..writeSucceeds = false;
    final path = '${temp.path}/out.bin';
    await YmodemProtocol().receive(savePath: path, callbacks: peer.callbacks());
    expect(peer.completed, isEmpty);
    expect(peer.errors.single, contains('写入失败'));
    await File(path).delete();
  });
  test('发送完成需要握手和结束块确认，NAK 可重传', () async {
    final peer = Peer()..enqueue([0x43, 0x15, 6, 0x43, 6, 0x43, 0x15, 6, 6]);
    await YmodemProtocol().send(
      Uint8List.fromList([1, 2, 3]),
      packetSize: 1024,
      intervalMs: 1,
      callbacks: peer.callbacks(),
    );
    expect(peer.errors, isEmpty);
    expect(peer.completed, [3]);
    expect(peer.writes.where((bytes) => bytes.length == 133), hasLength(3));
  });
  test('发送短写失败不报告进度完成', () async {
    final peer = Peer()
      ..enqueue([0x43])
      ..writeSucceeds = false;
    await YmodemProtocol().send(
      Uint8List.fromList([1]),
      packetSize: 1024,
      intervalMs: 1,
      callbacks: peer.callbacks(),
    );
    expect(peer.completed, isEmpty);
    expect(peer.errors.single, contains('写入失败'));
  });
}
