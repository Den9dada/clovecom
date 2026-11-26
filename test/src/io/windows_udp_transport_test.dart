import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/byte_transport.dart';
import 'package:clovecom/src/io/interface_params.dart';
import 'package:clovecom/src/io/windows_udp_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真实回环保留空数据报的来源并继续接收后续数据报', () async {
    final receiver = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    addTearDown(receiver.close);
    final sender = await WindowsUdpTransport.open(
      UdpPrefs(
        nicKey: '127.0.0.1',
        unicastHost: '127.0.0.1',
        unicastPort: receiver.boundPort,
      ),
    );
    addTearDown(sender.close);
    final received = receiver.datagrams.take(2).toList();
    final chunks = receiver.chunks.take(2).toList();
    final adapter = NetworkCommunicationTransport(
      receiver,
      InterfaceProtocol.udp,
    );
    addTearDown(adapter.close);
    final inputs = adapter.incoming.take(2).toList();

    await sender.send(Uint8List(0));
    await sender.send(Uint8List.fromList([0x41, 0x00, 0xff]));

    final packets = await received.timeout(const Duration(seconds: 2));
    expect(packets.map((packet) => packet.data), [
      [],
      [0x41, 0x00, 0xff],
    ]);
    expect(packets.map((packet) => packet.address.address), [
      '127.0.0.1',
      '127.0.0.1',
    ]);
    expect(packets.map((packet) => packet.port), [
      sender.boundPort,
      sender.boundPort,
    ]);
    final receivedChunks = await chunks.timeout(const Duration(seconds: 2));
    final adapted = await inputs.timeout(const Duration(seconds: 2));
    for (var index = 0; index < packets.length; index++) {
      expect(receivedChunks[index], same(packets[index].data));
      expect(adapted[index].bytes, same(packets[index].data));
      expect(adapted[index].datagram, isTrue);
      expect(adapted[index].peer, '127.0.0.1:${sender.boundPort}');
    }
    expect(() => packets.last.data[0] = 0, throwsUnsupportedError);
  }, skip: !Platform.isWindows);
  test('与 Dart UDP 非空双向互通且接收方不改写配置目的地址', () async {
    final configured = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(configured.close);
    final other = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(other.close);
    final transport = await WindowsUdpTransport.open(
      UdpPrefs(
        nicKey: '127.0.0.1',
        unicastHost: '127.0.0.1',
        unicastPort: configured.port,
      ),
    );
    addTearDown(transport.close);
    final inbound = transport.datagrams.first;
    other.send([9, 8, 7], InternetAddress.loopbackIPv4, transport.boundPort);
    final packet = await inbound.timeout(const Duration(seconds: 2));
    expect(packet.data, [9, 8, 7]);
    expect(packet.port, other.port);
    final outbound = configured
        .where((event) => event == RawSocketEvent.read)
        .map((_) => configured.receive())
        .where((packet) => packet != null)
        .first;
    await transport.send(Uint8List.fromList([1, 2, 3]));
    final reply = await outbound.timeout(const Duration(seconds: 2));
    expect(reply!.data, [1, 2, 3]);
    expect(reply.port, transport.boundPort);
    expect(reply.address.address, '127.0.0.1');
  }, skip: !Platform.isWindows);

  test('关闭幂等、结束流、释放本地端口并拒绝后续发送', () async {
    final transport = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    final packetsDone = transport.datagrams.drain<void>();
    final chunksDone = transport.chunks.drain<void>();
    final events = transport.events.toList();
    final port = transport.boundPort;
    await Future.wait([transport.close(), transport.close()]);
    await Future.wait([packetsDone, chunksDone]);
    expect(
      (await events).map((event) => event.type),
      contains(TransportEventType.closed),
    );
    await expectLater(transport.send(Uint8List(0)), throwsStateError);
    final rebound = await WindowsUdpTransport.open(
      UdpPrefs(nicKey: '127.0.0.1', localPort: port),
    );
    addTearDown(rebound.close);
    expect(rebound.boundPort, port);
  }, skip: !Platform.isWindows);
  test('广播模式启用 SO_BROADCAST 并仅在本机回环网段收发', () async {
    final receiver = await WindowsUdpTransport.open(const UdpPrefs());
    addTearDown(receiver.close);
    final sender = await WindowsUdpTransport.open(
      UdpPrefs(
        nicKey: '127.0.0.1',
        mode: UdpMode.broadcast,
        broadcastHost: '127.255.255.255',
        broadcastPort: receiver.boundPort,
      ),
    );
    addTearDown(sender.close);
    final incoming = receiver.datagrams.first;
    await sender.send(Uint8List.fromList([0xb0, 0xad]));
    final packet = await incoming.timeout(const Duration(seconds: 2));
    expect(packet.data, [0xb0, 0xad]);
    expect(packet.address.address, '127.0.0.1');
    expect(packet.port, sender.boundPort);
  }, skip: !Platform.isWindows);

  test('最大 IPv4 数据报完整接收，过大报文明确失败且不影响下一次发送', () async {
    final receiver = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    addTearDown(receiver.close);
    final sender = await WindowsUdpTransport.open(
      UdpPrefs(
        nicKey: '127.0.0.1',
        unicastHost: '127.0.0.1',
        unicastPort: receiver.boundPort,
      ),
    );
    addTearDown(sender.close);
    final incoming = receiver.datagrams.first;
    final bytes = Uint8List(65507)..[0] = 0x12;
    bytes[65506] = 0x34;
    await sender.send(bytes);
    expect((await incoming.timeout(const Duration(seconds: 2))).data, bytes);
    await expectLater(
      sender.send(Uint8List(65508)),
      throwsA(
        isA<SocketException>().having(
          (error) => error.osError?.errorCode,
          '原生错误码',
          10040,
        ),
      ),
    );
    final next = receiver.datagrams.first;
    await sender.send(Uint8List(0));
    expect((await next.timeout(const Duration(seconds: 2))).data, isEmpty);
  }, skip: !Platform.isWindows);

  test('可读回调内关闭会话后停止交付积压报文', () async {
    final receiver = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    addTearDown(receiver.close);
    final sender = await WindowsUdpTransport.open(
      UdpPrefs(
        nicKey: '127.0.0.1',
        unicastHost: '127.0.0.1',
        unicastPort: receiver.boundPort,
      ),
    );
    addTearDown(sender.close);
    final done = Completer<void>();
    final seen = <int>[];
    final subscription = receiver.datagrams.listen((packet) {
      seen.add(packet.data.single);
      unawaited(receiver.close());
    }, onDone: done.complete);
    addTearDown(subscription.cancel);

    await Future.wait([
      for (var i = 0; i < 4; i++) sender.send(Uint8List.fromList([i])),
    ]);
    await done.future.timeout(const Duration(seconds: 2));
    expect(seen, [0]);
    await receiver.close();
  }, skip: !Platform.isWindows);

  test('跨接收批次持续保留多来源的空数据报和顺序', () async {
    final receiver = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    addTearDown(receiver.close);
    final prefs = UdpPrefs(
      nicKey: '127.0.0.1',
      unicastHost: '127.0.0.1',
      unicastPort: receiver.boundPort,
    );
    final first = await WindowsUdpTransport.open(prefs);
    final second = await WindowsUdpTransport.open(prefs);
    addTearDown(first.close);
    addTearDown(second.close);
    final incoming = receiver.datagrams.take(130).toList();
    for (var index = 0; index < 130; index++) {
      await (index.isEven ? first : second).send(Uint8List(0));
    }
    final packets = await incoming.timeout(const Duration(seconds: 3));
    expect(packets, hasLength(130));
    expect(packets.every((packet) => packet.data.isEmpty), isTrue);
    expect(
      packets.map((packet) => packet.port),
      List.generate(
        130,
        (index) => index.isEven ? first.boundPort : second.boundPort,
      ),
    );
  }, skip: !Platform.isWindows);

  test('占用端口绑定失败，非法配置与缺失目标明确拒绝', () async {
    final transport = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    addTearDown(transport.close);
    await expectLater(
      WindowsUdpTransport.open(
        UdpPrefs(nicKey: '127.0.0.1', localPort: transport.boundPort),
      ),
      throwsA(isA<SocketException>()),
    );
    await expectLater(
      WindowsUdpTransport.open(const UdpPrefs(nicKey: '::1')),
      throwsArgumentError,
    );
    await expectLater(
      WindowsUdpTransport.open(const UdpPrefs(localPort: 65536)),
      throwsArgumentError,
    );
    await expectLater(transport.send(Uint8List(0)), throwsStateError);
  }, skip: !Platform.isWindows);
  test('消费者暂停不会阻止关闭并释放原生端口', () async {
    final transport = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    final subscription = transport.datagrams.listen((_) {});
    subscription.pause();
    addTearDown(subscription.cancel);
    final port = transport.boundPort;
    await transport.close().timeout(const Duration(seconds: 2));
    final rebound = await WindowsUdpTransport.open(
      UdpPrefs(nicKey: '127.0.0.1', localPort: port),
    );
    addTearDown(rebound.close);
    expect(rebound.boundPort, port);
  }, skip: !Platform.isWindows);
  test('Dart 发送端非空空非空数据报连续接收且原生流保持打开', () async {
    final receiver = await WindowsUdpTransport.open(
      const UdpPrefs(nicKey: '127.0.0.1'),
    );
    addTearDown(receiver.close);
    final sender = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(sender.close);
    final states = <TransportEvent>[];
    var streamEnded = false;
    final stateSubscription = receiver.events.listen(states.add);
    addTearDown(stateSubscription.cancel);
    final packets = <Datagram>[];
    final received = Completer<void>();
    final subscription = receiver.datagrams.listen(
      (packet) {
        packets.add(packet);
        if (packets.length == 3) received.complete();
      },
      onDone: () {
        streamEnded = true;
        if (!received.isCompleted) received.complete();
      },
    );
    addTearDown(subscription.cancel);
    var writable = Completer<void>();
    final senderSubscription = sender.listen((event) {
      if (event == RawSocketEvent.write && !writable.isCompleted) {
        writable.complete();
      }
    });
    addTearDown(senderSubscription.cancel);
    final sent = [
      sender.send([0x41], InternetAddress.loopbackIPv4, receiver.boundPort),
    ];
    expect(sent.first, 1);
    // Dart Windows 的异步 sendto 在前次发送尚未结束时可返回 0；
    // 每报之间先等真实可写，空报是否送达由接收端事实断言。
    await writable.future.timeout(const Duration(seconds: 2));
    writable = Completer<void>();
    sent.add(sender.send([], InternetAddress.loopbackIPv4, receiver.boundPort));
    sender.writeEventsEnabled = true;
    await writable.future.timeout(const Duration(seconds: 2));
    sent.add(
      sender.send([0x42], InternetAddress.loopbackIPv4, receiver.boundPort),
    );
    expect(sent.last, 1);
    await received.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        fail(
          '发送返回：$sent；接收：${packets.map((packet) => packet.data.toList())}；原生事件：$states',
        );
      },
    );
    expect(streamEnded, isFalse, reason: '原生事件：$states');
    expect(packets.map((packet) => packet.data), [
      [0x41],
      [],
      [0x42],
    ], reason: '原生事件：$states');
    expect(packets.every((packet) => packet.port == sender.port), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(streamEnded, isFalse, reason: '原生事件：$states');
    expect(
      states.where((event) => event.type == TransportEventType.error),
      isEmpty,
    );
  }, skip: !Platform.isWindows);
}
