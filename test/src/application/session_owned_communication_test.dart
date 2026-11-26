import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/src/application/communication_configuration_codec.dart';
import 'package:clovecom/src/application/communication_configuration_store.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_sessions.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/connections.dart';
import 'package:flutter_test/flutter_test.dart';

import 'communication_runtime_test.dart' show FakeTransport, eventually;

ConnectionDefinition _serial(String id) => ConnectionDefinition.serial(
  ConnectionConfig(
    id: id,
    protocolId: '',
    kind: TransportKind.serial,
    serialPort: 'COM$id',
  ),
);

class _Store implements CommunicationConfigurationStore {
  _Store(this.data);
  String data;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String contents) async => data = contents;
}

void main() {
  test('从旧文件迁移连接定义并忽略页面关联，启动时保持断开', () async {
    final expected = encodeConnectionDefinition(_serial('10'));
    final store = _Store(
      jsonEncode({
        'version': 1,
        'connections': [
          {
            ...expected,
            'receivePages': ['interfaceCommunication'],
            'sendPage': 'firmwareUpgrade',
          },
        ],
      }),
    );
    var opens = 0;
    final runtime = CommunicationRuntime(
      configurationStore: store,
      transportFactory: (_) async {
        opens++;
        return FakeTransport();
      },
    );
    addTearDown(runtime.dispose);
    await runtime.initialize();
    expect(runtime.configurationError, isNull);
    expect(runtime.connection('10').completelyClosed, isTrue);
    expect(opens, 0);
    await runtime.flushConfiguration();
    expect(jsonDecode(store.data), {
      'version': 2,
      'connections': [expected],
    });
  });

  test('会话标签自动分配不同颜色，自定义颜色随布局恢复', () async {
    final runtime = CommunicationRuntime();
    final store = _Store('{"layout":null,"display":{}}');
    final root = await Directory.systemTemp.createTemp('clovecom-tag-color-');
    CommunicationSessions create() => CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      store: store,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      await root.delete(recursive: true);
    });

    final first = create();
    await first.ready;
    final ids = List.generate(12, (index) => '${index + 10}');
    for (final id in ids) {
      runtime.addConnection(_serial(id));
    }
    final defaults = {for (final id in ids) id: first.tagColor(id)};
    expect(defaults.values.toSet(), hasLength(ids.length));
    first.setTagColor(ids.first, 0xff123abc);
    await first.flushLayout();
    first.dispose();

    final second = create();
    addTearDown(second.dispose);
    await second.ready;
    expect(second.tagColor(ids.first), 0xff123abc);
    expect(second.tagColor(ids.last), defaults[ids.last]);
    runtime.removeConnection(ids[1]);
    expect(second.tagColor(ids.last), defaults[ids.last]);
    await second.flushLayout();
    final data = jsonDecode(store.data) as Map<String, dynamic>;
    final colors = data['tagColors'] as Map<String, dynamic>;
    expect(colors, isNot(contains(ids[1])));
  });

  test('两个会话定向收发，协议任务独占自身连接并与会话同时观察原始包', () async {
    final transports = {'10': FakeTransport(), '11': FakeTransport()};
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async => transports[definition.id]!,
    );
    final history = await Directory.systemTemp.createTemp('clovecom-direct-');
    final workspace = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => history,
    );
    addTearDown(() async {
      await runtime.dispose();
      workspace.dispose();
      await history.delete(recursive: true);
    });
    await workspace.ready;
    for (final id in transports.keys) {
      runtime.addConnection(_serial(id));
      await workspace.connect(id, workspace.layout.groups.first);
    }

    final first = workspace['10']!;
    final second = workspace['11']!;
    expect((await first.write(Uint8List.fromList([1, 2]))).acceptedBytes, 2);
    final task = first.beginTask(ProtocolTaskKind.fileSend)!.channel!;
    transports['10']!.input.add(TransportInput([4]));
    transports['11']!.input.add(TransportInput([5]));
    expect(await task.readByte(100), 4);
    expect((await first.write(Uint8List.fromList([3]))).acceptedBytes, 0);
    expect((await second.write(Uint8List.fromList([6]))).acceptedBytes, 1);
    await eventually(
      () => first.receivedPackets == 1 && second.receivedPackets == 1,
    );

    await workspace.close('10');
    expect(first.closed, isTrue);
    expect(task.active, isFalse);
    expect(transports['10']!.closed, isTrue);
    expect(runtime.connection('10').completelyClosed, isTrue);
    expect(runtime.connection('11').connected, isTrue);
    expect((await second.write(Uint8List.fromList([7]))).acceptedBytes, 1);
    final records = (await second.history.read())!.records;
    expect(records.where((record) => !record.sent).single.packet!.bytes, [5]);
    expect(
      records
          .where((record) => record.sent)
          .map((record) => record.packet!.bytes),
      [
        [6],
        [7],
      ],
    );
  });

  test('Lua 升级读写只访问指定串口，结束后同一会话恢复普通发送', () async {
    final upgradePort = _UpgradePort();
    final otherPort = _UpgradePort();
    final library = ProtocolLibrary();
    await library.initialize();
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async =>
          definition.id == '10' ? upgradePort : otherPort,
    );
    addTearDown(() async {
      await runtime.dispose();
      library.dispose();
    });

    for (final id in ['10', '11']) {
      runtime.addConnection(_serial(id));
      await runtime.openConnection(id);
    }
    final draft = library.createInteraction(
      '单连接升级',
      InteractionPurpose.upgrade,
      source: newInteractionSource('单连接升级', InteractionPurpose.upgrade)
          .replaceFirst(
            '  ctx:fail("NotImplemented", "请先编写实际交互步骤和成功判据")',
            '''  local reader = ctx.link:reader()
  local fw = ctx.inputs.firmware
  ctx.link:send(fw:read(0, fw:info().size))
  assert(reader:read_exact(1, {deadline=ctx.time:after(2000)}):u8(0) == 6)
  return {status="success"}''',
          ),
    );
    await library.saveInteraction(draft.id);

    await runtime.firmwareUpgrades.start(
      connectionId: '10',
      protocol: library.savedInteraction(draft.id)!,
      runtime: library.runtime,
      load: () async => Uint8List.fromList([1, 2, 3]),
      firmwareName: 'test.bin',
    );
    expect(
      runtime.firmwareUpgrades.targets.single.phase,
      FirmwareUpgradePhase.succeeded,
    );
    expect(upgradePort.written, [
      [1, 2, 3],
    ]);
    expect(otherPort.written, isEmpty);
    expect(runtime.taskFor('10'), isNull);
    expect(
      (await runtime.writeTo('10', Uint8List.fromList([4]))).succeeded,
      isTrue,
    );
  });
}

class _UpgradePort extends FakeTransport {
  final written = <List<int>>[];

  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) async {
    written.add(bytes.toList());
    input.add(TransportInput([6]));
    return SerialWriteResult.success(bytes.length);
  }
}
