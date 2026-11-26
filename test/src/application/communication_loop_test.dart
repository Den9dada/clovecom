import 'package:clovecom/src/application/communication_transport.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_transports.dart'
    show add, RecordingTransport, CancelTransport, DelayedResultTransport;
import 'communication_runtime_test.dart' show eventually;

void main() {
  test('观察到开始发送后立即停止仍能定向取消该在途写', () async {
    final transport = CancelTransport();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    addTearDown(runtime.dispose);
    add(runtime, 'a');
    await runtime.openConnection('a');
    runtime.addListener(() {
      if (runtime.loopFor('a')?.phase == LoopPhase.running) {
        runtime.stopLoop('a');
      }
    });
    runtime.startLoop(
      'a',
      Uint8List.fromList([1]),
      interval: const Duration(milliseconds: 20),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.cancelled, 1);
    expect(runtime.loopFor('a')!.awaitingSettlement, isTrue);
    transport.finish();
    await eventually(() => !runtime.loopFor('a')!.awaitingSettlement);
    expect(transport.written, [
      [1],
    ]);
  });
  test('写结果仍悬挂时明确断开直接推进close，旧结束异常不影响重启', () async {
    final old = DelayedResultTransport();
    final fresh = RecordingTransport()..finish();
    var opens = 0;
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => ++opens == 1 ? old : fresh,
    );
    addTearDown(runtime.dispose);
    add(runtime, 'a');
    await runtime.openConnection('a');
    runtime.startLoop(
      'a',
      Uint8List.fromList([1]),
      interval: const Duration(milliseconds: 20),
    );
    await runtime
        .closeConnection('a')
        .timeout(const Duration(milliseconds: 100));
    await eventually(() => !runtime.loopFor('a')!.awaitingSettlement);
    expect(runtime.loopFor('a')!.phase, LoopPhase.stopped);
    await runtime.openConnection('a');
    runtime.startLoop(
      'a',
      Uint8List.fromList([2]),
      interval: const Duration(milliseconds: 20),
    );
    final broken = Completer<void>();
    old.pending.complete(
      SerialWriteResult.failure('旧写失败', settled: broken.future),
    );
    await Future<void>.delayed(Duration.zero);
    broken.completeError(StateError('旧证明失败'));
    await eventually(
      () =>
          runtime.loopFor('a')!.completedRounds >= 2 &&
          !runtime.loopFor('a')!.awaitingSettlement,
    );
    expect(runtime.loopFor('a')!.phase, LoopPhase.waiting);
    expect(runtime.loopFor('a')!.lastResult?.outcome, SendOutcome.succeeded);
    runtime.stopLoop('a');
  });
  test('停止的取消失败保持结束待确认且可见，重新启动不继承旧取消故障', () async {
    final transport = LateCancelTransport();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    addTearDown(runtime.dispose);
    add(runtime, 'a');
    await runtime.openConnection('a');
    runtime.startLoop(
      'a',
      Uint8List.fromList([1]),
      interval: const Duration(milliseconds: 20),
    );
    runtime.stopLoop('a');
    transport.cancel.completeError(StateError('取消失败'));
    await eventually(
      () => runtime.loopFor('a')!.reason?.contains('取消失败') == true,
    );
    expect(runtime.loopFor('a')!.awaitingSettlement, isTrue);
    expect(transport.closed, isFalse);
    runtime.startLoop(
      'a',
      Uint8List.fromList([2]),
      interval: const Duration(milliseconds: 20),
    );
    transport.finish();
    await eventually(() => runtime.loopFor('a')!.completedRounds >= 1);
    expect(runtime.loopFor('a')!.reason, isNull);
    runtime.stopLoop('a');
  });
  test('更新循环负载只作用于下一轮，清空不续发旧命令', () async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    addTearDown(runtime.dispose);
    add(runtime, 'a');
    await runtime.openConnection('a');
    runtime.startLoop(
      'a',
      Uint8List.fromList([10, 255, 13]),
      interval: const Duration(milliseconds: 20),
    );
    await eventually(() => transport.written.length == 1);
    expect(transport.written.single, [10, 255, 13]);
    runtime.updateLoopData('a', Uint8List.fromList([10, 255, 13, 10]));
    await eventually(() => transport.written.length == 2);
    expect(transport.written.last, [10, 255, 13, 10]);
    runtime.updateLoopData('a', Uint8List(0));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.written.length, 2);
    runtime.stopLoop('a');
  });
  test('停止只清本次循环的排队工作，不关闭连接也不误删手动发送', () async {
    final transport = RecordingTransport();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    addTearDown(runtime.dispose);
    add(runtime, 'a');
    await runtime.openConnection('a');
    final first = runtime.writeTo('a', Uint8List.fromList([1]));
    runtime.startLoop(
      'a',
      Uint8List.fromList([9]),
      interval: const Duration(milliseconds: 20),
    );
    expect(runtime.loopFor('a')!.phase, LoopPhase.delayed);
    runtime.stopLoop('a');
    final after = runtime.writeTo('a', Uint8List.fromList([2]));
    transport.finish();
    await first;
    await after;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.written, [
      [1],
      [2],
    ]);
    expect(transport.closed, isFalse);
    expect(runtime.connection('a').connected, isTrue);
    expect(runtime.loopFor('a')!.phase, LoopPhase.stopped);
    expect(runtime.loopFor('a')!.lastResult?.outcome, SendOutcome.notExecuted);
  });

  test('循环只在明确启动的连接上运行，停止后其他连接继续', () async {
    final transports = {
      for (final id in ['a', 'b', 'c']) id: RecordingTransport()..finish(),
    };
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => transports[d.id]!,
    );
    addTearDown(runtime.dispose);
    for (final id in transports.keys) {
      add(runtime, id);
      await runtime.openConnection(id);
    }
    for (final id in ['a', 'b']) {
      runtime.startLoop(
        id,
        Uint8List.fromList([1]),
        interval: const Duration(milliseconds: 20),
      );
    }
    await eventually(() => transports['b']!.written.length >= 2);
    runtime.stopLoop('a');
    final stoppedCount = transports['a']!.written.length;
    await eventually(() => transports['b']!.written.length >= 4);
    expect(transports['c']!.written, isEmpty);
    expect(transports['a']!.written.length, stoppedCount);
    expect(runtime.loopFor('a')!.phase, LoopPhase.stopped);
    runtime.startLoop(
      'c',
      Uint8List.fromList([2]),
      interval: const Duration(milliseconds: 20),
    );
    await eventually(() => transports['c']!.written.isNotEmpty);
    runtime.stopLoop('c');
    runtime.stopLoop('b');
    expect(transports['c']!.written.single, [2]);
  });

  test('连接断开并重连不复活旧循环，其他连接继续', () async {
    final a = <RecordingTransport>[];
    final b = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (d) async {
        if (d.id == 'b') return b;
        final current = RecordingTransport()..finish();
        a.add(current);
        return current;
      },
    );
    addTearDown(runtime.dispose);
    for (final id in ['a', 'b']) {
      add(runtime, id);
      await runtime.openConnection(id);
    }
    for (final id in ['a', 'b']) {
      runtime.startLoop(
        id,
        Uint8List.fromList([65]),
        interval: const Duration(milliseconds: 20),
      );
    }
    await eventually(() => b.written.length >= 2);
    await runtime.closeConnection('a');
    await runtime.openConnection('a');
    final count = b.written.length;
    await eventually(() => b.written.length >= count + 2);
    expect(a.last.written, isEmpty);
    expect(runtime.loopFor('a')!.phase, LoopPhase.stopped);
    runtime.stopLoop('b');
  });

  test('结果超时与结束异常不再排下一轮，其他目标继续且明确断开才释放', () async {
    final slow = DelayedResultTransport();
    final fast = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => d.id == 'a' ? slow : fast,
    );
    addTearDown(runtime.dispose);
    for (final id in ['a', 'b']) {
      add(runtime, id);
      await runtime.openConnection(id);
    }
    runtime.startLoop(
      'a',
      Uint8List.fromList([1]),
      interval: const Duration(milliseconds: 10),
      timeoutMs: 20,
    );
    runtime.startLoop(
      'b',
      Uint8List.fromList([1]),
      interval: const Duration(milliseconds: 10),
    );
    await eventually(
      () => runtime.loopFor('a')!.lastResult?.outcome == SendOutcome.unknown,
    );
    final broken = Completer<void>();
    slow.pending.complete(
      SerialWriteResult.failure('原生结束未知', settled: broken.future),
    );
    await Future<void>.delayed(Duration.zero);
    broken.completeError(StateError('结束证明失效'));
    await eventually(() => fast.written.length >= 5);
    expect(slow.written, [
      [1],
    ]);
    expect(runtime.loopFor('a')!.phase, LoopPhase.delayed);
    runtime.stopLoop('a');
    expect(runtime.loopFor('a')!.awaitingSettlement, isTrue);
    expect(runtime.connection('a').connected, isTrue);
    await runtime.closeConnection('a');
    await eventually(() => !runtime.loopFor('a')!.awaitingSettlement);
    expect(runtime.loopFor('a')!.phase, LoopPhase.stopped);
    runtime.stopLoop('b');
  });

  test('停止后重启的新运行不被旧结果和取消回调污染', () async {
    final transport = CancelTransport();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    addTearDown(runtime.dispose);
    add(runtime, 'a');
    await runtime.openConnection('a');
    runtime.startLoop(
      'a',
      Uint8List.fromList([1]),
      interval: const Duration(milliseconds: 20),
    );
    runtime.stopLoop('a');
    runtime.startLoop(
      'a',
      Uint8List.fromList([2]),
      interval: const Duration(milliseconds: 20),
    );
    expect(transport.cancelled, 1);
    transport.finish();
    await eventually(() => transport.written.length >= 3);
    runtime.stopLoop('a');
    expect(transport.written.first, [1]);
    expect(transport.written.skip(1).every((b) => b.single == 2), isTrue);
    expect(runtime.loopFor('a')!.completedRounds, greaterThanOrEqualTo(2));
    expect(transport.closed, isFalse);
  });
  test('循环草稿为空时暂停写出，恢复后仅后续轮次使用新内容', () async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    addTearDown(runtime.dispose);
    add(runtime, 'a');
    await runtime.openConnection('a');
    runtime.startLoop(
      'a',
      Uint8List.fromList([1]),
      interval: const Duration(milliseconds: 20),
    );
    await eventually(() => runtime.loopFor('a')!.completedRounds == 1);
    runtime.updateLoopData('a', Uint8List(0));
    await Future<void>.delayed(const Duration(milliseconds: 65));
    expect(transport.written, [
      [1],
    ]);
    final next = Uint8List.fromList([2]);
    runtime.updateLoopData('a', next);
    next[0] = 99;
    await eventually(() => transport.written.length == 2);
    runtime.stopLoop('a');
    expect(transport.written, [
      [1],
      [2],
    ]);
  });
  test('快连接的手动发送和循环不等待慢连接的结束证明', () async {
    final slow = RecordingTransport();
    final fast = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => d.id == 'a' ? slow : fast,
    );
    addTearDown(runtime.dispose);
    for (final id in ['a', 'b']) {
      add(runtime, id);
      await runtime.openConnection(id);
    }
    final payload = Uint8List.fromList([65, 13]);
    runtime.startLoop('a', payload, interval: const Duration(milliseconds: 20));
    runtime.startLoop('b', payload, interval: const Duration(milliseconds: 20));
    final manual = runtime.writeTo('b', Uint8List.fromList([66, 13]));
    expect((await manual).succeeded, isTrue);
    await eventually(() => fast.written.length >= 3);
    expect(slow.written, [
      [65, 13],
    ]);
    runtime.stopLoop('a');
    runtime.stopLoop('b');
    slow.finish();
    await eventually(() => !runtime.loopFor('a')!.awaitingSettlement);
    expect(slow.written, [
      [65, 13],
    ]);
    expect(fast.written, contains(orderedEquals([66, 13])));
  });
  test('慢目标等待原生结束时快目标独立循环，延后可见且不补历史轮次', () async {
    final slow = RecordingTransport();
    final fast = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => d.id == 'a' ? slow : fast,
    );
    addTearDown(runtime.dispose);
    for (final id in ['a', 'b']) {
      add(runtime, id);
      await runtime.openConnection(id);
    }
    final draft = Uint8List.fromList([65]);
    runtime.startLoop('a', draft, interval: const Duration(milliseconds: 20));
    runtime.startLoop('b', draft, interval: const Duration(milliseconds: 20));
    draft[0] = 99;
    await eventually(() => fast.written.length >= 3);
    expect(slow.written, [
      [65],
    ]);
    expect(runtime.loopFor('a')!.phase, LoopPhase.delayed);
    expect(runtime.loopFor('b')!.completedRounds, greaterThanOrEqualTo(2));
    runtime.stopLoop('b');
    slow.finish();
    await eventually(() => slow.written.length == 2);
    runtime.stopLoop('a');
    expect(slow.written, [
      [65],
      [65],
    ]);
  });
}

class LateCancelTransport extends RecordingTransport
    implements CancellableCommunicationTransport {
  final cancel = Completer<void>();
  @override
  Future<void> cancelWrite() => cancel.future;
}
