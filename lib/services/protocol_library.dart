import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../src/core/interaction_protocol.dart';
import '../src/core/protocol.dart';
import '../src/application/drafts.dart';
import '../src/application/interaction_draft.dart';
import '../src/application/lua_runtime.dart';
import '../src/application/point_table_lua_source.dart';
import '../src/application/ymodem_lua_source.dart';
import '../src/application/project_defaults.dart';

/// 编辑草稿与持久化版本分别管理，使用方只能明确载入已保存快照。
class ProtocolLibrary extends ChangeNotifier {
  ProtocolLibrary({LuaRuntime? runtime, this.persist})
    : runtime = runtime ?? LuaRuntime();

  final LuaRuntime runtime;
  final Future<void> Function(Map<String, dynamic>)? persist;
  final Map<String, ProtocolDraft> _protocols = {};
  final Map<String, InteractionDraft> _interactions = {};
  Map<String, ProtocolDefinition> _savedProtocols = {};
  Map<String, InteractionProtocol> _savedInteractions = {};
  final Map<String, int> _references = {};
  File? _file;
  bool _disposed = false;
  bool _initialized = false;
  int _sequence = 0;
  String? operation;
  List<ProtocolDraft> get protocolDrafts =>
      List.unmodifiable(_protocols.values);
  List<InteractionDraft> get interactionDrafts =>
      List.unmodifiable(_interactions.values);
  List<InteractionProtocol> get savedInteractions =>
      List.unmodifiable(_savedInteractions.values);
  InteractionProtocol? savedInteraction(String id) => _savedInteractions[id];
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  Future<void> initialize({File? file}) async {
    if (_initialized) return;
    _file = file;
    Map<String, dynamic>? json;
    if (file != null && await file.exists()) {
      json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['version'] != 1) throw const FormatException('不支持的协议库版本');
    }
    final protocols = <String, ProtocolDefinition>{};
    final interactions = <String, InteractionProtocol>{};
    for (final item in json?['protocols'] as List? ?? const []) {
      final value = ProtocolDefinition.fromJson(
        Map<String, dynamic>.from(item as Map),
      );
      if (protocols.containsKey(value.id)) {
        throw const FormatException('解析协议标识重复');
      }
      protocols[value.id] = value;
    }
    for (final item in json?['interactions'] as List? ?? const []) {
      final value = InteractionProtocol.fromJson(
        Map<String, dynamic>.from(item as Map),
      );
      if (interactions.containsKey(value.id)) {
        throw const FormatException('交互协议标识重复');
      }
      interactions[value.id] = value;
    }
    var needsSave = false;
    if (json?['pointTableSeeded'] != true) {
      final value = InteractionProtocol(
        id: _id('interaction'),
        name: '点表协议—Lua',
        source: pointTableLuaSource,
      );
      interactions[value.id] = value;
      needsSave = true;
    }
    if (json?['ymodemSeeded'] != true) {
      final names = interactions.values.map((p) => p.name).toSet();
      const name = '标准 YMODEM—Lua';
      final value = InteractionProtocol(
        id: _id('interaction'),
        name: names.contains(name) ? nextDraftName(name, names) : name,
        source: ymodemLuaSource,
      );
      interactions[value.id] = value;
      needsSave = true;
    }
    if (needsSave) {
      await _write(protocols, interactions);
    }
    _savedProtocols = protocols;
    _savedInteractions = interactions;
    for (final p in protocols.values) {
      _protocols[p.id] = ProtocolDraft(p, onChanged: _publish);
    }
    for (final p in interactions.values) {
      _interactions[p.id] = InteractionDraft(p, onChanged: _publish);
    }
    _initialized = true;
    _publish();
  }

  Future<void> _write(
    Map<String, ProtocolDefinition> protocols,
    Map<String, InteractionProtocol> interactions,
  ) async {
    final json = <String, dynamic>{
      'version': 1,
      'pointTableSeeded': true,
      'ymodemSeeded': true,
      'protocols': protocols.values.map((p) => p.toJson()).toList(),
      'interactions': interactions.values.map((p) => p.toJson()).toList(),
    };
    if (persist != null) {
      await persist!(json);
      return;
    }
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    await pending.rename(file.path);
  }

  Future<void> _command(String name, Future<void> Function() action) async {
    if (operation != null) throw StateError('请等待当前保存操作完成');
    operation = name;
    _publish();
    try {
      await action();
    } finally {
      operation = null;
      _publish();
    }
  }

  void _ensureEditable() {
    if (!_initialized) throw StateError('协议库尚未载入');
    if (operation != null) throw StateError('请等待当前保存操作完成');
  }

  ProtocolDraft protocol(String id) =>
      _protocols[id] ?? (throw ArgumentError('协议不存在'));
  InteractionDraft interaction(String id) =>
      _interactions[id] ?? (throw ArgumentError('交互协议不存在'));

  ProtocolDraft createProtocol(String name) {
    _ensureEditable();
    if (name.trim().isEmpty) throw const FormatException('协议名称不能为空');
    final draft = ProtocolDraft.create(
      id: _id('protocol'),
      name: name.trim(),
      onChanged: _publish,
    );
    _protocols[draft.id] = draft;
    _publish();
    return draft;
  }

  ProtocolDraft duplicateProtocol(String id, String name) {
    _ensureEditable();
    final draft = ProtocolDraft.copyOf(
      protocol(id),
      id: _id('protocol'),
      name: name,
      onChanged: _publish,
    );
    _protocols[draft.id] = draft;
    _publish();
    return draft;
  }

  String exportProtocol(String id) =>
      const JsonEncoder.withIndent('  ').convert(protocol(id).build().toJson());
  ProtocolDraft importProtocol(String source) {
    _ensureEditable();
    final value = jsonDecode(source.replaceFirst(RegExp(r'^\uFEFF'), ''));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('协议文件必须是 JSON 对象');
    }
    final definition = ProtocolDefinition.fromJson(value);
    final names = protocolDrafts.map((d) => d.values['name'] as String).toSet();
    final draft = ProtocolDraft.copyOf(
      ProtocolDraft(definition),
      id: _id('protocol'),
      name: names.contains(definition.name)
          ? nextDraftName(definition.name, names)
          : definition.name,
      onChanged: _publish,
    );
    _protocols[draft.id] = draft;
    _publish();
    return draft;
  }

  Future<void> saveProtocol(String id) => _command('保存协议', () async {
    final draft = protocol(id), revision = protocol(id).revision;
    final value = draft.build();
    final saved = {..._savedProtocols, id: value};
    await _write(saved, _savedInteractions);
    _savedProtocols = saved;
    draft.acceptSaved(value, savedRevision: revision);
  });
  Future<void> deleteProtocol(String id) => _command('删除协议', () async {
    final saved = {..._savedProtocols}..remove(id);
    await _write(saved, _savedInteractions);
    _savedProtocols = saved;
    _protocols.remove(id);
  });

  InteractionDraft createInteraction(
    String name,
    InteractionPurpose purpose, {
    String? source,
  }) {
    _ensureEditable();
    final names = interactionDrafts.map((d) => d.name).toSet();
    final unique = names.contains(name) ? nextDraftName(name, names) : name;
    final draft = InteractionDraft(
      InteractionProtocol(
        id: _id('interaction'),
        name: unique,
        source: source ?? newInteractionSource(unique, purpose),
      ),
      isNew: true,
      onChanged: _publish,
    );
    _interactions[draft.id] = draft;
    _publish();
    return draft;
  }

  Future<InteractionValidationResult> validateInteraction(String id) =>
      interaction(id).validate(runtime.validate);
  Future<void> saveInteraction(String id) => _command('保存交互协议', () async {
    final draft = interaction(id), revision = interaction(id).revision;
    final value = draft.build();
    final saved = {..._savedInteractions, id: value};
    await _write(_savedProtocols, saved);
    _savedInteractions = saved;
    draft.acceptSaved(value, revision);
  });
  Future<void> deleteInteraction(String id) => _command('删除交互协议', () async {
    if ((_references[id] ?? 0) > 0) throw StateError('交互协议正在被引用，请先在升级页卸载');
    final saved = {..._savedInteractions}..remove(id);
    await _write(_savedProtocols, saved);
    _savedInteractions = saved;
    _interactions.remove(id)?.invalidateValidation();
  });
  void retain(String id) => _references[id] = (_references[id] ?? 0) + 1;
  void release(String id) {
    final remaining = (_references[id] ?? 0) - 1;
    if (remaining <= 0) {
      _references.remove(id);
    } else {
      _references[id] = remaining;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final draft in interactionDrafts) {
      draft.invalidateValidation();
    }
    super.dispose();
  }
}
