import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/application/session_history.dart';
import 'package:clovecom/src/io/interface_params.dart';
import 'package:clovecom/src/io/recording.dart';
import 'package:clovecom/src/io/windows_udp_transport.dart';
import 'package:clovecom/widgets/communication_session_rows.dart';

// 使用 dart compile exe 生成独立程序，避免 JIT 预热影响结果。
Future<void> main(List<String> args) async {
  if (args.contains('--tail-rows') || args.contains('--tail-rows-filtered')) {
    _measureTailRows(hideReceive: args.contains('--tail-rows-filtered'));
    return;
  }
  if (args.contains('--repeat-tx-rows')) {
    final reuse = !args.contains('--without-reuse');
    for (final bytes in [10, 1024]) {
      _measureRepeatedRows(bytes, hex: false, reuse: reuse);
      _measureRepeatedRows(bytes, hex: true, reuse: reuse);
    }
    return;
  }
  if (args.contains('--repeat-long-rx-hex')) {
    for (final unique in [false, true]) {
      _measureRepeatedRows(
        1024,
        hex: true,
        reuse: true,
        received: true,
        unique: unique,
      );
    }
    return;
  }
  if (args.contains('--repeat-rx-rows')) {
    final reuse = !args.contains('--without-reuse');
    for (final unique in [false, true]) {
      for (final hex in [false, true]) {
        _measureRepeatedRows(
          10,
          hex: hex,
          reuse: reuse,
          received: true,
          unique: unique,
        );
      }
    }
    return;
  }
  if (args.contains('--format-hex')) {
    _measureHexRows(10);
    _measureHexRows(1024);
    return;
  }
  final root = await Directory.systemTemp.createTemp('clovecom-history-bench-');
  try {
    if (args.contains('--connection-storage')) {
      for (final id in ['COM10', 'connection-1795398000000000']) {
        await _measure(
          root,
          10,
          seeded: 8192,
          limits: [160],
          connectionId: id,
          compactConnection: !args.contains('--repeated-connection'),
          mixedDirections: args.contains('--mixed-directions'),
        );
      }
    } else if (args.contains('--append-confirmed-writes')) {
      await _measurePacketAppend(
        root,
        datagram: false,
        sent: true,
        wrapRecord: args.contains('--wrap-record'),
      );
    } else if (args.contains('--append-packets')) {
      await _measurePacketAppend(root, datagram: false);
      await _measurePacketAppend(root, datagram: true);
    } else if (args.contains('--udp-ingress')) {
      await _measureUdpIngress(root);
    } else if (args.contains('--tcp-ingress')) {
      await _measureTcpIngress(root);
    } else if (args.contains('--large-writes')) {
      await _measureLargeWrites(root);
    } else if (args.contains('--overlap')) {
      await _measure(root, 4096, limits: [], overlap: true);
    } else if (args.contains('--concurrent-subsets')) {
      await _measure(root, 4096, limits: [], concurrentSubsets: true);
    } else if (args.contains('--concurrent-reads')) {
      await _measure(root, 4096, limits: [], concurrentReads: true);
    } else if (args.contains('--rotation')) {
      await _measureRotation(root);
    } else if (args.contains('--pressure')) {
      await _measurePressure(root);
    } else if (args.contains('--export')) {
      await _measure(root, 64, seeded: 32768, limits: [], export: true);
    } else if (args.contains('--cached-sides')) {
      await _measure(root, 10, limits: [], cachedSides: true);
    } else if (args.contains('--cached-partial')) {
      await _measure(root, 4096, limits: [], cachedPartial: true);
    } else if (args.contains('--cached-span')) {
      await _measure(root, 4096, limits: [], cachedSpan: true);
    } else if (args.contains('--backtrack')) {
      await _measure(root, 4096, limits: [], backtrack: true);
    } else if (args.contains('--many-segments')) {
      await _measure(
        root,
        10,
        seeded: 8192,
        segmentBytes: 128,
        limits: [1, 32],
      );
    } else {
      for (final payloadBytes in [10, 1024, 4096]) {
        await _measure(root, payloadBytes);
      }
    }
  } finally {
    await root.delete(recursive: true);
  }
}

