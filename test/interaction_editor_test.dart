import 'dart:convert';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/ui/controllers/app_controller.dart';
import 'package:clovecom/ui/pages/protocol_editor_page.dart';
import 'package:clovecom/ui/widgets/ds_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/protocol_messages.dart';

void main() {
  testWidgets('解析与交互列表切换保留草稿，错误脚本可编辑和保存', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = ProtocolLibrary();
    await tester.runAsync(() => app.initialize());
    app.importProtocol(jsonEncode(mixedProtocol().toJson()));
    final controller = AppController(app);
    final draft = (await tester.runAsync(
      () async => app.createInteraction('控制脚本', InteractionPurpose.control),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            DsToastHost(key: DsToastHostState.rootKey, child: child!),
        home: Scaffold(body: ProtocolEditorPage(controller: controller)),
      ),
    );
    await tester.tap(find.text('交互协议编辑'));
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('控制脚本 *')));
    await tester.pump();
    // 自动校验也显示等待动画，先让真实 Lua 进程完成再等待界面稳定。
    for (var i = 0; i < 120 && draft.validating; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(draft.validating, isFalse);
    final panel = find.byKey(const ValueKey('interaction-find-panel'));
    final original = tester.getRect(panel);
    await tester.drag(
      find.byKey(const ValueKey('interaction-find-resize')),
      const Offset(-100, 0),
    );
    await tester.pump();
    expect(tester.getRect(panel).width, greaterThan(original.width));
    expect(tester.getRect(panel).right, closeTo(original.right, 0.5));
    expect(
      tester.getCenter(find.text('保存')).dy,
      closeTo(tester.getCenter(find.text('解析协议编辑')).dy, 0.5),
    );
    final originalSource = draft.source;
    await tester.tap(find.text('接口说明'));
    await tester.pump();
    for (
      var i = 0;
      i < 40 &&
          find.byKey(const ValueKey('lua-api-chapters')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    final apiPanel = find.byKey(const ValueKey('lua-api-panel'));
    final workspace = find.byKey(const ValueKey('interaction-workspace'));
    expect(apiPanel, findsOneWidget);
    expect(
      tester.getSize(apiPanel).width,
      closeTo(tester.getSize(workspace).width - 32, 0.5),
    );
    expect(
      tester.getSize(apiPanel).height,
      closeTo((tester.getSize(workspace).height - 28) / 2, 0.5),
    );
    expect(
      tester.getRect(apiPanel).top,
      closeTo(tester.getRect(workspace).top + 12, 0.5),
    );
    expect(find.text('API约定'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lua-usage-tab')));
    await tester.pumpAndSettle();
    expect(find.text('使用概览'), findsOneWidget);
    expect(find.text('API约定'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lua-api-chapters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编写完整脚本').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('return {run=function(ctx)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lua-api-tab')));
    await tester.pumpAndSettle();
    expect(find.text('全部API说明'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lua-api-chapters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数据源配置与运行时状态').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('ctx.data_source:describe()', findRichText: true),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(800, 700);
    await tester.pump();
    expect(
      tester.getSize(apiPanel).width,
      closeTo(tester.getSize(workspace).width - 32, 0.5),
    );
    expect(
      tester.getSize(apiPanel).height,
      closeTo((tester.getSize(workspace).height - 28) / 2, 0.5),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump();
    final initialApiRect = tester.getRect(apiPanel);
    final apiResize = find.byKey(const ValueKey('lua-api-resize'));
    await tester.drag(apiResize, const Offset(0, 80));
    await tester.pump();
    expect(tester.getRect(apiPanel).height, greaterThan(initialApiRect.height));
    expect(tester.getRect(apiPanel).top, closeTo(initialApiRect.top, 0.5));
    await tester.drag(apiResize, const Offset(0, -1000));
    await tester.pump();
    expect(tester.getSize(apiPanel).height, closeTo(200, 0.5));
    await tester.drag(apiResize, const Offset(0, 1000));
    await tester.pump();
    expect(
      tester.getSize(apiPanel).height,
      closeTo(tester.getSize(workspace).height - 108, 0.5),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('lua-api-close')));
    await tester.pump();
    expect(apiPanel, findsNothing);
    expect(draft.source, originalSource);
    final editor = find.byWidgetPredicate(
      (w) => w is TextField && w.key == ValueKey(draft.id),
    );
    await tester.enterText(editor, 'local a = 1\nlocal b = 2\nreturn {}');
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    final codeRect = tester.getRect(
      find.byKey(const ValueKey('interaction-code-hover')),
    );
    await mouse.moveTo(codeRect.topLeft + const Offset(20, 34));
    await tester.pump();
    final hoverLine = find.byKey(const ValueKey('interaction-hover-line'));
    final secondLineRect = tester.getRect(hoverLine);
    expect(secondLineRect.top, closeTo(codeRect.top + 29, 0.5));
    expect(secondLineRect.height, closeTo(21, 0.5));
    expect(tester.widget<TextField>(editor).decoration!.filled, isFalse);
    await mouse.moveTo(codeRect.topLeft + const Offset(20, 55));
    await tester.pump();
    expect(
      tester.getRect(hoverLine).top,
      closeTo(secondLineRect.top + 21, 0.5),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(hoverLine, findsNothing);
    await mouse.removePointer();
    List<InlineSpan> lineNumbers() =>
        (tester
                    .widget<Text>(
                      find.byKey(const ValueKey('interaction-line-numbers')),
                    )
                    .textSpan!
                as TextSpan)
            .children!;
    expect(lineNumbers()[2].style?.fontWeight, FontWeight.w600);
    final codeController = tester.widget<TextField>(editor).controller!;
    codeController.selection = const TextSelection.collapsed(offset: 12);
    await tester.pump();
    expect(lineNumbers()[1].style?.fontWeight, FontWeight.w600);
    expect(lineNumbers()[2].style, isNull);
    expect(draft.source, 'local a = 1\nlocal b = 2\nreturn {}');
    await tester.enterText(editor, 'return {run=function(}');
    await tester.pump();
    expect(draft.source, 'return {run=function(}');
    final validateButton = find.byKey(
      const ValueKey('interaction-validate-button'),
    );
    final idleButtonRect = tester.getRect(validateButton);
    final progress = find.descendant(
      of: validateButton,
      matching: find.byType(CircularProgressIndicator),
    );
    await tester.runAsync(() => tester.tap(find.text('校验')));
    await tester.pump();
    expect(progress, findsOneWidget);
    expect(tester.getRect(validateButton), idleButtonRect);
    for (var i = 0; i < 120 && progress.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(progress, findsNothing);
    expect(tester.getRect(validateButton), idleButtonRect);
    expect(find.textContaining('校验未通过：发现'), findsOneWidget);
    await tester.tap(find.text('解析协议编辑'));
    await tester.pump();
    expect(find.text('帧结构'), findsOneWidget);
    await tester.tap(find.text('交互协议编辑'));
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('控制脚本 *')));
    await tester.pump();
    expect(
      tester.widget<TextField>(editor).controller!.text,
      'return {run=function(}',
    );
    await tester.runAsync(() => tester.tap(find.text('保存')));
    await tester.pump();
    // 保存也会发起真实进程校验；结束前让其完成，避免遗留进程超时计时器。
    for (var i = 0; i < 120 && draft.validating; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(draft.validating, isFalse);
    expect(app.savedInteraction(draft.id)!.source, 'return {run=function(}');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    app.dispose();
  });
}
