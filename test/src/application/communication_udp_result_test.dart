import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/network_transports.dart';
import 'package:clovecom/src/io/interface_params.dart';

// 仅替换系统 socket 边界，send 的返回值由实际 dart:io 适配器解释。
class ControlledDatagram implements RawDatagramSocket {
  final events = StreamController<RawSocketEvent>.broadcast();
  int accepted = 0, sends = 0;
  @override
  int get port => 12345;
  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    sends++;
    return accepted;
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void close() {
    unawaited(events.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('dart:io UDP保留短接受数量，完整与合法空数据报成功', () async {
    final socket = ControlledDatagram();
    const prefs = UdpPrefs(unicastHost: '127.0.0.1', unicastPort: 12346);
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => NetworkCommunicationTransport(
        await UdpTransport.open(prefs, bindSocket: (_, _) async => socket),
        InterfaceProtocol.udp,
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'udp',
        name: 'UDP',
        protocol: InterfaceProtocol.udp,
        udp: prefs,
      ),
    );
    await runtime.openConnection('udp');
    socket.accepted = 1;
    final partial = await runtime.writeTo('udp', Uint8List.fromList([1, 2, 3]));
    expect(partial.succeeded, isFalse);
    expect(partial.acceptedBytes, 1);
    socket.accepted = 3;
    final full = await runtime.writeTo('udp', Uint8List.fromList([1, 2, 3]));
    expect(full.succeeded, isTrue);
    socket.accepted = 0;
    final empty = await runtime.writeTo('udp', Uint8List(0));
    expect(empty.succeeded, isTrue);
    expect(empty.acceptedBytes, 0);
    expect(socket.sends, 3);
  });
  test('dart:io UDP零接受明确失败且循环停止、不虚增TX或透明重发', () async {
    final socket = ControlledDatagram();
    const prefs = UdpPrefs(unicastHost: '127.0.0.1', unicastPort: 12346);
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => NetworkCommunicationTransport(
        await UdpTransport.open(prefs, bindSocket: (_, _) async => socket),
        InterfaceProtocol.udp,
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(
      ConnectionDefinition.network(
        id: 'udp',
        name: 'UDP',
        protocol: InterfaceProtocol.udp,
        udp: prefs,
      ),
    );
    await runtime.openConnection('udp');
    final result = await runtime.writeTo('udp', Uint8List.fromList([1, 2, 3]));
    expect(result.succeeded, isFalse);
    expect(result.acceptedBytes, 0);
    var written = 0;
    runtime.observeSessionWrites('udp', (bytes, _) => written += bytes.length);
    runtime.startLoop(
      'udp',
      Uint8List.fromList([1, 2, 3]),
      interval: const Duration(milliseconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(runtime.loopFor('udp')!.phase, LoopPhase.stopped);
    expect(runtime.loopFor('udp')!.lastResult!.acceptedBytes, 0);
    expect(written, 0);
    expect(socket.sends, 2);
  });
}
