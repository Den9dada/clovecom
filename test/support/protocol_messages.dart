import 'package:clovecom/protocol_editor.dart';

ProtocolDefinition messageDefinition({
  int type = 1,
  String name = '定位',
  PayloadKind kind = PayloadKind.position,
  List<int> header = const [0xaa, 0x55],
  DistanceUnit distanceUnit = DistanceUnit.meters,
}) => ProtocolDefinition(
  id: 'type_$type',
  name: name,
  kind: kind,
  distanceUnit: distanceUnit,
  fixedLength: kind == PayloadKind.display ? 4 : 6,
  fields: [
    ProtocolField(
      name: 'head',
      size: 2,
      role: FieldRole.header,
      type: FieldType.bytes,
      fixed: header,
    ),
    ProtocolField(
      name: 'type',
      size: 1,
      role: FieldRole.frameId,
      fixed: [type],
    ),
    if (kind == PayloadKind.display)
      ProtocolField(name: 'counter', size: 1)
    else ...[
      ProtocolField(name: 'tag', size: 1),
      ProtocolField(name: 'first', size: 1),
      ProtocolField(name: 'second', size: 1),
    ],
  ],
  mapping: switch (kind) {
    PayloadKind.position => {'tagId': 'tag', 'x': 'first', 'y': 'second'},
    PayloadKind.observation => {
      'tagId': 'tag',
      'angle': 'first',
      'distance': 'second',
    },
    PayloadKind.display => {},
  },
);

ProtocolDefinition mixedProtocol() => ProtocolDefinition.collection(
  id: 'mixed',
  name: '混合协议',
  messageTypes: [
    messageDefinition(),
    messageDefinition(type: 2, name: '心跳', kind: PayloadKind.display),
    messageDefinition(
      type: 3,
      name: '观测',
      kind: PayloadKind.observation,
      distanceUnit: DistanceUnit.centimeters,
    ),
  ],
);

ProtocolDefinition variableMessage() => ProtocolDefinition(
  id: 'variable',
  name: '可变数据',
  kind: PayloadKind.display,
  lengthCoverageMode: true,
  maxFrameLength: 64,
  fields: [
    ProtocolField(
      name: 'head',
      size: 2,
      role: FieldRole.header,
      type: FieldType.bytes,
      fixed: [0xbb, 0x66],
    ),
    ProtocolField(name: 'length', size: 1, role: FieldRole.length),
    ProtocolField(name: 'body', size: 1, type: FieldType.bytes),
    ProtocolField(name: 'tail', size: 1, role: FieldRole.tail, fixed: [0x0d]),
  ],
  lengthCoverages: [
    const LengthCoverage(
      lengthField: 'length',
      startField: 'body',
      endField: 'body',
      derivedField: 'body',
    ),
  ],
  mapping: {},
);
