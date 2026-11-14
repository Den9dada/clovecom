import 'package:clovecom/protocol_editor.dart';
import 'package:flutter_test/flutter_test.dart';

ProtocolDefinition twoSegments({int maxFrameLength = 65536}) =>
    ProtocolDefinition(
      id: 'segments',
      kind: PayloadKind.position,
      mapping: {},
      lengthCoverageMode: true,
      maxFrameLength: maxFrameLength,
      fields: [
        ProtocolField(
          name: 'head',
          size: 1,
          role: FieldRole.header,
          type: FieldType.bytes,
          fixed: [0x55],
        ),
        ProtocolField(name: 'length1', size: 1, role: FieldRole.length),
        ProtocolField(
          name: 'a',
          size: 2,
          type: FieldType.bytes,
          sampleValue: '0102',
        ),
        ProtocolField(
          name: 'b',
          size: 1,
          type: FieldType.bytes,
          sampleValue: 'AA0304',
        ),
        ProtocolField(name: 'length2', size: 1, role: FieldRole.length),
        ProtocolField(
          name: 'c',
          size: 1,
          type: FieldType.bytes,
          sampleValue: '0607',
        ),
        ProtocolField(
          name: 'check',
          size: 1,
          role: FieldRole.checksum,
          fromEnd: true,
        ),
        ProtocolField(
          name: 'tail',
          size: 1,
          role: FieldRole.tail,
          type: FieldType.bytes,
          fixed: [0xAA],
          fromEnd: true,
        ),
      ],
      checksum: ChecksumKind.sum8,
      lengthCoverages: const [
        LengthCoverage(
          lengthField: 'length1',
          startField: 'a',
          endField: 'b',
          derivedField: 'b',
        ),
        LengthCoverage(
          lengthField: 'length2',
          startField: 'c',
          endField: 'c',
          derivedField: 'c',
        ),
      ],
    );

