import 'package:clovecom/protocol_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/protocol_messages.dart';

void main() {
  test('混合消息保持顺序，每个分片位置均能恢复独立结构', () {
    final bytes = [
      0xaa,
      0x55,
      1,
      7,
      8,
      9,
      0xaa,
      0x55,
      2,
      42,
      0xaa,
      0x55,
      3,
      7,
      30,
      50,
    ];
    for (var cut = 0; cut <= bytes.length; cut++) {
      final decoder = FrameDecoder(mixedProtocol());
      final first = decoder.add(bytes.sublist(0, cut));
      final second = decoder.add(bytes.sublist(cut), endOfDatagram: true);
      final frames = [...first.frames, ...second.frames];
      expect(frames.map((f) => f.messageTypeName), ['定位', '心跳', '观测']);
      expect(frames[1].values, {'head': 'AA55', 'type': 2, 'counter': 42});
      expect(first.errorCount + second.errorCount, 0);
      expect(decoder.bufferedBytes, 0);
    }
  });

  test('未知消息与超限长度之后恢复，诊断及缓存有界', () {
    final protocol = ProtocolDefinition.collection(
      id: 'p',
      name: '测试',
      messageTypes: [messageDefinition(), variableMessage()],
    );
    final decoder = FrameDecoder(protocol);
    final result = decoder.add([
      ...List.filled(1000, 0),
      0xaa,
      0x55,
      99,
      1,
      2,
      0xbb,
      0x66,
      255,
      0xaa,
      0x55,
      1,
      7,
      8,
      9,
    ], endOfDatagram: true);
    expect(result.frames.single.messageTypeName, '定位');
    expect(result.errors.any((e) => e.contains('未知消息')), isTrue);
    expect(result.errors.length, lessThanOrEqualTo(32));
    expect(decoder.bufferedBytes, 0);
  });

  test('各消息独立长度规则，逐字节解析载荷中的帧头不提前分派', () {
    final protocol = ProtocolDefinition.collection(
      id: 'p',
      name: '测试',
      messageTypes: [messageDefinition(), variableMessage()],
    );
    final decoder = FrameDecoder(protocol);
    final frames = <ParsedFrame>[];
    for (final byte in [
      0xbb,
      0x66,
      3,
      0xaa,
      0x55,
      1,
      0x0d,
      0xaa,
      0x55,
      1,
      7,
      8,
      9,
    ]) {
      final batch = decoder.add([byte]);
      expect(batch.errors, isEmpty);
      frames.addAll(batch.frames);
    }
    expect(frames.map((f) => f.messageTypeName), ['可变数据', '定位']);
    expect(frames.first.values['body'], 'AA5501');
    expect(frames.first.layout!.sizes['body'], 3);
  });

  test('数据报中不完整的错误长度不会阻止后续完整消息恢复', () {
    final protocol = ProtocolDefinition.collection(
      id: 'p',
      name: '测试',
      messageTypes: [messageDefinition(), variableMessage()],
    );
    final result = FrameDecoder(
      protocol,
    ).add([0xbb, 0x66, 20, 1, 2, 0xaa, 0x55, 1, 7, 8, 9], endOfDatagram: true);
    expect(result.errorCount, greaterThan(0));
    expect(result.frames.single.values['tag'], 7);
  });

  test('相同识别规则与前缀重叠阻止保存，不依赖消息列表顺序', () {
    final a = messageDefinition();
    final b = ProtocolDefinition.fromJson({
      ...a.toJson(),
      'id': 'other',
      'name': '另一消息',
    });
    expect(
      () => ProtocolDefinition.collection(
        id: 'p',
        name: '协议',
        messageTypes: [a, b],
      ),
      throwsA(
        isA<FormatException>().having((e) => e.message, '原因', contains('识别冲突')),
      ),
    );
    final broad = ProtocolDefinition(
      id: 'broad',
      name: '无类型字段',
      fields: [a.fields.first],
      fixedLength: 2,
      kind: PayloadKind.display,
      mapping: {},
    );
    expect(
      () => ProtocolDefinition.collection(
        id: 'p',
        name: '协议',
        messageTypes: [a, broad],
      ),
      throwsFormatException,
    );
  });

  test('新格式往返保留类型与映射，旧格式保持原有字节行为', () {
    final restored = ProtocolDefinition.fromJson(mixedProtocol().toJson());
    expect(restored.toJson()['version'], 3);
    expect(restored.messageTypes.map((m) => m.name), ['定位', '心跳', '观测']);
    expect(restored.messageTypes.last.distanceUnit, DistanceUnit.centimeters);
    final old = messageDefinition();
    final oldRestored = ProtocolDefinition.fromJson(old.toJson());
    expect(oldRestored.toJson(), old.toJson());
    expect(
      FrameDecoder(
        oldRestored,
      ).add([0xaa, 0x55, 1, 7, 8, 9]).frames.single.values['tag'],
      7,
    );
    expect(
      () => ProtocolDefinition.fromJson({...restored.toJson(), 'version': 99}),
      throwsFormatException,
    );
  });

  test('可变载荷之后的固定类型字段拒绝用于识别', () {
    final old = variableMessage();
    final json = old.toJson();
    (json['fields'] as List).insert(
      3,
      ProtocolField(name: 'lateType', size: 1, fixed: [1]).toJson(),
    );
    final late = ProtocolDefinition.fromJson(json);
    expect(
      () => ProtocolDefinition.collection(
        id: 'p',
        name: '协议',
        messageTypes: [late],
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          '原因',
          contains('可变载荷之前'),
        ),
      ),
    );
  });

  test('校验失败后恢复其他消息，帧尾消息使用自身边界', () {
    final checked = ProtocolDefinition(
      id: 'checked',
      name: '校验消息',
      kind: PayloadKind.display,
      fixedLength: 5,
      checksum: ChecksumKind.xor8,
      fields: [
        ProtocolField(
          name: 'head',
          size: 2,
          role: FieldRole.header,
          type: FieldType.bytes,
          fixed: [0xcc, 0x77],
        ),
        ProtocolField(name: 'value', size: 2),
        ProtocolField(name: 'check', size: 1, role: FieldRole.checksum),
      ],
      mapping: {},
    );
    final tailed = ProtocolDefinition(
      id: 'tail',
      name: '帧尾消息',
      kind: PayloadKind.display,
      fields: [
        ProtocolField(
          name: 'head',
          size: 2,
          role: FieldRole.header,
          type: FieldType.bytes,
          fixed: [0xdd, 0x88],
        ),
        ProtocolField(name: 'value', size: 1),
        ProtocolField(
          name: 'tail',
          size: 1,
          role: FieldRole.tail,
          fixed: [13],
          fromEnd: true,
        ),
      ],
      mapping: {},
    );
    final protocol = ProtocolDefinition.collection(
      id: 'p',
      name: '协议',
      messageTypes: [checked, tailed, messageDefinition()],
    );
    final good = [0xcc, 0x77, 1, 2];
    final result = FrameDecoder(protocol).add([
      0xcc,
      0x77,
      1,
      2,
      0,
      0xdd,
      0x88,
      3,
      13,
      ...good,
      computeChecksum(ChecksumKind.xor8, good),
      0xaa,
      0x55,
      1,
      7,
      8,
      9,
    ], endOfDatagram: true);
    expect(result.frames.map((f) => f.messageTypeName), ['帧尾消息', '校验消息', '定位']);
    expect(
      result.errors.any((e) => e.contains('校验消息') && e.contains('校验失败')),
      isTrue,
    );
  });

  test('各消息保留自身用途、字段和映射，解析不依赖定位引擎', () {
    final result = FrameDecoder(mixedProtocol()).add([
      0xaa,
      0x55,
      1,
      7,
      8,
      9,
      0xaa,
      0x55,
      3,
      8,
      30,
      50,
      0xaa,
      0x55,
      2,
      42,
    ], endOfDatagram: true);
    expect(result.errors, isEmpty);
    expect(result.frames, hasLength(3));
    expect(result.frames.last.values['counter'], 42);
    expect(result.frames.last.messageTypeName, '心跳');
  });
}
