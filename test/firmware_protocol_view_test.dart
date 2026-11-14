import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/widgets/app_dropdown.dart';
import 'package:clovecom/widgets/baud_rate_input.dart';
import 'package:clovecom/ui/desktop_theme.dart';
import 'package:clovecom/src/application/lua_runtime.dart';
import 'package:clovecom/views/firmware_upgrade/firmware_upgrade_view.dart';
import 'package:clovecom/viewmodels/serial_port_viewmodel.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';
import 'services/serial/serial_port_directory_test.dart' show ports;

class CheckingRuntime extends LuaRuntime {
  int checks = 0;
  Completer<List<ScriptDiagnostic>>? pending;
  List<ScriptDiagnostic> diagnostics = [];
  @override
  Future<List<ScriptDiagnostic>> validate(InteractionProtocol protocol) async {
    checks++;
    return pending == null ? diagnostics : pending!.future;
  }
}

void main() {
  testWidgets('升级页自动载入、显示版本更新并通过选择框内图标卸载', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = CheckingRuntime();
    final library = ProtocolLibrary(runtime: runtime);
    await tester.runAsync(() => library.initialize());
    final draft = library.createInteraction(
      '界面升级测试',
      InteractionPurpose.upgrade,
      source: newInteractionSource('界面升级测试', InteractionPurpose.upgrade)
          .replaceFirst(
            '"purpose": "upgrade",',
            '"purpose": "upgrade", "data_source":{"persistent":{"baud_rate":1000000}},',
          ),
    );
    await tester.runAsync(() => library.saveInteraction(draft.id));
    final vm = SerialPortViewModel(
      protocolLibrary: library,
      directory: SerialPortDirectory(
        scan: () async => ports([]),
        changes: const Stream.empty(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: FirmwareUpgradeView(
            createViewModel: () => vm,
            protocolLibrary: library,
          ),
        ),
      ),
    );
    await tester.pump();
    final fileBounds = tester.getRect(
      find.byKey(const ValueKey('firmware-file-field')),
    );
    final buttonBounds = tester.getRect(
      find.byKey(const ValueKey('select-firmware-file')),
    );
    expect(fileBounds.height, 32);
    expect(buttonBounds.height, fileBounds.height);
    expect(buttonBounds.top, fileBounds.top);
    await tester.tap(find.byKey(const ValueKey('firmware-protocol-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('界面升级测试').last);
    await tester.pumpAndSettle();
    expect(find.text('载入协议'), findsNothing);
    expect(runtime.checks, 1);
    expect(vm.firmwareProtocols!.loaded!.id, draft.id);
    expect(vm.config.baudRate, 1000000);
    expect(find.text('已载入：界面升级测试'), findsNothing);
    expect(find.text('编辑协议'), findsNothing);
    expect(find.text('卸载协议'), findsNothing);
    expect(find.text('1000000'), findsOneWidget);
    vm.updateConfig(baudRate: 57600);
    draft.setSource('${draft.source}\n-- 新版本');
    await tester.runAsync(() => library.saveInteraction(draft.id));
    await tester.pump();
    expect(find.textContaining('协议有新版本'), findsOneWidget);
    expect(runtime.checks, 1);
    expect(vm.config.baudRate, 57600);
    expect(vm.firmwareProtocols!.hasNewVersion, isTrue);
    await tester.tap(find.byKey(ValueKey('firmware-protocol-${draft.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '界面升级测试'));
    await tester.pumpAndSettle();
    expect(runtime.checks, 2);
    expect(vm.config.baudRate, 1000000);
    expect(vm.firmwareProtocols!.hasNewVersion, isFalse);
    await tester.tap(find.byKey(const ValueKey('unload-firmware-protocol')));
    await tester.pump();
    expect(vm.firmwareProtocols!.loaded, isNull);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      find.byKey(const ValueKey('firmware-protocol-null')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('unload-firmware-protocol')),
      findsNothing,
    );
    expect(find.text('请先选择并载入升级协议'), findsOneWidget);
    expect(find.text('卸载协议'), findsNothing);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    library.dispose();
  });
  testWidgets('自动载入期间禁用选择，失败后恢复实际已载入协议且不重试', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = CheckingRuntime()
      ..diagnostics = [const ScriptDiagnostic('校验失败')];
    final library = ProtocolLibrary(runtime: runtime);
    await tester.runAsync(() => library.initialize());
    final first = library.savedInteractions.first,
        second = library.savedInteractions.last;
    final vm = SerialPortViewModel(
      protocolLibrary: library,
      directory: SerialPortDirectory(
        scan: () async => ports([]),
        changes: const Stream.empty(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: FirmwareUpgradeView(
            createViewModel: () => vm,
            protocolLibrary: library,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('firmware-protocol-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, first.name));
    await tester.pumpAndSettle();
    expect(runtime.checks, 1);
    expect(vm.firmwareProtocols!.loaded, isNull);
    expect(
      find.byKey(const ValueKey('firmware-protocol-null')),
      findsOneWidget,
    );
    runtime.diagnostics = [];
    await tester.tap(find.byKey(const ValueKey('firmware-protocol-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, first.name));
    await tester.pumpAndSettle();
    expect(runtime.checks, 2);
    expect(vm.firmwareProtocols!.loaded!.id, first.id);
    final optionDecorators = ['数据位', '停止位', '校验', '流控']
        .map(
          (label) => find.descendant(
            of: find.byKey(ValueKey('firmware-option-$label')),
            matching: find.byType(InputDecorator),
          ),
        )
        .toList();
    final beforeElements = optionDecorators.map(tester.element).toList();
    final beforeEnabled = optionDecorators
        .map(
          (finder) => tester.widget<InputDecorator>(finder).decoration.enabled,
        )
        .toList();
    final baudField = find.descendant(
      of: find.byType(BaudRateInput),
      matching: find.byType(TextField),
    );
    final beforeBaudElement = tester.element(baudField);
    final beforeBaudEnabled = tester.widget<TextField>(baudField).enabled;
    runtime.pending = Completer<List<ScriptDiagnostic>>();
    await tester.tap(find.byKey(ValueKey('firmware-protocol-${first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, second.name));
    await tester.pump();
    await tester.pump();
    expect(vm.firmwareProtocols!.loading, isTrue);
    expect(optionDecorators.map(tester.element).toList(), beforeElements);
    expect(tester.element(baudField), same(beforeBaudElement));
    expect(
      optionDecorators
          .map(
            (finder) =>
                tester.widget<InputDecorator>(finder).decoration.enabled,
          )
          .toList(),
      beforeEnabled,
      reason: '协议校验期间接口参数框不应切换为灰色禁用样式',
    );
    expect(tester.widget<TextField>(baudField).enabled, beforeBaudEnabled);
    await tester.tap(
      find.byKey(const ValueKey('firmware-option-数据位')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(
      find.byType(MenuItemButton),
      findsNothing,
      reason: '外观保持正常，但校验期间仍禁止打开接口参数菜单',
    );
    await tester.tap(baudField, warnIfMissed: false);
    await tester.pump();
    expect(tester.widget<TextField>(baudField).focusNode!.hasFocus, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('unload-firmware-protocol')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('正在校验并载入…'), findsNothing);
    expect(
      tester
          .widget<AppDropdownFormField<String>>(
            find.byKey(ValueKey('firmware-protocol-${second.id}')),
          )
          .onChanged,
      isNull,
    );
    runtime.pending!.complete([const ScriptDiagnostic('新协议校验失败')]);
    await tester.pumpAndSettle();
    expect(vm.firmwareProtocols!.loaded!.id, first.id);
    expect(
      find.byKey(ValueKey('firmware-protocol-${first.id}')),
      findsOneWidget,
    );
    expect(runtime.checks, 3);
    await tester.pump();
    expect(runtime.checks, 3);
    expect(find.text('载入协议'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    library.dispose();
  });
}
