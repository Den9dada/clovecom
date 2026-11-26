import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/ui/desktop_theme.dart';
import 'package:clovecom/views/serial_port/serial_port_view.dart';

void main() {
  testWidgets('空工作台提示通过会话列表打开会话', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: const Scaffold(body: SerialPortView()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('打开串口'), findsNothing);
    expect(find.text('通信连接订阅'), findsNothing);
    expect(find.text('双击会话列表中的会话以打开'), findsOneWidget);
    expect(find.byTooltip('打开连接会话'), findsNothing);
    expect(find.byTooltip('新建会话'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
