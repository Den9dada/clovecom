import 'dart:async';
import 'dart:typed_data';

import 'package:clovecom/protocols/transfer_protocol.dart';
import 'package:clovecom/services/serial/serial_byte_transport.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';
import 'package:clovecom/viewmodels/serial_port_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'serial_port_directory_test.dart' show ports;

class _FakeTransport implements SerialByteTransport {
  final input = StreamController<Uint8List>();
  @override
  Stream<Uint8List> get chunks => input.stream;
  @override
  bool send(Uint8List bytes, int timeoutMs) => true;
  @override
  void purge() {}
  @override
  void close() {}
}

/// 记录型传输协议 fake：与生产 YmodemProtocol 构成同一缝上的两个适配器。
class _RecordingProtocol implements TransferProtocol {
  @override
  String get name => 'FakeProto';
  @override
  String get receiveName => 'FakeProto 接收';
  @override
  String get description => '测试用传输协议';
  @override
  Future<void> send(
    Uint8List data, {
    required int packetSize,
    required int intervalMs,
    required TransferCallbacks callbacks,
  }) async {
    callbacks.onComplete(data.length);
  }

  @override
  Future<void> receive({
    required String savePath,
    required TransferCallbacks callbacks,
  }) async {
    callbacks.onComplete(0);
  }
}

SerialPortViewModel _vm({TransferProtocol? protocol}) {
  return SerialPortViewModel(
    directory: SerialPortDirectory(
      scan: () async => ports([]),
      changes: const Stream.empty(),
    ),
    openTransport: (_) => _FakeTransport(),
    transferProtocol: protocol,
  );
}

void main() {
  test('默认传输协议为 Ymodem-1K（删除注册表后行为不变）', () {
    final vm = _vm();
    expect(vm.transferProtocol.name, 'Ymodem-1K');
    expect(vm.transferProtocol.receiveName, 'Ymodem-1K 接收');
    vm.dispose();
  });

  test('注入的传输协议经 getter 暴露为同一实例', () {
    final fake = _RecordingProtocol();
    final vm = _vm(protocol: fake);
    expect(identical(vm.transferProtocol, fake), isTrue);
    expect(vm.transferProtocol.name, 'FakeProto');
    expect(vm.transferProtocol.receiveName, 'FakeProto 接收');
    vm.dispose();
  });
}