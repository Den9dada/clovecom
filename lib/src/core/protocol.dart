import 'dart:typed_data';

part 'length_coverage.dart';

bool _sameProtocolValue(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) =>
              right.containsKey(key) &&
              _sameProtocolValue(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_sameProtocolValue(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

enum FieldRole { header, frameId, length, data, checksum, tail, skip }

enum FieldType { uint, sint, float, bytes }

enum ChecksumKind { sum8, xor8, crc16Modbus }

enum PayloadKind { position, observation, display }

/// 距离字段的物理单位；引擎按 [toMeters] 换算到内部世界单位（米）后再参与解算。
enum DistanceUnit {
  meters,
  centimeters;

  double get toMeters => this == DistanceUnit.centimeters ? 0.01 : 1.0;
  String get label => this == DistanceUnit.centimeters ? '厘米' : '米';
  String get symbol => this == DistanceUnit.centimeters ? 'cm' : 'm';
}

class ProtocolField {
  ProtocolField({
    required this.name,
    required this.size,
    this.role = FieldRole.data,
    this.type = FieldType.uint,
    this.littleEndian = true,
    this.scale = 1,
    this.bias = 0,
    this.fromEnd = false,
    this.description = '',
    this.sampleValue = '',
    List<int>? fixed,
  }) : fixed = fixed == null ? null : List.unmodifiable(fixed);

  final String name;
  final int size;
  final FieldRole role;
  final FieldType type;
  final bool littleEndian;
  final double scale;
  final double bias;

  /// 可变长度帧的后缀字段，从帧末尾定位。
  final bool fromEnd;
  final List<int>? fixed;
  final String description;

  /// 仅供编辑器生成测试报文，不约束接收数据。
  final String sampleValue;

  Map<String, dynamic> toJson() => {
    'name': name,
    'size': size,
    'role': role.name,
    'type': type.name,
    'littleEndian': littleEndian,
    'scale': scale,
    'bias': bias,
    'fromEnd': fromEnd,
    'fixed': fixed,
    'description': description,
    'sampleValue': sampleValue,
  };
  factory ProtocolField.fromJson(Map<String, dynamic> json) => ProtocolField(
    name: json['name'] as String,
    size: json['size'] as int,
    role: FieldRole.values.byName(json['role'] as String),
    type: FieldType.values.byName(json['type'] as String),
    littleEndian: json['littleEndian'] as bool,
    scale: (json['scale'] as num).toDouble(),
    bias: (json['bias'] as num).toDouble(),
    fromEnd: json['fromEnd'] as bool,
    fixed: (json['fixed'] as List<dynamic>?)?.cast<int>(),
    description: json['description'] as String? ?? '',
    sampleValue: json['sampleValue'] as String? ?? '',
  );
}

/// 一个长度字段声明一个连续范围，其中只有一个字段按剩余长度解析。
class LengthCoverage {
  const LengthCoverage({
    required this.lengthField,
    required this.startField,
    required this.endField,
    this.derivedField = '',
  });
  final String lengthField;
  final String startField;
  final String endField;
  final String derivedField;
  Map<String, dynamic> toJson() => {
    'lengthField': lengthField,
    'startField': startField,
    'endField': endField,
    'derivedField': derivedField,
  };
  factory LengthCoverage.fromJson(Map<String, dynamic> json) => LengthCoverage(
    lengthField: json['lengthField'] as String,
    startField: json['startField'] as String,
    endField: json['endField'] as String,
    derivedField: json['derivedField'] as String? ?? '',
  );
}

class FrameLayout {
  FrameLayout(
    Map<String, int> offsets,
    Map<String, int> sizes,
    Map<String, int> lengthValues,
    this.frameLength,
  ) : offsets = Map.unmodifiable(offsets),
      sizes = Map.unmodifiable(sizes),
      lengthValues = Map.unmodifiable(lengthValues);
  final Map<String, int> offsets;
  final Map<String, int> sizes;
  final Map<String, int> lengthValues;
  final int frameLength;
}

class ProtocolDefinition {
  ProtocolDefinition({
    required this.id,
    String? name,
    required List<ProtocolField> fields,
    required this.kind,
    required Map<String, String> mapping,
    this.fixedLength,
    this.lengthField,
    this.lengthMultiplier = 1,
    this.lengthAdjustment = 0,
    this.maxFrameLength = 65536,
    this.checksum,
    this.checksumStart = 0,
    this.distanceUnit = DistanceUnit.meters,
    this.lengthCoverageMode = false,
    List<LengthCoverage> lengthCoverages = const [],
    List<ProtocolDefinition>? messageTypes,
  }) : name = name ?? id,
       _messageTypes = messageTypes == null
           ? null
           : List.unmodifiable(messageTypes),
       fields = List.unmodifiable(fields),
       mapping = Map.unmodifiable(mapping),
       lengthCoverages = List.unmodifiable(lengthCoverages) {
    _validate();
    if (_messageTypes != null) _validateMessageTypes();
  }

  /// 集合中的成员只描述一种消息；旧定义自然作为唯一默认消息使用。
  final List<ProtocolDefinition>? _messageTypes;
  bool get isMessageCollection => _messageTypes != null;
  List<ProtocolDefinition> get messageTypes => _messageTypes ?? [this];

  factory ProtocolDefinition.collection({
    required String id,
    required String name,
    required List<ProtocolDefinition> messageTypes,
  }) {
    if (messageTypes.isEmpty) throw const FormatException('协议至少需要一个消息类型');
    final first = messageTypes.first;
    return ProtocolDefinition(
      id: id,
      name: name,
      fields: first.fields,
      kind: first.kind,
      mapping: first.mapping,
      fixedLength: first.fixedLength,
      lengthField: first.lengthField,
      lengthMultiplier: first.lengthMultiplier,
      lengthAdjustment: first.lengthAdjustment,
      maxFrameLength: messageTypes
          .map((m) => m.maxFrameLength)
          .reduce((a, b) => a > b ? a : b),
      checksum: first.checksum,
      checksumStart: first.checksumStart,
      distanceUnit: first.distanceUnit,
      lengthCoverageMode: first.lengthCoverageMode,
      lengthCoverages: first.lengthCoverages,
      messageTypes: messageTypes,
    );
  }

  /// 只用位置已确定的前缀固定字段识别，载荷、帧尾和校验不参与分派。
  Map<int, int> get recognitionBytes {
    final result = <int, int>{};
    var offset = 0;
    for (final field in fields) {
      if (field.fromEnd || isDerived(field.name)) break;
      if (field.fixed != null &&
          field.role != FieldRole.tail &&
          field.role != FieldRole.checksum) {
        for (var i = 0; i < field.size; i++) {
          result[offset + i] = field.fixed![i];
        }
      }
      offset += field.size;
    }
    return result;
  }

  void _validateMessageTypes() {
    final ids = <String>{};
    final names = <String>{};
    for (final message in messageTypes) {
      if (message.isMessageCollection ||
          !ids.add(message.id) ||
          !names.add(message.name)) {
        throw FormatException('消息类型嵌套或标识/名称重复：${message.name}');
      }
      var variable = false;
      for (final field in message.fields) {
        variable = variable || field.fromEnd || message.isDerived(field.name);
        if (variable &&
            field.fixed != null &&
            field.role != FieldRole.tail &&
            field.role != FieldRole.checksum) {
          throw FormatException('消息类型 ${message.name}：用于识别的固定字段必须位于可变载荷之前');
        }
      }
    }
    for (var i = 0; i < messageTypes.length; i++) {
      for (var j = i + 1; j < messageTypes.length; j++) {
        final a = messageTypes[i];
        final b = messageTypes[j];
        final left = a.recognitionBytes;
        final right = b.recognitionBytes;
        if (!left.entries.any(
          (e) => right.containsKey(e.key) && right[e.key] != e.value,
        )) {
          throw FormatException(
            '消息类型识别冲突：${a.name} / ${b.name}，请配置可区分的帧头或固定类型字段',
          );
        }
      }
    }
  }

  final String id;
  final String name;
  final List<ProtocolField> fields;
  final PayloadKind kind;
  final Map<String, String> mapping;
  final int? fixedLength;
  final String? lengthField;
  final int lengthMultiplier;
  final int lengthAdjustment;
  final int maxFrameLength;
  final bool lengthCoverageMode;
  final List<LengthCoverage> lengthCoverages;
  final ChecksumKind? checksum;

  /// 校验覆盖 [checksumStart, 校验字段起始位置)，不包含校验字段。
  final int checksumStart;

  /// 距离字段的物理单位；仅在观测语义且映射了 distance 时生效。
  final DistanceUnit distanceUnit;

  /// 编辑信息不参与接收行为；消息身份和结构仍必须能安全对应。
  bool hasSameRuntimeSemantics(ProtocolDefinition other) {
    Map<String, dynamic> runtime(ProtocolDefinition definition) {
      final json = definition.toJson()..remove('name');
      if (definition.isMessageCollection) {
        json['messageTypes'] = definition.messageTypes.map(runtime).toList();
      } else {
        json['fields'] = definition.fields
            .map(
              (field) => field.toJson()
                ..remove('description')
                ..remove('sampleValue'),
            )
            .toList();
      }
      return json;
    }

    return _sameProtocolValue(runtime(this), runtime(other));
  }

  bool isDerived(String name) =>
      lengthCoverageMode &&
      lengthCoverages.any((rule) => rule.derivedField == name);
  int get minimumLength => fields.fold(
    0,
    (sum, field) => sum + (isDerived(field.name) ? 0 : field.size),
  );
  List<int> get header =>
      fields.first.role == FieldRole.header ? fields.first.fixed! : const [];
  bool get usesTail =>
      !lengthCoverageMode && fixedLength == null && lengthField == null;

  /// 只读取长度字段；尚未到达下一个长度字段时返回 null，等待后续输入。
  FrameLayout? resolveLayout(List<int> bytes, {int start = 0}) {
    final offsets = <String, int>{};
    final sizes = <String, int>{};
    final lengthValues = <String, int>{};
    var offset = 0;
    for (final field in fields) {
      offsets[field.name] = offset;
      var size = field.size;
      final derived = lengthCoverages
          .where((r) => r.derivedField == field.name)
          .firstOrNull;
      if (derived != null) {
        final first = fields.indexWhere((f) => f.name == derived.startField);
        final last = fields.indexWhere((f) => f.name == derived.endField);
        final fixed = fields
            .sublist(first, last + 1)
            .fold<int>(
              0,
              (sum, f) => sum + (f.name == field.name ? 0 : f.size),
            );
        size = lengthValues[derived.lengthField]! - fixed;
        if (size < 0) {
          throw FormatException(
            '长度规则 ${derived.lengthField}（${derived.startField} → ${derived.endField}）：${field.name} = ${lengthValues[derived.lengthField]} - $fixed = $size，自动长度不能为负数',
          );
        }
      }
      sizes[field.name] = size;
      offset += size;
      if (offset > maxFrameLength) {
        throw FormatException(
          '长度规则导致帧长 $offset 超过最大帧长 $maxFrameLength：${field.name}',
        );
      }
      if (lengthCoverages.any((r) => r.lengthField == field.name)) {
        if (start + offset > bytes.length) return null;
        final raw =
            _read(
                  Uint8List.fromList(
                    bytes.sublist(start + offsets[field.name]!, start + offset),
                  ),
                  field,
                  transform: false,
                )
                as int;
        lengthValues[field.name] = raw;
        final rule = lengthCoverages.firstWhere(
          (r) => r.lengthField == field.name,
        );
        if (raw > maxFrameLength) {
          throw FormatException(
            '长度规则 ${rule.lengthField}（${rule.startField} → ${rule.endField}）：$raw 超过最大帧长 $maxFrameLength',
          );
        }
      }
    }
    for (final rule in lengthCoverages.where((r) => r.derivedField.isEmpty)) {
      final first = fields.indexWhere((f) => f.name == rule.startField);
      final last = fields.indexWhere((f) => f.name == rule.endField);
      final expected = fields
          .sublist(first, last + 1)
          .fold<int>(0, (sum, field) => sum + sizes[field.name]!);
      if (lengthValues[rule.lengthField] != expected) {
        throw FormatException(
          '长度规则 ${rule.lengthField}（${rule.startField} → ${rule.endField}）：长度值 ${lengthValues[rule.lengthField]} 与固定字段总长度 $expected 不一致',
        );
      }
    }
    return FrameLayout(offsets, sizes, lengthValues, offset);
  }

  /// 领域映射完整时才生成定位事件；不影响原始帧解析。
  bool get hasPayloadMapping =>
      kind != PayloadKind.display &&
      mapping.containsKey('tagId') &&
      (kind == PayloadKind.position
          ? mapping.containsKey('x') && mapping.containsKey('y')
          : mapping.containsKey('angle') && mapping.containsKey('distance'));

  int offsetOf(ProtocolField field, int frameLength) {
    final index = fields.indexOf(field);
    if (lengthCoverageMode) {
      return fields
          .take(index)
          .fold(0, (sum, f) => sum + (isDerived(f.name) ? 0 : f.size));
    }
    if (field.fromEnd) {
      return frameLength - fields.skip(index).fold(0, (sum, f) => sum + f.size);
    }
    return fields.take(index).fold(0, (sum, f) => sum + f.size);
  }

  void _validate() {
    void require(bool condition, String message) {
      if (!condition) throw FormatException(message);
    }

    require(id.trim().isNotEmpty && fields.isNotEmpty, '协议标识和字段不能为空');
    require(name.trim().isNotEmpty, '协议名称不能为空');
    require(
      maxFrameLength > 0 && maxFrameLength <= 1048576,
      '最大帧长必须为 1..1048576',
    );
    require(fixedLength == null || lengthField == null, '固定帧长和长度字段不能同时配置');
    if (lengthCoverageMode) {
      require(fixedLength == null && lengthField == null, '覆盖范围模式不能同时配置旧帧长规则');
      require(lengthCoverages.isNotEmpty, '请为长度字段配置覆盖范围');
      final analysis = LengthCoverageAnalysis(
        fields: fields.map(CoverageFieldFacts.fromField).toList(),
        rules: lengthCoverages,
        enabled: true,
      );
      if (analysis.issues.isNotEmpty) {
        throw FormatException(analysis.issues.first.message);
      }
    }
    if (usesTail) {
      require(
        fields.first.role == FieldRole.header &&
            fields.last.role == FieldRole.tail &&
            fields.last.fromEnd,
        '帧尾定界需要首位帧头和末位从末尾定位的帧尾',
      );
    }
    require(lengthMultiplier > 0, '长度乘数必须为正整数');
    final names = <String>{};
    var suffix = false;
    for (final field in fields) {
      require(
        field.role != FieldRole.header || identical(field, fields.first),
        '帧头必须位于字段结构首位',
      );
      require(
        field.role != FieldRole.tail || identical(field, fields.last),
        '帧尾必须位于字段结构末位',
      );
      require(
        field.name.trim().isNotEmpty && names.add(field.name),
        '字段名为空或重复：${field.name}',
      );
      require(
        field.size > 0 && field.size <= maxFrameLength,
        '字段字节数无效：${field.name}',
      );
      require(
        field.type == FieldType.bytes ||
            (field.type == FieldType.float ? [4, 8] : [1, 2, 4, 8]).contains(
              field.size,
            ),
        '字段类型与字节数不匹配：${field.name}',
      );
      require(field.scale.isFinite && field.bias.isFinite, '字段缩放或偏移无效');
      require(
        lengthCoverageMode || !suffix || field.fromEnd,
        '从末尾定位的字段必须构成连续后缀',
      );
      suffix = field.fromEnd;
      if (field.fixed != null) {
        require(
          field.fixed!.length == field.size &&
              field.fixed!.every((b) => b >= 0 && b <= 255),
          '固定字节无效：${field.name}',
        );
      }
      if (field.role == FieldRole.header || field.role == FieldRole.tail) {
        require(field.fixed != null, '帧头/帧尾需要固定字节');
      }
    }
    require(minimumLength <= maxFrameLength, '字段总长度超过最大帧长');
    if (fixedLength != null) {
      require(
        fixedLength! >= minimumLength && fixedLength! <= maxFrameLength,
        '固定帧长超出有效范围',
      );
    } else if (lengthField != null) {
      final candidates = fields.where((f) => f.name == lengthField).toList();
      require(candidates.length == 1, '长度字段不存在');
      final field = candidates.single;
      require(
        field.role == FieldRole.length &&
            field.type == FieldType.uint &&
            !field.fromEnd &&
            field.size <= 4,
        '长度字段必须为前缀中的无符号整数，最多 4 字节',
      );
    }
    final checks = fields.where((f) => f.role == FieldRole.checksum).toList();
    require(
      checksum == null ? checks.isEmpty : checks.length == 1,
      '校验算法与校验字段必须同时配置',
    );
    if (checksum != null) {
      final f = checks.single;
      require(
        f.type == FieldType.uint &&
            f.size == (checksum == ChecksumKind.crc16Modbus ? 2 : 1),
        '校验字段类型或长度错误',
      );
      require(
        checksumStart >= 0 && checksumStart < offsetOf(f, minimumLength),
        '校验覆盖范围无效',
      );
    }
    const allowed = {
      'tagId',
      'anchorId',
      'x',
      'y',
      'z',
      'angle',
      'elevation',
      'distance',
      'timestamp',
      'anchorX',
      'anchorY',
      'anchorZ',
      'anchorHeading',
      'battery',
      'temperature',
      'pressure',
      'rssi',
      'successRate',
      'sos',
      'ack',
      'command',
      // 嗅探目标（UWB 嗅探页时槽图）：时间槽/信道号与消息类型。
      'slot',
      'messageType',
    };
    for (final entry in mapping.entries) {
      require(
        allowed.contains(entry.key) && names.contains(entry.value),
        '字段映射无效：${entry.key}',
      );
      final field = fields.firstWhere((f) => f.name == entry.value);
      require(field.role != FieldRole.skip, '不能映射跳过字段');
      if (entry.key != 'tagId' && entry.key != 'anchorId') {
        require(field.type != FieldType.bytes, '数值语义不能映射到字节串');
      }
    }
  }

  Map<String, dynamic> toJson() => isMessageCollection
      ? {
          'version': 3,
          'id': id,
          'name': name,
          'messageTypes': messageTypes.map((m) => m.toJson()).toList(),
        }
      : {
          'version': lengthCoverageMode ? 2 : 1,
          'id': id,
          'name': name,
          'fields': fields.map((f) => f.toJson()).toList(),
          'kind': kind.name,
          'mapping': mapping,
          'fixedLength': fixedLength,
          'lengthField': lengthField,
          'lengthMultiplier': lengthMultiplier,
          'lengthAdjustment': lengthAdjustment,
          'maxFrameLength': maxFrameLength,
          'checksum': checksum?.name,
          'checksumStart': checksumStart,
          'distanceUnit': distanceUnit.name,
          'lengthCoverageMode': lengthCoverageMode,
          'lengthCoverages': lengthCoverages.map((r) => r.toJson()).toList(),
        };
  factory ProtocolDefinition.fromJson(Map<String, dynamic> json) {
    if (json['version'] == 4 || json.containsKey('interaction')) {
      throw const FormatException('协议编辑器仅支持接收解析，不支持发送构造或交互流程');
    }
    if (json['version'] == 3) {
      final messages = <ProtocolDefinition>[];
      for (final raw in json['messageTypes'] as List<dynamic>) {
        final data = raw as Map<String, dynamic>;
        try {
          messages.add(ProtocolDefinition.fromJson(data));
        } on FormatException catch (error) {
          throw FormatException('消息类型 ${data['name']}：${error.message}');
        }
      }
      return ProtocolDefinition.collection(
        id: json['id'] as String,
        name: json['name'] as String,
        messageTypes: messages,
      );
    }
    if (json['version'] != 1 && json['version'] != 2) {
      throw const FormatException('不支持的协议版本');
    }
    if ((json['version'] == 2) != (json['lengthCoverageMode'] == true)) {
      throw const FormatException('协议版本与长度覆盖范围模式不一致');
    }
    return ProtocolDefinition(
      id: json['id'] as String,
      name: json['name'] as String?,
      fields: (json['fields'] as List<dynamic>)
          .map((f) => ProtocolField.fromJson(f as Map<String, dynamic>))
          .toList(),
      kind: PayloadKind.values.byName(json['kind'] as String),
      mapping: (json['mapping'] as Map<String, dynamic>).cast<String, String>(),
      fixedLength: json['fixedLength'] as int?,
      lengthField: json['lengthField'] as String?,
      lengthMultiplier: json['lengthMultiplier'] as int,
      lengthAdjustment: json['lengthAdjustment'] as int,
      maxFrameLength: json['maxFrameLength'] as int,
      checksum: json['checksum'] == null
          ? null
          : ChecksumKind.values.byName(json['checksum'] as String),
      checksumStart: json['checksumStart'] as int,
      lengthCoverageMode: json['lengthCoverageMode'] as bool? ?? false,
      lengthCoverages: (json['lengthCoverages'] as List<dynamic>? ?? [])
          .map((r) => LengthCoverage.fromJson(r as Map<String, dynamic>))
          .toList(),
      distanceUnit: json['distanceUnit'] == null
          ? DistanceUnit.meters
          : DistanceUnit.values.byName(json['distanceUnit'] as String),
    );
  }
}

class ParsedFrame {
  ParsedFrame(
    this.bytes,
    Map<String, Object> values, {
    this.layout,
    this.messageType,
  }) : values = Map.unmodifiable(values);
  final Uint8List bytes;
  final Map<String, Object> values;
  final FrameLayout? layout;
  final ProtocolDefinition? messageType;
  String get messageTypeName => messageType?.name ?? '默认消息';
}

class DecodeBatch {
  DecodeBatch(this.frames, this.errors, this.errorCount);
  final List<ParsedFrame> frames;
  final List<String> errors;
  final int errorCount;
}

/// 字节流解码器只保留一条连接的未完成帧，UDP 应每个数据报新建实例。
class FrameDecoder {
  FrameDecoder(ProtocolDefinition protocol) : _protocol = protocol;
  ProtocolDefinition _protocol;
  ProtocolDefinition get protocol => _protocol;
  late Map<ProtocolDefinition, Map<int, int>> _recognition = {
    for (final message in protocol.messageTypes)
      message: message.recognitionBytes,
  };
  final List<int> _buffer = [];
  int get bufferedBytes => _buffer.length;
  void reset() => _buffer.clear();

  /// 同步替换等价定义，半帧保持原样；已输出帧仍持有原来的不可变定义。
  void refreshMetadata(ProtocolDefinition next) {
    if (!protocol.hasSameRuntimeSemantics(next)) {
      throw StateError('接收规则变化不能作为编辑信息更新');
    }
    final recognition = {
      for (final message in next.messageTypes)
        message: message.recognitionBytes,
    };
    _protocol = next;
    _recognition = recognition;
  }

  DecodeBatch add(List<int> bytes, {bool endOfDatagram = false}) {
    final frames = <ParsedFrame>[];
    final errors = <String>[];
    var errorCount = 0;
    void report(String message) {
      errorCount++;
      if (errors.length < 32) errors.add(message);
    }

    // 分块摄入，避免单次输入或噪声导致无界缓存。
    for (var start = 0; start < bytes.length;) {
      final room = protocol.maxFrameLength - _buffer.length;
      final end = (start + room).clamp(0, bytes.length);
      _buffer.addAll(bytes.sublist(start, end));
      start = end;
      _drain(frames, report);
      if (_buffer.length >= protocol.maxFrameLength) {
        report('接收缓存达到帧长上限，丢弃无法解析的数据');
        _buffer.removeAt(0);
      }
    }
    if (endOfDatagram && protocol.isMessageCollection && _buffer.isNotEmpty) {
      _drain(frames, report, finalInput: true);
    }
    if (endOfDatagram && _buffer.isNotEmpty) {
      report('数据报结束时存在不完整帧');
      reset();
    }
    return DecodeBatch(frames, errors, errorCount);
  }

  void _drain(
    List<ParsedFrame> frames,
    void Function(String) report, {
    bool finalInput = false,
  }) {
    var skipped = 0;
    var cursor = 0;
    while (cursor < _buffer.length) {
      final available = _buffer.length - cursor;
      var protocol = this.protocol;
      if (protocol.isMessageCollection) {
        final matches = <ProtocolDefinition>[];
        var pending = false;
        for (final message in protocol.messageTypes) {
          var mismatch = false;
          var incomplete = false;
          for (final entry in _recognition[message]!.entries) {
            if (entry.key >= available) {
              incomplete = true;
            } else if (_buffer[cursor + entry.key] != entry.value) {
              mismatch = true;
              break;
            }
          }
          if (!mismatch) {
            if (incomplete) {
              pending = true;
            } else {
              matches.add(message);
            }
          }
        }
        if (pending) {
          if (!finalInput) break;
          report('数据报结束时存在不完整消息识别字段');
          cursor++;
          continue;
        }
        if (matches.length != 1) {
          if (matches.length > 1) {
            report('消息类型匹配存在歧义：${matches.map((m) => m.name).join(' / ')}');
          }
          cursor++;
          skipped++;
          continue;
        }
        protocol = matches.single;
      }
      final header = protocol.header;
      if (header.isNotEmpty) {
        if (available < header.length) {
          if (!finalInput) break;
          report('数据报结束时存在不完整帧头');
          cursor++;
          continue;
        }
        if (!_matches(_buffer, cursor, header)) {
          cursor++;
          skipped++;
          continue;
        }
      }
      var length = protocol.fixedLength;
      FrameLayout? layout;
      if (protocol.lengthCoverageMode) {
        try {
          layout = protocol.resolveLayout(_buffer, start: cursor);
          if (layout == null) {
            if (!finalInput) break;
            report('消息类型 ${protocol.name}：数据报结束时长度字段不完整');
            cursor++;
            continue;
          }
          length = layout.frameLength;
        } on FormatException catch (error) {
          report(
            this.protocol.isMessageCollection
                ? '消息类型 ${protocol.name}：${error.message}'
                : error.message,
          );
          cursor++;
          continue;
        }
      } else if (protocol.usesTail) {
        final tail = protocol.fields.last.fixed!;
        for (
          var end = protocol.minimumLength;
          end <= available && end <= protocol.maxFrameLength;
          end++
        ) {
          if (_matches(_buffer, cursor + end - tail.length, tail)) {
            length = end;
            break;
          }
        }
        if (length == null) {
          if (available >= protocol.maxFrameLength) {
            report('最大帧长内未找到帧尾');
            cursor++;
            continue;
          }
          if (!finalInput) break;
          report('消息类型 ${protocol.name}：数据报结束时未找到帧尾');
          cursor++;
          continue;
        }
      } else if (length == null) {
        final field = protocol.fields.firstWhere(
          (f) => f.name == protocol.lengthField,
        );
        final offset = protocol.offsetOf(field, protocol.minimumLength);
        if (available < offset + field.size) {
          if (!finalInput) break;
          report('消息类型 ${protocol.name}：数据报结束时长度字段不完整');
          cursor++;
          continue;
        }
        length =
            (_read(
                      Uint8List.fromList(
                        _buffer.sublist(
                          cursor + offset,
                          cursor + offset + field.size,
                        ),
                      ),
                      field,
                      transform: false,
                    )
                    as int) *
                protocol.lengthMultiplier +
            protocol.lengthAdjustment;
      }
      if (length < protocol.minimumLength || length > protocol.maxFrameLength) {
        report(
          this.protocol.isMessageCollection
              ? '消息类型 ${protocol.name}：帧长超出允许范围：$length'
              : '帧长超出允许范围：$length',
        );
        cursor++;
        continue;
      }
      if (available < length) {
        if (!finalInput) break;
        report('消息类型 ${protocol.name}：数据报结束时存在不完整帧');
        cursor++;
        continue;
      }
      final frame = Uint8List.fromList(
        _buffer.sublist(cursor, cursor + length),
      );
      try {
        final values = <String, Object>{};
        for (final field in protocol.fields) {
          final offset =
              layout?.offsets[field.name] ?? protocol.offsetOf(field, length);
          final size = layout?.sizes[field.name] ?? field.size;
          if (field.fixed != null && !_matches(frame, offset, field.fixed!)) {
            throw FormatException('固定字节不匹配：${field.name}');
          }
          if (field.role == FieldRole.checksum) {
            final actual = _read(
              Uint8List.sublistView(frame, offset, offset + size),
              field,
              transform: false,
            );
            final expected = computeChecksum(
              protocol.checksum!,
              frame.sublist(protocol.checksumStart, offset),
            );
            if (actual != expected) throw FormatException('校验失败：${field.name}');
          }
          if (field.role != FieldRole.skip) {
            values[field.name] = _read(
              Uint8List.sublistView(frame, offset, offset + size),
              field,
            );
          }
        }
        frames.add(
          ParsedFrame(frame, values, layout: layout, messageType: protocol),
        );
        cursor += length;
      } on FormatException catch (error) {
        report(
          this.protocol.isMessageCollection
              ? '消息类型 ${protocol.name}：${error.message}'
              : error.message,
        );
        // 从下一个字节重新同步，避免错误帧长吞掉后续合法帧。
        cursor++;
      }
    }
    if (cursor > 0) _buffer.removeRange(0, cursor);
    if (skipped > 0) {
      report(
        protocol.isMessageCollection
            ? '未知消息或非帧头数据：已跳过 $skipped 字节'
            : '已跳过 $skipped 个非帧头字节',
      );
    }
  }
}

bool _matches(List<int> bytes, int offset, List<int> fixed) {
  for (var i = 0; i < fixed.length; i++) {
    if (bytes[offset + i] != fixed[i]) return false;
  }
  return true;
}

Object _read(Uint8List bytes, ProtocolField field, {bool transform = true}) {
  if (field.type == FieldType.bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }
  final data = ByteData.sublistView(bytes);
  final endian = field.littleEndian ? Endian.little : Endian.big;
  // Dart 原生 int 为有符号 64 位；超出范围的无符号标识保留精确十进制字符串。
  if (field.type == FieldType.uint &&
      field.size == 8 &&
      data.getUint64(0, endian) < 0) {
    var exact = BigInt.zero;
    for (final byte in field.littleEndian ? bytes.reversed : bytes) {
      exact = (exact << 8) | BigInt.from(byte);
    }
    if (!transform || (field.scale == 1 && field.bias == 0)) {
      return exact.toString();
    }
    final transformed = exact.toDouble() * field.scale + field.bias;
    if (!transformed.isFinite) throw FormatException('数值不是有限值：${field.name}');
    return transformed;
  }
  final num value = switch (field.type) {
    FieldType.float =>
      field.size == 4 ? data.getFloat32(0, endian) : data.getFloat64(0, endian),
    FieldType.uint => switch (field.size) {
      1 => data.getUint8(0),
      2 => data.getUint16(0, endian),
      4 => data.getUint32(0, endian),
      _ => data.getUint64(0, endian),
    },
    FieldType.sint => switch (field.size) {
      1 => data.getInt8(0),
      2 => data.getInt16(0, endian),
      4 => data.getInt32(0, endian),
      _ => data.getInt64(0, endian),
    },
    FieldType.bytes => throw StateError('不可达的字段类型'),
  };
  final result = transform && (field.scale != 1 || field.bias != 0)
      ? value * field.scale + field.bias
      : value;
  if (!result.isFinite) throw FormatException('数值不是有限值：${field.name}');
  return result;
}

int computeChecksum(ChecksumKind kind, List<int> bytes) {
  var value = kind == ChecksumKind.crc16Modbus ? 0xffff : 0;
  for (final byte in bytes) {
    switch (kind) {
      case ChecksumKind.sum8:
        value = (value + byte) & 0xff;
      case ChecksumKind.xor8:
        value ^= byte;
      case ChecksumKind.crc16Modbus:
        value ^= byte;
        for (var i = 0; i < 8; i++) {
          value = (value & 1) != 0 ? (value >> 1) ^ 0xa001 : value >> 1;
        }
    }
  }
  return value;
}

DecodeBatch previewHex(ProtocolDefinition protocol, String hex) {
  final compact = hex.replaceAll(RegExp(r'\s+'), '');
  if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(compact)) {
    throw const FormatException('请输入完整的十六进制字节');
  }
  return FrameDecoder(protocol).add([
    for (var i = 0; i < compact.length; i += 2)
      int.parse(compact.substring(i, i + 2), radix: 16),
  ], endOfDatagram: true);
}
