import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/services/serial/serial_byte_transport.dart';
import 'package:clovecom/services/serial/serial_native_driver.dart';
import 'package:clovecom/services/serial/win32_serial_driver.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/connections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart' show ERROR_SUCCESS, Win32Result;

import 'communication_runtime_test.dart' show eventually;

void main() {
  final loopbackPorts = Platform.environment['CLOVECOM_SERIAL_LOOPBACK_PORTS'];
  test('互连串口双向循环每 10ms 写 10 字节，收发持续且连接保持打开', () async {
    final ports = loopbackPorts!.split(',').map((p) => p.trim()).toList();
    expect(ports, hasLength(2));
    expect(ports.toSet(), hasLength(2));

    final runtime = CommunicationRuntime();
    addTearDown(runtime.dispose);
    for (final port in ports) {
      runtime.addConnection(
        ConnectionDefinition.serial(
          ConnectionConfig(
            id: port,
            protocolId: '',
            kind: TransportKind.serial,
            serialPort: port,
          ),
        ),
      );
      await runtime.openConnection(port);
      expect(runtime.connection(port).connected, isTrue);
    }

    final fault = Completer<String?>();
    final elapsed = Stopwatch()..start();
    void watchConnections() {
      for (final connection in runtime.snapshot.connections) {
        if (!connection.connected && !fault.isCompleted) {
          fault.complete(
            '${connection.id} 在 ${elapsed.elapsedMilliseconds}ms 后断开：${connection.detail}',
          );
        }
      }
    }

    const bytesPerRound = 10;
    final counts = {for (final port in ports) port: 0};
    final writeTimes = {for (final port in ports) port: <int>[]};
    final observers = [
      for (final port in ports)
        runtime.observeSessionWrites(port, (_, _) {
          writeTimes[port]!.add(elapsed.elapsedMicroseconds);
        }),
    ];
    final receive = runtime.packets.listen((packet) {
      counts.update(packet.connectionId, (n) => n + packet.bytes.length);
    });
    runtime.addListener(watchConnections);
    var workspaceNotifications = 0;
    void workspaceChanged() => workspaceNotifications++;
    runtime.workspaceChanges.addListener(workspaceChanged);
    try {
      for (final port in ports) {
        runtime.startLoop(
          port,
          Uint8List.fromList(
            List.generate(bytesPerRound, (index) => 0x30 + index),
          ),
          interval: const Duration(milliseconds: 10),
        );
      }
      final beforeSteadyState = workspaceNotifications;
      expect(
        await fault.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () => null,
        ),
        isNull,
      );
      expect(workspaceNotifications, beforeSteadyState);
      final targets = ports.map((port) => runtime.loopFor(port)!);
      final rounds = {
        for (final target in targets)
          target.connectionId: target.completedRounds,
      };
      expect(rounds.keys, unorderedEquals(ports));
      for (final target in targets) {
        expect(target.phase, isNot(LoopPhase.stopped), reason: target.reason);

        expect(target.lastResult?.outcome, SendOutcome.succeeded);
      }
      final seconds =
          elapsed.elapsedMicroseconds / Duration.microsecondsPerSecond;
      for (final port in ports) {
        final stamps = writeTimes[port]!;
        final gaps = [
          for (var i = 1; i < stamps.length; i++) stamps[i] - stamps[i - 1],
        ]..sort();
        final rate = rounds[port]! / seconds;
        final rx = counts[port]!;
        stdout.writeln(
          '$port: ${rate.toStringAsFixed(2)} 轮/秒，'
          '完成 ${rounds[port]} 轮，收到 $rx 字节，'
          '确认间隔 p50/p95 ${gaps[gaps.length ~/ 2]}/${gaps[gaps.length * 95 ~/ 100]} 微秒',
        );
      }
      for (final port in ports) {
        expect(rounds[port]! / seconds, greaterThanOrEqualTo(92), reason: port);
        expect(
          counts[port]! / seconds,
          greaterThanOrEqualTo(920),
          reason: port,
        );
      }
    } finally {
      runtime.removeListener(watchConnections);
      runtime.workspaceChanges.removeListener(workspaceChanged);
      for (final port in ports) {
        runtime.stopLoop(port);
      }
      for (final stop in observers) {
        stop();
      }
      await receive.cancel();
    }
  }, skip: !Platform.isWindows || loopbackPorts == null);

  test('原生缓冲扩容后继续正确收发，未领取的读仍阻止关闭', () async {
    final ports = loopbackPorts!.split(',').map((port) => port.trim()).toList();
    expect(ports, hasLength(2));
    final sender = Win32SerialDriver();
    final receiver = Win32SerialDriver();
    addTearDown(sender.close);
    addTearDown(receiver.close);
    sender.open(SerialPortConfig(portName: ports[0], baudRate: 115200));
    receiver.open(SerialPortConfig(portName: ports[1], baudRate: 115200));

    Future<SerialNativeCompletion> collect(
      SerialNativeCompletion Function() poll,
    ) async {
      final timer = Stopwatch()..start();
      while (timer.elapsed < const Duration(seconds: 3)) {
        final result = poll();
        if (!result.pending) return result;
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw StateError('原生操作未终结');
    }

    for (final (index, length) in [3, 615, 23, 1025, 2, 917].indexed) {
      final bytes = Uint8List.fromList(
        List.generate(length, (i) => (i + index) & 255),
      );
      sender.startWrite(bytes);
      expect(() => sender.close(), throwsStateError);
      expect((await collect(sender.pollWrite)).count, length);
      final received = <int>[];
      final timer = Stopwatch()..start();
      while (received.length < length &&
          timer.elapsed < const Duration(seconds: 3)) {
        receiver.startRead(length - received.length + 1);
        final completed = await collect(receiver.pollRead);
        expect(completed.error, isNull);
        expect(receiver.close, throwsStateError);
        expect(
          () => receiver.takeReadBytes(completed.count! + 1),
          throwsRangeError,
        );
        if (length == 1025 && received.isEmpty && completed.count! > 0) {
          final merged = receiver.takeReadBytes(
            completed.count!,
            prefix: Uint8List.fromList([0xfe]),
          );
          expect(merged.length, completed.count! + 1);
          expect(merged.first, 0xfe);
          received.addAll(merged.skip(1));
        } else {
          received.addAll(receiver.takeReadBytes(completed.count!));
        }
        if (completed.count == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      expect(received, bytes);
    }
  }, skip: !Platform.isWindows || loopbackPorts == null);

  test('真实接收端空闲超时、清空后仍可读，关闭期间回收预投递读', () async {
    final ports = loopbackPorts!.split(',').map((port) => port.trim()).toList();
    final sender = await Win32SerialTransport.open(
      SerialPortConfig(portName: ports.first, baudRate: 115200),
    );
    addTearDown(sender.close);
    final receiver = await Win32SerialTransport.open(
      SerialPortConfig(portName: ports.last, baudRate: 115200),
    );
    addTearDown(receiver.close);
    final received = <int>[];
    final errors = <Object>[];
    final sub = receiver.chunks.listen(
      received.addAll,
      onError: (Object error) => errors.add(error),
    );
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(received, isEmpty);
    expect(errors, isEmpty);
    for (final message in [
      [1, 2, 3],
      List<int>.generate(8192, (index) => index & 255),
      [4, 5, 6, 7],
    ]) {
      final result = await sender.send(Uint8List.fromList(message), 1000);
      expect(result.acceptedBytes, message.length);
      await result.settled;
      await eventually(() => received.length == message.length);
      expect(received, message);
      received.clear();
      receiver.purge();
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
    await receiver.close().timeout(const Duration(seconds: 2));
    expect(errors, isEmpty);
  }, skip: !Platform.isWindows || loopbackPorts == null);
  test('1ms 循环在界面 isolate 忙碌期间继续写入并补齐确认记录', () async {
    const id = 'worker-clock';
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async => SerialCommunicationTransport(
        await Win32SerialTransport.open(
          serialViewConfig(definition.serial!),
          driverFactory: immediateDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition(id));
    await runtime.openConnection(id);
    final first = Completer<void>();
    final stopped = Completer<void>();
    final writes = <DateTime>[];
    final unsubscribe = runtime.observeTimedSessionWrites(id, (
      bytes,
      epoch,
      time,
    ) {
      expect(bytes, [0x41]);
      writes.add(time);
      if (!first.isCompleted) first.complete();
    });
    addTearDown(unsubscribe);
    runtime.addListener(() {
      final loop = runtime.loopFor(id);
      if (loop?.phase == LoopPhase.stopped &&
          loop?.awaitingSettlement == false &&
          !stopped.isCompleted) {
        stopped.complete();
      }
    });
    runtime.startLoop(
      id,
      Uint8List.fromList([0x41]),
      interval: const Duration(milliseconds: 1),
    );
    await first.future.timeout(const Duration(seconds: 2));
    // 界面长时间不处理回执时，worker 的有界批次会满，
    // 清空回执后必须能恢复发包。
    sleep(const Duration(milliseconds: 245));
    final resumedAt = DateTime.now();
    final resumed = Completer<void>();
    void watchResume() {
      if (!resumed.isCompleted && writes.last.isAfter(resumedAt)) {
        resumed.complete();
      }
    }

    runtime.addListener(watchResume);
    try {
      await resumed.future.timeout(const Duration(seconds: 2));
    } finally {
      runtime.removeListener(watchResume);
    }

    final before = writes.length;
    sleep(const Duration(milliseconds: 65));
    runtime.stopLoop(id);
    await stopped.future.timeout(const Duration(seconds: 2));
    expect(writes.length - before, greaterThan(25));
    expect(runtime.loopFor(id)?.completedRounds, writes.length);
    expect(runtime.connection(id).connected, isTrue);
  }, skip: !Platform.isWindows);

  test('预设的下一拍等上一笔原生写终结，期间不会重叠发起', () async {
    const id = 'worker-pending-tick';
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async => SerialCommunicationTransport(
        await Win32SerialTransport.open(
          serialViewConfig(definition.serial!),
          driverFactory: _delayedLoopDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition(id));
    await runtime.openConnection(id);
    final written = <int>[];
    final checked = Completer<void>();
    addTearDown(
      runtime.observeSessionWrites(id, (bytes, _) {
        written.add(bytes.single);
        if (written.length == 8) checked.complete();
      }),
    );
    runtime.startLoop(
      id,
      Uint8List.fromList([0x41]),
      interval: const Duration(milliseconds: 1),
    );
    await checked.future.timeout(const Duration(seconds: 2));
    expect(written.every((byte) => byte == 0x41), isTrue);
    expect(runtime.connection(id).connected, isTrue);
    expect(runtime.loopFor(id)?.workerTiming?.rearmSkipped, greaterThan(0));
    runtime.stopLoop(id);
  }, skip: !Platform.isWindows);
  test('工作 isolate 写入超过超时后停止循环并保留实际确认字节', () async {
    const id = 'worker-timeout';
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async => SerialCommunicationTransport(
        await Win32SerialTransport.open(
          serialViewConfig(definition.serial!),
          driverFactory: blockingDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition(id));
    await runtime.openConnection(id);
    final confirmed = <int>[];
    final unsubscribe = runtime.observeSessionWrites(
      id,
      (bytes, _) => confirmed.addAll(bytes),
    );
    addTearDown(unsubscribe);
    final stopped = Completer<void>();
    runtime.addListener(() {
      if (runtime.loopFor(id)?.phase == LoopPhase.stopped &&
          !stopped.isCompleted) {
        stopped.complete();
      }
    });
    runtime.startLoop(
      id,
      Uint8List.fromList([0x41]),
      interval: const Duration(milliseconds: 1),
      timeoutMs: 20,
    );
    await stopped.future.timeout(const Duration(seconds: 3));
    expect(runtime.loopFor(id)?.reason, contains('超时'));
    expect(runtime.loopFor(id)?.completedRounds, 1);
    expect(confirmed, [0x41]);
    expect(runtime.connection(id).connected, isTrue);
  }, skip: !Platform.isWindows);

  test('工作 isolate 循环向手动 FIFO 和协议任务交接发送权', () async {
    const id = 'worker-handoff';
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async => SerialCommunicationTransport(
        await Win32SerialTransport.open(
          serialViewConfig(definition.serial!),
          driverFactory: immediateDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition(id));
    await runtime.openConnection(id);
    final writes = <int>[];
    final started = Completer<void>();
    final resumed = Completer<void>();
    final unsubscribe = runtime.observeSessionWrites(id, (bytes, epoch) {
      writes.add(bytes.single);
      if (!started.isCompleted) started.complete();
      if (writes.contains(0x4e) &&
          bytes.single == 0x41 &&
          !resumed.isCompleted) {
        resumed.complete();
      }
    });
    addTearDown(unsubscribe);
    runtime.startLoop(
      id,
      Uint8List.fromList([0x41]),
      interval: const Duration(milliseconds: 1),
    );
    await started.future.timeout(const Duration(seconds: 2));
    final manual = await Future.wait([
      runtime.writeTo(id, Uint8List.fromList([0x4d])),
      runtime.writeTo(id, Uint8List.fromList([0x4e])),
    ]).timeout(const Duration(seconds: 2));
    expect(manual.every((result) => result.succeeded), isTrue);
    await resumed.future.timeout(const Duration(seconds: 2));
    final task = runtime
        .beginProtocolTask(id, ProtocolTaskKind.fileSend)!
        .channel!;
    try {
      final result = await task
          .write(Uint8List.fromList([0x50]))
          .timeout(const Duration(seconds: 2));
      expect(result.succeeded, isTrue);
      expect(writes.indexOf(0x4e), writes.indexOf(0x4d) + 1);
      expect(writes.last, 0x50);
      expect(runtime.loopFor(id)?.phase, LoopPhase.stopped);
      expect(runtime.loopFor(id)?.awaitingSettlement, isFalse);
    } finally {
      await task.cancel();
    }
  }, skip: !Platform.isWindows);

  test('原生查询偶发返回 FALSE 和错误码 0 时，循环继续且每轮只确认一次', () async {
    const id = 'ambiguous';
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async => SerialCommunicationTransport(
        await Win32SerialTransport.open(
          serialViewConfig(definition.serial!),
          driverFactory: _ambiguousCompletionDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition(id));
    await runtime.openConnection(id);
    final rounds = Completer<void>();
    final confirmed = <List<int>>[];
    final stopWatchingWrites = runtime.observeSessionWrites(
      id,
      (bytes, _) => confirmed.add(bytes),
    );
    void onChange() {
      if (!rounds.isCompleted &&
          (runtime.loopFor(id)?.completedRounds ?? 0) >= 3) {
        rounds.complete();
      }
    }

    runtime.addListener(onChange);
    try {
      runtime.startLoop(
        id,
        Uint8List.fromList([0x31, 0x32]),
        interval: const Duration(milliseconds: 10),
      );
      await rounds.future.timeout(const Duration(seconds: 3));
      expect(runtime.connection(id).connected, isTrue);
      expect(runtime.loopFor(id)?.lastResult?.outcome, SendOutcome.succeeded);
      expect(confirmed, [
        [0x31, 0x32],
        [0x31, 0x32],
        [0x31, 0x32],
      ]);
    } finally {
      runtime.stopLoop(id);
      runtime.removeListener(onChange);
      stopWatchingWrites();
    }
  });

  test('串口打开前后发送都保留调用时的字节快照', () async {
    final transport = Win32SerialTransport(
      SerialPortConfig(portName: 'TEST_SNAPSHOT'),
      driverFactory: _snapshotWriteDriver,
    );
    addTearDown(transport.close);
    for (var round = 0; round < 2; round++) {
      final bytes = Uint8List.fromList([0x41]);
      final result = transport.send(bytes, 1000);
      bytes[0] = 0xff;
      final outcome = await result;
      expect(outcome.acceptedBytes, 1);
      expect(outcome.succeeded, isTrue);
      expect(outcome.needsSettlement, isFalse);
      await outcome.settled;
    }
  });

  test('真实 worker 中原生发起同步阻塞时，界面和其他连接仍可推进', () async {
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => SerialCommunicationTransport(
        await Win32SerialTransport.open(
          serialViewConfig(d.serial!),
          driverFactory: d.id == 'slow' ? blockingDriver : immediateDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    for (final id in ['slow', 'fast']) {
      runtime.addConnection(serialDefinition(id));
      await runtime.openConnection(id);
    }
    var beats = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => beats++,
    );
    addTearDown(heartbeat.cancel);
    final writing = runtime.writeTo('slow', Uint8List.fromList([1]));
    final clock = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final result = await runtime.writeTo('fast', Uint8List.fromList([2]));
    expect(result.succeeded, isTrue);
    expect(clock.elapsedMilliseconds, lessThan(250));
    expect(beats, greaterThanOrEqualTo(2));
    expect((await writing).acceptedBytes, 1);
  });
  test('暂停再恢复接收后继续完整交付，不在暂停流里累积批次', () async {
    final transport = await Win32SerialTransport.open(
      SerialPortConfig(portName: 'TEST_RX'),
      driverFactory: continuousRxDriver,
    );
    addTearDown(transport.close);
    final received = <int>[];
    late StreamSubscription<Uint8List> subscription;
    subscription = transport.chunks.listen((bytes) {
      received.addAll(bytes);
      if (received.length == 1) subscription.pause();
    });
    addTearDown(subscription.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(received, [1]);
    subscription.resume();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(received.take(3), [1, 2, 3]);
  });
  test('pending 写入期间同连接接收与定向取消继续，后续FIFO等待原生终结', () async {
    late SerialCommunicationTransport transport;
    final runtime = CommunicationRuntime(
      transportFactory: (d) async {
        return transport = SerialCommunicationTransport(
          await Win32SerialTransport.open(
            serialViewConfig(d.serial!),
            driverFactory: pendingDriver,
          ),
        );
      },
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition('pending'));
    await runtime.openConnection('pending');
    final received = <int>[];
    final subscription = runtime.packets.listen(
      (packet) => received.addAll(packet.bytes),
    );
    addTearDown(subscription.cancel);
    final writing = runtime.writeTo('pending', Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(received, contains(0x41));
    var cancelled = false;
    final cancel = (transport as CancellableCommunicationTransport)
        .cancelWrite()
        .then((_) => cancelled = true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(received, contains(0x42));
    expect(cancelled, isFalse);
    var queuedCompleted = false;
    final queued = runtime.writeTo('pending', Uint8List.fromList([9])).then((
      result,
    ) {
      queuedCompleted = true;
      return result;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(queuedCompleted, isFalse);
    expect(cancelled, isFalse);
    await cancel;
    final result = await writing;
    expect(result.succeeded, isFalse);
    expect(result.acceptedBytes, isNull);
    expect((await queued).succeeded, isTrue);
  });
  test('worker 初始化失败被应用公开状态接住且可重新打开', () async {
    var first = true;
    final runtime = CommunicationRuntime(
      transportFactory: (d) async {
        final factory = first ? failingDriverFactory : immediateDriver;
        first = false;
        return SerialCommunicationTransport(
          await Win32SerialTransport.open(
            serialViewConfig(d.serial!),
            driverFactory: factory,
          ),
        );
      },
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition('open'));
    await expectLater(runtime.openConnection('open'), throwsStateError);
    expect(runtime.connection('open').phase, ConnectionPhase.failed);
    await runtime.openConnection('open');
    expect(runtime.connection('open').writable, isTrue);
  }, timeout: const Timeout(Duration(seconds: 3)));
  test('兼容串口适配器未提供取消能力时也等待原生 settled', () async {
    final native = DeferredSerialTransport();
    final transport = SerialCommunicationTransport(native);
    final result = await transport.write(Uint8List.fromList([1]), 10);
    expect(result.acceptedBytes, isNull);
    var cancelled = false;
    final cancel = transport.cancelWrite().then((_) => cancelled = true);
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isFalse);
    native.settled.complete();
    await cancel;
    expect(cancelled, isTrue);
  });
  test('短写通过应用入口返回可证实数量且不透明重发', () async {
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => SerialCommunicationTransport(
        await Win32SerialTransport.open(
          serialViewConfig(d.serial!),
          driverFactory: shortDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition('short'));
    await runtime.openConnection('short');
    final result = await runtime.writeTo(
      'short',
      Uint8List.fromList([1, 2, 3]),
    );
    expect(result.succeeded, isFalse);
    expect(result.acceptedBytes, 2);
    expect(result.reason, contains('短写'));
  });

  test('超时结果先到，取消后迟到正常完成不改结果或提前释放', () async {
    final transport = await Win32SerialTransport.open(
      SerialPortConfig(portName: 'TEST_TIMEOUT'),
      driverFactory: cancelRaceDriver,
    );
    addTearDown(transport.close);
    final subscription = transport.chunks.listen((_) {});
    addTearDown(subscription.cancel);
    final result = await transport.send(Uint8List.fromList([1, 2, 3]), 25);
    expect(result.succeeded, isFalse);
    expect(result.acceptedBytes, isNull);
    expect(result.reason, contains('超时'));
    var settled = false;
    result.settled.then((_) => settled = true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(settled, isFalse);
    expect(
      (await transport.send(Uint8List.fromList([9]), 1000)).acceptedBytes,
      0,
    );
    await result.settled;
    expect(result.acceptedBytes, isNull);
    expect(
      (await transport.send(Uint8List.fromList([9]), 1000)).succeeded,
      isTrue,
    );
  });

  test('关闭等待读写分别取消终结，重复关闭共用释放屏障', () async {
    late Win32SerialTransport native;
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => SerialCommunicationTransport(
        native = await Win32SerialTransport.open(
          serialViewConfig(d.serial!),
          driverFactory: pendingReadWriteDriver,
        ),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.addConnection(serialDefinition('close'));
    await runtime.openConnection('close');
    final writing = runtime.writeTo('close', Uint8List.fromList([1]));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    var closed = false;
    final closing = runtime.closeConnection('close').then((_) => closed = true);
    final sameClose = native.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(closed, isFalse);
    expect(runtime.connection('close').phase, ConnectionPhase.closing);
    await closing;
    await sameClose;
    expect(runtime.connection('close').phase, ConnectionPhase.closed);
    expect((await writing).succeeded, isFalse);
  });

  test('串口 worker 拒绝超大写，保留正常小写入能力', () async {
    final transport = await Win32SerialTransport.open(
      SerialPortConfig(portName: 'TEST_BUDGET'),
      driverFactory: immediateDriver,
    );
    addTearDown(transport.close);
    final result = await transport.send(
      Uint8List(Win32SerialTransport.maxWriteBytes + 1),
      1000,
    );
    expect(result.acceptedBytes, 0);
    expect(result.reason, contains('上限'));
    expect(
      (await transport.send(Uint8List.fromList([1]), 1000)).succeeded,
      isTrue,
    );
  });
  test('遗留异步构造在打开失败后迟订阅仍收到故障并结束', () async {
    final transport = Win32SerialTransport(
      SerialPortConfig(portName: 'TEST_FAILED'),
      driverFactory: failingDriverFactory,
    );
    await transport.close();
    await expectLater(transport.chunks.toList(), throwsStateError);
  });
}

ConnectionDefinition serialDefinition(String id) => ConnectionDefinition.serial(
  serialConnectionConfig(id, SerialPortConfig(portName: 'TEST_$id')),
);

SerialNativeDriver blockingDriver() => ScriptedSerialDriver(blockWriteMs: 400);
SerialNativeDriver immediateDriver() => ScriptedSerialDriver();

class ScriptedSerialDriver implements SerialNativeDriver {
  ScriptedSerialDriver({this.blockWriteMs = 0});
  final int blockWriteMs;
  int length = 0;
  @override
  void open(SerialPortConfig config) {}
  @override
  int get availableBytes => 0;
  @override
  void startWrite(Uint8List bytes) {
    if (blockWriteMs > 0) sleep(Duration(milliseconds: blockWriteMs));
    length = bytes.length;
  }

  @override
  SerialNativeCompletion pollWrite() =>
      SerialNativeCompletion.completed(length);
  @override
  void startRead(int maxBytes) {}
  @override
  SerialNativeCompletion pollRead() =>
      const SerialNativeCompletion.completed(0);
  @override
  Uint8List takeReadBytes(int count) => Uint8List(count);
  @override
  void cancelWrite() {}
  @override
  void cancelRead() {}
  @override
  void purge() {}
  @override
  void close() {}
}

SerialNativeDriver _snapshotWriteDriver() => _SnapshotWriteDriver();

class _SnapshotWriteDriver extends ScriptedSerialDriver {
  @override
  void startWrite(Uint8List bytes) {
    if (bytes.single != 0x41) {
      throw StateError('发起写入后，源缓冲区的修改污染了已发送数据');
    }
    super.startWrite(bytes);
  }
}

SerialNativeDriver _delayedLoopDriver() => _DelayedLoopDriver();

class _DelayedLoopDriver extends ScriptedSerialDriver {
  final _clock = Stopwatch()..start();
  int? _endAt;

  @override
  void startWrite(Uint8List bytes) {
    if (_endAt != null) throw StateError('上一笔写入仍在途');
    super.startWrite(bytes);
    _endAt = _clock.elapsedMicroseconds + 3500;
  }

  @override
  SerialNativeCompletion pollWrite() {
    if (_clock.elapsedMicroseconds < _endAt!) {
      return const SerialNativeCompletion.pending();
    }
    _endAt = null;
    return super.pollWrite();
  }

  @override
  void cancelWrite() {
    if (_endAt != null) _endAt = _clock.elapsedMicroseconds;
  }
}

SerialNativeDriver _ambiguousCompletionDriver() => _AmbiguousCompletionDriver();

class _AmbiguousCompletionDriver extends ScriptedSerialDriver {
  bool _firstQuery = false;

  @override
  void startWrite(Uint8List bytes) {
    super.startWrite(bytes);
    _firstQuery = true;
  }

  @override
  SerialNativeCompletion pollWrite() {
    final ambiguous = _firstQuery;
    _firstQuery = false;
    return interpretSerialOverlappedResult(
      Win32Result(value: !ambiguous, error: ERROR_SUCCESS),
      length,
      length,
    );
  }
}

SerialNativeDriver continuousRxDriver() => ContinuousRxDriver();

class ContinuousRxDriver extends ScriptedSerialDriver {
  int sequence = 0;
  @override
  int get availableBytes => 1;
  @override
  SerialNativeCompletion pollRead() =>
      const SerialNativeCompletion.completed(1);
  @override
  Uint8List takeReadBytes(int count) => Uint8List.fromList([++sequence]);
}

SerialNativeDriver pendingDriver() => PendingSerialDriver();

class PendingSerialDriver extends ScriptedSerialDriver {
  final clock = Stopwatch()..start();
  int writes = 0;
  int? cancelledAt;
  bool pending = false;
  int rxSequence = 0;
  @override
  void startWrite(Uint8List bytes) {
    super.startWrite(bytes);
    pending = ++writes == 1;
  }

  @override
  SerialNativeCompletion pollWrite() {
    if (!pending) return super.pollWrite();
    if (cancelledAt == null || clock.elapsedMilliseconds - cancelledAt! < 180) {
      return const SerialNativeCompletion.pending();
    }
    pending = false;
    return const SerialNativeCompletion.failed('原生取消已完成');
  }

  @override
  void cancelWrite() {
    cancelledAt ??= clock.elapsedMilliseconds;
  }

  @override
  int get availableBytes =>
      writes > 0 &&
          (rxSequence == 0 || (rxSequence == 1 && cancelledAt != null))
      ? 1
      : 0;
  @override
  SerialNativeCompletion pollRead() =>
      const SerialNativeCompletion.completed(1);
  @override
  Uint8List takeReadBytes(int count) =>
      Uint8List.fromList([0x41 + rxSequence++]);
  @override
  void close() {
    if (pending) throw StateError('原生写缓冲仍被访问，禁止释放');
  }
}

SerialNativeDriver failingDriverFactory() => throw StateError('驱动初始化失败');

class DeferredSerialTransport implements SerialByteTransport {
  final settled = Completer<void>();
  @override
  Stream<Uint8List> get chunks => const Stream.empty();
  @override
  Future<SerialWriteResult> send(Uint8List bytes, int timeoutMs) async =>
      SerialWriteResult.failure('超时', settled: settled.future);
  @override
  void purge() {}
  @override
  Future<void> close() => settled.future;
}

SerialNativeDriver shortDriver() => ShortSerialDriver();

class ShortSerialDriver extends ScriptedSerialDriver {
  @override
  SerialNativeCompletion pollWrite() =>
      SerialNativeCompletion.completed(length - 1);
}

SerialNativeDriver cancelRaceDriver() => CancelRaceDriver();

class CancelRaceDriver extends PendingSerialDriver {
  @override
  SerialNativeCompletion pollWrite() {
    final result = super.pollWrite();
    return result.error == null
        ? result
        : SerialNativeCompletion.completed(length);
  }
}

SerialNativeDriver pendingReadWriteDriver() => PendingReadWriteDriver();

class PendingReadWriteDriver extends PendingSerialDriver {
  bool reading = false;
  int? readCancelledAt;
  @override
  int get availableBytes => 1;
  @override
  void startRead(int maxBytes) {
    reading = true;
  }

  @override
  SerialNativeCompletion pollRead() {
    if (readCancelledAt == null ||
        clock.elapsedMilliseconds - readCancelledAt! < 260) {
      return const SerialNativeCompletion.pending();
    }
    reading = false;
    return const SerialNativeCompletion.failed('原生读取消已完成');
  }

  @override
  void cancelRead() {
    readCancelledAt ??= clock.elapsedMilliseconds;
  }

  @override
  void close() {
    super.close();
    if (reading) throw StateError('原生读缓冲仍被访问，禁止释放');
  }
}
