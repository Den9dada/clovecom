import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/services/serial/serial_byte_transport.dart';
import 'package:clovecom/services/serial/serial_connection_owner.dart';

/// 连接所有者接口级测试：直接实例化深模块＋假传输工厂，断言独占租约不变量。
class _FakeTransport implements SerialByteTransport {
  _FakeTransport(SerialPortConfig config) : port = config.portName;
  final String port;
  final _controller = StreamController<Uint8List>();
  Completer<void>? closeGate;
  bool closed = false;
  int closeCount = 0;
  int purgeCount = 0;
  final sent = <Uint8List>[];

  @override
  Stream<Uint8List> get chunks => _controller.stream;
  @override
  Future<SerialWriteResult> send(Uint8List bytes, int timeoutMs) async {
    sent.add(bytes);
    return SerialWriteResult.success(bytes.length);
  }

  @override
  void purge() => purgeCount++;
  @override
  Future<void> close() async {
    closed = true;
    closeCount++;
    await closeGate?.future;
    unawaited(_controller.close());
  }
}

void main() {
  SerialPortConfig config(String port) => SerialPortConfig(portName: port);

  group('SerialConnectionOwner', () {
    test('底层关闭完成前不能重新租用同一串口', () async {
      final owner = SerialConnectionOwner();
      final fake = _FakeTransport(config('COM3'))
        ..closeGate = Completer<void>();
      final lease = owner.acquire(config('COM3'), (_) => fake);
      final closing = lease.close();
      expect(owner.isLeased('COM3'), isTrue);
      expect(
        () => owner.acquire(config('COM3'), _FakeTransport.new),
        throwsStateError,
      );
      fake.closeGate!.complete();
      await closing;
      expect(owner.isLeased('COM3'), isFalse);
    });
    test('租用后端口被标记占用', () {
      final owner = SerialConnectionOwner();
      owner.acquire(config('COM3'), _FakeTransport.new);
      expect(owner.isLeased('COM3'), isTrue);
    });

    test('第二个借用者被拒绝（不排队），首个租约不受影响', () {
      final owner = SerialConnectionOwner();
      final first = owner.acquire(config('COM3'), _FakeTransport.new);
      expect(
        () => owner.acquire(config('COM3'), _FakeTransport.new),
        throwsA(isA<StateError>()),
      );
      expect(owner.isLeased('COM3'), isTrue);
      first.close();
    });

    test('不同端口可并发租用', () {
      final owner = SerialConnectionOwner();
      owner.acquire(config('COM3'), _FakeTransport.new);
      owner.acquire(config('COM4'), _FakeTransport.new);
      expect(owner.isLeased('COM3'), isTrue);
      expect(owner.isLeased('COM4'), isTrue);
    });

    test('close 释放租约后可再次租用', () async {
      final owner = SerialConnectionOwner();
      final lease = owner.acquire(config('COM3'), _FakeTransport.new);
      await lease.close();
      expect(owner.isLeased('COM3'), isFalse);
      owner.acquire(config('COM3'), _FakeTransport.new);
      expect(owner.isLeased('COM3'), isTrue);
    });

    test('close 幂等：内层传输仅关闭一次', () async {
      final owner = SerialConnectionOwner();
      final fake = _FakeTransport(config('COM3'));
      final lease = owner.acquire(config('COM3'), (_) => fake);
      await lease.close();
      await lease.close();
      expect(fake.closeCount, 1);
      expect(owner.isLeased('COM3'), isFalse);
    });

    test('打开失败不登记租约，可重试', () {
      final owner = SerialConnectionOwner();
      expect(
        () => owner.acquire(config('COM3'), (_) => throw StateError('设备不存在')),
        throwsA(isA<StateError>()),
      );
      expect(owner.isLeased('COM3'), isFalse);
      owner.acquire(config('COM3'), _FakeTransport.new);
      expect(owner.isLeased('COM3'), isTrue);
    });

    test('租约传输委托 send/purge/chunks 给内层', () async {
      final owner = SerialConnectionOwner();
      final fake = _FakeTransport(config('COM3'));
      final lease = owner.acquire(config('COM3'), (_) => fake);
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect((await lease.send(bytes, 100)).succeeded, isTrue);
      lease.purge();
      expect(fake.sent, [bytes]);
      expect(fake.purgeCount, 1);
      final received = <Uint8List>[];
      final sub = lease.chunks.listen(received.add);
      fake._controller.add(Uint8List.fromList([9]));
      await Future<void>.delayed(Duration.zero);
      expect(received, [
        [9],
      ]);
      await sub.cancel();
      await lease.close();
    });

    test('陈旧租约重复 close 不误释新租约', () async {
      final owner = SerialConnectionOwner();
      final old = owner.acquire(config('COM3'), _FakeTransport.new);
      await old.close();
      owner.acquire(config('COM3'), _FakeTransport.new);
      await old.close(); // 已释放，幂等无操作
      expect(owner.isLeased('COM3'), isTrue);
    });
  });
}
