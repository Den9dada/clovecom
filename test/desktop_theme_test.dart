import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/ui/desktop_theme.dart';
import 'package:clovecom/ui/theme/terminal_color_schemes.dart';

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

  test('buildDesktopTheme 适配深色主题与高亮主色对比度', () {
    final dracula = buildDesktopTheme(
      scheme: resolveTerminalColorScheme('dracula'),
    );
    expect(dracula.brightness, Brightness.dark);
    expect(dracula.colorScheme.surface, const Color(0xff282a36));
    expect(dracula.colorScheme.onSurface, const Color(0xfff8f8f2));

    final cobalt2 = buildDesktopTheme(
      scheme: resolveTerminalColorScheme('cobalt2'),
    );
    expect(cobalt2.colorScheme.primary, const Color(0xffff55ff));
    expect(cobalt2.colorScheme.onPrimary, const Color(0xff171717));
    expect(
      identical(
        buildDesktopTheme(scheme: resolveTerminalColorScheme('dracula')),
        dracula,
      ),
      isTrue,
    );
    expect(
      dracula.extension<TerminalThemeExtension>()?.scheme.id,
      'dracula',
    );
  });
}
