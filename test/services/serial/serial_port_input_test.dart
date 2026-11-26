import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';
import 'package:clovecom/widgets/serial_port_input.dart';
import 'serial_port_directory_test.dart' show ports;

void main() {
  testWidgets('菜单展开后显示新快照，移除页面释放菜单', (tester) async {
    var names = ['COM2'];
    final directory = SerialPortDirectory(
      scan: () async => ports(names),
      changes: const Stream.empty(),
    );
    await directory.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: SerialPortInput(
              directory: directory,
              value: '',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('选择串口'));
    await tester.pumpAndSettle();
    expect(find.text('COM2 - '), findsOneWidget);
    names = ['COM10'];
    await directory.refresh(evictStaleSelection: true);
    await tester.pumpAndSettle();
    expect(find.text('COM2 - '), findsNothing);
    expect(find.text('COM10 - '), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    directory.dispose();
  });
}
