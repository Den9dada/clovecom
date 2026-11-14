import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/ui/desktop_theme.dart';
import 'package:clovecom/views/serial_port/serial_port_view.dart';

void main() {
  testWidgets('连接按钮完整容纳文字和图标', (tester) async {
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
    final label = find.text('打开串口');
    final button = find.ancestor(
      of: label,
      matching: find.byType(FilledButton),
    );
    final buttonRect = tester.getRect(button);
    final labelRect = tester.getRect(label);
    expect(labelRect.top, greaterThanOrEqualTo(buttonRect.top));
    expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
    expect(labelRect.height, greaterThanOrEqualTo(12));
    final iconRect = tester.getRect(
      find.descendant(of: button, matching: find.byIcon(Icons.link)),
    );
    expect(iconRect.top, greaterThanOrEqualTo(buttonRect.top));
    expect(iconRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
    await tester.pumpWidget(const SizedBox());
  });
}
