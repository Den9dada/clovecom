import 'dart:convert';
import 'dart:typed_data';
import '../core/protocol.dart';
import 'project_defaults.dart';

Map<String, dynamic> _copy(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// 草稿可暂时无效；只有 build/保存才进入已校验运行模型。
abstract class EditableDraft<T> {
  EditableDraft(
    Map<String, dynamic> value, {
    bool isNew = false,
    this.onChanged,
  }) : _isNew = isNew,
       _data = _copy(value),
       _baseline = jsonEncode(value);
  Map<String, dynamic> _data;
  String _baseline;
  bool _isNew;
  final void Function()? onChanged;
  int _revision = 0;
  int get revision => _revision;
  String get id => _data['id'] as String;
  bool get isDirty => _isNew || jsonEncode(_data) != _baseline;
  Map<String, dynamic> get values => _copy(_data);
  void changed() {
    _revision++;
    onChanged?.call();
  }

  void discard() {
    _data = jsonDecode(_baseline) as Map<String, dynamic>;
    changed();
  }

  void _saved(Map<String, dynamic> value, {int? savedRevision}) {
    // 保存过程中仍允许编辑，新修改不会被旧保存结果覆盖。
    _baseline = jsonEncode(value);
    if (savedRevision == null || savedRevision == revision) {
      _data = _copy(value);
    }
    _isNew = false;
    onChanged?.call();
  }

  T build();
  List<String> validate() {
    try {
      build();
      return const [];
    } catch (error) {
      return [error.toString()];
    }
  }
}

class ProtocolDraftIssue {
  const ProtocolDraftIssue({
    required this.messageId,
    required this.messageName,
    required this.code,
    required this.message,
    this.lengthField,
    this.fieldName,
  });
  final String messageId;
  final String messageName;
  final String code;
  final String message;
  final String? lengthField;
  final String? fieldName;
  String get display => '消息类型 $messageName：$message';
}

class ParsePreview {
  ParsePreview({
    required this.revision,
    required this.hex,
    required List<ParsedFrame> frames,
    required List<String> errors,
    required this.errorCount,
  }) : frames = List.unmodifiable(frames),
       errors = List.unmodifiable(errors);
  final int revision;

  /// 触发本次解析的 Hex 文本。
  final String hex;
  final List<ParsedFrame> frames;
  final List<String> errors;
  final int errorCount;
  bool get succeeded => frames.isNotEmpty && errorCount == 0;
}

enum ProtocolFrameMode { fixed, length, tail, coverage }

class ProtocolDraft extends EditableDraft<ProtocolDefinition> {
  ProtocolDraft(ProtocolDefinition protocol, {super.onChanged})
    : super(protocol.toJson());
  ProtocolDraft.create({
    required String id,
    required String name,
    super.onChanged,
  }) : super({
         'version': 1,
         'id': id,
         'name': name,
         'fields': <dynamic>[],
         'kind': 'position',
         'mapping': <String, dynamic>{},
         'fixedLength': null,
         'lengthField': null,
         'lengthMultiplier': 1,
         'lengthAdjustment': 0,
         'maxFrameLength': 65536,
         'checksum': null,
         'checksumStart': 0,
         'distanceUnit': DistanceUnit.meters.name,
         'lengthCoverageMode': false,
         'lengthCoverages': <dynamic>[],
       }, isNew: true);
  ProtocolDraft.copyOf(
    ProtocolDraft other, {
    required String id,
    required String name,
    super.onChanged,
  }) : super({..._copy(other._data), 'id': id, 'name': name}, isNew: true);

  int _selectedMessage = 0;
  int get selectedMessageIndex => _selectedMessage;
  List<dynamic>? get _messages => _data['messageTypes'] as List<dynamic>?;
  int get messageCount => _messages?.length ?? 1;
  Map<String, dynamic> get _messageData => _messages == null
      ? _data
      : messageCount == 0
      ? _emptyMessage
      : _messages![_selectedMessage] as Map<String, dynamic>;
  final Map<String, dynamic> _emptyMessage = {
    'fields': <dynamic>[],
    'mapping': <String, dynamic>{},
    'lengthCoverages': <dynamic>[],
  };
  String messageName(int index) =>
      _messages == null ? '默认消息' : _messages![index]['name'] as String;
  String get selectedMessageName =>
      messageCount == 0 ? '无消息类型' : messageName(_selectedMessage);

  @override
  Map<String, dynamic> get values =>
      _copy({..._messageData, 'id': id, 'name': _data['name']});

  void selectMessage(int index) {
    RangeError.checkValidIndex(index, List.filled(messageCount, 0));
    if (_selectedMessage == index) return;
    _selectedMessage = index;
    _resetFieldIdentities();
    _preview = null;
    _sampleRevision = null;
    onChanged?.call();
  }

  void _ensureCollection() {
    if (_messages != null) return;
    final first = _copy(_data);
    first['id'] = 'default';
    first['name'] = '默认消息';
    _data = {
      'version': 3,
      'id': id,
      'name': _data['name'],
      'messageTypes': [first],
    };
  }

  void addMessage({bool copySelected = false}) {
    _ensureCollection();
    final name = nextDraftName(
      copySelected ? '$selectedMessageName 副本' : '新消息',
      List.generate(messageCount, messageName),
    );
    final json = copySelected && messageCount > 0
        ? _copy(_messageData)
        : ProtocolDraft.create(id: 'new', name: name)._data;
    var ordinal = 1;
    while (_messages!.any((m) => m['id'] == 'message_$ordinal')) {
      ordinal++;
    }
    json['id'] = 'message_$ordinal';
    json['name'] = name;
    _messages!.add(json);
    _selectedMessage = messageCount - 1;
    _resetFieldIdentities();
    changed();
  }

  void renameMessage(String name) {
    if (name.trim().isEmpty) throw const FormatException('消息类型名称不能为空');
    _ensureCollection();
    if (_messages!.asMap().entries.any(
      (e) => e.key != _selectedMessage && e.value['name'] == name.trim(),
    )) {
      throw const FormatException('消息类型名称重复');
    }
    _messageData['name'] = name.trim();
    changed();
  }

  void removeMessage() {
    _ensureCollection();
    if (messageCount == 0) return;
    _messages!.removeAt(_selectedMessage);
    _selectedMessage = (_selectedMessage - 1).clamp(
      0,
      messageCount == 0 ? 0 : messageCount - 1,
    );
    _resetFieldIdentities();
    changed();
  }

  void _resetFieldIdentities() {
    _fieldIdentities = List.generate(fieldCount, (_) => Object());
  }

  List<String> validateSelected() {
    try {
      buildSelected();
      return [];
    } catch (error) {
      return [error.toString()];
    }
  }

  int _coverageRevision = -1;
  Object? _coverageData;
  final Map<String, LengthCoverageAnalysis> _coverageCache = {};
  LengthCoverageAnalysis _coverageAnalysis(Map<String, dynamic> message) {
    if (_coverageRevision != revision || !identical(_coverageData, _data)) {
      _coverageRevision = revision;
      _coverageData = _data;
      _coverageCache.clear();
    }
    return _coverageCache.putIfAbsent(
      '${message['id']}',
      () => LengthCoverageAnalysis(
        fields: [
          for (final field in message['fields'] as List<dynamic>)
            CoverageFieldFacts.fromDraft(
              Map<String, dynamic>.from(field as Map),
            ),
        ],
        rules: [
          for (final rule in message['lengthCoverages'] as List<dynamic>? ?? [])
            LengthCoverage.fromJson(Map<String, dynamic>.from(rule as Map)),
        ],
        enabled: message['lengthCoverageMode'] == true,
      ),
    );
  }

  CoverageEditorState coverageEditor(String source) =>
      _coverageAnalysis(_messageData).editor(source);

  List<ProtocolDraftIssue> get issues {
    final result = <ProtocolDraftIssue>[];
    final messages = _messages == null ? [_data] : _messages!;
    for (final raw in messages) {
      final message = Map<String, dynamic>.from(raw as Map);
      final messageId = '${message['id']}';
      final name = _messages == null ? '默认消息' : '${message['name']}';
      final analysis = _coverageAnalysis(message);
      for (final issue in analysis.issues) {
        result.add(
          ProtocolDraftIssue(
            messageId: messageId,
            messageName: name,
            code: issue.code,
            message: issue.message,
            lengthField: issue.lengthField,
            fieldName: issue.fieldName,
          ),
        );
      }
      if (analysis.issues.isEmpty) {
        try {
          _buildMessage(_copy(message));
        } catch (error) {
          result.add(
            ProtocolDraftIssue(
              messageId: messageId,
              messageName: name,
              code: 'message',
              message: error.toString(),
            ),
          );
        }
      }
    }
    if (result.isEmpty) {
      try {
        build();
      } catch (error) {
        result.add(
          ProtocolDraftIssue(
            messageId: '',
            messageName: '整个协议',
            code: 'protocol',
            message: error.toString(),
          ),
        );
      }
    }
    return List.unmodifiable(result);
  }

  List<ProtocolDraftIssue> get selectedIssues => issues
      .where(
        (issue) =>
            issue.messageId == '${_messageData['id']}' ||
            issue.code == 'protocol',
      )
      .toList();

  @override
  List<String> validate() => issues.map((issue) => issue.display).toList();

  ParsePreview? _preview;
  bool _testSelectedOnly = false;
  bool get testSelectedOnly => _testSelectedOnly;
  set testSelectedOnly(bool value) {
    if (_testSelectedOnly == value) return;
    _testSelectedOnly = value;
    _preview = null;
    onChanged?.call();
  }

  ParsePreview? get preview => _preview?.revision == revision ? _preview : null;
  String _inputHex = '';
  String get inputHex => _inputHex;

  /// 测试输入不修改协议草稿，但修改后必须立即使旧预览失效。
  set inputHex(String value) {
    if (value == _inputHex) return;
    _inputHex = value;
    _preview = null;
    onChanged?.call();
  }

  String? _sample;
  int? _sampleRevision;
  String get sampleHex {
    if (_sampleRevision != revision) _updateSample();
    return _sample!;
  }

  void _updateSample() {
    try {
      _sample = generateSampleHex();
    } catch (error) {
      _sample = '生成失败：$error';
    }
    _sampleRevision = revision;
  }

  void refreshSample() {
    _updateSample();
    onChanged?.call();
  }

  List<dynamic> get _fields => _messageData['fields'] as List<dynamic>;
  Map<String, dynamic> get _mapping =>
      _messageData['mapping'] as Map<String, dynamic>;
  // 编辑器专用标识，不写入协议文件；重命名、排序和保存均保持稳定。
  late List<Object> _fieldIdentities = List.generate(
    fieldCount,
    (_) => Object(),
  );
  Object fieldIdentity(int index) => _fieldIdentities[index];
  int get fieldCount => _fields.length;
  Map<String, dynamic> field(int index) =>
      _copy(_fields[index] as Map<String, dynamic>);

  void set(String key, Object? value) {
    if (!{
      'name',
      'kind',
      'fixedLength',
      'lengthField',
      'lengthMultiplier',
      'lengthAdjustment',
      'maxFrameLength',
      'checksum',
      'checksumStart',
      'distanceUnit',
      'lengthCoverageMode',
      'lengthCoverages',
    }.contains(key)) {
      throw ArgumentError('未知或只读的协议属性：$key');
    }
    if (key == 'kind' && value == 'display') _ensureCollection();
    if (key == 'name') {
      _data[key] = value;
    } else {
      _messageData[key] = value;
    }
    changed();
  }

  void addField(ProtocolField field, {String? semantic}) {
    _insertField(field, semantic: semantic);
    changed();
  }

  /// 一次添加意图同时协调长度字段，不向观察者暴露中间状态。
  void addConfiguredField(ProtocolField field, {String? semantic}) {
    _insertField(field, semantic: semantic);
    if (field.role == FieldRole.length &&
        _messageData['lengthField'] == null &&
        !usesLengthCoverage) {
      _messageData['fixedLength'] = null;
      _messageData['lengthField'] = field.name;
    }
    changed();
  }

  void _insertField(ProtocolField field, {String? semantic}) {
    if (_fields.any((f) => (f as Map<String, dynamic>)['name'] == field.name)) {
      throw const FormatException('字段名称重复');
    }
    final suffixIndex = _fields.indexWhere((f) => f['fromEnd'] == true);
    final index = field.role == FieldRole.header
        ? 0
        : !field.fromEnd && suffixIndex >= 0
        ? suffixIndex
        : fieldCount;
    _fieldIdentities.insert(index, Object());
    _fields.insert(index, field.toJson());
    if (semantic != null) _mapping[semantic] = field.name;
  }

  /// 先计算关联值再发布；草稿暂时无效仍允许继续编辑。
  void setFrameMode(ProtocolFrameMode mode) {
    int? fixedLength;
    String? lengthField;
    if (mode == ProtocolFrameMode.fixed) {
      try {
        fixedLength = totalFieldBytes;
      } on FormatException {
        fixedLength = 0;
      }
    } else if (mode == ProtocolFrameMode.length) {
      final lengths = _fields.where((field) => field['role'] == 'length');
      lengthField = lengths.isEmpty ? '' : lengths.first['name'] as String;
    }
    _messageData['fixedLength'] = fixedLength;
    _messageData['lengthField'] = lengthField;
    _messageData['lengthCoverageMode'] = mode == ProtocolFrameMode.coverage;
    _messageData['lengthCoverages'] ??= <dynamic>[];
    changed();
  }

  bool get usesLengthCoverage => _messageData['lengthCoverageMode'] == true;
  List<LengthCoverage> get lengthCoverages =>
      (_messageData['lengthCoverages'] as List<dynamic>? ?? [])
          .map((r) => LengthCoverage.fromJson(r as Map<String, dynamic>))
          .toList();

  void setLengthCoverage(
    String source, {
    String? startField,
    String? endField,
    String? derivedField,
  }) {
    final rules = lengthCoverages;
    final old = rules.where((r) => r.lengthField == source).firstOrNull;
    final start = startField ?? old?.startField ?? '';
    final end = endField ?? old?.endField ?? '';
    // 选择变长数据段是一项完整编辑意图，不能留下 uint + 自动长度的矛盾状态。
    if (derivedField != null && derivedField.isNotEmpty) {
      final target = _fields
          .where((f) => f['name'] == derivedField)
          .firstOrNull;
      if (target == null ||
          (target['role'] != 'data' && target['role'] != 'skip') ||
          target['fixed'] != null) {
        throw const FormatException('自动长度字段必须是无固定值的数据或跳过字段');
      }
      if (target['type'] != 'bytes' &&
          '${target['sampleValue'] ?? ''}'.trim().isNotEmpty) {
        try {
          final field = ProtocolField.fromJson(
            Map<String, dynamic>.from(target as Map),
          );
          final bytes = encodeSample(
            ProtocolDefinition(
              id: 'sample-conversion',
              kind: PayloadKind.display,
              mapping: {},
              fields: [field],
              fixedLength: field.size,
            ),
          );
          target['sampleValue'] = bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');
        } on FormatException {
          // 不覆盖尚未输入完成的样例，保留内容供用户修正。
        }
      }
      target['type'] = 'bytes';
    }
    final next = LengthCoverage(
      lengthField: source,
      startField: start,
      endField: end,
      derivedField:
          derivedField ??
          ((old != null && old.startField.isNotEmpty && old.endField.isNotEmpty
                  ? old.derivedField
                  : null) ??
              (start == end &&
                      start.isNotEmpty &&
                      _fields.any(
                        (f) =>
                            f['name'] == start &&
                            f['type'] == 'bytes' &&
                            (f['role'] == 'data' || f['role'] == 'skip') &&
                            f['fixed'] == null,
                      )
                  ? start
                  : '')),
    );
    _messageData['lengthCoverages'] = [
      for (final rule in rules)
        (rule.lengthField == source ? next : rule).toJson(),
      if (old == null) next.toJson(),
    ];
    changed();
  }

  void removeLengthCoverage(String source) {
    _messageData['lengthCoverages'] = [
      for (final r in lengthCoverages)
        if (r.lengthField != source) r.toJson(),
    ];
    changed();
  }

  LengthCoverage? coverageOf(int index) {
    return _coverageAnalysis(_messageData).covering(index).firstOrNull;
  }

  String lengthFormula(LengthCoverage rule) {
    return coverageEditor(rule.lengthField).formula;
  }

  /// 字段身份不随重排变化；解除旧角色和建立新角色只通知一次。
  void assignFieldSemantic(Object identity, String? semantic) {
    final index = _fieldIdentities.indexOf(identity);
    if (index < 0) throw StateError('字段已不存在');
    final name = _fields[index]['name'] as String;
    _mapping.removeWhere((_, value) => value == name);
    if (semantic != null) _mapping[semantic] = name;
    changed();
  }

  void updateField(int index, Map<String, dynamic> changes) {
    final previous = field(index);
    if (changes.keys.any((key) => !previous.containsKey(key))) {
      throw const FormatException('字段属性未知');
    }
    final next = {...previous, ...changes};
    // 修改关联规则前先检查身份，失败不能留下部分解除的自动长度引用。
    if (next['name'] != previous['name'] &&
        _fields.asMap().entries.any(
          (entry) =>
              entry.key != index &&
              (entry.value as Map<String, dynamic>)['name'] == next['name'],
        )) {
      throw const FormatException('字段名称重复');
    }
    if (usesLengthCoverage &&
        lengthCoverages.any((r) => r.derivedField == previous['name']) &&
        (next['type'] != 'bytes' ||
            (next['role'] != 'data' && next['role'] != 'skip') ||
            next['fixed'] != null)) {
      // 改回定长类型时同时解除自动长度，恢复有效的字段宽度。
      for (final rule in _messageData['lengthCoverages'] as List<dynamic>) {
        if (rule['derivedField'] == previous['name']) rule['derivedField'] = '';
      }
      final size = int.tryParse('${next['size']}');
      final validSizes = next['type'] == 'float' ? [4, 8] : [1, 2, 4, 8];
      if (size == null ||
          size <= 0 ||
          (next['type'] != 'bytes' && !validSizes.contains(size))) {
        next['size'] = next['type'] == 'float' ? 4 : 1;
      }
    }
    if (next['name'] != previous['name']) {
      for (final key in _mapping.keys.toList()) {
        if (_mapping[key] == previous['name']) _mapping[key] = next['name'];
      }
      if (_messageData['lengthField'] == previous['name']) {
        _messageData['lengthField'] = next['name'];
      }
      for (final rule
          in _messageData['lengthCoverages'] as List<dynamic>? ?? []) {
        for (final key in [
          'lengthField',
          'startField',
          'endField',
          'derivedField',
        ]) {
          if (rule[key] == previous['name']) rule[key] = next['name'];
        }
      }
    }
    _fields[index] = _copy(next);
    changed();
  }

  void mapField(String semantic, String? fieldName) {
    if (fieldName == null) {
      _mapping.remove(semantic);
    } else {
      _mapping[semantic] = fieldName;
    }
    changed();
  }

  void removeField(int index) {
    _fieldIdentities.removeAt(index);
    final removed = _fields.removeAt(index) as Map<String, dynamic>;
    _mapping.removeWhere((_, value) => value == removed['name']);
    if (_messageData['lengthField'] == removed['name']) {
      _messageData['lengthField'] = null;
    }
    changed();
  }

  /// newIndex 是移动完成后的目标索引，不使用 Flutter ReorderableList 的原始索引语义。
  void moveField(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= fieldCount ||
        newIndex < 0 ||
        newIndex >= fieldCount) {
      throw RangeError('字段索引越界');
    }
    final moved = _fields.removeAt(oldIndex);
    _fields.insert(newIndex, moved);
    final identity = _fieldIdentities.removeAt(oldIndex);
    _fieldIdentities.insert(newIndex, identity);
    changed();
  }

  @override
  void discard() {
    _data = jsonDecode(_baseline) as Map<String, dynamic>;
    _selectedMessage = 0;
    _resetFieldIdentities();
    changed();
  }

  int get totalFieldBytes => _fields.fold(
    0,
    (sum, value) =>
        sum + _integer((value as Map<String, dynamic>)['size'], '字段字节数'),
  );
  int byteOffset(int index, {int? frameLength}) {
    if (usesLengthCoverage &&
        _fields
            .take(index)
            .any(
              (f) => lengthCoverages.any((r) => r.derivedField == f['name']),
            )) {
      throw const FormatException('实际偏移由报文长度确定');
    }
    final current = field(index);
    if (current['fromEnd'] == true && !usesLengthCoverage) {
      final length =
          frameLength ??
          (_messageData['fixedLength'] == null
              ? totalFieldBytes
              : _integer(_messageData['fixedLength'], '总帧长'));
      return length -
          _fields
              .skip(index)
              .fold<int>(
                0,
                (sum, value) =>
                    sum +
                    _integer((value as Map<String, dynamic>)['size'], '字段字节数'),
              );
    }
    return _fields
        .take(index)
        .fold<int>(
          0,
          (sum, value) =>
              sum + _integer((value as Map<String, dynamic>)['size'], '字段字节数'),
        );
  }

  @override
  ProtocolDefinition build() {
    if (_messages == null) return _buildMessage(_copy(_data));
    return ProtocolDefinition.collection(
      id: id,
      name: _data['name'] as String,
      messageTypes: [
        for (final raw in _messages!)
          _buildMessage(_copy(raw as Map<String, dynamic>)),
      ],
    );
  }

  ProtocolDefinition buildSelected() {
    if (messageCount == 0) throw const FormatException('协议至少需要一个消息类型');
    final json = _copy(_messageData);
    if (_messages == null) json['name'] = '默认消息';
    final message = _buildMessage(json);
    if (_messages != null) {
      ProtocolDefinition.collection(
        id: id,
        name: _data['name'] as String,
        messageTypes: [message],
      );
    }
    return message;
  }

  ProtocolDefinition _buildMessage(Map<String, dynamic> json) {
    try {
      final usesLengthCoverage = json['lengthCoverageMode'] == true;
      final lengthCoverages = (json['lengthCoverages'] as List<dynamic>? ?? [])
          .map((r) => LengthCoverage.fromJson(r as Map<String, dynamic>))
          .toList();
      json['version'] = usesLengthCoverage ? 2 : 1;
      for (final key in [
        'fixedLength',
        'lengthMultiplier',
        'lengthAdjustment',
        'maxFrameLength',
        'checksumStart',
      ]) {
        if (json[key] != null) json[key] = _integer(json[key], key);
      }
      for (final value in json['fields'] as List<dynamic>) {
        final f = value as Map<String, dynamic>;
        f['size'] =
            usesLengthCoverage &&
                lengthCoverages.any((r) => r.derivedField == f['name'])
            ? 1
            : _integer(f['size'], '${f['name']} 字节数');
        for (final key in ['scale', 'bias']) {
          if (f[key] is String) {
            f[key] =
                double.tryParse(f[key] as String) ??
                (throw FormatException('${f['name']} $key 不是数值'));
          }
        }
      }
      return ProtocolDefinition.fromJson(json);
    } on FormatException catch (error) {
      throw FormatException('消息类型 ${json['name']}：${error.message}');
    } catch (error) {
      throw FormatException('协议草稿字段类型无效：$error');
    }
  }

  ParsePreview testHex(String text, {bool selectedOnly = false}) {
    _inputHex = text;
    try {
      final batch = FrameDecoder(
        selectedOnly ? buildSelected() : build(),
      ).add(parseHexBytes(text), endOfDatagram: true);
      _preview = ParsePreview(
        revision: revision,
        hex: text,
        frames: batch.frames,
        errors: batch.frames.isEmpty && batch.errors.isEmpty
            ? ['没有完整数据帧']
            : batch.errors,
        errorCount: batch.frames.isEmpty && batch.errors.isEmpty
            ? 1
            : batch.errorCount,
      );
    } catch (error) {
      _preview = ParsePreview(
        revision: revision,
        hex: text,
        frames: [],
        errors: [error.toString()],
        errorCount: 1,
      );
    }
    onChanged?.call();
    return _preview!;
  }

  String generateSampleHex({int? frameLength}) => encodeSample(
    buildSelected(),
    frameLength: frameLength,
  ).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  void acceptSaved(ProtocolDefinition definition, {int? savedRevision}) =>
      _saved(definition.toJson(), savedRevision: savedRevision);
}

