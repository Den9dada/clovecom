import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/ui/desktop_theme.dart';

void main() {
  test('动作禁用优先于按下和选中，危险动作不混入品牌背景', () {
    final primary = desktopActionStyle(DesktopActionKind.primary);
    expect(
      primary.backgroundColor!.resolve({
        WidgetState.disabled,
        WidgetState.pressed,
        WidgetState.selected,
      }),
      DesktopTokens.secondary,
    );
    expect(
      primary.backgroundColor!.resolve({WidgetState.hovered}),
      DesktopTokens.brandHover,
    );
    expect(
      primary.backgroundColor!.resolve({
        WidgetState.pressed,
        WidgetState.hovered,
      }),
      DesktopTokens.brandPressed,
    );
    final danger = desktopActionStyle(DesktopActionKind.danger, selected: true);
    expect(danger.foregroundColor!.resolve({}), DesktopTokens.error);
    expect(danger.side!.resolve({})!.color, DesktopTokens.error);
    expect(
      danger.side!.resolve({WidgetState.focused})!.color,
      DesktopTokens.brand,
    );
  });
  testWidgets('忙碌阻止重复执行，行内动作保持24高', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: Center(
            child: DesktopAction(
              label: '写入',
              busy: true,
              inline: true,
              onPressed: () => calls++,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(TextButton)).height, 24);
    await tester.tap(find.byType(TextButton));
    expect(calls, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
