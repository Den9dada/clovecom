import 'dart:io';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/io/interface_params.dart';
import 'package:clovecom/src/io/interface_scan.dart';
import 'package:clovecom/src/io/nic_scanner.dart';
import 'package:clovecom/views/serial_port/serial_port_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'src/application/communication_runtime_test.dart' show FakeTransport;
import 'support/communication_transports.dart' show add;

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _mount(WidgetTester tester, CommunicationRuntime runtime) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(runtime.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<CommunicationRuntime>.value(
      value: runtime,
      child: const MaterialApp(home: Scaffold(body: SerialPortView())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _rightClick(WidgetTester tester, Offset position) async {
  await tester.tapAt(
    position,
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('会话列表可调宽和折叠，支持串口会话的完整右键操作', (tester) async {
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => FakeTransport(),
      interfaceScanner: () async => InterfaceScanResult(
        serialPorts: [
          PortDetailInfo(
            portName: 'COM7',
            friendlyName: '调试接口',
            hardwareID: '',
            manufactureName: '',
          ),
        ],
        nics: const [],
      ),
    );
    await _mount(tester, runtime);

    final list = _key('communication-session-list');
    final initialWidth = tester.getSize(list).width;
    expect(
      find.descendant(of: list, matching: find.textContaining('COM7')),
      findsNothing,
    );
    expect(find.byTooltip('打开连接会话'), findsNothing);
    await tester.drag(_key('session-list-resize'), const Offset(-65, 0));
    await tester.pumpAndSettle();
    final resizedWidth = tester.getSize(list).width;
    expect(resizedWidth, greaterThan(initialWidth));
    await tester.tap(find.byTooltip('折叠会话列表'));
    await tester.pumpAndSettle();
    expect(list, findsNothing);
    await tester.tap(find.byTooltip('展开会话列表'));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, resizedWidth);

    await _rightClick(tester, tester.getCenter(_key('session-list-body')));
    expect(find.bySubtype<PopupMenuItem>(), findsOneWidget);
    await _choose(tester, '新建会话');
    final dialog = _key('session-configuration-dialog');
    expect(tester.getSize(dialog), const Size(620, 600));
    expect(
      ModalRoute.of(tester.element(dialog))!.barrierColor,
      Colors.transparent,
    );
    expect(find.byType(TabBarView), findsOneWidget);
    await tester.tap(_key('connection-serial-interface'));
    await tester.pumpAndSettle();
    await _choose(tester, '串口 · COM7 - 调试接口');
    await tester.enterText(_key('connection-baud'), '9600');
    await _choose(tester, '保存');

    final original = runtime.snapshot.connections.single;
    final listItem = _key('session-list-${original.id}');
    expect(original.name, 'COM7');
    expect(original.definition.serial!.baudRate, 9600);
    final tab = _key('session-tab-${original.id}');
    expect(tab, findsNothing);
    await tester.tap(listItem, kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    final selection = find.descendant(
      of: listItem,
      matching: find.byType(Semantics),
    );
    expect(
      tester
          .widgetList<Semantics>(selection)
          .any((item) => item.properties.selected == true),
      isTrue,
    );
    expect(tab, findsNothing);
    expect(runtime.connection(original.id).completelyClosed, isTrue);

    await _rightClick(tester, tester.getCenter(listItem));
    expect(find.bySubtype<PopupMenuItem>(), findsNWidgets(5));
    for (final label in ['打开会话', '复制会话', '删除会话', '新建会话', '会话配置']) {
      expect(find.text(label), findsOneWidget);
    }
    await _choose(tester, '打开会话');
    expect(tab, findsOneWidget);
    expect(runtime.connection(original.id).connected, isTrue);
    final link = _key('session-link-${original.id}');
    expect(tester.widget<IconButton>(link).onPressed, isNotNull);
    await tester.runAsync(() async {
      await tester.tap(link);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    final disconnected = runtime.connection(original.id);
    expect(
      disconnected.completelyClosed,
      isTrue,
      reason: '${disconnected.phase} ${disconnected.detail}',
    );

    await _rightClick(tester, tester.getCenter(listItem));
    await _choose(tester, '会话配置');
    await tester.enterText(_key('connection-baud'), '57600');
    final colorInput = _key('session-tag-color-input');
    await tester.enterText(colorInput, '#0G0');
    await _choose(tester, '保存');
    expect(find.textContaining('请输入六位十六进制颜色'), findsOneWidget);
    expect(runtime.connection(original.id).definition.serial!.baudRate, 9600);
    await tester.enterText(colorInput, '#123ABC');
    await _choose(tester, '保存');
    const customColor = Color(0xff123abc);
    final icon = _key('session-tab-label-${original.id}');
    final stripe = _key('session-tab-stripe-${original.id}');
    expect(tester.widget<Icon>(icon).color, customColor);
    final decoration = tester.widget<Ink>(stripe).decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, customColor);
    final swatch = _key('session-list-label-${original.id}');
    expect(tester.widget<ColoredBox>(swatch).color, customColor);
    expect(runtime.connection(original.id).definition.serial!.baudRate, 57600);

    await _rightClick(tester, tester.getCenter(listItem));
    await _choose(tester, '复制会话');
    final copy = runtime.snapshot.connections.last;
    expect(copy.id, isNot(original.id));
    final copySwatch = _key('session-list-label-${copy.id}');
    expect(tester.widget<ColoredBox>(copySwatch).color, isNot(customColor));
    expect(copy.name, 'COM7（副本）');
    expect(copy.definition.serial!.serialPort, 'COM7');
    expect(copy.definition.serial!.baudRate, 57600);

    await _rightClick(tester, tester.getCenter(listItem));
    await _choose(tester, '删除会话');
    await _choose(tester, '取消');
    expect(tab, findsOneWidget);

    await _rightClick(tester, tester.getCenter(listItem));
    await _choose(tester, '删除会话');
    await _choose(tester, '删除');
    expect(listItem, findsNothing);
    expect(tab, findsNothing);
    expect(runtime.snapshot.connections.single.id, copy.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('从会话配置选择网卡并保存协议与本地端口', (tester) async {
    final runtime = CommunicationRuntime(
      interfaceScanner: () async => InterfaceScanResult(
        serialPorts: const [],
        nics: [
          NicEndpoint(name: '测试网卡', address: InternetAddress('192.0.2.10')),
        ],
      ),
    );
    await _mount(tester, runtime);

    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    final dialog = _key('session-configuration-dialog');
    final serialBounds = tester.getRect(dialog);
    final baud = _key('connection-baud');
    await tester.enterText(baud, '460800');
    await _choose(tester, '网络');
    expect(find.text('自动重连').hitTestable(), findsOneWidget);
    await _choose(tester, '串口');
    expect(tester.widget<TextFormField>(baud).controller!.text, '460800');
    await _choose(tester, '网络');
    expect(tester.getRect(dialog), serialBounds);
    expect(_key('connection-baud'), findsNothing);
    await tester.tap(_key('connection-network-interface'));
    await tester.pumpAndSettle();
    await _choose(tester, '网卡 · 测试网卡 (192.0.2.10)');
    await tester.tap(_key('connection-protocol'));
    await tester.pumpAndSettle();
    await _choose(tester, 'TCP 服务端');
    await tester.enterText(_key('connection-localPort'), '5500');
    await _choose(tester, '保存');

    final definition = runtime.snapshot.connections.single.definition;
    expect(definition.protocol, InterfaceProtocol.tcpServer);
    expect(definition.tcpServer.nicKey, '192.0.2.10');
    expect(definition.tcpServer.localPort, 5500);
    await _rightClick(
      tester,
      tester.getCenter(_key('session-list-${definition.id}')),
    );
    await _choose(tester, '会话配置');
    expect(tester.getRect(dialog), serialBounds);
    expect(_key('connection-network-interface'), findsOneWidget);
    expect(_key('connection-baud'), findsNothing);
    await _choose(tester, '取消');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点击会话列表项立即更新选中高亮，无需等待双击超时', (tester) async {
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => FakeTransport(),
    );
    add(runtime, 's1');
    add(runtime, 's2');
    await _mount(tester, runtime);

    final colors = Theme.of(
      tester.element(_key('communication-session-list')),
    ).colorScheme;

    await tester.tap(_key('session-list-s1'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(
      tester.widget<Material>(_key('session-list-s1')).color,
      colors.secondaryContainer,
    );

    await tester.tap(_key('session-list-s2'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(
      tester.widget<Material>(_key('session-list-s2')).color,
      colors.secondaryContainer,
    );
    expect(
      tester.widget<Material>(_key('session-list-s1')).color,
      colors.surfaceContainerLow,
    );

    // 等待超过双击超时窗口后，选中状态不会回跳到 s1，也不会误触发打开。
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.widget<Material>(_key('session-list-s2')).color,
      colors.secondaryContainer,
    );
    expect(_key('session-tab-s1'), findsNothing);

    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
