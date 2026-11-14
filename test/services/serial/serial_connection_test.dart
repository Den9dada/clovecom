import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/services/serial/serial_byte_transport.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';
import 'package:clovecom/viewmodels/serial_port_viewmodel.dart';
import 'serial_port_directory_test.dart' show ports;

class FakeTransport implements SerialByteTransport {
  final input = StreamController<Uint8List>();
  bool closed = false;
  @override
  Stream<Uint8List> get chunks => input.stream;
  @override
  bool send(Uint8List bytes, int timeoutMs) => !closed;
  @override
  void purge() {}
  @override
  void close() {
    closed = true;
  }
}

void main() {
  test('连接失败可重试，成功后错误清除且重复连接不重复打开', () async {
    final transport = FakeTransport();
    var attempts = 0;
    final vm = SerialPortViewModel(
      directory: SerialPortDirectory(
        scan: () async => ports([]),
        changes: const Stream.empty(),
      ),
      openTransport: (_) {
        if (++attempts == 1) throw StateError('占用');
        return transport;
      },
    );
    vm.updateConfig(portName: 'COM2');
    expect(await vm.connect(), isFalse);
    expect(vm.state.error, contains('占用'));
    expect(await vm.connect(), isTrue);
    expect(vm.state.error, isNull);
    expect(await vm.connect(), isTrue);
    expect(attempts, 2);
    vm.dispose();
    expect(transport.closed, isTrue);
    await transport.input.close();
  });

  test('设备拔出关闭连接并清理选择，手动端口仍可保留', () async {
    var names = ['COM2'];
    final transport = FakeTransport();
    final vm = SerialPortViewModel(
      directory: SerialPortDirectory(
        scan: () async => ports(names),
        changes: const Stream.empty(),
      ),
      openTransport: (_) => transport,
    );
    await Future<void>.delayed(Duration.zero);
    vm.updateConfig(portName: 'COM2');
    await vm.connect();
    names = [];
    await vm.refreshPorts();
    expect(vm.state.isConnected, isFalse);
    expect(transport.closed, isTrue);
    expect(vm.config.portName, isEmpty);
    vm.updateConfig(portName: 'COM99');
    await vm.refreshPorts();
    expect(vm.config.portName, 'COM99');
    vm.dispose();
    await transport.input.close();
  });

  test('旧连接数据不能进入新连接，读流异常自动断开', () async {
    final old = FakeTransport();
    final current = FakeTransport();
    var opens = 0;
    final vm = SerialPortViewModel(
      directory: SerialPortDirectory(
        scan: () async => ports([]),
        changes: const Stream.empty(),
      ),
      openTransport: (_) => ++opens == 1 ? old : current,
    );
    vm.updateConfig(portName: 'COM2');
    await vm.connect();
    await vm.disconnect();
    await vm.connect();
    old.input.add(Uint8List.fromList([65]));
    current.input.add(Uint8List.fromList([66]));
    await Future<void>.delayed(Duration.zero);
    expect(vm.messages.where((m) => m.dataLength > 0).single.data, 'B');
    current.input.addError(StateError('读失败'));
    await Future<void>.delayed(Duration.zero);
    expect(vm.state.isConnected, isFalse);
    expect(current.closed, isTrue);
    vm.dispose();
    await old.input.close();
    await current.input.close();
  });
}
