import 'dart:async';

import 'package:clovecom/src/application/interaction_draft.dart';
import 'package:clovecom/src/core/interaction_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InteractionDraft draft;
  late List<({bool validating, bool runnable, List<String> diagnostics})>
  notifications;

  setUp(() {
    notifications = [];
    draft = InteractionDraft(
      InteractionProtocol(id: 'script', name: '查询', source: 'return {}'),
      onChanged: () => notifications.add((
        validating: draft.validating,
        runnable: draft.runnable,
        diagnostics: draft.diagnostics.map((value) => value.message).toList(),
      )),
    );
  });

  test('协议脚本在校验期间编辑会立即结束旧校验等待', () async {
    final completion = Completer<List<ScriptDiagnostic>>();
    final checking = draft.validate((_) => completion.future);
    expect(draft.validating, isTrue);

    draft.setSource('return { run = function() end }');

    expect(draft.validating, isFalse);
    completion.complete(const []);
    expect((await checking).status, InteractionValidationStatus.superseded);
    expect(draft.runnable, isFalse);
  });

  test('超过大小上限的协议脚本以校验失败返回，不遗留等待状态', () async {
    draft.setSource('a' * (InteractionProtocol.maxSourceBytes + 1));

    final result = await draft.validate((_) async => const []);

    expect(result.status, InteractionValidationStatus.failed);
    expect(result.diagnostics.single.message, contains('1 MiB'));
    expect(draft.validating, isFalse);
    expect(draft.runnable, isFalse);
  });

  test('协议脚本校验开始和完成均通知观察者，校验不修改内容版本', () async {
    final completion = Completer<List<ScriptDiagnostic>>();
    final checking = draft.validate((protocol) {
      expect(protocol.source, 'return {}');
      return completion.future;
    });

    expect(notifications, hasLength(1));
    expect(notifications.single.validating, isTrue);
    expect(notifications.single.runnable, isFalse);
    expect(notifications.single.diagnostics, isEmpty);
    expect(draft.revision, 0);
    expect(draft.isDirty, isFalse);
    completion.complete(const []);

    expect((await checking).status, InteractionValidationStatus.passed);
    expect(notifications.last.validating, isFalse);
    expect(notifications.last.runnable, isTrue);
    expect(draft.revision, 0);
    expect(draft.isDirty, isFalse);
  });

  test('同一文本重复校验时，旧请求失败不结束新请求等待', () async {
    final first = Completer<List<ScriptDiagnostic>>();
    final second = Completer<List<ScriptDiagnostic>>();
    final older = draft.validate((_) => first.future);
    final newer = draft.validate((_) => second.future);

    first.completeError(StateError('旧进程失败'));
    final oldResult = await older;

    expect(oldResult.status, InteractionValidationStatus.superseded);
    expect(oldResult.diagnostics, isEmpty);
    expect(draft.validating, isTrue);
    expect(draft.diagnostics, isEmpty);
    second.complete(const []);
    expect((await newer).status, InteractionValidationStatus.passed);
    expect(draft.runnable, isTrue);
  });

  test('新请求先完成后，旧请求成功不能覆盖当前失败诊断', () async {
    final first = Completer<List<ScriptDiagnostic>>();
    final second = Completer<List<ScriptDiagnostic>>();
    final older = draft.validate((_) => first.future);
    final newer = draft.validate((_) => second.future);
    second.complete(const [ScriptDiagnostic('当前脚本缺少 run', line: 1)]);

    expect((await newer).status, InteractionValidationStatus.failed);
    final publishedCount = notifications.length;
    first.complete(const []);

    expect((await older).status, InteractionValidationStatus.superseded);
    expect(draft.runnable, isFalse);
    expect(draft.validating, isFalse);
    expect(draft.diagnostics.single.message, '当前脚本缺少 run');
    expect(notifications, hasLength(publishedCount));
  });

  test('协议脚本文本改动后又恢复原文，不复活此前校验', () async {
    final completion = Completer<List<ScriptDiagnostic>>();
    final checking = draft.validate((_) => completion.future);

    draft.setSource('return { changed = true }');
    draft.setSource('return {}');
    completion.complete(const []);

    expect((await checking).status, InteractionValidationStatus.superseded);
    expect(draft.runnable, isFalse);
    expect(draft.validating, isFalse);
    expect(draft.isDirty, isFalse);
  });

  test('丢弃协议脚本修改会结束等待，迟到诊断不污染保存内容', () async {
    draft.setSource('return { run = function( }');
    final completion = Completer<List<ScriptDiagnostic>>();
    final checking = draft.validate((_) => completion.future);

    draft.discard();

    expect(draft.source, 'return {}');
    expect(draft.validating, isFalse);
    expect(draft.diagnostics, isEmpty);
    final publishedCount = notifications.length;
    completion.complete(const [ScriptDiagnostic('旧脚本语法错误')]);
    expect((await checking).status, InteractionValidationStatus.superseded);
    expect(draft.diagnostics, isEmpty);
    expect(notifications, hasLength(publishedCount));
  });

  test('当前校验失败以诊断交付并可重新校验恢复', () async {
    final failed = await draft.validate((_) => throw StateError('进程不可用'));

    expect(failed.status, InteractionValidationStatus.failed);
    expect(failed.diagnostics.single.message, contains('进程不可用'));
    expect(draft.validating, isFalse);
    expect(draft.runnable, isFalse);
    expect(notifications.last.validating, isFalse);

    final passed = await draft.validate((_) async => const []);
    expect(passed.status, InteractionValidationStatus.passed);
    expect(draft.diagnostics, isEmpty);
    expect(draft.runnable, isTrue);
  });

  test('删除或关闭时失效校验，迟到完成不再发布状态', () async {
    final completion = Completer<List<ScriptDiagnostic>>();
    final checking = draft.validate((_) => completion.future);

    draft.invalidateValidation();

    expect(draft.validating, isFalse);
    expect(draft.runnable, isFalse);
    final publishedCount = notifications.length;
    completion.complete(const []);
    expect((await checking).status, InteractionValidationStatus.superseded);
    expect(notifications, hasLength(publishedCount));
  });

  test('错误协议脚本仍可保存，校验诊断不可被外部修改', () async {
    draft.setSource('return { run = function( }');
    final diagnostics = [const ScriptDiagnostic('语法错误')];
    final result = await draft.validate((_) async => diagnostics);
    diagnostics.clear();

    final saved = draft.build();
    draft.acceptSaved(saved, draft.revision);

    expect(result.status, InteractionValidationStatus.failed);
    expect(draft.diagnostics.single.message, '语法错误');
    expect(result.diagnostics.single.message, '语法错误');
    expect(() => draft.diagnostics.clear(), throwsUnsupportedError);
    expect(() => result.diagnostics.clear(), throwsUnsupportedError);
    expect(draft.isDirty, isFalse);
    expect(draft.runnable, isFalse);
    draft.setSource('return {}');
    expect(saved.source, 'return { run = function( }');
  });

  test('仅重命名或重复写入同一文本不使内容校验失效', () async {
    final completion = Completer<List<ScriptDiagnostic>>();
    final checking = draft.validate((_) => completion.future);

    draft.rename('查询设备');
    draft.setSource('return {}');
    completion.complete(const []);

    expect((await checking).status, InteractionValidationStatus.passed);
    expect(draft.runnable, isTrue);
    expect(draft.name, '查询设备');
  });
}
