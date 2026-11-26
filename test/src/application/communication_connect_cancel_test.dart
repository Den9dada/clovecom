import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/io/interface_params.dart';

// 控制 SDK 的 socket 边界，保留默认生产工厂及真实内核生命周期。
final class PendingConnect extends IOOverrides {
  final started = Completer<void>();
  final socket = Completer<Socket>();
  int cancelled = 0;
  @override
  Future<Socket> socketConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    started.complete();
    return socket.future;
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) async {
    started.complete();
    return ConnectionTask.fromSocket(socket.future, () {
      cancelled++;
      if (!socket.isCompleted) {
        socket.completeError(const SocketException('已取消'));
      }
    });
  }
}

void main() {
  test('默认工厂主动断开取消SDK连接任务且新一轮能独立打开', () async {
    final pending = PendingConnect();
    final runtime = CommunicationRuntime();
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'tcp',
        name: '本地客户端',
        protocol: InterfaceProtocol.tcpClient,
        tcpClient: const TcpClientPrefs(
          remoteHost: '127.0.0.1',
          remotePort: 12345,
        ),
      ),
    );
    try {
      await IOOverrides.runWithIOOverrides(() async {
        final opening = runtime.openConnection('tcp');
        await pending.started.future;
        final closing = runtime.closeConnection('tcp');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(pending.cancelled, 1);
        await closing.timeout(const Duration(milliseconds: 250));
        await opening;
        expect(runtime.connection('tcp').phase, ConnectionPhase.closed);
      }, pending);
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final clients = <Socket>[];
      final sub = server.listen(clients.add);
      try {
        runtime.updateConnection(
          ConnectionDefinition.network(
            id: 'tcp',
            name: '本地客户端',
            protocol: InterfaceProtocol.tcpClient,
            tcpClient: TcpClientPrefs(
              remoteHost: '127.0.0.1',
              remotePort: server.port,
            ),
          ),
        );
        await runtime.openConnection('tcp');
        expect(runtime.connection('tcp').phase, ConnectionPhase.open);
        await runtime.closeConnection('tcp');
      } finally {
        for (final client in clients) {
          client.destroy();
        }
        await sub.cancel();
        await server.close();
      }
    } finally {
      if (!pending.socket.isCompleted) {
        pending.socket.completeError(const SocketException('测试清理'));
      }
      await runtime.dispose();
    }
  });
}