void main() {
  test('将 u8 数据字段设为自动长度时统一切换为字节数据并可解析变长消息', () {
    final draft = ProtocolDraft.create(id: 'variable-u8', name: '变长消息');
    draft.addField(
      ProtocolField(name: 'Length', size: 2, role: FieldRole.length),
    );
    draft.addField(ProtocolField(name: 'ID', size: 4));
    draft.addField(ProtocolField(name: 'u8', size: 1, sampleValue: '0'));
    draft.setFrameMode(ProtocolFrameMode.coverage);
    draft.setLengthCoverage(
      'Length',
      startField: 'ID',
      endField: 'u8',
      derivedField: 'u8',
    );
    expect(draft.field(2)['type'], 'bytes');
    expect(draft.field(2)['sampleValue'], '00');
    draft.updateField(2, {'size': '', 'sampleValue': '01 02 03'});
    expect(draft.validate(), isEmpty);
    final preview = draft.testHex(draft.generateSampleHex());
    expect(preview.succeeded, isTrue);
    expect(preview.frames.single.layout!.sizes['u8'], 3);
    expect(preview.frames.single.values['u8'], '010203');
    draft.updateField(2, {'type': 'uint'});
    expect(draft.lengthCoverages.single.derivedField, '');
    expect(draft.field(2)['size'], 1);
    expect(draft.validate(), isEmpty);
  });
  test('覆盖字段全部定长时无需指定自动长度字段', () {
    final protocol = ProtocolDefinition(
      id: 'fixed-coverage',
      kind: PayloadKind.display,
      mapping: {},
      lengthCoverageMode: true,
      fields: [
        ProtocolField(name: 'Length', size: 2, role: FieldRole.length),
        ProtocolField(name: 'Anchor ID', size: 4),
        ProtocolField(name: 'Angle', size: 4, type: FieldType.float),
      ],
      lengthCoverages: const [
        LengthCoverage(
          lengthField: 'Length',
          startField: 'Anchor ID',
          endField: 'Angle',
          derivedField: '',
        ),
      ],
    );
    final result = FrameDecoder(protocol).add([8, 0, 1, 0, 0, 0, 0, 0, 0, 0]);
    expect(result.frames.single.layout!.frameLength, 10);
    expect(result.frames.single.layout!.sizes['Anchor ID'], 4);
    expect(encodeSample(protocol).take(2), [8, 0]);
    expect(protocol.resolveLayout([8]), isNull);
    expect(
      () => protocol.resolveLayout([7, 0]),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          '错误原因',
          contains('固定字段总长度'),
        ),
      ),
    );
    final json = protocol.toJson();
    (json['lengthCoverages'] as List).single.remove('derivedField');
    expect(
      ProtocolDefinition.fromJson(json).lengthCoverages.single.derivedField,
      '',
    );
    expect(
      ProtocolDefinition.fromJson(
        protocol.toJson(),
      ).lengthCoverages.single.derivedField,
      '',
    );
  });
  test('单个定长数值字段不会被强制指定为自动长度字段', () {
    final draft = ProtocolDraft.create(id: 'single-fixed', name: '定长覆盖');
    draft.addField(
      ProtocolField(name: 'Length', size: 1, role: FieldRole.length),
    );
    draft.addField(ProtocolField(name: 'ID', size: 4));
    draft.setFrameMode(ProtocolFrameMode.coverage);
    draft.setLengthCoverage('Length', startField: 'ID', endField: 'ID');
    expect(draft.lengthCoverages.single.derivedField, '');
    expect(draft.validate(), isEmpty);
    expect(encodeSample(draft.build()).first, 4);
  });
  test('多字节长度按字段字节序读取原始值，整帧上限包含范围外字段', () {
    final protocol = ProtocolDefinition(
      id: 'endian',
      kind: PayloadKind.position,
      mapping: {},
      lengthCoverageMode: true,
      maxFrameLength: 5,
      fields: [
        ProtocolField(
          name: 'len',
          size: 2,
          role: FieldRole.length,
          littleEndian: false,
          scale: 10,
          bias: 5,
        ),
        ProtocolField(name: 'data', size: 1, type: FieldType.bytes),
      ],
      lengthCoverages: const [
        LengthCoverage(
          lengthField: 'len',
          startField: 'data',
          endField: 'data',
          derivedField: 'data',
        ),
      ],
    );
    final frame = FrameDecoder(
      protocol,
    ).add([0, 3, 0xAB, 0xCD, 0xEF]).frames.single;
    expect(frame.values['data'], 'ABCDEF');
    expect(frame.layout!.lengthValues['len'], 3);
    expect(frame.layout!.frameLength, 5);
    final overflow = FrameDecoder(protocol).add([0, 4]);
    expect(overflow.frames, isEmpty);
    expect(overflow.errors.any((e) => e.contains('最大帧长')), isTrue);
  });

  test('自动长度为零时，校验起点不能超过最短有效布局', () {
    final fields = [
      ProtocolField(name: 'len', size: 1, role: FieldRole.length),
      ProtocolField(name: 'data', size: 9, type: FieldType.bytes),
      ProtocolField(name: 'check', size: 1, role: FieldRole.checksum),
    ];
    const rules = [
      LengthCoverage(
        lengthField: 'len',
        startField: 'data',
        endField: 'data',
        derivedField: 'data',
      ),
    ];
    expect(
      () => ProtocolDefinition(
        id: 'check',
        kind: PayloadKind.position,
        mapping: {},
        fields: fields,
        lengthCoverageMode: true,
        lengthCoverages: rules,
        checksum: ChecksumKind.sum8,
        checksumStart: 2,
      ),
      throwsFormatException,
    );
    final protocol = ProtocolDefinition(
      id: 'check',
      kind: PayloadKind.position,
      mapping: {},
      fields: fields,
      lengthCoverageMode: true,
      lengthCoverages: rules,
      checksum: ChecksumKind.sum8,
    );
    expect(FrameDecoder(protocol).add([0, 0]).frames.single.values['data'], '');
  });

  test('自动字段不使用已清空的固定长度，项目持久化保留新模式', () {
    final draft = ProtocolDraft(twoSegments());
    draft.updateField(3, {'size': ''});
    expect(draft.validate(), isEmpty);
    final protocol = draft.build();
    final restored = ProtocolDefinition.fromJson(protocol.toJson());
    expect(restored.lengthCoverageMode, isTrue);
    expect(
      FrameDecoder(restored).add(encodeSample(protocol)).frames,
      hasLength(1),
    );
    expect(
      () => ProtocolDefinition.fromJson({...protocol.toJson(), 'version': 1}),
      throwsFormatException,
    );
    draft.setFrameMode(ProtocolFrameMode.fixed);
    expect(draft.validate(), isNotEmpty);
  });

  test('两个独立范围按顺序解析，载荷中的帧尾不会截断，逐字节接收和粘包一致', () {
    final protocol = twoSegments();
    final bytes = encodeSample(protocol);
    expect(bytes, [0x55, 5, 1, 2, 0xAA, 3, 4, 2, 6, 7, 0x1D, 0xAA]);
    final decoder = FrameDecoder(protocol);
    final frames = <ParsedFrame>[];
    for (final byte in [...bytes, ...bytes]) {
      final batch = decoder.add([byte]);
      expect(batch.errors, isEmpty);
      frames.addAll(batch.frames);
    }
    expect(frames, hasLength(2));
    final frame = frames.first;
    expect(frame.values['b'], 'AA0304');
    expect(frame.values['c'], '0607');
    expect(frame.layout!.offsets['length2'], 7);
    expect(frame.layout!.offsets['tail'], 11);
    expect(frame.layout!.sizes['b'], 3);
    expect(frame.layout!.lengthValues, {'length1': 5, 'length2': 2});
    expect(decoder.bufferedBytes, 0);
    expect(
      FrameDecoder(protocol).add([...bytes, ...bytes]).frames,
      hasLength(2),
    );
  });

  test('单范围三个字段可推导中间字段并移动后续偏移', () {
    final protocol = ProtocolDefinition(
      id: 'middle',
      kind: PayloadKind.position,
      mapping: {},
      lengthCoverageMode: true,
      fields: [
        ProtocolField(name: 'len', size: 1, role: FieldRole.length),
        ProtocolField(name: 'a', size: 2, type: FieldType.bytes),
        ProtocolField(name: 'b', size: 1, type: FieldType.bytes),
        ProtocolField(name: 'c', size: 3, type: FieldType.bytes),
      ],
      lengthCoverages: const [
        LengthCoverage(
          lengthField: 'len',
          startField: 'a',
          endField: 'c',
          derivedField: 'b',
        ),
      ],
    );
    final frame = FrameDecoder(
      protocol,
    ).add([7, 1, 2, 3, 4, 5, 6, 7]).frames.single;
    expect(frame.values['b'], '0304');
    expect(frame.values['c'], '050607');
    expect(frame.layout!.offsets['c'], 5);
  });

  test('覆盖范围包含长度字段自身，零长度可解析和生成样例', () {
    final protocol = ProtocolDefinition(
      id: 'self',
      kind: PayloadKind.position,
      mapping: {},
      lengthCoverageMode: true,
      fields: [
        ProtocolField(name: 'len', size: 1, role: FieldRole.length),
        ProtocolField(name: 'payload', size: 1, type: FieldType.bytes),
      ],
      lengthCoverages: const [
        LengthCoverage(
          lengthField: 'len',
          startField: 'len',
          endField: 'payload',
          derivedField: 'payload',
        ),
      ],
    );
    expect(encodeSample(protocol), [1]);
    final frame = FrameDecoder(protocol).add([1]).frames.single;
    expect(frame.values['payload'], '');
    expect(frame.layout!.sizes['payload'], 0);
    expect(
      FrameDecoder(
        protocol,
      ).add([3, 0xAB, 0xCD]).frames.single.values['payload'],
      'ABCD',
    );
  });

  test('负长度和超限立即报错，随后可恢复合法帧', () {
    final protocol = twoSegments(maxFrameLength: 20);
    final valid = encodeSample(protocol);
    final batch = FrameDecoder(
      protocol,
    ).add([0x55, 1, 0, 0, 0x55, 21, ...valid]);
    expect(batch.frames, hasLength(1));
    expect(
      batch.errors.any((e) => e.contains('length1') && e.contains('负数')),
      isTrue,
    );
    expect(
      batch.errors.any((e) => e.contains('length1') && e.contains('最大帧长')),
      isTrue,
    );
    final tooLong = [...valid]..[7] = 20;
    final over = FrameDecoder(protocol).add(tooLong);
    expect(over.frames, isEmpty);
    expect(over.errors.any((e) => e.contains('最大帧长')), isTrue);
  });

  test('合法长度未收齐等待，数据报结束与校验帧尾失败给出错误', () {
    final protocol = twoSegments();
    final bytes = encodeSample(protocol);
    final decoder = FrameDecoder(protocol);
    final first = decoder.add(bytes.sublist(0, 7));
    expect(first.frames, isEmpty);
    expect(first.errors, isEmpty);
    expect(decoder.add(bytes.sublist(7)).frames, hasLength(1));
    expect(
      FrameDecoder(
        protocol,
      ).add(bytes.sublist(0, 7), endOfDatagram: true).errors,
      contains('数据报结束时存在不完整帧'),
    );
    final badTail = [...bytes]..[11] = 0;
    expect(
      FrameDecoder(protocol).add(badTail).errors,
      contains('固定字节不匹配：tail'),
    );
    final badCheck = [...bytes]..[10] = 0;
    expect(FrameDecoder(protocol).add(badCheck).errors, contains('校验失败：check'));
  });

  test('重叠、缺失引用、反向依赖与非字节自动字段拒绝配置', () {
    final json = twoSegments().toJson();
    void invalid(List<Map<String, dynamic>> rules) {
      expect(
        () => ProtocolDefinition.fromJson({...json, 'lengthCoverages': rules}),
        throwsFormatException,
      );
    }

    invalid([
      const LengthCoverage(
        lengthField: 'length1',
        startField: 'a',
        endField: 'c',
        derivedField: 'b',
      ).toJson(),
      const LengthCoverage(
        lengthField: 'length2',
        startField: 'c',
        endField: 'c',
        derivedField: 'c',
      ).toJson(),
    ]);
    invalid([
      const LengthCoverage(
        lengthField: 'missing',
        startField: 'a',
        endField: 'b',
        derivedField: 'b',
      ).toJson(),
    ]);
    invalid([
      const LengthCoverage(
        lengthField: 'length2',
        startField: 'a',
        endField: 'b',
        derivedField: 'b',
      ).toJson(),
    ]);
    invalid([
      const LengthCoverage(
        lengthField: 'length1',
        startField: 'length2',
        endField: 'length2',
        derivedField: 'length2',
      ).toJson(),
    ]);
  });

  test('新协议 JSON 往返保留规则；旧协议缺少新增属性时保留乘数调整量', () {
    final original = twoSegments();
    final restored = ProtocolDefinition.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
    expect(restored.toJson()['version'], 2);
    expect(
      FrameDecoder(restored).add(encodeSample(restored)).frames,
      hasLength(1),
    );
    final legacy = ProtocolDefinition(
      id: 'legacy',
      kind: PayloadKind.position,
      mapping: {},
      lengthField: 'len',
      lengthMultiplier: 2,
      lengthAdjustment: 1,
      fields: [
        ProtocolField(name: 'len', size: 1, role: FieldRole.length),
        ProtocolField(name: 'data', size: 2, type: FieldType.bytes),
      ],
    );
    final json = legacy.toJson()
      ..remove('lengthCoverageMode')
      ..remove('lengthCoverages');
    final old = ProtocolDefinition.fromJson(json);
    expect(old.lengthCoverageMode, isFalse);
    expect(old.toJson()['version'], 1);
    expect(
      FrameDecoder(old).add([1, 0xAA, 0xBB]).frames.single.values['data'],
      'AABB',
    );
  });

  test('生成样例时长度值超过字段宽度不能截断写入', () {
    final draft = ProtocolDraft(twoSegments());
    draft.updateField(3, {'sampleValue': List.filled(254, 'FF').join()});
    expect(() => draft.generateSampleHex(), throwsFormatException);
  });

  test('草稿重命名保持引用，删除或移动导致规则失效，切换旧模式后可恢复规则', () {
    final draft = ProtocolDraft(twoSegments());
    draft.updateField(3, {'name': 'payload1'});
    expect(draft.lengthCoverages.first.derivedField, 'payload1');
    expect(draft.validate(), isEmpty);
    expect(draft.coverageOf(3)!.lengthField, 'length1');
    expect(() => draft.byteOffset(4), throwsFormatException);
    draft.moveField(1, 3);
    expect(draft.validate().single, contains('之前'));
    draft.moveField(3, 1);
    draft.removeField(3);
    expect(draft.validate().single, contains('不存在'));
    expect(draft.lengthCoverages.first.derivedField, 'payload1');
    draft.discard();
    draft.setFrameMode(ProtocolFrameMode.fixed);
    expect(draft.usesLengthCoverage, isFalse);
    draft.setFrameMode(ProtocolFrameMode.coverage);
    expect(draft.validate(), isEmpty);
    expect(draft.build().lengthField, isNull);
  });

  test('单字段范围自动选择目标，多范围编辑与预览变化同步', () {
    final draft = ProtocolDraft(twoSegments());
    draft.removeLengthCoverage('length2');
    draft.setLengthCoverage('length2', startField: 'c', endField: 'c');
    expect(draft.lengthCoverages.last.derivedField, 'c');
    final preview = draft.testHex(draft.generateSampleHex());
    expect(preview.succeeded, isTrue);
    expect(preview.frames.single.layout!.sizes['c'], 2);
    draft.updateField(5, {'sampleValue': ''});
    expect(draft.preview, isNull);
    expect(
      draft.testHex(draft.generateSampleHex()).frames.single.layout!.sizes['c'],
      0,
    );
  });
}
