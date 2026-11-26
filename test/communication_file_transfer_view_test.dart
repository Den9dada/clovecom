import 'dart:typed_data';

import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/views/serial_port/serial_port_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/communication_transports.dart' show add;
import 'support/ymodem_device.dart';
import 'support/session_list_actions.dart';
import 'src/application/communication_runtime_test.dart' show eventually;

void main() {
  testWidgets('关闭文件会话只取消并销毁本会话任务', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final devices = {
      'a': YmodemDevice()..holdHeader = true,
      'b': YmodemDevice()..holdHeader = true,
    };
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => devices[d.id]!,
    );
    addTearDown(() => tester.runAsync(runtime.dispose));
    await tester.runAsync(() async {
      for (final id in devices.keys) {
        add(runtime, id);
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<CommunicationRuntime>.value(
        value: runtime,
        child: const MaterialApp(home: Scaffold(body: SerialPortView())),
      ),
    );
    await tester.pumpAndSettle();
    for (final id in devices.keys) {
      await openSessionFromList(tester, id);
    }
    var finished = 0;
    final operations = [
      for (final id in devices.keys)
        runtime.fileTransfers
            .startSend(
              connectionId: id,
              load: () async => Uint8List.fromList([1, 2, 3]),
              fileName: 'same.bin',
            )
            .whenComplete(() => finished++),
    ];
    for (final device in devices.values) {
      device.reply([0x43]);
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(runtime.fileTransfers.targets, hasLength(2));
    expect(find.textContaining('文件发送 · 传输中'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('session-close-a')));
      await eventually(() => runtime.fileTransfers.targets.length == 1);
    });
    await tester.pumpAndSettle();
    expect(runtime.fileTransfers.targets.single.connectionId, 'b');
    expect(
      runtime.fileTransfers.targets.single.phase,
      FileTransferPhase.running,
    );
    expect(runtime.connection('a').phase, ConnectionPhase.closed);
    devices['b']!.reply([6, 0x43]);
    for (var retry = 0; retry < 50 && finished < operations.length; retry++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(finished, operations.length);
    await Future.wait(operations);
    expect(runtime.connection('a').completelyClosed, isTrue);
    expect(
      runtime.fileTransfers.targets.single.phase,
      FileTransferPhase.succeeded,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
