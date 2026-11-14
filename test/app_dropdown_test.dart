import 'package:clovecom/widgets/app_dropdown.dart';
import 'package:clovecom/widgets/baud_rate_input.dart';
import 'package:clovecom/ui/desktop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('桌面选择框常态边框与输入框等高且聚焦后不变高', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 136,
                height: 32,
                child: BaudRateInput(value: 9600, onChanged: (_) {}),
              ),
              SizedBox(
                width: 136,
                height: 32,
                child: AppDropdownFormField<int>(
                  value: 8,
                  decoration: const InputDecoration(
                    isDense: true,
                    constraints: BoxConstraints.tightFor(height: 32),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 8, child: Text('8')),
                    DropdownMenuItem(value: 6, child: Text('6')),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Rect borderOf(Finder text) {
      final box = InputDecorator.containerOf(tester.element(text))!;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    final before = borderOf(find.text('8'));
    final baud = borderOf(
      find.descendant(
        of: find.byType(BaudRateInput),
        matching: find.byType(EditableText),
      ),
    );
    expect(before.height, closeTo(32, 0.1));
    expect(before.top, closeTo(baud.top, 0.1));
    expect(before.height, closeTo(baud.height, 0.1));
    await tester.tap(find.byType(AppDropdownFormField<int>));
    await tester.pumpAndSettle();
    final anchorDecorator = find.descendant(
      of: find.byType(AppDropdownFormField<int>),
      matching: find.byType(InputDecorator),
    );
    final focused = borderOf(
      find.descendant(of: anchorDecorator, matching: find.text('8')),
    );
    expect(focused, before);
    final decorator = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byType(AppDropdownFormField<int>),
        matching: find.byType(InputDecorator),
      ),
    );
    expect(decorator.isFocused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('菜单反复开关时保留独立且稳定的选择框语义节点', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('相邻内容'),
              SizedBox(
                width: 180,
                child: AppDropdownFormField<int>(
                  initialValue: 1,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('已选项')),
                    DropdownMenuItem(value: 2, child: Text('其他项')),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final anchor = find.byType(AppDropdownFormField<int>);
    final boundary = find.descendant(
      of: anchor,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.container &&
            widget.explicitChildNodes,
      ),
    );
    expect(boundary, findsOneWidget);
    final node = tester.getSemantics(boundary);
    final nodeId = node.id;
    for (var cycle = 0; cycle < 5; cycle++) {
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(boundary).id, nodeId);
      expect(node.attached, isTrue);
      expect(find.widgetWithText(MenuItemButton, '其他项'), findsOneWidget);
      await tester.tapAt(const Offset(400, 400));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(boundary).id, nodeId);
      expect(node.attached, isTrue);
      expect(find.byType(MenuItemButton), findsNothing);
    }
    semantics.dispose();
  });
  testWidgets('长菜单可滚动，Escape 和点击外部均可关闭', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 180,
              child: AppDropdownFormField<int>(
                menuMaxHeight: 180,
                items: List.generate(
                  30,
                  (index) =>
                      DropdownMenuItem(value: index, child: Text('菜单项$index')),
                ),
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );
    final anchor = find.byType(AppDropdownFormField<int>);
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.widgetWithText(MenuItemButton, '菜单项0')).right,
      lessThanOrEqualTo(800),
    );
    await tester.ensureVisible(find.widgetWithText(MenuItemButton, '菜单项29'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '菜单项29'));
    await tester.pumpAndSettle();
    expect(selected, 29);
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 500));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });
  for (final bottom in [false, true]) {
    testWidgets(bottom ? '下方不足时菜单翻转到上方' : '菜单紧贴选择框下方且选择后关闭', (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: bottom ? Alignment.bottomCenter : Alignment.topCenter,
              child: SizedBox(
                width: 180,
                child: AppDropdownFormField<int>(
                  initialValue: 2,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('选项一')),
                    DropdownMenuItem(value: 2, child: Text('选项二')),
                  ],
                  onChanged: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      final anchor = tester.getRect(find.byType(AppDropdownFormField<int>));
      await tester.tap(find.byType(AppDropdownFormField<int>));
      await tester.pumpAndSettle();
      final item = tester.getRect(find.widgetWithText(MenuItemButton, '选项一'));
      if (bottom) {
        expect(item.bottom, lessThanOrEqualTo(anchor.top));
      } else {
        expect(item.top, greaterThanOrEqualTo(anchor.bottom));
        expect(item.top - anchor.bottom, lessThan(20));
      }
      await tester.tap(find.widgetWithText(MenuItemButton, '选项一'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(find.byType(MenuItemButton), findsNothing);
    });
  }
  testWidgets('禁用选择框不会打开菜单', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: AppDropdownFormField<int>(
              initialValue: 1,
              items: [DropdownMenuItem(value: 1, child: Text('选项一'))],
              onChanged: null,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AppDropdownFormField<int>));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });
}
