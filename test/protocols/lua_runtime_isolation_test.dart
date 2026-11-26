import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/src/application/lua_runtime.dart';
import 'package:clovecom/src/application/firmware_upgrade.dart';
import 'package:clovecom/src/io/connections.dart';
import 'package:flutter_test/flutter_test.dart';

String script(String body) => newInteractionSource(
  '测试升级',
  InteractionPurpose.upgrade,
).replaceFirst('  ctx:fail("NotImplemented", "请先编写实际交互步骤和成功判据")', body);

void main() {
  test('Lua日志和进度消息均按UTF8字节截断为4KiB', () async {
    final run = LuaRuntime().start(
      InteractionProtocol(
        id: 'logs',
        name: '日志',
        source: script('''
  ctx:log("info",string.rep("中",10000))
  ctx:progress({completed=1,total=1,message=string.rep("文",10000)})
  return {status="success"}
'''),
      ),
      LuaRunContext(
        config: ConnectionConfig(
          id: 'a',
          protocolId: '',
          kind: TransportKind.serial,
          serialPort: 'COM1',
        ),
        inbound: StreamController<Never>().stream,
        send: (_) async {},
      ),
    );
    final messages = <String>[];
    final sub = run.events.listen((event) {
      if (event.message != null) messages.add(event.message!);
    });
    await run.released;
    await sub.cancel();
    expect(messages.length, 4);
    expect(
      messages.every((message) => utf8.encode(message).length <= 4096),
      isTrue,
    );
  });

  test('真实Lua输入清理异常通过released报告失败而非无期限悬挂', () async {
    final input = StreamController<Never>(
      onCancel: () => throw StateError('输入清理失败'),
    );
    final run = LuaRuntime().start(
      InteractionProtocol(
        id: 'owner',
        name: 'owner',
        source: script('return {status="success"}'),
      ),
      LuaRunContext(
        config: ConnectionConfig(
          id: 'a',
          protocolId: '',
          kind: TransportKind.serial,
          serialPort: 'COM1',
        ),
        inbound: input.stream,
        send: (_) async {},
      ),
    );
    await expectLater(
      run.released.timeout(const Duration(seconds: 1)),
      throwsA(isA<StateError>()),
    );
  });

  test('协议校验进程输出超过1MiB时按IPC预算失败', () async {
    final temp = await Directory.systemTemp.createTemp('clovecom_t8_validate_');
    addTearDown(() => temp.delete(recursive: true));
    final sdk = await File(
      '${temp.path}/loud.lua',
    ).writeAsString("io.read('*l'); io.write(string.rep('x',2097152))");
    final diagnostics = await LuaRuntime(sdk: sdk.path).validate(
      InteractionProtocol(id: 'check', name: '校验', source: script('return {}')),
    );
    expect(diagnostics.map((d) => d.message).join(), contains('ResourceLimit'));
  });

  test('Lua固件快照复制前拒绝超过16MiB的输入', () {
    expect(
      () => LuaRunContext(
        config: ConnectionConfig(
          id: 'a',
          protocolId: '',
          kind: TransportKind.serial,
          serialPort: 'COM1',
        ),
        inbound: const Stream.empty(),
        send: (_) async {},
        firmware: Uint8List(16777217),
      ),
      throwsA(isA<LuaHostError>()),
    );
  });

  test('暂停Lua事件观察不会产生无限邮箱，明确失败并仍能释放', () async {
    final run = LuaRuntime().start(
      InteractionProtocol(
        id: 'events',
        name: '事件预算',
        source: script('''
  ctx:progress({completed=1,total=2})
  ctx:sleep(30000)
  return {status="success"}
'''),
      ),
      LuaRunContext(
        config: ConnectionConfig(
          id: 'a',
          protocolId: '',
          kind: TransportKind.serial,
          serialPort: 'COM1',
        ),
        inbound: StreamController<Never>().stream,
        send: (_) async {},
      ),
    );
    final terminal = run.events.firstWhere((event) => event.terminal != null);
    final paused = run.events.listen((_) {});
    paused.pause();
    try {
      final event = await terminal.timeout(const Duration(milliseconds: 1500));
      expect(event.terminal, UpgradeTerminal.failed);
      expect(event.error, contains('ResourceLimit'));
    } finally {
      paused.resume();
      await paused.cancel();
      await run.cancel();
    }
  });

  test('真实Lua进程总量有上限，超额运行明确失败且已有运行继续', () async {
    final runs = <LuaRun>[];
    final terminals = <Future<UpgradeRunEvent>>[];
    for (var i = 0; i < 5; i++) {
      final run = LuaRuntime().start(
        InteractionProtocol(
          id: 'limit',
          name: '预算',
          source: script('''
  ctx:sleep(30000)
  return {status="success"}
'''),
        ),
        LuaRunContext(
          config: ConnectionConfig(
            id: 'a',
            protocolId: '',
            kind: TransportKind.serial,
            serialPort: 'COM1',
          ),
          inbound: StreamController<Never>().stream,
          send: (_) async {},
        ),
      );
      runs.add(run);
      terminals.add(run.events.firstWhere((event) => event.terminal != null));
    }
    try {
      final rejected = await terminals.last.timeout(
        const Duration(milliseconds: 1500),
      );
      expect(rejected.terminal, UpgradeTerminal.failed);
      expect(rejected.error, contains('ResourceLimit'));
    } finally {
      await Future.wait(runs.map((run) => run.cancel()));
      await Future.wait(terminals);
    }
  });

  test('取消超过旧五秒阈值仍等待真实在途写结束，不能把超时当释放证明', () async {
    final started = Completer<void>(), writeDone = Completer<void>();
    final run = LuaRuntime().start(
      InteractionProtocol(
        id: 'release',
        name: '释放',
        source: script('''
  ctx.link:reader()
  ctx.link:send(bytes.from_hex("01"))
  return {status="success"}
'''),
      ),
      LuaRunContext(
        config: ConnectionConfig(
          id: 'a',
          protocolId: '',
          kind: TransportKind.serial,
          serialPort: 'COM1',
        ),
        inbound: StreamController<Never>().stream,
        send: (_) async {
          started.complete();
          await writeDone.future;
        },
      ),
    );
    var released = false;
    Object? error;
    unawaited(
      run.released.then(
        (_) {
          released = true;
        },
        onError: (Object e) {
          error = e;
        },
      ),
    );
    await started.future;
    final cancel = run.cancel().catchError((Object e) {
      error = e;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5300));
      expect(released, isFalse);
      expect(error, isNull);
    } finally {
      writeDone.complete();
      await cancel;
    }
    expect(released, isTrue);
  });
  test('每次Lua运行的嵌套target和schema完全快照且不可变', () {
    final target = <String, dynamic>{
      'nested': <String, dynamic>{
        'values': [1],
      },
    };
    final schema = <String, dynamic>{
      'serial.rts': <String, dynamic>{'supported': true},
    };
    LuaRunContext context() => LuaRunContext(
      config: ConnectionConfig(
        id: 'a',
        protocolId: '',
        kind: TransportKind.serial,
        serialPort: 'COM1',
      ),
      inbound: const Stream.empty(),
      send: (_) async {},
      target: target,
      runtimeSchema: schema,
    );
    final a = context(), b = context();
    (schema['serial.rts'] as Map)['supported'] = false;
    (target['nested']['values'] as List).add(2);
    expect((a.runtimeSchema['serial.rts'] as Map)['supported'], isTrue);
    expect(a.target['nested']['values'], [1]);
    expect(
      () => (a.target['nested']['values'] as List).add(3),
      throwsUnsupportedError,
    );
    expect(
      () => (a.runtimeSchema['serial.rts'] as Map)['supported'] = false,
      throwsUnsupportedError,
    );
    expect(b.target['nested']['values'], [1]);
  });
}
