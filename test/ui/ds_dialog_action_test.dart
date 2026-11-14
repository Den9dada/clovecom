import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/ui/widgets/ds_dialog.dart';

/// DsDialogAction 接口级测试：直接实例化深模块，断言反馈不变量，
/// 不 pump 整页（接口即测试面）。
void main() {
  group('DsDialogAction', () {
    test('成功执行：返回 true，busy 复位，无错误', () async {
      final action = DsDialogAction();
      addTearDown(action.dispose);
      var ran = false;
      final ok = await action.run(() async {
        ran = true;
      });
      expect(ok, isTrue);
      expect(ran, isTrue);
      expect(action.busy, isFalse);
      expect(action.error, isNull);
    });

    test('防重入：忙碌期间二次 run 返回 false 且不执行', () async {
      final action = DsDialogAction();
      addTearDown(action.dispose);
      final gate = Completer<void>();
      var calls = 0;
      final first = action.run(() {
        calls++;
        return gate.future;
      });
      expect(action.busy, isTrue);
      final second = await action.run(() async {
        calls++;
      });
      expect(second, isFalse);
      expect(calls, 1);
      gate.complete();
      expect(await first, isTrue);
      expect(action.busy, isFalse);
    });

    test('失败：返回 false，保留错误并经 onFailed 适配器分发', () async {
      final action = DsDialogAction();
      addTearDown(action.dispose);
      Object? reported;
      final ok = await action.run(
        () async => throw StateError('boom'),
        onFailed: (e) => reported = e,
      );
      expect(ok, isFalse);
      expect(action.error, contains('boom'));
      expect(reported, isA<StateError>());
      expect(action.busy, isFalse);
    });

    test('缺省适配器：错误仅保留，不分发', () async {
      final action = DsDialogAction();
      addTearDown(action.dispose);
      final ok = await action.run(() async => throw 'fail');
      expect(ok, isFalse);
      expect(action.error, 'fail');
    });

    test('清除旧错误：失败后成功 run 清空 error', () async {
      final action = DsDialogAction();
      addTearDown(action.dispose);
      await action.run(() async => throw 'fail');
      expect(action.error, isNotNull);
      await action.run(() async {});
      expect(action.error, isNull);
    });

    test('clearError 清除保留错误', () async {
      final action = DsDialogAction();
      addTearDown(action.dispose);
      await action.run(() async => throw 'fail');
      action.clearError();
      expect(action.error, isNull);
    });

    test('销毁后 run 返回 false 且不通知', () async {
      final action = DsDialogAction();
      var notifications = 0;
      action.addListener(() => notifications++);
      action.dispose();
      final ok = await action.run(() async {});
      expect(ok, isFalse);
      expect(notifications, 0);
    });

    test('busy 与失败均通知监听者', () async {
      final action = DsDialogAction();
      addTearDown(action.dispose);
      var notifications = 0;
      action.addListener(() => notifications++);
      await action.run(() async => throw 'fail');
      expect(notifications, greaterThanOrEqualTo(2));
    });
  });
}