Future<void> _measure(
  Directory root,
  int payloadBytes, {
  int seeded = 2048,
  int segmentBytes = 256 * 1024,
  List<int> limits = const [32, 160],
  bool backtrack = false,
  bool cachedSpan = false,
  bool cachedSides = false,
  bool cachedPartial = false,
  bool export = false,
  bool concurrentReads = false,
  bool concurrentSubsets = false,
  bool overlap = false,
  String connectionId = 'bench',
  bool compactConnection = false,
  bool mixedDirections = false,
}) async {
  final history = SessionHistory(
    () async => root,
    () {},
    maxBytes: 64 * 1024 * 1024,
    segmentBytes: segmentBytes,
    connectionId: compactConnection ? connectionId : null,
  );
  final payload = TransportInput(Uint8List(payloadBytes));
  final timestamp = DateTime.utc(2026);
  var sequence = 0;
  void append(int count) {
    for (var i = 0; i < count; i++) {
      final number = ++sequence;
      final sent = mixedDirections ? number.isEven : number == seeded - 100;
      history.append(
        SessionRecord(
          RawPacket.fromInput(
            payload,
            connectionId: connectionId,
            receivedAt: timestamp,
            epoch: 1,
            sequence: mixedDirections && sent ? 0 : number,
          ),
          sent: sent,
        ),
      );
    }
  }

  Timer? writer;
  try {
    final seeding = Stopwatch()..start();
    for (var i = 0; i < seeded; i += 64) {
      append(64);
      await history.flush();
    }
    seeding.stop();
    var diskBytes = 0, segments = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        diskBytes += await entity.length();
        segments++;
      }
    }
    stdout.writeln(
      '$payloadBytes B / $seeded 条：$segments 段，磁盘 $diskBytes 字节，'
      '写入 ${seeding.elapsedMicroseconds} µs',
    );
    if (segmentBytes == 128) {
      await _measureSparseSeek(history, seeded - 100);
    }
    writer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      append(40);
    });
    if (backtrack) await _measureBacktrack(history);
    if (cachedSpan) await _measureCachedSpan(history);
    if (cachedSides) await _measureCachedSides(history);
    if (cachedPartial) await _measureCachedPartial(history);
    if (export) await _measureExport(root, history, seeded);
    if (concurrentReads) await _measureConcurrentReads(history);
    if (concurrentSubsets) await _measureConcurrentSubsets(history);
    if (overlap) await _measureOverlap(history);
    for (final limit in limits) {
      final samples = <int>[], dispatch = <int>[];
      for (var i = 0; i < 240; i++) {
        final cursor = 400 + ((i * 137) % (seeded - 400));
        final timer = Stopwatch()..start();
        final query = i.isEven
            ? history.readPage(before: cursor, limit: limit)
            : history.readPage(after: cursor - 400, limit: limit);
        if (i >= 40) dispatch.add(timer.elapsedMicroseconds);
        final page = await query;
        timer.stop();
        if (page.records.isEmpty) throw StateError('历史分页为空');
        var expected = i.isEven ? page.records.first.sequence : cursor - 399;
        for (final row in page.records) {
          final sent = mixedDirections
              ? expected.isEven
              : expected == seeded - 100;
          final packetSequence = mixedDirections && sent ? 0 : expected;
          if (row.sequence != expected++ ||
              row.sent != sent ||
              row.packet?.sequence != packetSequence ||
              row.packet?.bytes.length != payloadBytes ||
              row.packet?.connectionId != connectionId) {
            throw StateError('历史分页出现缺口或内容不匹配');
          }
        }
        if (i.isEven && expected != cursor) {
          throw StateError('历史分页返回错误的范围');
        }
        if (i >= 40) samples.add(timer.elapsedMicroseconds);
      }
      samples.sort();
      dispatch.sort();
      int percentile(List<int> sorted, double fraction) =>
          sorted[(sorted.length * fraction).ceil() - 1];
      stdout.writeln(
        '$payloadBytes B / $limit 条  '
        'p50=${percentile(samples, .50)} µs  p95=${percentile(samples, .95)} µs  '
        'p99=${percentile(samples, .99)} µs，提交读取 P50/P95 '
        '${percentile(dispatch, .50)}/${percentile(dispatch, .95)} µs',
      );
    }
    writer.cancel();
    await history.flush();
    if (history.error != null || history.truncated) {
      throw StateError('基准运行期间历史未完整保存 ${history.error}');
    }
  } finally {
    writer?.cancel();
    await history.close();
  }
}