int _integer(Object? value, String name) {
  if (value is int) return value;
  if (value is String) {
    return int.tryParse(value) ?? (throw FormatException('$name 必须为整数'));
  }
  throw FormatException('$name 必须为整数');
}

List<int> parseHexBytes(String text) {
  final compact = text
      .replaceAll(RegExp(r'0[xX]'), '')
      .replaceAll(RegExp(r'\s+'), '');
  if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(compact)) {
    throw const FormatException('请输入完整的十六进制字节');
  }
  return [
    for (var i = 0; i < compact.length; i += 2)
      int.parse(compact.substring(i, i + 2), radix: 16),
  ];
}

/// 样例值是线上的原始数值；长度和校验字段由配置自动计算。
Uint8List encodeSample(ProtocolDefinition protocol, {int? frameLength}) {
  final sizes = <String, int>{
    for (final field in protocol.fields)
      field.name: protocol.isDerived(field.name)
          ? parseHexBytes(field.sampleValue.trim()).length
          : field.size,
  };
  final offsets = <String, int>{};
  var computedLength = 0;
  for (final field in protocol.fields) {
    offsets[field.name] = computedLength;
    computedLength += sizes[field.name]!;
  }
  final length =
      frameLength ??
      protocol.fixedLength ??
      (protocol.lengthCoverageMode ? computedLength : protocol.minimumLength);
  if (protocol.lengthCoverageMode && length != computedLength) {
    throw const FormatException('覆盖范围模式的样例帧长由字段样例确定');
  }
  if (length < protocol.minimumLength ||
      length > protocol.maxFrameLength ||
      (protocol.fixedLength != null && length != protocol.fixedLength)) {
    throw const FormatException('样例帧长无效');
  }
  final bytes = Uint8List(length);
  for (final field in protocol.fields) {
    final offset = protocol.lengthCoverageMode
        ? offsets[field.name]!
        : protocol.offsetOf(field, length);
    final size = sizes[field.name]!;
    if (field.fixed != null) {
      bytes.setAll(offset, field.fixed!);
      continue;
    }
    if (field.role == FieldRole.checksum || field.role == FieldRole.skip) {
      continue;
    }
    var sample = field.sampleValue.trim();
    if (protocol.lengthCoverageMode) {
      final rule = protocol.lengthCoverages
          .where((r) => r.lengthField == field.name)
          .firstOrNull;
      if (rule != null) {
        final first = protocol.fields.indexWhere(
          (f) => f.name == rule.startField,
        );
        final last = protocol.fields.indexWhere((f) => f.name == rule.endField);
        sample =
            '${protocol.fields.sublist(first, last + 1).fold<int>(0, (sum, f) => sum + sizes[f.name]!)}';
      }
    }
    if (field.name == protocol.lengthField) {
      final numerator = length - protocol.lengthAdjustment;
      if (numerator < 0 || numerator % protocol.lengthMultiplier != 0) {
        throw const FormatException('总帧长无法由长度字段规则表达');
      }
      sample = '${numerator ~/ protocol.lengthMultiplier}';
    }
    if (field.type == FieldType.bytes) {
      final data = sample.isEmpty
          ? List<int>.filled(size, 0)
          : parseHexBytes(sample);
      if (data.length != size) {
        throw FormatException('${field.name} 样例字节数不匹配');
      }
      bytes.setAll(offset, data);
    } else if (field.type == FieldType.float) {
      final value = double.tryParse(sample.isEmpty ? '0' : sample);
      if (value == null || !value.isFinite) {
        throw FormatException('${field.name} 样例必须为有限数值');
      }
      final data = ByteData.sublistView(bytes);
      final endian = field.littleEndian ? Endian.little : Endian.big;
      if (field.size == 4) {
        data.setFloat32(offset, value, endian);
        if (!data.getFloat32(offset, endian).isFinite) {
          throw FormatException('${field.name} 超出 float32 范围');
        }
      } else {
        data.setFloat64(offset, value, endian);
      }
    } else {
      var value = BigInt.tryParse(sample.isEmpty ? '0' : sample);
      if (value == null) throw FormatException('${field.name} 样例必须为整数');
      final bits = field.size * 8;
      final signed = field.type == FieldType.sint;
      final min = signed ? -(BigInt.one << (bits - 1)) : BigInt.zero;
      final max = (BigInt.one << (signed ? bits - 1 : bits)) - BigInt.one;
      if (value < min || value > max) {
        throw FormatException('${field.name} 样例超出字段范围');
      }
      if (value.isNegative) value += BigInt.one << bits;
      for (var i = 0; i < field.size; i++) {
        bytes[offset + (field.littleEndian ? i : field.size - i - 1)] =
            ((value >> (8 * i)) & BigInt.from(255)).toInt();
      }
    }
  }
  if (protocol.checksum != null) {
    final field = protocol.fields.firstWhere(
      (f) => f.role == FieldRole.checksum,
    );
    final offset = protocol.lengthCoverageMode
        ? offsets[field.name]!
        : protocol.offsetOf(field, length);
    final check = computeChecksum(
      protocol.checksum!,
      bytes.sublist(protocol.checksumStart, offset),
    );
    for (var i = 0; i < field.size; i++) {
      bytes[offset + (field.littleEndian ? i : field.size - i - 1)] =
          (check >> (i * 8)) & 255;
    }
  }
  return bytes;
}
