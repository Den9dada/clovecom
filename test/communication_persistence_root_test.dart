import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/main.dart';
import 'package:clovecom/src/application/communication_runtime.dart';

import 'support/communication_store.dart'
    show ControlledStore, serialDefinition;

void main() {
  testWidgets('关闭窗口等待配置保存，失败可重试且重复请求只退出一次', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('window_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    var nativeCloses = 0;
    var preventClose = true;
    Future<void> nativeClose() async {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {'eventName': 'close'}),
        ),
        (_) => done.complete(),
      );
      await done.future;
    }

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setPreventClose') {
        preventClose = (call.arguments as Map)['isPreventClose'] as bool;
      }
      if (call.method == 'close') {
        if (!preventClose) nativeCloses++;
        // Windows 放行 WM_CLOSE 时，插件仍会通知 Dart 一次。
        await nativeClose();
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final store = ControlledStore()..failWrites = true;
    final runtime = CommunicationRuntime(configurationStore: store);
    await runtime.initialize();
    await tester.pumpWidget(
      MyApp(runtime: runtime, ownsRuntime: true, manageWindow: true),
    );
    await tester.pump();
    runtime.addConnection(serialDefinition('a'));
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    expect(nativeCloses, 0);
    expect(runtime.configurationError, contains('保存失败'));
    store.failWrites = false;
    final gate = Completer<void>();
    store.writeGate = gate.future;
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await nativeClose();
    expect(nativeCloses, 0);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(nativeCloses, 1);
    expect(preventClose, isFalse);
    final restored = CommunicationRuntime(configurationStore: store);
    await restored.initialize();
    expect(restored.snapshot.connections.map((c) => c.id), ['a']);
    await restored.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
