import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/connections.dart';
import 'package:clovecom/src/io/interface_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('主动断开与首次失败回收交错时，清理完成不能再安排重连', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var attempts = 0;
    final runtime = CommunicationRuntime(
      retryBase: const Duration(milliseconds: 5),
      transportFactory: (_) async {
        attempts++;
        return attempts == 1
            ? GateCloseTransport(started, release)
            : FakeTransport();
      },
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'client',
        name: '客户端',
        protocol: InterfaceProtocol.tcpClient,
        tcpClient: const TcpClientPrefs(autoReconnect: true),
      ),
    );
    final opening = runtime.openConnection('client');
    await started.future;
    final closing = runtime.closeConnection('client');
    release.complete();
    await opening;
    await closing;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(attempts, 1);
    expect(runtime.connection('client').phase, ConnectionPhase.closed);
  });
  test('写结果已超时但未 settled 时，关闭不释放物理占用', () async {
    final settled = Completer<void>();
    final transport = FakeTransport(
      writeResult: SerialWriteResult.failure('写超时', settled: settled.future),
      closeGate: settled.future,
    );
    var calls = 0;
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => ++calls == 1 ? transport : FakeTransport(),
    );
    addTearDown(runtime.dispose);
    for (final id in ['a', 'b']) {
      runtime.addConnection(
        ConnectionDefinition.serial(
          ConnectionConfig(
            id: id,
            kind: TransportKind.serial,
            protocolId: '',
            serialPort: 'COM7',
          ),
        ),
      );
    }
    await runtime.openConnection('a');
    final writing = runtime.writeTo('a', Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    var closed = false;
    final closing = runtime.closeConnection('a').then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(runtime.connection('a').phase, ConnectionPhase.closing);
    await expectLater(runtime.openConnection('b'), throwsStateError);
    settled.complete();
    final result = await writing;
    expect(result.acceptedBytes, isNull);
    expect(result.succeeded, isFalse);
    await closing;
    await runtime.openConnection('b');
  });
  test('迟到打开的资源关闭失败时保持关闭中并保留物理占用', () async {
    final pending = Completer<CommunicationTransport>();
    var calls = 0;
    final runtime = CommunicationRuntime(
      transportFactory: (_) =>
          ++calls == 1 ? pending.future : Future.value(FakeTransport()),
    );
    addTearDown(runtime.dispose);
    for (final id in ['a', 'b']) {
      runtime.addConnection(
        ConnectionDefinition.serial(
          ConnectionConfig(
            id: id,
            kind: TransportKind.serial,
            protocolId: '',
            serialPort: 'COM7',
          ),
        ),
      );
    }
    final opening = runtime.openConnection('a');
    final closing = runtime.closeConnection('a');
    final late = FailingCloseTransport();
    pending.complete(late);
    await opening;
    await expectLater(closing, throwsStateError);
    expect(runtime.connection('a').phase, ConnectionPhase.closing);
    await expectLater(runtime.openConnection('b'), throwsStateError);
    late.failClose = false;
    await runtime.closeConnection('a');
    await runtime.openConnection('b');
  });
  test('真实 TCP 客户端对端关闭后进入故障而不保留可写状态', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final accepted = server.first;
    final runtime = CommunicationRuntime();
    addTearDown(runtime.dispose);
    addTearDown(server.close);
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'client',
        name: '客户端',
        protocol: InterfaceProtocol.tcpClient,
        tcpClient: TcpClientPrefs(remotePort: server.port),
      ),
    );
    await runtime.openConnection('client');
    final peer = await accepted;
    peer.destroy();
    await eventually(
      () => runtime.connection('client').phase == ConnectionPhase.failed,
    );
    expect(runtime.connection('client').writable, isFalse);
  });
  test('真实网络工厂在公开状态报告系统分配端口，客户端断开后继续监听', () async {
    final runtime = CommunicationRuntime();
    addTearDown(runtime.dispose);
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'server',
        name: '服务端',
        protocol: InterfaceProtocol.tcpServer,
        tcpServer: const TcpServerPrefs(nicKey: '127.0.0.1'),
      ),
    );
    await runtime.openConnection('server');
    expect(runtime.connection('server').detail, startsWith('127.0.0.1:'));
    final port = int.parse(
      runtime.connection('server').detail!.split(':').last,
    );
    final client = await Socket.connect('127.0.0.1', port);
    addTearDown(client.destroy);
    await eventually(() => runtime.connection('server').writable);
    final incoming = runtime.packets.first;
    client.add([1]);
    await client.flush();
    expect((await incoming).peer, '127.0.0.1:${client.port}');
    final epoch = runtime.connection('server').epoch;
    client.destroy();
    await eventually(
      () => runtime.connection('server').phase == ConnectionPhase.listening,
    );
    final next = await Socket.connect('127.0.0.1', port);
    addTearDown(next.destroy);
    await eventually(() => runtime.connection('server').writable);
    expect(runtime.connection('server').epoch, greaterThan(epoch));
  });
  test('观察服务端监听和可写状态，换客户端刷新数据轮次', () async {
    final transport = FakeTransport(
      initial: const CommunicationTransportState(
        writable: false,
        listening: true,
      ),
    );
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'server',
        name: '服务端',
        protocol: InterfaceProtocol.tcpServer,
      ),
    );
    final packets = <dynamic>[];
    final sub = runtime.packets.listen(packets.add);
    addTearDown(sub.cancel);
    await runtime.openConnection('server');
    expect(runtime.connection('server').phase, ConnectionPhase.listening);
    expect(
      (await runtime.writeTo('server', Uint8List.fromList([1]))).succeeded,
      isFalse,
    );
    transport.changes.add(
      const CommunicationTransportState(
        writable: true,
        listening: true,
        peer: '127.0.0.1:42',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final firstEpoch = runtime.connection('server').epoch;
    transport.input.add(TransportInput([10]));
    await Future<void>.delayed(Duration.zero);
    transport.changes.add(
      const CommunicationTransportState(writable: false, listening: true),
    );
    transport.changes.add(
      const CommunicationTransportState(
        writable: true,
        listening: true,
        peer: '127.0.0.1:43',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    transport.input.add(TransportInput([20]));
    await Future<void>.delayed(Duration.zero);
    expect(packets.map((p) => p.bytes), [
      [10],
      [20],
    ]);
    expect(packets.first.epoch, firstEpoch);
    expect(packets.last.epoch, greaterThan(firstEpoch));
    expect(packets.last.sequence, greaterThan(packets.first.sequence));
    expect(
      (await runtime.writeTo('server', Uint8List.fromList([2]))).succeeded,
      isTrue,
    );
  });
  test('TCP 客户端首次失败继续重试，主动断开停止重试', () async {
    var attempts = 0;
    final runtime = CommunicationRuntime(
      retryBase: const Duration(milliseconds: 5),
      transportFactory: (_) async {
        attempts++;
        throw StateError('暂时不可达');
      },
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'net',
        name: '测试',
        protocol: InterfaceProtocol.tcpClient,
        tcpClient: const TcpClientPrefs(autoReconnect: true),
      ),
    );
    await runtime.openConnection('net');
    expect(runtime.connection('net').phase, ConnectionPhase.reconnecting);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(attempts, greaterThan(1));
    await runtime.closeConnection('net');
    final stopped = attempts;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(attempts, stopped);
    expect(runtime.connection('net').phase, ConnectionPhase.closed);
  });
  test('主动断开未完成的打开，迟到资源会回收且关闭前不能改参数', () async {
    final pending = Completer<CommunicationTransport>();
    final runtime = CommunicationRuntime(
      transportFactory: (_) => pending.future,
    );
    addTearDown(runtime.dispose);
    final d = ConnectionDefinition.serial(
      ConnectionConfig(
        id: 'a',
        kind: TransportKind.serial,
        protocolId: '',
        serialPort: 'COM7',
      ),
    );
    runtime.addConnection(d);
    final opening = runtime.openConnection('a');
    final closing = runtime.closeConnection('a');
    expect(runtime.connection('a').phase, ConnectionPhase.closing);
    expect(() => runtime.updateConnection(d), throwsStateError);
    final late = FakeTransport();
    pending.complete(late);
    await opening;
    await closing;
    expect(late.closed, isTrue);
    expect(runtime.connection('a').phase, ConnectionPhase.closed);
    expect(runtime.connection('a').writable, isFalse);
  });
  test('应用内同一物理串口只能打开一个连接，不同串口可同时运行', () async {
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => FakeTransport(),
    );
    addTearDown(runtime.dispose);
    for (final entry in {'a': 'COM7', 'b': 'COM7', 'c': 'COM8'}.entries) {
      runtime.addConnection(
        ConnectionDefinition.serial(
          ConnectionConfig(
            id: entry.key,
            kind: TransportKind.serial,
            protocolId: '',
            serialPort: entry.value,
          ),
        ),
      );
    }
    await runtime.openConnection('a');
    await expectLater(runtime.openConnection('b'), throwsStateError);
    await runtime.openConnection('c');
    expect(
      runtime.snapshot.connections.where((c) => c.writable).map((c) => c.id),
      ['a', 'c'],
    );
    expect(() => runtime.snapshot.connections.clear(), throwsUnsupportedError);
    await runtime.closeConnection('a');
    await runtime.openConnection('b');
    expect(runtime.connection('b').writable, isTrue);
  });
}