Future<void> _measureSparseSeek(SessionHistory history, int expected) async {
  final baseline = Stopwatch()..start();
  var cursor = 0, pages = 0;
  int? found;
  while (found == null) {
    final page = await history.readPage(after: cursor);
    pages++;
    if (page.records.isEmpty) throw StateError('未找到历史 TX');
    found = page.records.where((row) => row.sent).firstOrNull?.sequence;
    cursor = page.records.last.sequence;
  }
  baseline.stop();
  final indexed = Stopwatch()..start();
  final target = history.firstSentOrNoticeAtOrAfter(1);
  if (target != expected || found != expected) {
    throw StateError('发送记录索引不一致');
  }
  final page = await history.readPage(after: 0, skipReceiveEdge: true);
  indexed.stop();
  if (page.records.first.sequence != expected) throw StateError('定位到错误记录');
  final lookups = Stopwatch()..start();
  const repeats = 10000;
  for (var i = 0; i < repeats; i++) {
    if (history.firstSentOrNoticeAtOrAfter(1 + (i % 200)) != expected ||
        history.firstSentOrNoticeAtOrAfter(expected + 1) != null) {
      throw StateError('稀疏 TX 索引重复查询结果不一致');
    }
  }
  final lookupMicros = lookups.elapsedMicroseconds / (2 * repeats);
  stdout.writeln('稀疏 TX 索引单次平均 ${lookupMicros.toStringAsFixed(2)} µs');
  stdout.writeln(
    '稀疏 TX 跳转：顺序扫描 $pages 页用时 ${baseline.elapsedMicroseconds} µs，'
    '索引定位并读取目标页用时 ${indexed.elapsedMicroseconds} µs',
  );
}

