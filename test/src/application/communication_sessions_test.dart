import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/src/application/communication_configuration_store.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_sessions.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/application/session_history.dart';
import 'package:clovecom/src/application/session_layout.dart';
import 'package:clovecom/src/io/recording.dart';
import 'package:flutter_test/flutter_test.dart';

import 'communication_runtime_test.dart' show eventually;
import '../../support/communication_transports.dart'
    show add, DelayedResultTransport, RecordingTransport;

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('session-test-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('串口溢出标记历史缺口，协议任务结束且会话继续收发', () async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    final sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      sessions.dispose();
    });
    await sessions.ready;
    add(runtime, 'a');
    await sessions.connect('a', sessions.layout.groups.first);
    final session = sessions['a']!;
    final task = session.beginTask(ProtocolTaskKind.fileReceive)!.channel!;
    await task.ready;
    final packets = <RawPacket>[];
    final subscription = runtime.packets.listen(packets.add);
    addTearDown(subscription.cancel);

    transport.input
      ..add(TransportInput([0xe4]))
      ..addError(const SerialReceiveOverrun(1))
      ..add(TransportInput([0xb8, 0xad]));
    await task.released.timeout(const Duration(seconds: 2));
    await eventually(() => session.receivedPackets == 2);
    expect(task.reason, contains('串口接收溢出'));
    expect(packets.map((packet) => packet.bytes), [
      [0xe4],
      [0xb8, 0xad],
    ]);
    expect(session.connection?.connected, isTrue);
    expect(session.serialReceiveOverruns, 1);
    expect(session.missedInputPackets, 0);

    await session.history.flush();
    final page = (await session.history.readPage()).records;
    expect(page.map((row) => row.sequence), [1, 2, 3]);
    expect(page.first.packet!.bytes, [0xe4]);
    expect(page[1].notice, contains('丢失字节数未知'));
    expect(page.last.packet!.bytes, [0xb8, 0xad]);
    expect(page.last.textPrefix, isEmpty);
    expect((await session.write(Uint8List.fromList([0x41]))).succeeded, isTrue);
  });

  test('同一工作区的两个会话在同一轮事件内发布可见更新', () async {
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => RecordingTransport()..finish(),
    );
    final sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      sessions.dispose();
    });
    await sessions.ready;
    for (final id in ['a', 'b']) {
      add(runtime, id);
      await sessions.connect(id, sessions.layout.groups.first);
    }
    final first = sessions['a']!;
    final second = sessions['b']!;
    var inBatch = false;
    final shared = Completer<bool>();
    first.addListener(() {
      inBatch = true;
      scheduleMicrotask(() => inBatch = false);
    });
    second.addListener(() {
      if (!shared.isCompleted) shared.complete(inBatch);
    });
    await first.write(Uint8List.fromList([1]));
    await second.write(Uint8List.fromList([2]));
    expect(await shared.future.timeout(const Duration(seconds: 2)), isTrue);
  });

  test('从打开游标记录，每会话文件独立，短写只记已确认前缀', () async {
    final a = RecordingTransport()..finish();
    final b = _ReusingWriteTransport()
      ..answer = SerialWriteResult.failure('短写', acceptedBytes: 1)
      ..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => d.id == 'a' ? a : b,
    );
    final sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      sessions.dispose();
    });
    await sessions.ready;
    for (final id in ['a', 'b']) {
      add(runtime, id);
      await sessions.connect(id, sessions.layout.groups.first);
    }
    expect(await root.list().where((entry) => entry is File).isEmpty, isTrue);
    final first = sessions['a']!;
    final second = sessions['b']!;
    final observed = <RawPacket>[];
    final observerDone = Completer<void>();
    first.packets.listen(observed.add, onDone: observerDone.complete);
    a.input.add(TransportInput([11]));
    b.input.add(TransportInput([22], peer: 'device:1', datagram: true));
    await eventually(
      () => first.receivedPackets == 1 && second.receivedPackets == 1,
    );
    await second.write(Uint8List.fromList([33, 44]));
    b.lastBuffer![0] = 99;
    final confirmed = second.latest.last.packet!.bytes;
    expect(confirmed, [33]);
    expect(() => confirmed[0] = 100, throwsUnsupportedError);
    final firstHistory = (await first.history.read())!.records;
    final secondHistory = (await second.history.read())!.records;
    expect(firstHistory.map((r) => r.packet!.bytes), [
      [11],
    ]);
    expect(secondHistory.map((r) => r.packet!.bytes), [
      [22],
      [33],
    ]);
    expect(secondHistory.first.packet!.peer, 'device:1');
    expect(secondHistory.first.packet!.datagram, isTrue);
    expect(secondHistory.last.sent, isTrue);
    expect(a.written, isEmpty);
    final exported = File('${root.path}/export.jsonl');
    await first.history.exportTo(exported);
    expect(await root.list().where((entity) => entity is Directory).length, 2);
    await sessions.close('a');
    await observerDone.future;
    expect(observed.map((packet) => packet.bytes), [
      [11],
    ]);
    expect(runtime.connection('a').completelyClosed, isTrue);
    expect(await root.list().where((entity) => entity is Directory).length, 1);
    expect(await exported.exists(), isTrue);
    expect((await second.history.read())!.records.length, 2);
  });

  test('关闭再打开期间迟到的写入结果属于旧会话', () async {
    final transport = DelayedResultTransport();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    await runtime.openConnection('a');
    final sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      sessions.dispose();
    });
    await sessions.ready;
    sessions.open('a', sessions.layout.groups.first);
    final previous = sessions['a']!;
    final send = previous.write(Uint8List.fromList([1, 2]));
    await sessions.close('a');
    sessions.open('a', sessions.layout.groups.first);
    transport.pending.complete(SerialWriteResult.success(2));
    await (await send).settled;
    expect(sessions['a']!.sentBytes, 0);
    expect(await sessions['a']!.history.read(), isNull);
    expect(previous.closed, isTrue);
  });

  test('嵌套拆分与关闭状态在重启恢复，合并保持会话身份', () async {
    final runtime = CommunicationRuntime();
    for (final id in ['a', 'b', 'c', 'd']) {
      add(runtime, id);
    }
    final store = FileCommunicationConfigurationStore(
      file: File('${root.path}/layout.json'),
    );
    CommunicationSessions create() => CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      store: store,
      historyRoot: () async => root,
    );
    final first = create();
    await first.ready;
    for (final id in ['a', 'b', 'c']) {
      first.open(id, first.layout.groups.first);
    }
    first.move('c', first.layout.groups.first, SessionDrop.bottom);
    first.move('b', first.layout.groups.first, SessionDrop.right);
    first.resize(first.layout as SessionSplit, 0.63);
    first['b']!.display.fontSize = 19;
    expect(first['c']!.connection!.completelyClosed, isTrue);
    first.saveDisplay();
    await first.flushLayout();
    first.dispose();

    final second = create();
    addTearDown(() async {
      await runtime.dispose();
      second.dispose();
    });
    await second.ready;
    expect(second.layout.groups.map((group) => group.tabs.single), [
      'a',
      'b',
      'c',
    ]);
    expect((second.layout as SessionSplit).ratio, 0.63);
    expect(second['b']!.display.fontSize, 19);
    expect(second['c']!.connection!.completelyClosed, isTrue);
    expect(second.unopened.single.id, 'd');
    expect(await second['b']!.history.read(), isNull);
    final unchanged = second['b'];
    second.merge(second.layout.groups.elementAt(1));
    expect(second.layout.groups.length, 2);
    expect(second['b'], same(unchanged));
  });

  test('双会话并发接收时后台写入大批历史，分页保持顺序', () async {
    final transports = {
      'a': RecordingTransport()..finish(),
      'b': RecordingTransport()..finish(),
    };
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => transports[d.id]!,
    );
    final sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      sessions.dispose();
    });
    await sessions.ready;
    for (final id in transports.keys) {
      add(runtime, id);
      await sessions.connect(id, sessions.layout.groups.first);
    }
    sessions.move('b', sessions.layout.groups.first, SessionDrop.right);
    for (var batch = 0; batch < 10; batch++) {
      for (var packet = 0; packet < 32; packet++) {
        transports['a']!.input.add(TransportInput(List.filled(512, packet)));
        transports['b']!.input.add(
          TransportInput(List.filled(512, 255 - packet)),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await eventually(
      () =>
          sessions['a']!.receivedPackets == 320 &&
          sessions['b']!.receivedPackets == 320,
    );
    expect(sessions.pendingInputBytes, 0);
    for (final id in transports.keys) {
      final session = sessions[id]!;
      final newest = (await session.history.read())!;
      final earlier = (await session.history.read(before: newest.before))!;
      expect(earlier.before, 0);
      expect(earlier.records.length + newest.records.length, 320);
      final boundary = session.latest[200];
      final preceding = await session.history.readOlderThan(boundary.sequence);
      final oldest = await session.history.readOlderThan(
        preceding.first.sequence,
      );
      expect(
        [...oldest, ...preceding].map((record) => record.sequence),
        session.latest.take(200).map((record) => record.sequence),
      );
      expect(session.history.truncated, isFalse);
      expect(session.missedInputPackets, 0);
      expect(
        [
          ...earlier.records,
          ...newest.records,
        ].map((record) => record.packet!.bytes.first),
        List.generate(
          320,
          (index) => id == 'a' ? index % 32 : 255 - index % 32,
        ),
      );
    }
  });

  test('突发接收下一事件轮开始，另一会话的短包无需等长队列耗尽', () async {
    final transports = {
      'a': RecordingTransport()..finish(),
      'b': RecordingTransport()..finish(),
    };
    final runtime = CommunicationRuntime(
      transportFactory: (definition) async => transports[definition.id]!,
    );
    await runZoned(
      () async {
        final sessions = CommunicationSessions(
          runtime: runtime,
          defaults: DisplayConfig.new,
          historyRoot: () async => root,
        );
        addTearDown(() async {
          await runtime.dispose();
          sessions.dispose();
        });
        await sessions.ready;
        for (final id in transports.keys) {
          add(runtime, id);
        }
        for (final id in transports.keys) {
          await sessions.connect(id, sessions.layout.groups.first);
        }
        const burst = 640;
        final received = runtime.packets.take(burst + 1).last;
        final payload = TransportInput(Uint8List(512));
        for (var index = 0; index < burst; index++) {
          transports['a']!.input.add(payload);
        }
        transports['b']!.input.add(TransportInput([7]));
        await received;
        await Future<void>.delayed(Duration.zero);

        final first = sessions['a']!;
        final second = sessions['b']!;
        expect(first.receivedPackets, inExclusiveRange(0, burst));
        expect(second.receivedPackets, 1);
        expect(second.latest.single.packet!.bytes, [7]);
        await eventually(() => first.receivedPackets == burst);
        expect(sessions.pendingInputBytes, 0);
        expect(first.missedInputPackets, 0);
      },
      zoneSpecification: ZoneSpecification(
        // 延长常规合批计时，断言事件顺序时无需依赖机器负载。
        createTimer: (self, parent, zone, duration, callback) =>
            parent.createTimer(
              zone,
              duration == const Duration(milliseconds: 12)
                  ? const Duration(seconds: 1)
                  : duration,
              callback,
            ),
      ),
    );
  });

  test('发送回执不会同步耗尽接收突发，落盘顺序保留回执边界', () async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    final sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      sessions.dispose();
    });
    await sessions.ready;
    add(runtime, 'burst');
    await sessions.connect('burst', sessions.layout.groups.first);
    final session = sessions['burst']!;
    const before = 1600;
    final ingress = Completer<void>();
    final listen = runtime.packets.listen((packet) {
      if (packet.sequence == before) ingress.complete();
    });
    for (var i = 0; i < before; i++) {
      transport.input.add(TransportInput([1]));
    }
    await ingress.future;
    await listen.cancel();
    const confirmations = 160;
    for (var index = 0; index < confirmations; index++) {
      final result = await session.write(Uint8List.fromList([2]));
      expect(result.succeeded, isTrue);
    }
    expect(session.sentPackets, confirmations);
    expect(session.receivedPackets, lessThan(before));
    for (var i = 0; i < 32; i++) {
      transport.input.add(TransportInput([3]));
    }
    await eventually(
      () =>
          session.receivedPackets == before + 32 &&
          sessions.pendingInputBytes == 0,
    );
    await session.history.flush();
    final page = await session.history.readPage(after: 0, limit: 1800);
    expect(page.records.length, before + confirmations + 32);
    expect(page.records[before].sent, isTrue);
    expect(page.records.map((row) => row.packet!.bytes.single), [
      ...List.filled(before, 1),
      ...List.filled(confirmations, 2),
      ...List.filled(32, 3),
    ]);

    await session.clear();
    final receivedBeforeOverflow = session.receivedPackets;
    final beforeOverflow = Completer<void>();
    final watchingOverflow = runtime.packets.listen((packet) {
      if (packet.sequence == before + 32 + before) beforeOverflow.complete();
    });
    for (var i = 0; i < before; i++) {
      transport.input.add(TransportInput([4]));
    }
    await beforeOverflow.future;
    await watchingOverflow.cancel();
    await session.write(Uint8List.fromList([5]));
    for (var i = 0; i < 2300; i++) {
      transport.input.add(TransportInput([6]));
    }
    await eventually(
      () =>
          session.receivedPackets -
              receivedBeforeOverflow +
              session.missedInputPackets ==
          before + 2300,
    );
    await session.history.flush();
    final recovered = (await session.history.readPage(
      after: 0,
      limit: 4,
    )).records;
    expect(recovered[0].notice, contains('1600 条'));
    expect(recovered[1].sent, isTrue);
    expect(recovered[1].packet!.bytes, [5]);
    expect(recovered[2].notice, contains('252 条'));
    expect(recovered[3].packet!.bytes, [6]);
  });

  test('突发覆盖只记录待处理数据缺口，消费后归还全部队列预算', () async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    final sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      historyRoot: () async => root,
    );
    addTearDown(() async {
      await runtime.dispose();
      sessions.dispose();
    });
    await sessions.ready;
    add(runtime, 'burst');
    await sessions.connect('burst', sessions.layout.groups.first);
    final session = sessions['burst']!;
    for (var index = 0; index < 2200; index++) {
      transport.input.add(TransportInput([index % 256]));
    }
    await eventually(
      () => session.receivedPackets + session.missedInputPackets == 2200,
    );
    expect(session.missedInputPackets, 152);
    expect(sessions.pendingInputBytes, 0);
    await session.history.flush();
    final history = (await session.history.readPage(
      after: 0,
      limit: 2050,
    )).records;
    expect(history.first.notice, contains("152"));
    expect(history.skip(1).map((entry) => entry.packet!.bytes.single), [
      for (var index = 152; index < 2200; index++) index % 256,
    ]);
    await sessions.close('burst');
    expect(sessions.pendingInputBytes, 0);
  });
  test('超出批次字节预算的单条记录独立编码，普通分段保持容量', () async {
    final history = SessionHistory(
      () async => root,
      () {},
      connectionId: 'large',
    );
    addTearDown(history.close);
    final lengths = [65536, 10, 65535, 100 * 1024, 160 * 1024, 100 * 1024];
    for (final (index, length) in lengths.indexed) {
      final bytes = Uint8List(length)..[length - 1] = index + 1;
      history.append(
        SessionRecord(
          RawPacket(
            connectionId: 'large',
            receivedAt: DateTime.utc(2026),
            bytes: bytes,
            datagram: true,
          ),
        ),
      );
    }
    await history.flush();

    await for (final file
        in root.list(recursive: true).where((entry) => entry is File)) {
      expect(
        await (file as File).length(),
        lessThanOrEqualTo(history.segmentBytes),
      );
    }
    final page = await history.readPage(after: 0);
    expect(page.records.map((row) => row.packet!.bytes.length), lengths);
    expect(page.records.map((row) => row.packet!.bytes.last), [
      1,
      2,
      3,
      4,
      5,
      6,
    ]);
  });

  test('高水位历史跳过常规合批等待，下一事件轮即启动写入', () async {
    var started = false;
    final storageReady = Completer<Directory>();
    final history = SessionHistory(
      () {
        started = true;
        return storageReady.future;
      },
      () {},
      pendingLimit: 1024,
    );
    addTearDown(history.close);

    SessionRecord make(int byte) => SessionRecord(
      RawPacket(
        connectionId: 'burst',
        receivedAt: DateTime.utc(2026),
        bytes: Uint8List(256)..fillRange(0, 256, byte),
      ),
    );
    history.append(make(1));
    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);
    history.append(make(2));
    try {
      await Future<void>.delayed(Duration.zero);
      expect(started, isTrue);
    } finally {
      storageReady.complete(root);
      await history.flush();
    }
    final saved = await history.readPage(after: 0);
    expect(saved.records.map((row) => row.packet!.bytes.first), [1, 2]);
    expect(history.truncated, isFalse);
  });

  test('历史写入缺口隔离磁盘前缀，实时视图保留完整 UTF-8', () async {
    final history = SessionHistory(() async => root, () {}, pendingLimit: 330);
    addTearDown(history.close);

    SessionRecord append(List<int> bytes) => history.append(
      SessionRecord(
        RawPacket(
          connectionId: 'utf8',
          receivedAt: DateTime.utc(2026),
          bytes: bytes,
          epoch: 1,
        ),
      ),
    );

    append([0x41]);
    append([0x42]);
    final omitted = append([0xe4]);
    await history.flush();
    final continuation = append([0xb8]);
    await history.flush();
    final last = append([0xad]);
    expect(continuation.textPrefix, [0xe4]);
    expect(last.textPrefix, [0xe4, 0xb8]);
    await history.flush();
    final page = await history.readPage(after: 0);
    expect(
      page.records.any((row) => row.sequence == omitted.sequence),
      isFalse,
    );
    expect(
      page.records.where((row) => row.notice != null).single.notice,
      contains('1 条'),
    );
    expect(page.records.skip(3).map((row) => row.textPrefix), [
      isEmpty,
      isEmpty,
    ]);

    append([0xe4]);
    final complete = append([0xb8, 0xad]);
    await history.flush();
    expect(complete.textPrefix, [0xe4]);
    expect((await history.readPage()).records.last.textPrefix, [0xe4]);
  });

  test('历史轮换有界，写盘失败保留缺口并可恢复', () async {
    var failWrites = true;
    final history = SessionHistory(
      () async {
        if (failWrites) throw const FileSystemException('模拟无可用空间');
        return root;
      },
      () {},
      maxBytes: 1500,
      segmentBytes: 400,
    );
    addTearDown(history.close);
    SessionRecord record(int n) => SessionRecord(
      RawPacket(
        connectionId: 'a',
        receivedAt: DateTime(2026),
        bytes: List.filled(100, n),
      ),
    );
    history.append(record(1));
    await history.flush();
    expect(history.error, contains('模拟无可用空间'));
    history.append(record(2));
    failWrites = false;
    await history.recover();
    expect((await history.read())!.records.single.notice, contains('2 条'));
    expect(history.error, isNull);
    for (var i = 3; i < 25; i++) {
      history.append(record(i));
    }
    await history.flush();
    final latest = (await history.read())!;
    expect(latest.records.last.packet!.bytes.first, 24);
    expect(history.truncated, isTrue);
    final files = await root
        .list(recursive: true)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    expect(
      files.fold<int>(0, (bytes, file) => bytes + file.lengthSync()),
      lessThanOrEqualTo(1500),
    );
  });

  test('旧分段已不存在时，轮换仍保留新记录并回收目录', () async {
    final history = SessionHistory(
      () async => root,
      () {},
      maxBytes: 380,
      segmentBytes: 210,
    );
    addTearDown(history.close);

    void append(int byte) => history.append(
      SessionRecord(
        RawPacket(
          connectionId: 'a',
          receivedAt: DateTime.utc(2026),
          bytes: Uint8List(100)..[0] = byte,
        ),
      ),
    );
    append(1);
    append(2);
    await history.flush();

    final folder = (await root.list().single) as Directory;
    final old = File('${folder.path}${Platform.pathSeparator}0.bin');
    await old.delete();
    append(3);
    await history.flush();

    expect(history.error, isNull);
    expect(history.truncated, isTrue);
    final page = await history.readPage(after: 0);
    expect(page.records.map((row) => row.packet!.bytes.first), [2, 3]);
    expect(await old.exists(), isTrue);
    await history.close();
    expect(await folder.exists(), isFalse);
  });

  test('不相关旧文件清理失败时仍能分页读取健康分段', () async {
    final history = SessionHistory(
      () async => root,
      () {},
      maxBytes: 225,
      segmentBytes: 200,
    );
    addTearDown(history.close);
    void append(int length, int value) => history.append(
      SessionRecord(
        RawPacket(
          connectionId: 'a',
          receivedAt: DateTime.utc(2026),
          bytes: Uint8List(length)..[0] = value,
        ),
      ),
    );
    append(130, 1);
    append(20, 2);
    await history.flush();
    final folder = (await root.list().single) as Directory;
    final oldPath = '${folder.path}${Platform.pathSeparator}0.bin';
    await File(oldPath).delete();
    final blocked = await Directory(oldPath).create();
    try {
      append(2, 3);
      await history.flush();
      expect(history.error, contains('历史写入失败'));
      final page = await history.readPage(after: 0);
      expect(page.records.single.packet!.bytes.first, 2);
    } finally {
      await blocked.delete();
    }
  });

  test('双向游标只读已发布范围，分页保留跨记录 UTF-8 前缀', () async {
    final historyRoot = Completer<Directory>();
    final history = SessionHistory(
      () => historyRoot.future,
      () {},
      segmentBytes: 200,
    );
    addTearDown(() async {
      if (!historyRoot.isCompleted) historyRoot.complete(root);
      await history.close();
    });
    SessionRecord record(List<int> bytes, {bool sent = false}) => SessionRecord(
      RawPacket(connectionId: 'a', receivedAt: DateTime(2026), bytes: bytes),
      sent: sent,
    );
    final first = history.append(record([0xe4]));
    history.append(record([0x41], sent: true));
    final third = history.append(record([0xb8, 0xad]));
    for (final byte in [0xf0, 0x9f, 0x98, 0x80]) {
      history.append(record([byte]));
    }
    final writing = history.flush();
    expect((await history.readPage()).records, isEmpty);
    historyRoot.complete(root);
    await writing;

    final next = (await history.readPage(
      after: first.sequence,
      limit: 1,
    )).records;
    expect(next.single.sent, isTrue);
    final last = (await history.readPage(
      after: next.single.sequence,
      byteLimit: 1,
    )).records.single;
    expect(last.sequence, third.sequence);
    expect(last.textPrefix, [0xe4]);
    expect(last.packet!.bytes, [0xb8, 0xad]);
    final split = (await history.readPage(after: third.sequence)).records;
    expect(split.map((row) => row.textPrefix), [
      [],
      [0xf0],
      [0xf0, 0x9f],
      [0xf0, 0x9f, 0x98],
    ]);
    expect(split.map((row) => row.packet!.bytes.single), [
      0xf0,
      0x9f,
      0x98,
      0x80,
    ]);
    expect(
      (await history.readPage(before: third.sequence)).records
          .map((record) => record.sequence),
      [first.sequence, next.single.sequence],
    );
  });

  test('轮换后跨分段游标与位置索引在记录边界保持一致', () async {
    final history = SessionHistory(
      () async => root,
      () {},
      maxBytes: 1024,
      segmentBytes: 100,
    );
    addTearDown(history.close);
    for (var index = 1; index <= 40; index++) {
      history.append(
        SessionRecord(
          RawPacket(
            connectionId: 'a',
            receivedAt: DateTime(2026),
            bytes: [index],
          ),
        ),
      );
    }
    await history.flush();
    final oldest = history.oldestPublishedSequence!;
    expect(oldest, greaterThan(1));
    expect(history.publishedSequence, 40);
    final retained = [
      for (var sequence = oldest; sequence <= 40; sequence++) sequence,
    ];
    List<int> sequences(Iterable<SessionRecord> rows) => [
      for (final row in rows) row.sequence,
    ];
    final tail = await history.read(limit: 8);
    expect(sequences(tail!.records), retained.skip(retained.length - 8));
    for (final cursor in [
      oldest - 1,
      oldest,
      oldest + 1,
      32,
      40,
      41,
      0x7fffffffffffffff,
    ]) {
      final newer = await history.readPage(after: cursor, limit: 4);
      final older = await history.readPage(before: cursor, limit: 4);
      expect(newer.oldest, oldest);
      expect(older.oldest, oldest);
      expect(
        sequences(newer.records),
        retained.where((id) => id > cursor).take(4),
      );
      expect(
        sequences(older.records),
        retained.reversed.where((id) => id < cursor).take(4).toList().reversed,
      );
    }
  });

  test('历史紧凑头保留无符号边界，超长 UTF-8 标识使用完整头', () async {
    final history = SessionHistory(() async => root, () {});
    addTearDown(history.close);
    final timestamp = DateTime.utc(1965, 1, 2, 3, 4, 5, 6, 7);
    final expected = [
      for (var i = 1; i <= 2; i++)
        RawPacket(
          connectionId: '连接',
          receivedAt: timestamp,
          bytes: [i],
          epoch: 1,
          sequence: i,
          peer: '远端',
          datagram: i.isEven,
        ),
      RawPacket(
        connectionId: '连接',
        receivedAt: timestamp,
        bytes: [0, 127, 255],
        epoch: 0xffffffff,
        sequence: 0xffffffff,
        peer: '',
        datagram: true,
      ),
      RawPacket(
        connectionId: '连接',
        receivedAt: timestamp,
        bytes: [99],
        epoch: 1,
        sequence: 2,
        peer: '端' * 21845,
      ),
      RawPacket(
        connectionId: '连接',
        receivedAt: timestamp,
        bytes: [42],
        epoch: -1,
        sequence: -1,
      ),
    ];
    for (final (index, packet) in expected.indexed) {
      history.append(SessionRecord(packet, sent: index == 0));
      if (index == 1) await history.flush();
    }
    await history.flush();
    final page = await history.readPage(after: 0);
    expect(page.records.first.sent, isTrue);
    expect(page.records[1].sent, isFalse);
    expect(
      page.records.map((row) => row.packet!.toJson()),
      expected.map((packet) => packet.toJson()),
    );
  });

  test('分页按字节预算双向取整，并允许首条单独超过预算', () async {
    final history = SessionHistory(() async => root, () {}, segmentBytes: 560);
    addTearDown(history.close);
    final sizes = [3, 7, 180, 0, 1, 240, 80, 25, 3];
    for (final (index, size) in sizes.indexed) {
      history.append(
        SessionRecord(
          RawPacket(
            connectionId: 'a',
            receivedAt: DateTime.utc(2026),
            bytes: List.filled(size, index),
          ),
        ),
      );
    }
    await history.flush();
    for (final bytes in [1, 30, 70, 77, 200, 380, 1200]) {
      for (final limit in [1, 4, 160]) {
        for (final forward in [true, false]) {
          final expected = <int>[];
          var remaining = bytes;
          final ids = [for (var i = 1; i <= sizes.length; i++) i];
          for (final seq in forward ? ids : ids.reversed) {
            // 每条含 29 字节紧凑头部、1 字节连接标识和原始负载。
            final cost = sizes[seq - 1] + 30;
            if (expected.length == limit ||
                (expected.isNotEmpty && remaining < cost)) {
              break;
            }
            expected.add(seq);
            remaining -= cost;
          }
          final page = await history.readPage(
            after: forward ? 0 : null,
            before: forward ? null : sizes.length + 1,
            limit: limit,
            byteLimit: bytes,
          );
          expect(
            page.records.map((row) => row.sequence),
            forward ? expected : expected.reversed,
          );
        }
      }
    }
  });

  test('跳过纯接收分段查找下一条发送或缺口，轮换后不再返回旧记录', () async {
    final history = SessionHistory(
      () async => root,
      () {},
      maxBytes: 800,
      segmentBytes: 96,
    );
    addTearDown(history.close);
    SessionRecord packet({bool sent = false}) => SessionRecord(
      RawPacket(connectionId: 'a', receivedAt: DateTime(2026), bytes: [65]),
      sent: sent,
    );
    final sent = history.append(packet(sent: true));
    for (var row = 0; row < 10; row++) {
      history.append(packet());
    }
    final gap = history.append(const SessionRecord(null, notice: '缺口'));
    expect(history.firstSentOrNoticeAtOrAfter(0), isNull);
    await history.flush();
    expect(history.firstSentOrNoticeAtOrAfter(0), sent.sequence);
    expect(history.firstSentOrNoticeAtOrAfter(sent.sequence + 1), gap.sequence);
    final forwards = await history.readPage(
      after: sent.sequence,
      limit: 1,
      skipReceiveEdge: true,
    );
    final backwards = await history.readPage(
      before: gap.sequence,
      limit: 1,
      skipReceiveEdge: true,
    );
    expect(forwards.records.single.sequence, gap.sequence);
    expect(backwards.records.single.sequence, sent.sequence);
    expect(
      (await history.readPage(
        before: sent.sequence,
        skipReceiveEdge: true,
      )).records,
      isEmpty,
    );
    for (var row = 0; row < 25; row++) {
      history.append(packet());
    }
    await history.flush();
    expect(history.firstSentOrNoticeAtOrAfter(0), isNull);
    final recent = history.append(packet(sent: true));
    await history.flush();
    expect(history.firstSentOrNoticeAtOrAfter(0), recent.sequence);
    await history.clear();
    expect(history.firstSentOrNoticeAtOrAfter(0), isNull);
    history.append(packet());
    await history.flush();
    expect(history.firstSentOrNoticeAtOrAfter(0), isNull);
    final firstTxInLastSegment = history.append(packet(sent: true));
    await history.flush();
    expect(
      history.firstSentOrNoticeAtOrAfter(0),
      firstTxInLastSegment.sequence,
    );
    expect(
      history.firstSentOrNoticeAtOrAfter(firstTxInLastSegment.sequence + 1),
      isNull,
    );
  });
  test('清空操作保留清空发起之后接收的字节', () async {
    final history = SessionHistory(() async => root, () {});
    addTearDown(history.close);
    SessionRecord record(int value) => SessionRecord(
      RawPacket(connectionId: 'a', receivedAt: DateTime(2026), bytes: [value]),
    );
    history.append(record(1));
    final writing = history.flush();
    final clearing = history.clear();
    final latest = history.append(record(2));
    await writing;
    await clearing;
    await history.flush();
    final rows = (await history.readPage()).records;
    expect(rows.single.sequence, latest.sequence);
    expect(rows.single.packet!.bytes, [2]);
  });

  test('传输适配器只复制一次原始缓冲，给会话的记录保持不可修改', () {
    final source = Uint8List.fromList([0x01, 0x02]);
    final input = TransportInput(source, peer: '本地对端', datagram: true);
    final record = RawPacket.fromInput(
      input,
      connectionId: 'a',
      receivedAt: DateTime(2026),
      epoch: 4,
      sequence: 5,
    );
    source[0] = 0xff;
    expect(record.bytes, [0x01, 0x02]);
    expect(identical(record.bytes, input.bytes), isTrue);
    expect(() => record.bytes[0] = 0, throwsUnsupportedError);
    expect(record.datagram, isTrue);
    expect(record.peer, '本地对端');
  });

  test('复用的写句柄允许同时读取快照并在清空时释放本段', () async {
    final history = SessionHistory(() async => root, () {});
    addTearDown(history.close);
    SessionRecord record(int value) => SessionRecord(
      RawPacket(connectionId: 'a', receivedAt: DateTime(2026), bytes: [value]),
    );

    final first = history.append(record(1));
    await history.flush();
    final snapshot = history.readPage();
    final second = history.append(record(2));
    await history.flush();

    expect((await snapshot).records.map((row) => row.sequence), [
      first.sequence,
    ]);
    expect((await history.readPage()).records.map((row) => row.sequence), [
      first.sequence,
      second.sequence,
    ]);
    await history.clear();
    expect(await root.list().toList(), isEmpty);
    final third = history.append(record(3));
    await history.flush();
    expect((await history.readPage()).records.single.sequence, third.sequence);
  });

  test('分段和同批历史均保留原始包字段及 JSONL 导出', () async {
    for (final segmentBytes in [100, 2048]) {
      final history = SessionHistory(
        () async => root,
        () {},
        segmentBytes: segmentBytes,
        connectionId: '连接-串口',
      );
      addTearDown(history.close);
      final expected = [
        history.append(
          SessionRecord(
            RawPacket(
              connectionId: '连接-串口',
              receivedAt: DateTime.utc(1965, 1, 2, 3, 4, 5, 6, 7),
              bytes: [0, 0xff, 0xe4, 0x80],
              epoch: 1 << 35,
              sequence: (1 << 40) + 3,
              peer: '本地对端',
              datagram: true,
            ),
            sent: true,
          ),
        ),
        history.append(const SessionRecord(null, notice: '历史缺口：第一段')),
        history.append(
          SessionRecord(
            RawPacket(
              connectionId: '另一个连接',
              receivedAt: DateTime.utc(2026),
              bytes: [],
              peer: '',
            ),
          ),
        ),
        history.append(
          SessionRecord(
            RawPacket(
              connectionId: '连接-串口',
              receivedAt: DateTime.utc(2026),
              bytes: [0x61, 0x62, 0x63],
            ),
          ),
        ),
        for (final sequence in [0, 7])
          history.append(
            SessionRecord(
              RawPacket(
                connectionId: '连接-串口',
                receivedAt: DateTime.utc(2026),
                bytes: [0x64],
                sequence: sequence,
                epoch: 5,
              ),
              sent: true,
            ),
          ),
      ].map((record) => record.toJson()).toList();
      await history.flush();
      final page = await history.readPage();
      expect(page.records.map((record) => record.toJson()), expected);
      final destination = File('${root.path}/binary-history-export.jsonl');
      await history.exportTo(destination);
      expect((await destination.readAsLines()).map(jsonDecode), expected);
      await history.close();
    }
  });

  test('重复读页可独立修改结果，清空后读取新记录', () async {
    final history = SessionHistory(() async => root, () {});
    addTearDown(history.close);

    history.append(const SessionRecord(null, notice: '旧历史'));
    await history.flush();
    final pages = await Future.wait([
      history.readPage(after: 0),
      history.readPage(before: 2),
    ]);
    final [first, second] = pages;
    expect(first.records.single, same(second.records.single));
    first.records.clear();
    expect(second.records.single.notice, '旧历史');
    second.records.clear();

    await history.clear();
    history.append(const SessionRecord(null, notice: '新历史'));
    await history.flush();
    final fresh = await history.readPage(after: 0);
    expect(fresh.records.single.notice, '新历史');
    expect(fresh.records.single.sequence, 2);
  });

  for (final segmentBytes in [200, 512]) {
    test('重叠页补齐缺失的两端并保持记录顺序（分段 $segmentBytes 字节）', () async {
      final history = SessionHistory(
        () async => root,
        () {},
        segmentBytes: segmentBytes,
      );
      addTearDown(history.close);
      for (var number = 1; number <= 8; number++) {
        history.append(
          SessionRecord(
            RawPacket(
              connectionId: 'a',
              receivedAt: DateTime.utc(2026),
              bytes: [number],
            ),
          ),
        );
      }
      await history.flush();

      final cached = (await history.readPage(after: 2, limit: 4)).records;
      final expanded = (await history.readPage(before: 8, limit: 6)).records;
      expect(expanded.map((row) => row.packet!.bytes.single), [
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      expect(expanded[1], same(cached.first));
      expect(expanded[4], same(cached.last));
      final subset = (await history.readPage(before: 6, limit: 2)).records;
      expect(subset.map((row) => row.sequence), [4, 5]);
      expect(subset.first, same(cached[1]));
    });
  }

  test('相邻缓存页共享中间记录，补齐两端后保持顺序', () async {
    final history = SessionHistory(() async => root, () {}, segmentBytes: 200);
    addTearDown(history.close);
    for (var value = 1; value <= 10; value++) {
      history.append(
        SessionRecord(
          RawPacket(
            connectionId: 'a',
            receivedAt: DateTime.utc(2026),
            bytes: [value],
          ),
        ),
      );
    }
    await history.flush();
    final first = (await history.readPage(after: 2, limit: 3)).records;
    final second = (await history.readPage(after: 5, limit: 3)).records;
    final joined = (await history.readPage(after: 1, limit: 8)).records;
    expect(joined.map((row) => row.packet!.bytes.single), [
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
    ]);
    expect(joined[1], same(first.first));
    expect(joined[6], same(second.last));
  });

  test('混合长短包跨分段时复用占多数读取字节的缓存记录', () async {
    final history = SessionHistory(
      () async => root,
      () {},
      segmentBytes: 32768,
    );
    addTearDown(history.close);
    for (var sequence = 1; sequence <= 24; sequence++) {
      final size = sequence >= 8 && sequence <= 10 ? 24 * 1024 : 8;
      history.append(
        SessionRecord(
          RawPacket(
            connectionId: 'a',
            receivedAt: DateTime.utc(2026),
            bytes: Uint8List(size)..[size - 1] = sequence,
          ),
        ),
      );
    }
    await history.flush();

    final cached = (await history.readPage(after: 7, limit: 3)).records;
    final later = (await history.readPage(after: 11, limit: 13)).records;
    final expanded = (await history.readPage(before: 25, limit: 24)).records;
    expect(
      expanded.map((record) => record.sequence),
      List.generate(24, (i) => i + 1),
    );
    expect(
      expanded.map((record) => record.packet!.bytes.last),
      List.generate(24, (i) => i + 1),
    );
    expect(expanded[7], same(cached.first));
    expect(expanded[9], same(cached.last));
    expect(expanded[11], same(later.first));
    expect(expanded.last, same(later.last));
  });

  test('清空与跨分段分页并发时保留已开始的读取快照', () async {
    final history = SessionHistory(() async => root, () {}, segmentBytes: 200);
    addTearDown(history.close);
    for (var index = 1; index <= 8; index++) {
      history.append(
        SessionRecord(
          RawPacket(
            connectionId: 'a',
            receivedAt: DateTime(2026),
            bytes: [index],
          ),
        ),
      );
    }
    await history.flush();
    final page = history.readPage(after: 0);
    final samePage = history.readPage(before: 9);
    final subset = history.readPage(after: 2, limit: 4);
    await history.clear();
    expect((await history.readPage()).records, isEmpty);
    expect((await page).records.map((row) => row.packet!.bytes.single), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
    ]);
    expect((await samePage).records.first, same((await page).records.first));
    final saved = (await subset).records;
    expect(saved.map((row) => row.sequence), [3, 4, 5, 6]);
    expect(saved.first, same((await page).records[2]));
    expect(await root.list().toList(), isEmpty);

    history.append(const SessionRecord(null, notice: '关闭前已发布'));
    await history.flush();
    final inFlight = history.readPage();
    await history.close();
    expect((await inFlight).records.single.notice, '关闭前已发布');
    expect(await root.list().toList(), isEmpty);
  });

  test('并发父页末尾损坏时，完整的子区间仍可读取', () async {
    final history = SessionHistory(() async => root, () {}, segmentBytes: 512);
    addTearDown(history.close);
    for (var index = 1; index <= 8; index++) {
      history.append(
        SessionRecord(
          RawPacket(
            connectionId: 'a',
            receivedAt: DateTime.utc(2026),
            bytes: [index],
          ),
        ),
      );
    }
    await history.flush();
    history.append(
      SessionRecord(
        RawPacket(
          connectionId: 'a',
          receivedAt: DateTime.utc(2026),
          bytes: Uint8List(512),
        ),
      ),
    );
    await history.flush();
    final folder = await root.list().single;
    final segment = File('${folder.path}${Platform.pathSeparator}0.bin');
    final handle = await segment.open(mode: FileMode.append);
    try {
      await handle.truncate(await handle.length() - 1);
    } finally {
      await handle.close();
    }

    final parent = history.readPage(after: 0, limit: 8);
    final failure = expectLater(parent, throwsStateError);
    final subset = await history.readPage(after: 0, limit: 4);
    expect(subset.records.map((row) => row.packet!.bytes.single), [1, 2, 3, 4]);
    await failure;
  });

  test('慢速导出时写入和轮换继续，导出保留固定快照', () async {
    final history = SessionHistory(
      () async => root,
      () {},
      maxBytes: 1300,
      segmentBytes: 300,
    );
    addTearDown(history.close);
    SessionRecord record(int value) => SessionRecord(
      RawPacket(
        connectionId: 'a',
        receivedAt: DateTime(2026),
        bytes: List.filled(100, value),
      ),
    );
    for (var i = 1; i <= 4; i++) {
      history.append(record(i));
    }
    await history.flush();
    final folder = (await root.list().single) as Directory;
    final segments = (await folder.list().cast<File>().toList())
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(segments.length, 2);
    final originalFirst = await segments.first.readAsBytes();
    final destination = _SlowExport(pauseAfterChunks: 1);
    final export = history.exportTo(destination);
    await destination.started.future;
    try {
      for (var i = 5; i <= 14; i++) {
        history.append(record(i));
      }
      await history.flush().timeout(const Duration(seconds: 5));
      final retained = await history.readPage();
      expect(retained.oldest, greaterThan(4));
      expect(retained.records.last.sequence, 14);
      if (await segments.first.exists()) {
        expect(
          await segments.first.readAsBytes(),
          isNot(orderedEquals(originalFirst)),
        );
      }
      expect(await segments.last.exists(), isTrue);
    } finally {
      destination.resume.complete();
      await export;
    }
    expect(await segments.last.exists(), isFalse);
    final exported = const LineSplitter().convert(
      utf8.decode(destination.bytes),
    );
    expect(
      exported.map((line) => (jsonDecode(line) as Map)['recordSequence']),
      [1, 2, 3, 4],
    );
  });
}

class _ReusingWriteTransport extends RecordingTransport {
  Uint8List? lastBuffer;

  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) {
    lastBuffer = bytes;
    return super.write(bytes, timeoutMs);
  }
}

class _SlowExport implements File, StreamConsumer<List<int>> {
  _SlowExport({required this.pauseAfterChunks});

  final int pauseAfterChunks;
  final started = Completer<void>();
  final resume = Completer<void>();
  final bytes = <int>[];

  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => IOSink(this, encoding: encoding);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    var chunks = 0;
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (++chunks == pauseAfterChunks) {
        started.complete();
        await resume.future;
      }
    }
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
