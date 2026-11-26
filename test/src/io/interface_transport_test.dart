// 接口通信传输层与参数模型测试（决策 Q8/Q9/Q15/Q19/Q20/Q23）
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/byte_transport.dart';
import 'package:clovecom/src/io/interface_params.dart';
import 'package:clovecom/src/io/network_transports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('参数校验', () {
    test('TCP客户端需要有效远端', () {
      expect(
        validateNetworkParams(
          protocol: InterfaceProtocol.tcpClient,
          tcpClient: const TcpClientPrefs(remoteHost: ''),
          tcpServer: const TcpServerPrefs(),
          udp: const UdpPrefs(),
        ),
        isNotNull,
      );
      expect(
        validateNetworkParams(
          protocol: InterfaceProtocol.tcpClient,
          tcpClient: const TcpClientPrefs(
            remoteHost: '127.0.0.1',
            remotePort: 9000,
          ),
          tcpServer: const TcpServerPrefs(),
          udp: const UdpPrefs(),
        ),
        isNull,
      );
    });

    test('validateNetworkParams 只检查当前协议', () {
      expect(
        validateNetworkParams(
          protocol: InterfaceProtocol.tcpServer,
          tcpClient: const TcpClientPrefs(remoteHost: ''),
          tcpServer: const TcpServerPrefs(localPort: 9000),
          udp: const UdpPrefs(mode: UdpMode.broadcast),
        ),
        isNull,
      );
    });

    test('本地端口留空（0）视为系统自动分配，校验通过（Q23）', () {
      expect(
        validateNetworkParams(
          protocol: InterfaceProtocol.tcpServer,
          tcpClient: const TcpClientPrefs(),
          tcpServer: const TcpServerPrefs(),
          udp: const UdpPrefs(),
        ),
        isNull,
      );
      expect(
        validateNetworkParams(
          protocol: InterfaceProtocol.tcpClient,
          tcpClient: const TcpClientPrefs(
            remoteHost: '127.0.0.1',
            remotePort: 9000,
            localPort: 0,
          ),
          tcpServer: const TcpServerPrefs(),
          udp: const UdpPrefs(),
        ),
        isNull,
      );
    });

    test('UDP 广播未填目的地址时给出可辨识原因（决策 Q20）', () {
      final error = validateNetworkParams(
        protocol: InterfaceProtocol.udp,
        tcpClient: const TcpClientPrefs(),
        tcpServer: const TcpServerPrefs(),
        udp: const UdpPrefs(mode: UdpMode.broadcast),
      );
      expect(error, contains('广播'));
    });

    test('端口越界拒绝', () {
      expect(
        validateNetworkParams(
          protocol: InterfaceProtocol.tcpServer,
          tcpClient: const TcpClientPrefs(),
          tcpServer: const TcpServerPrefs(localPort: 70000),
          udp: const UdpPrefs(),
        ),
        isNotNull,
      );
    });
  });

  group('参数模型持久化', () {
    test('InterfacePrefs JSON 往返保留各协议参数', () {
      final prefs = InterfacePrefs(
        lastKind: InterfaceKind.nic,
        lastProtocol: InterfaceProtocol.udp,
        tcpClient: const TcpClientPrefs(
          nicKey: '192.168.1.5',
          remoteHost: '10.0.0.1',
          remotePort: 1234,
          localPort: 5678,
          autoReconnect: true,
        ),
        tcpServer: const TcpServerPrefs(localPort: 4321),
        udp: const UdpPrefs(
          mode: UdpMode.broadcast,
          unicastHost: '10.0.0.2',
          unicastPort: 7007,
          broadcastHost: '192.168.1.255',
          broadcastPort: 5555,
          localPort: 6666,
        ),
      );
      final restored = InterfacePrefs.fromJson(
        jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>,
      );
      expect(restored.lastKind, InterfaceKind.nic);
      expect(restored.lastProtocol, InterfaceProtocol.udp);
      expect(restored.tcpClient.nicKey, '192.168.1.5');
      expect(restored.tcpClient.localPort, 5678);
      expect(restored.tcpClient.autoReconnect, isTrue);
      expect(restored.tcpServer.localPort, 4321);
      expect(restored.udp.mode, UdpMode.broadcast);
      expect(restored.udp.unicastHost, '10.0.0.2');
      expect(restored.udp.unicastPort, 7007);
      expect(restored.udp.broadcastHost, '192.168.1.255');
      expect(restored.udp.broadcastPort, 5555);
      expect(restored.udp.localPort, 6666);
      // 生效视图跟随模式：广播模式取广播目的
      expect(restored.udp.targetHost, '192.168.1.255');
      expect(restored.udp.targetPort, 5555);
    });

    test('旧版键迁移：listenPort 与单一 target 字段（Q23 前格式）', () {
      final restored = InterfacePrefs.fromJson({
        'lastKind': 'nic',
        'lastProtocol': 'udp',
        'tcpServer': {'nicKey': '', 'listenPort': 9000},
        'udp': {
          'mode': 'unicast',
          'targetHost': '10.1.2.3',
          'targetPort': 8888,
        },
      });
      expect(restored.tcpServer.localPort, 9000);
      expect(restored.udp.unicastHost, '10.1.2.3');
      expect(restored.udp.unicastPort, 8888);
      expect(restored.udp.broadcastHost, isEmpty);
    });

    test('UDP 单播/广播目的互不覆盖', () {
      var prefs = const UdpPrefs();
      prefs = prefs.copyWith(unicastHost: '10.0.0.9', unicastPort: 6000);
      prefs = prefs.copyWith(
        mode: UdpMode.broadcast,
        broadcastHost: '192.168.0.255',
        broadcastPort: 6001,
      );
      expect(prefs.targetHost, '192.168.0.255');
      expect(prefs.mode, UdpMode.broadcast);
      final backToUnicast = prefs.copyWith(mode: UdpMode.unicast);
      expect(backToUnicast.targetHost, '10.0.0.9');
      expect(backToUnicast.targetPort, 6000);
    });
  });

  group('回环传输', () {
    /// broadcast 流不回放已发事件，用记录器 + 轮询规避订阅竞态。
    List<TransportEvent> recordEvents(ByteTransport transport) {
      final log = <TransportEvent>[];
      transport.events.listen(log.add);
      return log;
    }

    Future<void> waitEvent(
      List<TransportEvent> log,
      bool Function(TransportEvent) test,
    ) async {
      for (var i = 0; i < 100; i++) {
        if (log.any(test)) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError('等待传输事件超时');
    }

    test('TCP服务端与客户端字节互通，第二连接被拒（Q19）', () async {
      final server = await TcpServerTransport.listen(
        const TcpServerPrefs(nicKey: '127.0.0.1', localPort: 0),
      );
      final serverEvents = recordEvents(server);
      final port = server.boundPort;

      final client = await TcpClientTransport.connect(
        TcpClientPrefs(remoteHost: '127.0.0.1', remotePort: port),
      );
      await waitEvent(serverEvents, (e) => e.type.name == 'peerConnected');

      final serverReceived = Completer<Uint8List>();
      server.chunks.listen((data) {
        if (!serverReceived.isCompleted) serverReceived.complete(data);
      });
      await client.send(Uint8List.fromList([1, 2, 3]));
      final serverBytes = await serverReceived.future;
      expect(serverBytes, [1, 2, 3]);
      expect(() => serverBytes[0] = 0, throwsUnsupportedError);

      final adapter = NetworkCommunicationTransport(
        client,
        InterfaceProtocol.tcpClient,
      );
      final fromAdapter = adapter.incoming.first;
      final clientReceived = Completer<Uint8List>();
      client.chunks.listen((data) {
        if (!clientReceived.isCompleted) clientReceived.complete(data);
      });
      await server.send(Uint8List.fromList([9, 8]));
      final clientBytes = await clientReceived.future;
      expect(clientBytes, [9, 8]);
      expect((await fromAdapter).bytes, same(clientBytes));
      expect(() => clientBytes[0] = 0, throwsUnsupportedError);

      // 占用中：第二连接应被快速断开（对端 destroy 后读流收到 onDone）
      final extra = await Socket.connect('127.0.0.1', port);
      final extraClosed = Completer<bool>();
      extra.listen(
        (_) {},
        onDone: () {
          if (!extraClosed.isCompleted) extraClosed.complete(true);
        },
        onError: (Object _) {
          if (!extraClosed.isCompleted) extraClosed.complete(true);
        },
      );
      expect(
        await extraClosed.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        ),
        isTrue,
        reason: '单客户端语义下第二连接应被拒绝',
      );
      extra.destroy();

      await adapter.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('TCP服务端在客户端断开后可再接收新连接', () async {
      final server = await TcpServerTransport.listen(
        const TcpServerPrefs(nicKey: '127.0.0.1', localPort: 0),
      );
      final events = recordEvents(server);
      final port = server.boundPort;

      final first = await TcpClientTransport.connect(
        TcpClientPrefs(remoteHost: '127.0.0.1', remotePort: port),
      );
      await waitEvent(events, (e) => e.type.name == 'peerConnected');
      await first.close();
      await waitEvent(events, (e) => e.type.name == 'peerDisconnected');

      final second = await TcpClientTransport.connect(
        TcpClientPrefs(remoteHost: '127.0.0.1', remotePort: port),
      );
      final delivered = Completer<bool>();
      server.chunks.listen((_) {
        if (!delivered.isCompleted) delivered.complete(true);
      });
      await second.send(Uint8List.fromList([1]));
      expect(
        await delivered.future.timeout(const Duration(seconds: 5)),
        isTrue,
        reason: '断开后新客户端应可继续收发',
      );
      await second.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('TCP客户端可指定本地源端口连接（Q23）', () async {
      final server = await TcpServerTransport.listen(
        const TcpServerPrefs(nicKey: '127.0.0.1', localPort: 0),
      );
      final events = recordEvents(server);
      // 先占一个临时端口再释放，作为客户端本地端口（回环环境冲突概率极低）
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sourcePort = reserved.port;
      await reserved.close();

      final client = await TcpClientTransport.connect(
        TcpClientPrefs(
          remoteHost: '127.0.0.1',
          remotePort: server.boundPort,
          localPort: sourcePort,
        ),
      );
      // 本地端口绑定成功：服务端可见 peerConnected（见 waitEvent）
      await waitEvent(events, (e) => e.type.name == 'peerConnected');

      final echoed = Completer<Uint8List>();
      server.chunks.listen((d) {
        if (!echoed.isCompleted) echoed.complete(d);
      });
      await client.send(Uint8List.fromList([42]));
      expect(await echoed.future.timeout(const Duration(seconds: 5)), [42]);

      await client.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('UDP 单播回环收发', () async {
      final peer = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final udp = await UdpTransport.open(
        UdpPrefs(
          nicKey: '127.0.0.1',
          localPort: 0,
          unicastHost: '127.0.0.1',
          unicastPort: peer.port,
        ),
      );
      final boundPort = udp.boundPort;
      final adapter = NetworkCommunicationTransport(udp, InterfaceProtocol.udp);
      final fromAdapter = adapter.incoming.first;

      final received = Completer<Uint8List>();
      udp.chunks.listen((data) {
        if (!received.isCompleted) received.complete(data);
      });
      // 对端保持常驻监听：若在 .first 处取消订阅，Windows 下该 socket
      // 后续 send 会返回 0（实测），回包发不出去。
      final peerGot = Completer<Datagram>();
      peer.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = peer.receive();
          if (dg != null && !peerGot.isCompleted) peerGot.complete(dg);
        }
      });
      await udp.send(Uint8List.fromList([7, 7, 7]));
      final datagram = await peerGot.future;
      expect(datagram.data, [7, 7, 7]);

      peer.send(
        Uint8List.fromList([4, 5]),
        InternetAddress('127.0.0.1'),
        boundPort,
      );
      final bytes = await received.future;
      expect(bytes, [4, 5]);
      final input = await fromAdapter;
      expect(input.bytes, same(bytes));
      expect(input.datagram, isTrue);
      expect(input.peer, '127.0.0.1:${peer.port}');
      expect(() => bytes[0] = 0, throwsUnsupportedError);

      peer.close();
      await adapter.close();
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