Future<void> _measureBacktrack(SessionHistory history) async {
  final samples = <int>[];
  for (var i = 0; i < 240; i++) {
    final cursor = i.isEven ? 512 : 672;
    final timer = Stopwatch()..start();
    final page = await history.readPage(after: cursor, limit: 96);
    timer.stop();
    if (page.records.length != 96 ||
        page.records.first.sequence != cursor + 1 ||
        page.records.last.sequence != cursor + 96) {
      throw StateError('往返读取的历史范围不一致');
    }
    if (i >= 40) samples.add(timer.elapsedMicroseconds);
    // 模拟连续回看，让实时输入和落盘也能推进。
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  samples.sort();
  final p50 = samples[samples.length ~/ 2];
  final p95 = samples[(samples.length * .95).ceil() - 1];
  stdout.writeln('相邻页往返读取 P50/P95：$p50/$p95 µs');
}

Future<void> _measureExport(
  Directory root,
  SessionHistory history,
  int expected,
) async {
  final destination = File('${root.path}${Platform.pathSeparator}export.jsonl');
  final timer = Stopwatch()..start();
  await history.exportTo(destination);
  timer.stop();
  var rows = 0;
  await for (final line
      in destination
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    final row = jsonDecode(line) as Map<String, dynamic>;
    if (row['recordSequence'] != ++rows) throw StateError('导出记录顺序不一致');
  }
  if (rows != expected) throw StateError('导出记录条数 $rows，预期 $expected');
  stdout.writeln('JSONL 导出 $rows 条，耗时 ${timer.elapsedMicroseconds} µs');
}

Future<void> _measurePressure(Directory root) async {
  final history = SessionHistory(
    () async => root,
    () {},
    maxBytes: 16 * 1024 * 1024,
    pendingLimit: 512 * 1024,
  );
  final input = TransportInput(Uint8List(4096));
  final start = DateTime.utc(2026);
  var count = 0;
  try {
    final elapsed = Stopwatch()..start();
    for (var burst = 0; burst < 60; burst++) {
      for (var row = 0; row < 48; row++) {
        history.append(
          SessionRecord(
            RawPacket.fromInput(
              input,
              connectionId: 'pressure',
              receivedAt: start,
              epoch: 1,
              sequence: ++count,
            ),
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 9));
    }
    await history.flush();
    elapsed.stop();
    var cursor = 0, saved = 0, gaps = 0;
    while (cursor < history.publishedSequence) {
      final page = await history.readPage(after: cursor, limit: 128);
      if (page.records.isEmpty) throw StateError('历史分页未推进');
      for (final row in page.records) {
        if (row.packet != null) {
          saved++;
        } else {
          gaps++;
        }
      }
      cursor = page.records.last.sequence;
    }
    if (history.error != null) throw StateError(history.error!);
    stdout.writeln(
      '持续突发保留 $saved/$count 条，缺口 $gaps 个，写入 ${elapsed.elapsedMilliseconds} ms',
    );
  } finally {
    await history.close();
  }
}

Future<void> _measureRotation(Directory root) async {
  final history = SessionHistory(
    () async => root,
    () {},
    maxBytes: 2 * 1024 * 1024,
    segmentBytes: 16 * 1024,
  );
  final input = TransportInput(Uint8List(4096));
  final timestamp = DateTime.utc(2026);
  var sequence = 0;
  try {
    final timer = Stopwatch()..start();
    for (var batch = 0; batch < 64; batch++) {
      for (var record = 0; record < 48; record++) {
        history.append(
          SessionRecord(
            RawPacket.fromInput(
              input,
              connectionId: 'rotation',
              receivedAt: timestamp,
              epoch: 1,
              sequence: ++sequence,
            ),
          ),
        );
      }
      await history.flush();
    }
    timer.stop();
    final oldest = history.oldestPublishedSequence;
    if (history.error != null ||
        !history.truncated ||
        oldest == null ||
        oldest <= 1) {
      throw StateError('基准未完成历史轮换：${history.error}');
    }
    var diskBytes = 0;
    await for (final file in root.list(recursive: true)) {
      if (file is File) diskBytes += await file.length();
    }
    if (diskBytes > history.maxBytes) throw StateError('历史超过容量：$diskBytes');
    var expected = oldest;
    while (expected <= sequence) {
      final page = await history.readPage(after: expected - 1, limit: 128);
      if (page.records.isEmpty) throw StateError('轮换后分页未推进');
      for (final row in page.records) {
        if (row.sequence != expected++ || row.packet == null) {
          throw StateError('轮换后历史存在缺口');
        }
      }
    }
    stdout.writeln(
      '轮换写入 $sequence 条，保留 ${sequence - oldest + 1} 条，'
      '磁盘 $diskBytes 字节，耗时 ${timer.elapsedMicroseconds} µs',
    );
  } finally {
    await history.close();
  }
}

Future<void> _measureConcurrentReads(SessionHistory history) async {
  final samples = <int>[];
  for (var trial = 0; trial < 80; trial++) {
    final cursor = 200 + trial * 9;
    final watch = Stopwatch()..start();
    final pages = await Future.wait([
      for (var reader = 0; reader < 12; reader++)
        history.readPage(after: cursor, limit: 96),
    ]);
    watch.stop();
    if (trial >= 10) samples.add(watch.elapsedMicroseconds);
    if (pages.any(
      (page) =>
          page.records.length != 96 ||
          page.records.first.sequence != cursor + 1 ||
          page.records.last.sequence != cursor + 96,
    )) {
      throw StateError('并发分页范围不一致');
    }
    pages.first.records.clear();
    if (pages.last.records.length != 96) throw StateError('并发分页结果互相影响');
  }
  samples.sort();
  stdout.writeln(
    '12 路同页读取 P50/P95 ${samples[samples.length ~/ 2]}/'
    '${samples[(samples.length * .95).ceil() - 1]} µs',
  );
}

Future<void> _measureOverlap(SessionHistory history) async {
  final samples = <int>[];
  for (var trial = 0; trial < 240; trial++) {
    final start = 100 + trial * 3;
    final timer = Stopwatch()..start();
    final page = trial.isEven
        ? await history.readPage(after: start - 1, limit: 96)
        : await history.readPage(before: start + 96, limit: 96);
    timer.stop();
    if (trial >= 40) samples.add(timer.elapsedMicroseconds);
    if (page.records.length != 96 ||
        page.records.first.sequence != start ||
        page.records.last.sequence != start + 95) {
      throw StateError('重叠历史分页范围不正确');
    }
  }
  samples.sort();
  stdout.writeln(
    '重叠页 P50/P95 ${samples[samples.length ~/ 2]}/'
    '${samples[(samples.length * .95).ceil() - 1]} µs',
  );
}

Future<void> _measureCachedSides(SessionHistory history) async {
  final samples = <int>[];
  for (var trial = 0; trial < 240; trial++) {
    final cursor = 80 + (trial * 307) % 1400;
    final cached = await history.readPage(after: cursor + 16, limit: 64);
    final timer = Stopwatch()..start();
    final page = await history.readPage(after: cursor, limit: 96);
    timer.stop();
    if (trial >= 40) samples.add(timer.elapsedMicroseconds);
    if (page.records.length != 96 ||
        !identical(page.records[16], cached.records.first) ||
        !identical(page.records[79], cached.records.last)) {
      throw StateError('两端补页未复用中间记录');
    }
    for (final (index, record) in page.records.indexed) {
      if (record.sequence != cursor + index + 1 ||
          record.packet?.bytes.length != 10) {
        throw StateError('两端补页的范围或字节不一致');
      }
    }
  }
  samples.sort();
  final p50 = samples[99];
  final p95 = samples[189];
  final p99 = samples[197];
  stdout.writeln('同段两端补页 P50/P95/P99 $p50/$p95/$p99 µs');
}

Future<void> _measureCachedSpan(SessionHistory history) async {
  final samples = <int>[];
  for (var trial = 0; trial < 240; trial++) {
    final start = 64 + trial * 7;
    final first = await history.readPage(after: start - 1, limit: 32);
    final last = await history.readPage(after: start + 31, limit: 32);
    final timer = Stopwatch()..start();
    final joined = trial.isEven
        ? await history.readPage(after: start + 15, limit: 32)
        : await history.readPage(before: start + 48, limit: 32);
    timer.stop();
    if (trial >= 40) samples.add(timer.elapsedMicroseconds);
    var expected = start + 16;
    if (joined.records.length != 32 ||
        joined.records.any((record) => record.sequence != expected++)) {
      throw StateError('跨缓存页的记录范围不一致');
    }
    joined.records.clear();
    if (first.records.length != 32 || last.records.length != 32) {
      throw StateError('跨缓存页的结果影响了已有页面');
    }
  }
  samples.sort();
  stdout.writeln(
    '跨缓存页 P50/P95/P99 ${samples[99]}/${samples[189]}/${samples[197]} µs',
  );
}

void _measureRepeatedRows(
  int size, {
  required bool hex,
  required bool reuse,
  bool received = false,
  bool unique = false,
}) {
  const batches = 280;
  const rowsPerBatch = 64;
  final input = TransportInput.takeOwned(
    Uint8List(size)..fillRange(0, size, 65),
  );
  final now = DateTime.utc(2026);
  final projection = SessionDisplayRows();
  final expected = hex ? List.filled(size, '41').join(' ') : 'A' * size;
  final expectations = List.generate(rowsPerBatch, (index) {
    if (!unique) return expected;
    final head = index + 32;
    return hex
        ? head.toRadixString(16).padLeft(2, '0').toUpperCase() +
              expected.substring(2)
        : String.fromCharCode(head) + expected.substring(1);
  });
  final samples = <int>[];
  for (var batch = 0; batch < batches; batch++) {
    final rows = [
      for (var index = 0; index < rowsPerBatch; index++)
        SessionDisplayRow(
          SessionRecord(
            RawPacket.fromInput(
              received
                  ? TransportInput.takeOwned(
                      Uint8List(size)
                        ..fillRange(0, size, 65)
                        ..[0] = unique ? index + 32 : 65,
                    )
                  : input,
              connectionId: 'bench',
              receivedAt: now,
              epoch: 1,
              sequence: 0,
            ),
            sequence: batch * rowsPerBatch + index + 1,
            sent: !received,
          ),
          0,
        ),
    ];
    final results = List<String>.filled(rowsPerBatch, '');
    final timer = Stopwatch()..start();
    for (var index = 0; index < rowsPerBatch; index++) {
      final row = rows[index];
      results[index] = reuse
          ? projection.textFor(row, hex: hex)
          : row.text(hex: hex);
    }
    timer.stop();
    if (batch >= 40) samples.add(timer.elapsedTicks);
    for (var index = 0; index < rowsPerBatch; index++) {
      if (results[index] != expectations[index]) {
        throw StateError('报文显示内容不一致');
      }
    }
  }
  samples.sort();
  final format = hex ? 'HEX' : 'UTF-8';
  final frequency = Stopwatch().frequency;
  String microseconds(int ticks) =>
      (ticks * Duration.microsecondsPerSecond / frequency).toStringAsFixed(2);
  final p50 = microseconds(samples[119]);
  final p95 = microseconds(samples[227]);
  final workload = received ? (unique ? '不同接收' : '重复接收') : '重复发送';
  stdout.writeln(
    '$rowsPerBatch 条 × $size B $workload $format P50/P95 $p50/$p95 µs',
  );
}

void _measureHexRows(int bytesPerRow) {
  final bytes = Uint8List.fromList([
    for (var i = 0; i < bytesPerRow; i++) (i * 137 + 11) & 255,
  ]);
  final packet = RawPacket(
    connectionId: 'hex',
    receivedAt: DateTime.utc(2026),
    bytes: bytes,
  );
  final expected = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
  final samples = <int>[];
  final timer = Stopwatch();
  for (var batch = 0; batch < 260; batch++) {
    final rows = [
      for (var i = 0; i < 32; i++)
        SessionDisplayRow(SessionRecord(packet, sequence: i + 1), 0),
    ];
    final results = List<String>.filled(rows.length, '');
    timer
      ..reset()
      ..start();
    for (var i = 0; i < rows.length; i++) {
      results[i] = rows[i].text(hex: true);
    }
    timer.stop();
    if (batch >= 60) samples.add(timer.elapsedMicroseconds);
    if (results.any((result) => result != expected)) {
      throw StateError('十六进制文本与原始字节不一致');
    }
  }
  samples.sort();
  stdout.writeln(
    '${packet.bytes.length} B 十六进制格式化 32 行 P50/P95/P99 '
    '${samples[99]}/${samples[189]}/${samples[197]} µs',
  );
}

Future<void> _measureLargeWrites(Directory root) async {
  const length = 512 * 1024;
  const count = 96;
  final history = SessionHistory(
    () async => root,
    () {},
    maxBytes: 64 * 1024 * 1024,
  );
  final bytes = Uint8List(length);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = (17 * index + 73) & 255;
  }
  final input = TransportInput.takeOwned(bytes);
  final watch = Stopwatch()..start();
  try {
    for (var index = 1; index <= count; index++) {
      history.append(
        SessionRecord(
          RawPacket.fromInput(
            input,
            connectionId: 'large-record',
            receivedAt: DateTime.utc(2026),
            epoch: 1,
            sequence: index,
          ),
        ),
      );
      await history.flush();
    }
    watch.stop();
    if (history.error != null || history.truncated) {
      throw StateError('大块历史写入不完整');
    }
    final readTimes = <int>[];
    for (var index = 1; index <= count; index++) {
      final readTimer = Stopwatch()..start();
      final records = (await history.readPage(
        after: index - 1,
        limit: 1,
      )).records;
      readTimes.add(readTimer.elapsedMicroseconds);
      final record = records.single;
      final actual = record.packet!.bytes;
      if (record.sequence != index || actual.length != length) {
        throw StateError('大块历史索引不一致');
      }
      for (var offset = 0; offset < actual.length; offset++) {
        if (actual[offset] != bytes[offset]) throw StateError('大块历史内容不一致');
      }
    }
    readTimes.sort();
    stdout.writeln(
      '单条读取 P50/P95/P99 ${readTimes[47]}/${readTimes[91]}/${readTimes[95]} µs',
    );
    stdout.writeln('$count 条 × $length 字节，写入 ${watch.elapsedMicroseconds} µs');
  } finally {
    await history.close();
  }
}

void _measureTailRows({required bool hideReceive}) {
  const windowSize = 400;
  const step = 32;
  const iterations = 2400;
  final payload = TransportInput.takeOwned(Uint8List(10));
  final packet = RawPacket.fromInput(
    payload,
    connectionId: 'rows',
    receivedAt: DateTime.utc(2026),
    epoch: 1,
    sequence: 0,
  );
  final records = [
    for (var index = 1; index <= windowSize + iterations * step; index++)
      SessionRecord(packet, sequence: index, sent: index % 100 == 0),
  ];
  final rows = SessionDisplayRows();
  final timer = Stopwatch();
  for (var start = 0; start <= iterations * step; start += step) {
    final window = records.sublist(start, start + windowSize);
    if (start >= 200 * step) timer.start();
    rows.replace(window, hideReceive: hideReceive, liveTail: true);
    timer.stop();
    final last = start + windowSize;
    if (rows.length != (hideReceive ? windowSize ~/ 100 : windowSize) ||
        rows.lastOrNull?.id != (hideReceive ? last ~/ 100 * 100 : last, 0)) {
      throw StateError('实时尾部投影范围错误');
    }
  }
  stdout.writeln('实时尾部 2201 次换窗，总计 ${timer.elapsedMicroseconds} µs');
}

Future<void> _measureConcurrentSubsets(SessionHistory history) async {
  final samples = <int>[];
  for (var trial = 0; trial < 80; trial++) {
    final cursor = 192 + (trial * 307) % 1400;
    final watch = Stopwatch()..start();
    final pages = await Future.wait([
      history.readPage(after: cursor, limit: 96),
      for (var offset = 1; offset <= 12; offset++)
        history.readPage(after: cursor + offset, limit: 80),
    ]);
    watch.stop();
    if (trial >= 10) samples.add(watch.elapsedMicroseconds);
    for (var offset = 1; offset < pages.length; offset++) {
      final rows = pages[offset].records;
      if (rows.length != 80 ||
          rows.first.sequence != cursor + offset + 1 ||
          rows.last.sequence != cursor + offset + 80) {
        throw StateError('并发子页范围不一致');
      }
    }
    pages.first.records.clear();
    if (pages.last.records.length != 80) throw StateError('并发子页结果互相影响');
  }
  samples.sort();
  stdout.writeln(
    '12 路并发子页 P50/P95 ${samples[samples.length ~/ 2]}/'
    '${samples[(samples.length * .95).ceil() - 1]} µs',
  );
}

Future<void> _measureCachedPartial(SessionHistory history) async {
  final samples = <int>[];
  for (var trial = 0; trial < 120; trial++) {
    final cursor = 80 + (trial * 307) % 1400;
    final first = await history.readPage(after: cursor, limit: 32);
    final second = await history.readPage(after: cursor + 32, limit: 32);
    final watch = Stopwatch()..start();
    final page = await history.readPage(after: cursor, limit: 96);
    watch.stop();
    if (trial >= 20) samples.add(watch.elapsedMicroseconds);
    for (var index = 0; index < page.records.length; index++) {
      final row = page.records[index];
      if (row.sequence != cursor + index + 1 ||
          row.packet?.bytes.length != 4096) {
        throw StateError('多页部分命中返回了错误记录');
      }
    }
    if (page.records.length != 96 ||
        first.records.length != 32 ||
        second.records.length != 32) {
      throw StateError('多页部分命中的结果长度不一致');
    }
  }
  samples.sort();
  stdout.writeln('多页部分命中 P50/P95 ${samples[49]}/${samples[94]} µs');
}

Future<void> _measurePacketAppend(
  Directory root, {
  required bool datagram,
  bool sent = false,
  bool wrapRecord = false,
}) async {
  const batches = 140, batchSize = 1024;
  final input = TransportInput(ascii.encode('1234567890'), datagram: datagram);
  final now = DateTime.utc(2026);
  final packets = [
    for (var index = 0; index < batchSize; index++)
      RawPacket.fromInput(
        input,
        connectionId: 'bench',
        receivedAt: now,
        epoch: 1,
        sequence: sent ? 0 : index + 1,
      ),
  ];
  final history = SessionHistory(
    () async => root,
    () {},
    maxBytes: 8 * 1024 * 1024,
  );
  final samples = <int>[];
  try {
    for (var batch = 0; batch < batches; batch++) {
      final timer = Stopwatch()..start();
      for (final packet in packets) {
        if (wrapRecord) {
          history.append(SessionRecord(packet, sent: sent));
        } else {
          history.appendPacket(packet, sent: sent);
        }
      }
      timer.stop();
      if (batch >= 20) samples.add(timer.elapsedMicroseconds);
      await history.flush();
    }
    if (history.error != null ||
        history.truncated ||
        history.oldestPublishedSequence != 1 ||
        history.publishedSequence != batches * batchSize) {
      throw StateError('入队基准未完整保存历史');
    }
    final last = (await history.readPage(limit: 1)).records.single;
    if (last.sent != sent || last.packet?.sequence != (sent ? 0 : batchSize)) {
      throw StateError('入队基准未还原记录方向和包序号');
    }
    samples.sort();
    final type = sent
        ? '发送回执'
        : datagram
        ? '独立报文'
        : '字节流';
    final p50 = samples[samples.length ~/ 2];
    final p95 = samples[(samples.length * .95).ceil() - 1];
    stdout.writeln('$type $batchSize × 10 B 短包入队 P50/P95 $p50/$p95 µs');
  } finally {
    await history.close();
  }
}

Future<void> _measureTcpIngress(Directory root) async {
  const burstBytes = 256 * 1024;
  const bursts = 120;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = server.first;
  final history = SessionHistory(
    () async => root,
    () {},
    maxBytes: 4 * 1024 * 1024,
  );
  CommunicationTransport? client;
  Socket? peer;
  StreamSubscription<TransportInput>? input;
  try {
    client = await openCommunicationTransport(
      ConnectionDefinition.network(
        id: 'loopback',
        name: 'TCP 回环',
        protocol: InterfaceProtocol.tcpClient,
        tcpClient: TcpClientPrefs(
          remoteHost: '127.0.0.1',
          remotePort: server.port,
        ),
      ),
    );
    peer = await accepted;
    final bytes = Uint8List.fromList(List.generate(burstBytes, (i) => i & 255));
    final samples = <int>[];
    var received = 0, packetCount = 0;
    final time = DateTime.utc(2026);
    Completer<void>? arrived;
    input = client.incoming.listen((chunk) {
      for (final byte in chunk.bytes) {
        if (byte != (received++ & 255)) {
          arrived?.completeError(StateError('TCP 接收数据内容错误'));
          return;
        }
      }
      history.append(
        SessionRecord(
          RawPacket.fromInput(
            chunk,
            connectionId: 'loopback',
            receivedAt: time,
            epoch: 1,
            sequence: ++packetCount,
          ),
        ),
      );
      if (received % burstBytes == 0) arrived?.complete();
    });
    for (var index = 0; index < bursts; index++) {
      arrived = Completer<void>();
      final watch = Stopwatch()..start();
      peer.add(bytes);
      await peer.flush();
      await arrived.future.timeout(const Duration(seconds: 3));
      if (index >= 20) samples.add(watch.elapsedMicroseconds);
      await history.flush();
    }
    final first = history.oldestPublishedSequence;
    if (received != bursts * burstBytes ||
        first == null ||
        first <= 1 ||
        history.publishedSequence != packetCount ||
        history.error != null) {
      throw StateError('TCP 回环或历史轮换失败');
    }
    final tail = (await history.readPage(limit: 1)).records.single;
    if (tail.packet?.sequence != packetCount) throw StateError('历史末包未保存');
    samples.sort();
    stdout.writeln(
      'TCP 256 KiB 接收并入队 P50/P95 ${samples[49]}/${samples[94]} µs，'
      '$received 字节、$packetCount 个接收块，历史轮换至首条 $first',
    );
  } finally {
    await input?.cancel();
    await client?.close();
    peer?.destroy();
    await server.close();
    await history.close();
  }
}

Future<void> _measureUdpIngress(Directory root) async {
  const perBurst = 16;
  const bursts = 160;
  const length = 1200;
  final local = InternetAddress.loopbackIPv4;
  final transport = await WindowsUdpTransport.open(
    UdpPrefs(nicKey: local.address),
  );
  final sender = await WindowsUdpTransport.open(
    UdpPrefs(
      nicKey: local.address,
      unicastHost: local.address,
      unicastPort: transport.boundPort,
    ),
  );
  final receiver = NetworkCommunicationTransport(
    transport,
    InterfaceProtocol.udp,
  );
  final history = SessionHistory(
    () async => root,
    () {},
    maxBytes: 1024 * 1024,
  );
  final payloads = [
    for (var i = 0; i < perBurst; i++)
      Uint8List(length)..fillRange(0, length, i),
  ];
  final samples = <int>[];
  var packets = 0;
  late Completer<void> arrived;
  final input = receiver.incoming.listen((chunk) {
    final expected = payloads[packets % perBurst];
    if (!chunk.datagram ||
        chunk.peer != '${local.address}:${sender.boundPort}' ||
        chunk.bytes.length != length ||
        chunk.bytes.any((byte) => byte != expected[0])) {
      arrived.completeError(StateError('UDP 报文边界、来源或负载不一致'));
      return;
    }
    packets++;
    history.append(
      SessionRecord(
        RawPacket.fromInput(
          chunk,
          connectionId: 'udp',
          receivedAt: DateTime.utc(2026),
          epoch: 1,
          sequence: packets,
        ),
      ),
    );
    if (packets % perBurst == 0) arrived.complete();
  });
  try {
    for (var index = 0; index < bursts; index++) {
      arrived = Completer<void>();
      final watch = Stopwatch()..start();
      for (final payload in payloads) {
        await sender.send(payload);
      }
      await arrived.future.timeout(const Duration(seconds: 3));
      if (index >= 20) samples.add(watch.elapsedMicroseconds);
      await history.flush();
    }
    if (history.error != null ||
        packets != bursts * perBurst ||
        history.publishedSequence != packets ||
        history.oldestPublishedSequence! <= 1) {
      throw StateError('UDP 历史写入或轮换失败');
    }
    final last = (await history.readPage(limit: 1)).records.single.packet!;
    if (last.sequence != packets ||
        !last.datagram ||
        last.peer != '${local.address}:${sender.boundPort}') {
      throw StateError('UDP 历史没有保存末包或来源');
    }
    samples.sort();
    stdout.writeln(
      'UDP $perBurst × $length B 入队 P50/P95 '
      '${samples[69]}/${samples[132]} µs，共 $packets 个报文，历史已轮换',
    );
  } finally {
    await input.cancel();
    await receiver.close();
    await sender.close();
    await history.close();
  }
}
