import 'dart:async';
import 'dart:typed_data';
import 'package:clovecom/services/serial/serial_transfer_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('三个任务入口共用独占规则', () {
    final controller = SerialTransferController();
    for (final kind in SerialTransferKind.values) {
      final session = controller.begin(kind, write: (_, _) => true);
      for (final next in SerialTransferKind.values) {
        expect(
          () => controller.begin(next, write: (_, _) => true),
          throwsStateError,
        );
      }
      session.finish();
      expect(controller.isBusy, isFalse);
    }
  });
  test('字节与整块交替读取不丢失剩余数据', () async {
    final controller = SerialTransferController();
    final session = controller.begin(
      SerialTransferKind.receive,
      write: (_, _) => true,
    );
    controller.accept(Uint8List.fromList([6, 0x43, 0xFF]));
    expect(await session.readByte(100), 6);
    expect(await session.readData(100), [0x43, 0xFF]);
    final pending = session.readByte(100);
    controller.accept(Uint8List.fromList([9, 8]));
    expect(await pending, 9);
    expect(await session.readByte(100), 8);
    session.finish();
  });
  test('取消解除等待、立即停止写入并只清理一次', () async {
    final controller = SerialTransferController();
    var writes = 0, cleanups = 0;
    final session = controller.begin(
      SerialTransferKind.send,
      write: (_, _) {
        writes++;
        return true;
      },
    );
    session.addCleanup(() => cleanups++);
    final pending = session.readByte(10000);
    session.cancel();
    session.cancel();
    session.finish();
    expect(await pending, isNull);
    expect(session.write(Uint8List.fromList([1]), 100), isFalse);
    expect(writes, 0);
    expect(cleanups, 1);
  });
  test('旧任务异步恢复和回调不能污染新会话', () async {
    final controller = SerialTransferController();
    final loaded = Completer<void>();
    var events = 0, writes = 0;
    final old = controller.begin(
      SerialTransferKind.send,
      write: (_, _) {
        writes++;
        return true;
      },
    );
    final callbacks = old.callbacks(
      onProgress: (_) => events++,
      onLog: (_) => events++,
      onError: (_) => events++,
      onComplete: (_) => events++,
    );
    final resume = () async {
      await loaded.future;
      old.write(Uint8List.fromList([1]), 100);
      callbacks.onComplete(1);
      callbacks.onError('晚到错误');
      old.finish();
    }();
    old.cancel();
    final next = controller.begin(
      SerialTransferKind.receive,
      write: (_, _) => true,
    );
    loaded.complete();
    await resume;
    expect(next.isActive, isTrue);
    expect(events, 0);
    expect(writes, 0);
    next.finish();
  });
  test('失败后不允许再完成，完成事件只报告一次', () {
    final controller = SerialTransferController();
    final session = controller.begin(
      SerialTransferKind.send,
      write: (_, _) => false,
    );
    var successes = 0, errors = 0;
    final callbacks = session.callbacks(
      onProgress: (_) {},
      onLog: (_) {},
      onError: (_) => errors++,
      onComplete: (_) => successes++,
    );
    callbacks.onError('短写');
    callbacks.onComplete(2);
    callbacks.onError('重复');
    expect(errors, 1);
    expect(successes, 0);
    expect(callbacks.isCancelled(), isTrue);
    session.finish();
    final next = controller.begin(
      SerialTransferKind.send,
      write: (_, _) => true,
    );
    final done = next.callbacks(
      onProgress: (_) {},
      onLog: (_) {},
      onError: (_) {},
      onComplete: (_) => successes++,
    );
    done.onComplete(2);
    done.onComplete(2);
    expect(successes, 1);
    next.finish();
  });
  test('固件原始字节不经过日志或文本编码', () {
    final controller = SerialTransferController();
    final session = controller.begin(
      SerialTransferKind.firmware,
      write: (_, _) => true,
    );
    Uint8List? received;
    session.onData = (data) => received = data;
    final bytes = Uint8List.fromList([0, 0xFF, 0xC0, 0x80]);
    controller.accept(bytes);
    bytes[0] = 7;
    expect(received, [0, 0xFF, 0xC0, 0x80]);
    session.cancel();
    expect(controller.accept(bytes), isFalse);
  });
  test('超时不会吞掉稍后到达的数据，取消中断发送间隔', () async {
    final controller = SerialTransferController();
    final session = controller.begin(
      SerialTransferKind.send,
      write: (_, _) => true,
    );
    expect(await session.readByte(1), isNull);
    controller.accept(Uint8List.fromList([6]));
    expect(await session.readByte(10), 6);
    final delay = session.delay(const Duration(seconds: 30));
    session.cancel();
    await delay.timeout(const Duration(seconds: 1));
  });
}
