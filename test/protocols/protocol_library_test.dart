import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/services/firmware_protocol_binding.dart';
import 'package:clovecom/src/application/lua_runtime.dart';
import 'package:clovecom/src/application/ymodem_lua_source.dart';

class ControlledRuntime extends LuaRuntime {
  Completer<List<ScriptDiagnostic>>? pending;
  @override
  Future<List<ScriptDiagnostic>> validate(InteractionProtocol protocol) async =>
      pending == null ? <ScriptDiagnostic>[] : pending!.future;
}

void main() {
  test('旧协议库补齐 YMODEM 一次，不覆盖同名脚本或恢复已删点表', () async {
    final dir = await Directory.systemTemp.createTemp(
      'clovecom-script-migration-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final original = InteractionProtocol(
      id: 'custom',
      name: '标准 YMODEM—Lua',
      source: newInteractionSource('用户脚本', InteractionPurpose.upgrade),
    );
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'pointTableSeeded': true,
        'protocols': [],
        'interactions': [original.toJson()],
      }),
    );
    final app = ProtocolLibrary();
    await app.initialize(file: file);
    expect(app.savedInteraction('custom')!.source, original.source);
    expect(app.savedInteractions, hasLength(2));
    final ymodem = app.savedInteractions.singleWhere(
      (p) => p.source == ymodemLuaSource,
    );
    expect(ymodem.name, '标准 YMODEM—Lua 1');
    expect(jsonDecode(await file.readAsString())['ymodemSeeded'], isTrue);
    await app.deleteInteraction(ymodem.id);
    final reopened = ProtocolLibrary();
    await reopened.initialize(file: file);
    expect(reopened.savedInteractions.single.id, 'custom');
    app.dispose();
    reopened.dispose();
  });

  test('协议库落盘重开，删除预置脚本后不会再次补回', () async {
    final dir = await Directory.systemTemp.createTemp(
      'clovecom-protocol-test-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final app = ProtocolLibrary();
    await app.initialize(file: file);
    final id = app.savedInteractions.first.id;
    await app.deleteInteraction(id);
    await app.deleteInteraction(app.savedInteractions.single.id);
    final second = ProtocolLibrary();
    await second.initialize(file: file);
    expect(second.savedInteractions, isEmpty);
    expect(jsonDecode(await file.readAsString())['pointTableSeeded'], isTrue);
    app.dispose();
    second.dispose();
  });

  test('保存失败保留草稿和旧持久化版本', () async {
    var fail = false;
    final app = ProtocolLibrary(
      persist: (_) async {
        if (fail) throw StateError('磁盘写入失败');
      },
    );
    await app.initialize();
    final d = app.interactionDrafts.first;
    final saved = app.savedInteraction(d.id)!;
    d.setSource('${d.source}\n-- 修改');
    fail = true;
    await expectLater(app.saveInteraction(d.id), throwsStateError);
    expect(d.isDirty, isTrue);
    expect(app.savedInteraction(d.id)!.digest, saved.digest);
    expect(app.operation, isNull);
    app.dispose();
  });

  test('载入固定版本、保存后提示更新、引用保护与明确卸载', () async {
    final app = ProtocolLibrary(runtime: ControlledRuntime());
    await app.initialize();
    final binding = FirmwareProtocolBinding(app);
    final d = app.interactionDrafts.first;
    await binding.load(d.id, locked: () => false);
    final old = binding.loaded!;
    d.setSource('${d.source}\n-- 新版本');
    await app.saveInteraction(d.id);
    expect(binding.loaded!.digest, old.digest);
    expect(binding.hasNewVersion, isTrue);
    await expectLater(app.deleteInteraction(d.id), throwsStateError);
    binding.unload();
    await app.deleteInteraction(d.id);
    expect(app.savedInteraction(d.id), isNull);
    binding.dispose();
    app.dispose();
  });

  test('错误脚本允许保存，但校验失败不能替换已载入内容', () async {
    final runtime = ControlledRuntime();
    final app = ProtocolLibrary(runtime: runtime);
    await app.initialize();
    final binding = FirmwareProtocolBinding(app);
    final original = app.interactionDrafts.first;
    Future<void> load(String id) => binding.load(id, locked: () => false);
    await load(original.id);
    final invalid = app.createInteraction(
      '错误脚本',
      InteractionPurpose.upgrade,
      source:
          '${newInteractionSource('错误脚本', InteractionPurpose.upgrade)}\nthis is invalid lua',
    );
    await app.saveInteraction(invalid.id);
    runtime.pending = Completer()..complete([const ScriptDiagnostic('语法错误')]);
    await expectLater(load(invalid.id), throwsStateError);
    expect(binding.loaded!.id, original.id);
    binding.dispose();
    app.dispose();
  });

  test('载入只保留不可变配置建议，实际配置由通信管理负责', () async {
    final app = ProtocolLibrary(runtime: ControlledRuntime());
    await app.initialize();
    final source = newInteractionSource('升级', InteractionPurpose.upgrade)
        .replaceFirst(
          '"purpose": "upgrade",',
          '"purpose": "upgrade", "data_source": {"persistent":{"baud_rate":115200}},',
        );
    final draft = app.createInteraction(
      '升级',
      InteractionPurpose.upgrade,
      source: source,
    );
    await app.saveInteraction(draft.id);
    final binding = FirmwareProtocolBinding(app);
    Future<void> load() => binding.load(draft.id, locked: () => false);
    await load();
    expect(binding.loaded, isNotNull);
    expect(binding.configSuggestion, {'baud_rate': 115200});
    expect(
      () => binding.configSuggestion['baud_rate'] = 1,
      throwsUnsupportedError,
    );
    await load();
    expect(binding.loaded, isNotNull);
    binding.dispose();
    app.dispose();
  });

  test('卸载使晚到校验失效，不得重新建立绑定', () async {
    final runtime = ControlledRuntime()..pending = Completer();
    final app = ProtocolLibrary(runtime: runtime);
    await app.initialize();
    final binding = FirmwareProtocolBinding(app);
    final loading = binding.load(
      app.savedInteractions.first.id,
      locked: () => false,
    );
    binding.unload();
    runtime.pending!.complete([]);
    expect(await loading, isFalse);
    expect(binding.loaded, isNull);
    expect(binding.loading, isFalse);
    binding.dispose();
    app.dispose();
  });
}