class FakeTransport implements CommunicationTransport {
  FakeTransport({
    this.initial = const CommunicationTransportState(writable: true),
    this.writeResult,
    this.closeGate,
  });
  final SerialWriteResult? writeResult;
  final Future<void>? closeGate;
  final CommunicationTransportState initial;
  final input = StreamController<TransportInput>.broadcast();
  final changes = StreamController<CommunicationTransportState>.broadcast();
  bool closed = false;
  @override
  CommunicationTransportState get state => initial;
  @override
  Stream<TransportInput> get incoming => input.stream;
  @override
  Stream<CommunicationTransportState> get states => changes.stream;
  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) async =>
      writeResult ?? SerialWriteResult.success(bytes.length);
  @override
  Future<void> close() async {
    await closeGate;
    closed = true;
    await input.close();
    await changes.close();
  }
}

Future<void> eventually(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('公开状态未在限定时间内到达');
}

class FailingCloseTransport extends FakeTransport {
  bool failClose = true;
  @override
  Future<void> close() async {
    if (failClose) throw StateError('尚未回收');
    await super.close();
  }
}

class GateCloseTransport extends FakeTransport {
  GateCloseTransport(this.started, this.release)
    : super(
        initial: const CommunicationTransportState(
          writable: false,
          closed: true,
        ),
      );
  final Completer<void> started;
  final Completer<void> release;
  @override
  Future<void> close() async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.close();
  }
}
