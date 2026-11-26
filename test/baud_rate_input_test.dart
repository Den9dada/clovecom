import 'package:clovecom/widgets/baud_rate_input.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('自定义波特率立即同步，非法值不提交，预设仍可选择', (tester) async {
    var rate = 9600;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                SizedBox(
                  width: 200,
                  child: BaudRateInput(
                    value: rate,
                    onChanged: (value) => setState(() => rate = value),
                  ),
                ),
                TextButton(
                  onPressed: () => FocusScope.of(context).unfocus(),
                  child: const Text('失焦'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '250000');
    await tester.pump();
    expect(rate, 250000);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(rate, 250000);
    expect(find.text('请输入有效的正整数'), findsOneWidget);
    await tester.tap(find.text('失焦'));
    await tester.pumpAndSettle();
    expect(find.text('250000'), findsOneWidget);
    await tester.tap(find.byTooltip('常用波特率'));
    await tester.pumpAndSettle();
    final fieldRect = tester.getRect(find.byType(TextField));
    final menuRect = tester.getRect(
      find.widgetWithText(MenuItemButton, '1200'),
    );
    expect(menuRect.left, closeTo(fieldRect.left, 0.1));
    expect(menuRect.width, closeTo(fieldRect.width, 0.1));
    expect(menuRect.top, greaterThanOrEqualTo(fieldRect.bottom));
    await tester.ensureVisible(find.widgetWithText(MenuItemButton, '115200'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '115200'));
    await tester.pumpAndSettle();
    expect(rate, 115200);
    expect(find.text('115200'), findsOneWidget);
  });

  testWidgets('连接后禁用手动输入和预设选择', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: BaudRateInput(value: 9600, onChanged: null),
          ),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byTooltip('常用波特率'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });
}
