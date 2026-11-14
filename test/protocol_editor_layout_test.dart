import 'dart:convert';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/ui/controllers/app_controller.dart';
import 'package:clovecom/ui/layout/responsive.dart';
import 'package:clovecom/ui/pages/protocol_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/protocol_messages.dart';

Future<AppController> mountEditor(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final second = ProtocolDefinition.collection(
    id: 'second',
    name: '协议二',
    messageTypes: [
      messageDefinition(type: 4, name: '状态消息', kind: PayloadKind.display),
    ],
  );
  final library = ProtocolLibrary();
  await tester.runAsync(() => library.initialize());
  library.importProtocol(const JsonEncoder().convert(mixedProtocol().toJson()));
  library.importProtocol(const JsonEncoder().convert(second.toJson()));
  final controller = AppController(library);
  addTearDown(() {
    controller.dispose();
    library.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Responsive(
          canvasSize: size,
          density: appDensityFor(size),
          child: ProtocolEditorPage(controller: controller),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('切换字段复用属性输入节点并将编辑写入当前字段', (tester) async {
    final controller = await mountEditor(tester);
    final draft = controller.protocolDrafts.first;
    Finder row(int index) => find.descendant(
      of: find.byType(ReorderableListView),
      matching: find.byKey(ObjectKey(draft.fieldIdentity(index))),
    );
    await tester.tap(row(0));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('protocol-field-name'));
    final originalElement = tester.element(input);
    await tester.tap(row(1));
    await tester.pumpAndSettle();
    expect(tester.element(input), same(originalElement));
    final nameField = find.descendant(
      of: input,
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(nameField).controller!.text,
      draft.field(1)['name'],
    );
    await tester.enterText(nameField, 'current_type');
    await tester.pumpAndSettle();
    expect(draft.field(1)['name'], 'current_type');
    expect(draft.field(0)['name'], 'head');
  });
  testWidgets('移除两个搜索框，鼠标悬停显示字段默认属性且不修改草稿', (tester) async {
    final controller = await mountEditor(tester);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            ['搜索字段类型…', '搜索协议…'].contains(w.decoration?.hintText),
      ),
      findsNothing,
    );
    final draft = controller.protocolDrafts.first;
    final revision = draft.revision;
    final field = find.byKey(const ValueKey('library-item-header'));
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: field, matching: find.byType(Tooltip)),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(field));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text(tooltip.message!), findsOneWidget);
    expect(tooltip.message, contains('长度：2 字节'));
    expect(tooltip.message, contains('固定字节：55 AA'));
    expect(tooltip.message, contains('角色：帧头'));
    expect(draft.revision, revision);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('顶部字段横向排列，贴边把手折叠展开保留草稿和预览', (tester) async {
    final controller = await mountEditor(tester);
    final draft = controller.protocolDrafts.first;
    final library = find.byKey(const ValueKey('protocol-field-library'));
    final tree = find.byKey(const ValueKey('protocol-tree-panel'));
    final header = find.byKey(const ValueKey('library-item-header'));
    final u8 = find.byKey(const ValueKey('library-item-u8'));
    expect(tester.getTopLeft(library).dy, lessThan(tester.getTopLeft(tree).dy));
    expect(tester.getTopLeft(header).dy, tester.getTopLeft(u8).dy);
    expect(tester.getTopLeft(header).dx, lessThan(tester.getTopLeft(u8).dx));
    draft.testHex('AA 55 01 07 08 09');
    await tester.pumpAndSettle();
    final revision = draft.revision;
    final preview = draft.preview;
    final expandedHeight = tester.getSize(library).height;
    final treeTop = tester.getTopLeft(tree).dy;
    await tester.tap(find.byTooltip('折叠字段库'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-item-header')), findsNothing);
    expect(find.byTooltip('展开字段库'), findsOneWidget);
    expect(tester.getSize(library).height, 17);
    expect(tester.getTopLeft(tree).dy, lessThan(treeTop));
    expect(draft.revision, revision);
    expect(draft.preview, same(preview));
    await tester.tap(find.byTooltip('展开字段库'));
    await tester.pumpAndSettle();
    expect(tester.getSize(library).height, expandedHeight);
    await tester.tap(find.byKey(const ValueKey('library-item-u8')));
    await tester.pumpAndSettle();
    expect(draft.fieldCount, 6);
    expect(draft.preview, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('协议二级消息独立折叠，切换消息与协议后保留草稿和折叠状态', (tester) async {
    final controller = await mountEditor(tester);
    final first = controller.protocolDrafts.first;
    final second = controller.protocolDrafts.last;
    Finder message(ProtocolDraft draft, int index) =>
        find.byKey(ValueKey('protocol-message-${draft.id}-$index'));
    await tester.tap(message(first, 1));
    await tester.pumpAndSettle();
    expect(first.selectedMessageIndex, 1);
    expect(find.text('消息类型：心跳'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-item-u8')));
    await tester.pumpAndSettle();
    expect(first.fieldCount, 4);
    expect(second.fieldCount, 3);
    await tester.tap(find.byKey(ValueKey('protocol-node-toggle-${first.id}')));
    await tester.pumpAndSettle();
    expect(message(first, 0), findsNothing);
    expect(message(second, 0), findsOneWidget);
    expect(first.selectedMessageIndex, 1);
    await tester.tap(message(second, 0));
    await tester.pumpAndSettle();
    expect(controller.selectedProtocolId, second.id);
    await tester.tap(find.byKey(ValueKey('protocol-node-${first.id}')));
    await tester.pumpAndSettle();
    expect(controller.selectedProtocolId, first.id);
    expect(message(first, 1), findsNothing);
    expect(first.fieldCount, 4);
    await tester.tap(find.byKey(ValueKey('protocol-node-toggle-${first.id}')));
    await tester.pumpAndSettle();
    expect(message(first, 1), findsOneWidget);
    await tester.tap(message(first, 0));
    await tester.pumpAndSettle();
    expect(first.fieldCount, 5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('两行字段同步横向滚动，无滚动条且边缘提示随位置更新', (tester) async {
    final controller = await mountEditor(tester, size: const Size(960, 640));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('field-library-scroll'));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: row, matching: find.byType(Scrollable)),
        )
        .position;
    final header = find.byKey(const ValueKey('library-item-header'));
    final tag = find.byKey(const ValueKey('library-item-tag-id'));
    final headerStart = tester.getTopLeft(header).dx;
    final tagStart = tester.getTopLeft(tag).dx;
    expect(
      find.descendant(of: row, matching: find.byType(Scrollbar)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('field-library-more-right')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('field-library-more-left')), findsNothing);
    Future<void> wheel(double delta) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(row),
          scrollDelta: Offset(0, delta),
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(position.pixels, 0);
    await wheel(1000);
    expect(position.pixels, position.maxScrollExtent);
    // 模拟布局阶段排队的旧尺寸通知：不能覆盖已经滚到末尾的位置。
    ScrollMetricsNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: position.maxScrollExtent,
        pixels: 0,
        viewportDimension: position.viewportDimension,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1,
      ),
      context: tester.element(row),
    ).dispatch(tester.element(row));
    await tester.pumpAndSettle();

    expect(headerStart - tester.getTopLeft(header).dx, position.pixels);
    expect(tagStart - tester.getTopLeft(tag).dx, position.pixels);
    expect(
      find.byKey(const ValueKey('field-library-more-right')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('field-library-more-left')),
      findsOneWidget,
    );
    final viewport = tester.getRect(row);
    final last = tester.getRect(
      find.byKey(const ValueKey('library-item-message-type')),
    );
    expect(viewport.contains(last.topLeft), isTrue);
    expect(viewport.contains(last.bottomRight), isTrue);
    await wheel(-1000);
    expect(position.pixels, 0);
    expect(find.byKey(const ValueKey('field-library-more-left')), findsNothing);
    expect(
      find.byKey(const ValueKey('field-library-more-right')),
      findsOneWidget,
    );
    await wheel(1000);
    final target = find.byKey(const ValueKey('library-item-message-type'));
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(controller.protocolDrafts.first.fieldCount, 6);
    await tester.tap(find.byTooltip('折叠字段库'));
    await tester.pumpAndSettle();
    final second = controller.protocolDrafts.last;
    await tester.tap(find.byKey(ValueKey('protocol-message-${second.id}-0')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开字段库'), findsOneWidget);
    await tester.tap(find.byTooltip('展开字段库'));
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(second.fieldCount, 4);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('field-library-more-left')), findsNothing);
    expect(
      find.byKey(const ValueKey('field-library-more-right')),
      findsNothing,
    );

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
