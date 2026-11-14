import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/main.dart';
import 'package:clovecom/widgets/serial_port_input.dart';
import 'package:clovecom/widgets/app_dropdown.dart';
import 'package:clovecom/views/firmware_upgrade/firmware_upgrade_view.dart';

void main() {
  testWidgets('升级页独立导航、串口配置和状态保留', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('clovecom/serial_ports');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => [],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.widgetWithText(Tab, '固件升级'), findsNothing);
    expect(find.widgetWithText(Tab, '文件接收'), findsOneWidget);
    await tester.tap(find.text('固件升级'));
    await tester.pump();
    expect(find.byType(FirmwareUpgradeView), findsOneWidget);
    expect(find.text('选择固件'), findsOneWidget);
    expect(find.text('选择脚本'), findsNothing);
    expect(find.text('请先选择并载入升级协议'), findsOneWidget);
    expect(find.text('升级日志'), findsOneWidget);
    expect(find.text('每包字节数'), findsNothing);
    expect(find.text('发送间隔 (ms)'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('firmware-option-数据位')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.widgetWithText(MenuItemButton, '6'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
      tester
          .widget<AppDropdownFormField<int>>(
            find.byKey(const ValueKey('firmware-option-数据位')),
          )
          .value,
      6,
    );
    final upgradeInput = find.descendant(
      of: find.byType(FirmwareUpgradeView),
      matching: find.byType(SerialPortInput),
    );
    await tester.enterText(
      find.descendant(of: upgradeInput, matching: find.byType(TextField)),
      'COM99',
    );
    await tester.pump();
    await tester.tap(find.text('串口通信'));
    await tester.pump();
    final serialInput = tester.widget<SerialPortInput>(
      find.byType(SerialPortInput),
    );
    expect(serialInput.value, isEmpty);
    await tester.tap(find.text('固件升级'));
    await tester.pump();
    expect(tester.widget<SerialPortInput>(upgradeInput).value, 'COM99');
    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();
    expect(find.text('开始升级'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
