import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/services/serial/serial_byte_transport.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_sessions.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/application/session_history.dart';
import 'package:clovecom/widgets/communication_session_data_view.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show ClearSelectionEvent, SelectWordSelectionEvent;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

typedef _CpuWindow = ({String phase, int start, int end});

Future<void> main() async {
  try {
    await _run();
    stdout.writeln('会话视图基准通过');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
  exit(0);
}

Future<void> _measureHexShaping() async {
  runApp(const SizedBox.shrink());
  await SchedulerBinding.instance.endOfFrame;
  final lines = List.generate(
    40,
    (row) => List.generate(
      1024,
      (byte) => (((byte * 131 + row * 53) ^ (byte >> 3)) & 0xff)
          .toRadixString(16)
          .padLeft(2, '0')
          .toUpperCase(),
    ).join(' '),
  );
  final body = ThemeData().textTheme.bodyMedium!;
  final font = Platform.environment['CLOVECOM_BENCH_HEX_FONT'] ?? 'monospace';
  stdout.writeln('HEX 排版字体 $font');
  for (final size in [8.0, 13.0, 22.0, 32.0]) {
    final style = body.copyWith(fontFamily: font, fontSize: size);
    TextPainter painter(String text) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    double caret(TextPainter text, int index) =>
        text.getOffsetForCaret(TextPosition(offset: index), Rect.zero).dx;

    final alphabet = painter('0123456789 ABCDEF');
    final advance = (caret(alphabet, 15) - caret(alphabet, 0)) / 15;
    alphabet.dispose();
    const glyphs = '0123456789 ABCDEF';
    final advances = Float64List(128 * 128);
    for (final left in glyphs.codeUnits) {
      final isolated = painter(String.fromCharCode(left));
      advances[left * 128] = isolated.width;
      isolated.dispose();
      for (final right in glyphs.codeUnits) {
        final pair = painter(String.fromCharCodes([left, right, 48]));
        advances[left * 128 + right] = caret(pair, 1) - caret(pair, 0);
        pair.dispose();
      }
    }
    Float32List positions(String text) {
      // 与 Windows 字形布局的单精度坐标累加对照。
      final result = Float32List(text.length + 1);
      for (var index = 0; index < text.length; index++) {
        final next = index + 1 == text.length ? 0 : text.codeUnitAt(index + 1);
        result[index + 1] =
            result[index] + advances[text.codeUnitAt(index) * 128 + next];
      }
      return result;
    }

    var verified = 0, equalWidthVerified = 0;
    var maximum = 0.0;
    final chunks = <String>[];
    for (final (index, line) in lines.indexed) {
      final full = painter(line);
      final first = index * 71 % (line.length - 100);
      final count = (380 / advance).ceil() + 8;
      final chunk = line.substring(
        first,
        (first + count).clamp(0, line.length),
      );
      final clipped = painter(chunk);
      // 以完整段落为准，对比每个片段边界、行高和命中位置。
      final geometry = positions(line);
      var error = (full.width - geometry.last).abs();
      final height = (full.height - clipped.height).abs();
      if (height > error) error = height;
      if ((full.width - advance * line.length).abs() < .05) {
        equalWidthVerified++;
      }
      final translation = geometry[first + 4] - caret(clipped, 4);
      for (var column = 4; column < chunk.length - 4; column++) {
        final fullX = caret(full, first + column);
        final modelX = geometry[first + column];
        final modelError = (fullX - modelX).abs();
        final clipError = (fullX - caret(clipped, column) - translation).abs();
        if (modelError > error) error = modelError;
        if (clipError > error) error = clipError;
        final interior = (modelX * 3 + geometry[first + column + 1]) / 4;
        final hit = full.getPositionForOffset(
          Offset(interior, full.height / 2),
        );
        if (hit.offset != first + column) error = double.infinity;
      }
      if (error > maximum) maximum = error;
      if (error < .05) verified++;
      chunks.add(chunk);
      full.dispose();
      clipped.dispose();
    }
    final fullTimes = <int>[], chunkTimes = <int>[], geometryTimes = <int>[];
    var checksum = 0.0;
    for (var repeat = 0; repeat < 70; repeat++) {
      for (final clipped in [repeat.isEven, repeat.isOdd]) {
        final timer = Stopwatch()..start();
        for (final text in clipped ? chunks : lines) {
          painter(text).dispose();
        }
        timer.stop();
        if (repeat >= 10) {
          (clipped ? chunkTimes : fullTimes).add(timer.elapsedMicroseconds);
        }
      }
      final timer = Stopwatch()..start();
      for (final line in lines) {
        checksum += positions(line).last;
      }
      timer.stop();
      if (repeat >= 10) geometryTimes.add(timer.elapsedMicroseconds);
    }
    if (checksum <= 0) throw StateError('缺少长行几何样本');
    geometryTimes.sort();
    fullTimes.sort();
    chunkTimes.sort();
    final fullTiming = _percentiles(fullTimes);
    final chunkTiming = _percentiles(chunkTimes);
    final geometryTiming = _percentiles(geometryTimes);
    final maxDeviation = maximum.toStringAsFixed(3);
    stdout.writeln(
      '字号 $size 40 行排版 P50/P95/P99，完整 $fullTiming µs，'
      '横向片段 $chunkTiming µs，字符位置 $geometryTiming µs，'
      '等宽校验 $equalWidthVerified/40，实际字符宽度校验 $verified/40，最大偏差 $maxDeviation px',
    );
  }
}

Future<void> _measureSerialReceipts(
  List<String> ports,
  int baud,
  int size,
  Duration interval,
  Duration phase,
) async {
  final links = <Win32SerialTransport>[];
  final subscriptions = <StreamSubscription<Uint8List>>[];
  final loops = <SerialWorkerLoop>[];
  final bytes = [0, 1]
      .map(
        (index) => Uint8List.fromList(
          List.generate(size, (offset) => (index * 97 + offset * 131) & 255),
        ),
      )
      .toList();
  final received = [0, 0], confirmed = [0, 0];
  final ages = [<int>[], <int>[]];
  String? failure;
  try {
    for (final port in ports) {
      links.add(
        await Win32SerialTransport.open(
          SerialPortConfig(portName: port, baudRate: baud),
        ),
      );
    }
    for (final (index, link) in links.indexed) {
      final expected = bytes[1 - index];
      subscriptions.add(
        link.chunks.listen((chunk) {
          for (final value in chunk) {
            if (value != expected[received[index] % size]) {
              failure ??= '回执基准接收内容不一致';
            }
            received[index]++;
          }
        }),
      );
      final loop = link.startWorkerLoop(
        bytes[index],
        interval: interval,
        timeoutMs: 500,
        immediate: true,
        onRounds: (rounds, timing) {
          final now = DateTime.now().microsecondsSinceEpoch;
          if (!timing.usesNativeWriter) failure ??= '未使用原生写入';
          for (final round in rounds) {
            if (round.accepted != size || round.reason != null) {
              failure ??= round.reason ?? '回执基准写入不完整';
            }
            confirmed[index] += round.accepted ?? 0;
            ages[index].add(now - round.timestampMicros);
          }
        },
      );
      if (loop == null) throw StateError('回执基准启动循环失败');
      loops.add(loop);
    }

    await Future<void>.delayed(phase);
    for (final loop in loops) {
      loop.stop(cancelInFlight: false);
    }
    for (final result in await Future.wait(
      loops.map((loop) => loop.done),
    ).timeout(const Duration(seconds: 6))) {
      if (result.reason != null || result.unavailable) {
        failure ??= result.reason ?? '原生循环不可用';
      }
    }
    final deadline = Stopwatch()..start();
    while ((received[0] < confirmed[1] || received[1] < confirmed[0]) &&
        deadline.elapsed < const Duration(seconds: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (failure != null ||
        received[0] != confirmed[1] ||
        received[1] != confirmed[0] ||
        ages.any((samples) => samples.length < 100)) {
      throw StateError(failure ?? '回执基准字节或样本数不一致');
    }
    for (final (index, samples) in ages.indexed) {
      samples.sort();
      final timing = _percentiles(samples);
      final rounds = samples.length;
      final port = ports[index];
      final count = confirmed[index];
      stdout.writeln(
        '$port 回执送达 P50/P95/P99 $timing µs，$rounds 轮，已核对 $count 字节',
      );
    }
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await Future.wait(links.map((link) => link.close()));
  }
}

class _BurstTransport implements CommunicationTransport {
  final input = StreamController<TransportInput>.broadcast(sync: true);

  @override
  CommunicationTransportState get state =>
      const CommunicationTransportState(writable: true);

  @override
  Stream<TransportInput> get incoming => input.stream;

  @override
  Stream<CommunicationTransportState> get states => const Stream.empty();

  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) async =>
      SerialWriteResult.success(bytes.length);

  @override
  Future<void> close() => input.close();
}

Future<void> _measureSessionBurst() async {
  final transport = _BurstTransport();
  final root = await Directory.systemTemp.createTemp('clovecom-burst-bench-');
  final runtime = CommunicationRuntime(
    transportFactory: (_) async => transport,
  );
  final sessions = CommunicationSessions(
    runtime: runtime,
    defaults: DisplayConfig.new,
    historyRoot: () async => root,
  );
  try {
    await sessions.ready;
    const id = 'burst';
    runtime.addConnection(
      ConnectionDefinition.serial(
        serialConnectionConfig(id, SerialPortConfig(portName: id)),
      ),
    );
    await sessions.connect(id, sessions.layout.groups.first);
    final session = sessions[id]!;
    final input = TransportInput.takeOwned(Uint8List(192));
    final command = Uint8List.fromList([0x42]);
    final samples = <int>[];
    for (var batch = 0; batch < 280; batch++) {
      final before = session.receivedPackets;
      for (var index = 0; index < 128; index++) {
        transport.input.add(input);
      }
      final timer = Stopwatch()..start();
      await session.write(command);
      timer.stop();
      if (session.receivedPackets != before + 128 ||
          session.latest.last.packet?.bytes.singleOrNull != command.single) {
        throw StateError('回执前的接收批次未完整写入历史');
      }
      if (batch >= 40) samples.add(timer.elapsedMicroseconds);
      if (batch % 32 == 31) await session.history.flush();
    }
    await session.history.flush();
    if (session.missedInputPackets != 0 || session.history.truncated) {
      throw StateError('接收批次基准出现缺口');
    }
    samples.sort();
    final timings = _percentiles(samples);
    stdout.writeln('回执前消费 128 条接收记录 P50/P95/P99 $timings µs');
  } finally {
    await runtime.dispose();
    sessions.dispose();
    await root.delete(recursive: true);
  }
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.environment['CLOVECOM_BENCH_SESSION_BURST'] == '1') {
    await _measureSessionBurst();
    return;
  }
  if (Platform.environment['CLOVECOM_BENCH_HEX_SHAPING'] == '1') {
    await _measureHexShaping();
    return;
  }
  final ports = Platform.environment['CLOVECOM_SERIAL_LOOPBACK_PORTS']
      ?.split(',')
      .map((port) => port.trim())
      .toList();
  if (ports == null ||
      ports.length != 2 ||
      ports.toSet().length != 2 ||
      ports.any((port) => port.isEmpty)) {
    throw ArgumentError('请通过 CLOVECOM_SERIAL_LOOPBACK_PORTS 指定一对互连的测试串口');
  }
  final intervalMs = int.parse(
    Platform.environment['CLOVECOM_SERIAL_LOOPBACK_INTERVAL_MS'] ?? '1',
  );
  if (intervalMs <= 0) throw ArgumentError.value(intervalMs, 'intervalMs');
  final baudRate = int.parse(
    Platform.environment['CLOVECOM_BENCH_BAUD'] ?? '115200',
  );
  final payloadBytes = int.parse(
    Platform.environment['CLOVECOM_BENCH_PAYLOAD_BYTES'] ?? '10',
  );
  final variantCount = int.parse(
    Platform.environment['CLOVECOM_BENCH_PAYLOAD_VARIANTS'] ?? '1',
  );
  if (variantCount < 1 ||
      variantCount > 256 ||
      (variantCount > 1 && payloadBytes < 2)) {
    throw ArgumentError('变化负载需至少 2 字节，负载种类须在 1–256 之间');
  }
  if (variantCount > 1 && variantCount * payloadBytes > 16 * 1024 * 1024) {
    throw ArgumentError('每个方向的变化负载总量须不超过 16 MiB');
  }
  final wheelScale = double.parse(
    Platform.environment['CLOVECOM_BENCH_WHEEL_SCALE'] ?? '1',
  );
  final wheelSubsteps = int.parse(
    Platform.environment['CLOVECOM_BENCH_WHEEL_SUBSTEPS'] ?? '1',
  );
  if (wheelSubsteps < 1) {
    throw ArgumentError.value(wheelSubsteps, 'wheelSubsteps');
  }
  final minimumRounds = double.parse(
    Platform.environment['CLOVECOM_BENCH_MIN_ROUNDS_PER_SECOND'] ?? '0',
  );
  final maxPayload = const SendBudget().maxWriteBytes;
  if (baudRate <= 0 || payloadBytes <= 0 || payloadBytes > maxPayload) {
    throw ArgumentError('波特率须为正数，基准负载须在 1–$maxPayload 字节之间');
  }
  if (!wheelScale.isFinite ||
      wheelScale <= 0 ||
      !minimumRounds.isFinite ||
      minimumRounds < 0) {
    throw ArgumentError('滚轮倍率须为正数，最低发送速率须为非负数');
  }
  final phaseSeconds = int.parse(
    Platform.environment['CLOVECOM_SERIAL_LOOPBACK_PHASE_SECONDS'] ?? '6',
  );
  if (phaseSeconds < 4) throw ArgumentError.value(phaseSeconds, 'phaseSeconds');
  final phase = Duration(seconds: phaseSeconds);
  if (Platform.environment['CLOVECOM_BENCH_SERIAL_RECEIPTS'] == '1') {
    await _measureSerialReceipts(
      ports,
      baudRate,
      payloadBytes,
      Duration(milliseconds: intervalMs),
      phase,
    );
    return;
  }
  final expectRotation =
      Platform.environment['CLOVECOM_EXPECT_HISTORY_ROTATION'] == '1';
  final historyBudget = Platform.environment['CLOVECOM_BENCH_HISTORY_BYTES'];
  final historyMaxBytes = historyBudget == null
      ? SessionHistory.defaultMaxBytes
      : int.parse(historyBudget);
  if (historyMaxBytes <= 0) {
    throw ArgumentError.value(historyMaxBytes, 'CLOVECOM_BENCH_HISTORY_BYTES');
  }
  final root = await Directory.systemTemp.createTemp('clovecom-view-bench-');
  final runtime = CommunicationRuntime();
  final sessions = CommunicationSessions(
    runtime: runtime,
    defaults: DisplayConfig.new,
    historyRoot: () async => root,
    historyMaxBytes: historyMaxBytes,
  );
  Timer? payloadChanges;
  try {
    await sessions.ready;
    final views = <OpenCommunicationSession>[];
    for (final port in ports) {
      runtime.addConnection(
        ConnectionDefinition.serial(
          serialConnectionConfig(
            port,
            SerialPortConfig(portName: port, baudRate: baudRate),
          ),
        ),
      );
      await sessions.connect(port, sessions.layout.groups.first);
      if (!runtime.connection(port).connected) {
        throw StateError('$port 打开失败：${runtime.connection(port).detail}');
      }
      final view = sessions[port]!;
      view.display.timestampMillis =
          Platform.environment['CLOVECOM_BENCH_TIMESTAMP_MILLIS'] == '1';
      view.display.wrap = Platform.environment['CLOVECOM_BENCH_NOWRAP'] != '1';
      view.display.hex = Platform.environment['CLOVECOM_BENCH_HEX'] == '1';
      views.add(view);
    }
    final keys = [for (final _ in views) GlobalKey()];
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (final (index, session) in views.indexed)
                Expanded(
                  child: CommunicationSessionDataView(
                    key: keys[index],
                    session: session,
                    saveDisplay: () {},
                    layoutMenu: const [],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await SchedulerBinding.instance.endOfFrame;
    final variants = [
      for (var direction = 0; direction < ports.length; direction++)
        _buildBenchmarkPayloads(payloadBytes, variantCount, direction),
    ];
    stdout.writeln('$baudRate 波特，$intervalMs ms 间隔，每轮 $payloadBytes 字节');
    final interval = Duration(milliseconds: intervalMs);
    for (final (index, port) in ports.indexed) {
      runtime.startLoop(port, variants[index].first, interval: interval);
    }
    if (variantCount > 1) {
      // 更换循环草稿时让原生写入器继续使用既有定时机制。
      final cadence = Duration(milliseconds: max(intervalMs * 4, 20));
      payloadChanges = Timer.periodic(cadence, (timer) {
        final next = timer.tick % variantCount;
        for (final (index, port) in ports.indexed) {
          runtime.updateLoopData(port, variants[index][next]);
        }
      });
      stdout.writeln(
        '固定种子生成 $variantCount 种负载，每 ${cadence.inMilliseconds} ms 更换',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 3));

    Offset scrollOrigin(GlobalKey key) {
      final box = key.currentContext!.findRenderObject()! as RenderBox;
      return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
    }

    void scroll(GlobalKey key, double dy) {
      GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(
          position: scrollOrigin(key),
          scrollDelta: Offset(0, dy),
        ),
      );
    }

    final holdDrag = Platform.environment['CLOVECOM_BENCH_HOLD_DRAG'] == '1';
    final hoverMs = int.parse(
      Platform.environment['CLOVECOM_BENCH_SCROLLBAR_HOVER_MS'] ?? '0',
    );

    Future<int> seekOldest(
      int pointer, {
      bool rapid = false,
      int viewIndex = 0,
      int recordOffset = 0,
      List<int>? samples,
    }) async {
      final oldest = views[viewIndex].history.oldestPublishedSequence!;
      final target = oldest + recordOffset;
      final trackKey = ValueKey(
        'session-history-scrollbar-${views[viewIndex].id}',
      );
      final thumbKey = ValueKey('session-history-thumb-${views[viewIndex].id}');
      RenderBox? track, thumb;
      void findScrollbar(Element element) {
        if (element.widget.key == trackKey) {
          track = element.findRenderObject() as RenderBox?;
        } else if (element.widget.key == thumbKey) {
          thumb = element.findRenderObject() as RenderBox?;
        }
        if (track == null || thumb == null) {
          element.visitChildren(findScrollbar);
        }
      }

      keys[viewIndex].currentContext!.visitChildElements(findScrollbar);
      final box = track;
      final thumbBox = thumb;
      if (box == null || thumbBox == null) {
        throw StateError('没有找到历史滚动条或滑块');
      }
      final height = box.size.height;
      final thumbHeight = thumbBox.size.height;
      final y = recordOffset == 0
          ? 1.0
          : thumbHeight / 2 +
                (height - thumbHeight) *
                    recordOffset /
                    (views[viewIndex].latestSequence! - oldest);
      final point = box.localToGlobal(Offset(box.size.width / 2, y));
      final gesture = GestureBinding.instance;
      final hover = pointer == 1 && hoverMs > 0;
      final hoverPosition = box.localToGlobal(
        Offset(box.size.width / 2, height * .8),
      );
      if (hover) {
        gesture.handlePointerEvent(
          PointerHoverEvent(
            position: hoverPosition,
            device: 10001,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await Future<void>.delayed(Duration(milliseconds: hoverMs));
      }
      final jump = Stopwatch()..start();
      Offset? heldPointer;
      int? moveMicros;
      if (rapid) {
        final x = box.size.width / 2;
        var position = box.localToGlobal(Offset(x, height * .8));
        gesture.handlePointerEvent(
          PointerDownEvent(position: position, pointer: pointer),
        );
        final moves = Stopwatch()..start();
        void moveTo(double y) {
          final next = box.localToGlobal(Offset(x, y));
          gesture.handlePointerEvent(
            PointerMoveEvent(
              pointer: pointer,
              position: next,
              delta: next - position,
            ),
          );
          position = next;
        }

        for (var index = 0; index < 120; index++) {
          moveTo(height * (.1 + (index * 17 % 80) / 100));
        }
        // 从最后一次位移前计时，计入指针事件内同步执行的定位工作。
        jump.reset();
        moveTo(recordOffset == 0 ? -10 : y);
        moves.stop();
        moveMicros = moves.elapsedMicroseconds;
        if (holdDrag) {
          heldPointer = position;
        } else {
          gesture.handlePointerEvent(
            PointerUpEvent(position: position, pointer: pointer),
          );
        }
      } else {
        gesture.handlePointerEvent(
          PointerDownEvent(position: point, pointer: pointer),
        );
        gesture.handlePointerEvent(
          PointerUpEvent(position: point, pointer: pointer),
        );
      }
      while (views[viewIndex].historyAnchor?.sequence != target &&
          jump.elapsed < const Duration(seconds: 4)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      jump.stop();
      final anchor = views[viewIndex].historyAnchor?.sequence;
      if (hover) {
        gesture.handlePointerEvent(
          PointerRemovedEvent(
            position: hoverPosition,
            device: 10001,
            kind: PointerDeviceKind.mouse,
          ),
        );
      }
      if (heldPointer != null) {
        gesture.handlePointerEvent(
          PointerUpEvent(position: heldPointer, pointer: pointer),
        );
      }
      if (anchor != target) {
        Element? firstRow;
        void findFirstRow(Element element) {
          if (element.widget.key == ValueKey((target, 0))) {
            firstRow = element;
          } else if (firstRow == null) {
            element.visitChildren(findFirstRow);
          }
        }

        keys[viewIndex].currentContext!.visitChildElements(findFirstRow);
        final row = firstRow?.findRenderObject();
        final location = row is RenderBox
            ? row.localToGlobal(Offset.zero).dy
            : null;
        throw StateError(
          '没有到达目标 $target，当前锚点 $anchor，当时首条 $oldest，'
          '当前首条 ${views[viewIndex].history.oldestPublishedSequence}，目标行屏幕纵坐标 $location',
        );
      }
      if (samples == null) {
        if (moveMicros != null) {
          stdout.writeln('快速拖动合计 121 次位移，指针处理 $moveMicros µs');
        }
        stdout.writeln('滚动条定位首条 ${jump.elapsedMicroseconds} µs，记录 $anchor');
      } else {
        samples.add(jump.elapsedMicroseconds);
      }
      return oldest;
    }

    final throughput = (
      sentRounds: minimumRounds,
      receivedBytes: minimumRounds * payloadBytes,
    );
    final cpuDirectory = Platform.environment['CLOVECOM_BENCH_CPU_DIRECTORY'];
    final cpuWindows = cpuDirectory == null ? null : <_CpuWindow>[];
    await _measure(
      '实时跟随',
      views,
      runtime,
      phase,
      throughput: throughput,
      cpuWindows: cpuWindows,
    );
    if (Platform.environment['CLOVECOM_BENCH_WARM_OLDEST'] == '1') {
      final history = views.first.history;
      final first = history.oldestPublishedSequence!;
      final timer = Stopwatch()..start();
      final page = await history.readPage(after: first - 1);
      timer.stop();
      if (page.records.firstOrNull?.sequence != first) {
        throw StateError('预读时最早历史已轮换');
      }
      stdout.writeln(
        '历史首段预读 ${timer.elapsedMicroseconds} µs，${page.records.length} 条',
      );
    }
    final oldest = await seekOldest(
      1,
      rapid:
          holdDrag || Platform.environment['CLOVECOM_BENCH_RAPID_SEEK'] == '1',
    );
    if (Platform.environment['CLOVECOM_BENCH_WINDOW_SEEK'] == '1') {
      final samples = <int>[];
      final cpuStart = cpuWindows == null ? null : Timeline.now;
      for (var trial = 0; trial < 48; trial++) {
        await seekOldest(
          100 + trial,
          rapid: holdDrag,
          recordOffset: trial.isEven ? 40 : 10,
          samples: samples,
        );
      }
      if (cpuStart != null) {
        cpuWindows?.add((phase: '窗口内定位', start: cpuStart, end: Timeline.now));
      }
      samples.sort();
      stdout.writeln(
        '窗口内定位 ${samples.length} 次，P50/P95/P99 ${_percentiles(samples)} µs',
      );
      await seekOldest(2);
    }
    final pauseBoth = Platform.environment['CLOVECOM_BENCH_PAUSE_BOTH'] == '1';
    if (pauseBoth) {
      await seekOldest(3, viewIndex: 1);
    }
    await _measure(
      '回看停留',
      views,
      runtime,
      phase,
      minimumFrames: pauseBoth ? 30 : 60,
      throughput: throughput,
      cpuWindows: cpuWindows,
    );
    if (Platform.environment['CLOVECOM_BENCH_SELECT_WORD'] == '1') {
      Element? verticalViewport;
      void findViewport(Element element) {
        if (element.widget is Viewport) {
          verticalViewport = element;
        } else if (verticalViewport == null) {
          element.visitChildren(findViewport);
        }
      }

      keys.first.currentContext!.visitChildElements(findViewport);
      final selection = verticalViewport
          ?.findAncestorWidgetOfExactType<SelectionContainer>()
          ?.delegate;
      if (selection == null) throw StateError('没有找到会话选区');
      final origin = scrollOrigin(keys.first);
      Offset? point;
      for (var shift = 0; shift < 16; shift++) {
        final candidate = origin.translate(shift.toDouble(), 0);
        selection.dispatchSelectionEvent(
          SelectWordSelectionEvent(globalPosition: candidate),
        );
        if (selection.getSelectedContent()?.plainText.length == 2) {
          point = candidate;
          break;
        }
        selection.dispatchSelectionEvent(const ClearSelectionEvent());
      }
      if (point == null) throw StateError('没有选中长 HEX 行的单个字节');
      final selectedPoint = point;
      selection.dispatchSelectionEvent(const ClearSelectionEvent());
      var selectedWords = 0;
      final toggling = Timer.periodic(const Duration(milliseconds: 33), (
        timer,
      ) {
        if (timer.tick.isOdd) {
          selection.dispatchSelectionEvent(
            SelectWordSelectionEvent(globalPosition: selectedPoint),
          );
          if (selection.getSelectedContent()?.plainText.length == 2) {
            selectedWords++;
          }
        } else {
          selection.dispatchSelectionEvent(const ClearSelectionEvent());
        }
      });
      try {
        await _measure(
          '反复选择单个字节',
          views,
          runtime,
          phase,
          throughput: throughput,
          cpuWindows: cpuWindows,
        );
      } finally {
        toggling.cancel();
        selection.dispatchSelectionEvent(const ClearSelectionEvent());
      }
      if (selectedWords < 15) throw StateError('单字节选区样本不足');
      stdout.writeln('成功选择单个字节 $selectedWords 次');
    }
    final sampleLiveLag =
        !pauseBoth &&
        Platform.environment['CLOVECOM_BENCH_LIVE_RENDER_LAG'] == '1';
    final liveLag = <int>[];
    void captureLiveLag() {
      var displayed = 0;
      void inspect(Element element) {
        final key = element.widget.key;
        if (key is ValueKey<(int, int)>) {
          final sequence = key.value.$1;
          if (sequence > displayed) displayed = sequence;
        } else {
          element.visitChildren(inspect);
        }
      }

      keys.last.currentContext!.visitChildElements(inspect);
      final latest = views.last.latestSequence;
      if (displayed > 0 && latest != null && latest >= displayed) {
        liveLag.add(latest - displayed);
      }
    }

    final wheelSamples = <int>[];
    final wheelTimer = Stopwatch();
    final reverseWheel =
        Platform.environment['CLOVECOM_BENCH_REVERSE_WHEEL'] == '1';
    final scrolling = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      wheelTimer
        ..reset()
        ..start();
      // 反复切换方向，同时保留总体向后的位移以跨越多个分页。
      final delta = reverseWheel && timer.tick % 16 < 3 ? -112.0 : 80.0;
      final step = (reverseWheel ? delta : 56.0) * wheelScale / wheelSubsteps;
      for (var index = 0; index < wheelSubsteps; index++) {
        scroll(keys.first, step);
      }
      wheelTimer.stop();
      wheelSamples.add(wheelTimer.elapsedMicroseconds);
      if (sampleLiveLag && timer.tick % 4 == 0) captureLiveLag();
    });
    try {
      final scrollingPhase = _measure(
        '连续回看',
        views,
        runtime,
        phase,
        throughput: throughput,
        cpuWindows: cpuWindows,
      );
      if (Platform.environment['CLOVECOM_BENCH_EXPORT_HISTORY'] == '1') {
        final exportTimer = Stopwatch()..start();
        await Future.wait([
          scrollingPhase,
          for (final (index, view) in views.indexed)
            view
                .exportTo(
                  File(
                    '${root.path}${Platform.pathSeparator}session-$index.jsonl',
                  ),
                )
                .then((_) {
                  stdout.writeln(
                    '${view.id} 收发及回看期间完成导出，耗时 ${exportTimer.elapsedMilliseconds} ms',
                  );
                }),
        ]);
      } else {
        await scrollingPhase;
      }
    } finally {
      scrolling.cancel();
    }
    wheelSamples.sort();
    stdout.writeln(
      '滚轮处理 P50/P95/P99 ${_percentiles(wheelSamples)} µs，'
      '${wheelSamples.length} 组，每组 $wheelSubsteps 次事件',
    );
    if (sampleLiveLag) {
      if (liveLag.length < 10) throw StateError('实时显示落后样本不足');
      liveLag.sort();
      final timings = _percentiles(liveLag);
      final samples = liveLag.length;
      final maximum = liveLag.last;
      stdout.writeln(
        '另一面板实时显示落后 P50/P95/P99 $timings 条，$samples 个样本，最多 $maximum 条',
      );
    }
    final after = views.first.historyAnchor?.sequence ?? 0;
    if (after <= oldest + 300) {
      throw StateError('连续滚动没有跨越历史页，停止于记录 $after');
    }
    stdout.writeln('连续滚动从记录 $oldest 到 $after');
    if (expectRotation && await seekOldest(2) <= oldest) {
      throw StateError('滚动期间磁盘历史未发生轮换');
    }
    // 清空循环草稿并以普通发送排队交接。标记经过最后一笔循环写入，
    // 两端收到标记后才能严格核对发送确认和接收，避免停止时取消在途写。
    payloadChanges?.cancel();
    const markers = [0xa5, 0x5a];
    final beforeDrain = [for (final view in views) view.sentBytes];
    final receiverPause = int.parse(
      Platform.environment['CLOVECOM_BENCH_RX_PAUSE_MS'] ?? '0',
    );
    if (receiverPause > 0) sleep(Duration(milliseconds: receiverPause));
    for (final port in ports) {
      runtime.updateLoopData(port, Uint8List(0));
    }
    final markersSent = await Future.wait([
      for (final (index, port) in ports.indexed)
        runtime.writeTo(port, Uint8List.fromList([markers[index]])),
    ]);
    for (final (index, result) in markersSent.indexed) {
      if (!result.succeeded || result.acceptedBytes != 1) {
        throw StateError('${ports[index]} 结束标记未确认写入');
      }
      await result.settled;
      runtime.stopLoop(ports[index]);
    }
    final settlement = Stopwatch()..start();
    while (ports.any(
          (port) => runtime.loopFor(port)?.awaitingSettlement == true,
        ) ||
        sessions.pendingInputBytes != 0 ||
        views[0].receivedBytes < views[1].sentBytes ||
        views[1].receivedBytes < views[0].sentBytes) {
      if (settlement.elapsed > const Duration(seconds: 6)) {
        throw StateError(
          '等待收发排空超时，${views[0].id} 发送/接收 '
          '${views[0].sentBytes}/${views[0].receivedBytes}，${views[1].id} '
          '发送/接收 ${views[1].sentBytes}/${views[1].receivedBytes}，'
          '待处理 ${sessions.pendingInputBytes} 字节，'
          '驱动溢出 ${views[0].serialReceiveOverruns}/${views[1].serialReceiveOverruns}，'
          '会话队列丢包 ${views[0].missedInputPackets}/${views[1].missedInputPackets}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    stdout.writeln(
      '结束标记确认后排空 ${settlement.elapsedMilliseconds} ms，'
      '测量结束后确认 ${views[0].sentBytes - beforeDrain[0]}/'
      '${views[1].sentBytes - beforeDrain[1]} 字节（含结束标记）',
    );
    for (final session in views) {
      await session.history.flush();
    }
    for (final (index, session) in views.indexed) {
      if ((!expectRotation && session.history.truncated) ||
          session.serialReceiveOverruns != 0 ||
          session.history.error != null ||
          session.missedInputPackets != 0) {
        throw StateError('${session.id} 历史未完整保存：${session.history.error}');
      }
      final peer = views[1 - index];
      final delta = session.sentBytes - peer.receivedBytes;
      if (delta != 0) {
        throw StateError('${session.id} 的确认发送和对端接收相差 $delta 字节');
      }
      if (variantCount == 1) {
        await _verifyHistoryPayload(
          session,
          variants[index].first,
          markers[index],
          markers[1 - index],
          rotated: expectRotation,
        );
      } else {
        await _verifyVariantHistory(
          session,
          peer,
          variants[index],
          markers[index],
          rotated: expectRotation,
        );
      }
      final entries = (await session.history.readPage(limit: 3000)).records;
      final sent = [
        for (final row in entries)
          if (row.sent && row.packet?.bytes.length == payloadBytes)
            row.packet!.receivedAt,
      ];
      final intervals = [
        for (var i = 1; i < sent.length; i++)
          sent[i].difference(sent[i - 1]).inMicroseconds,
      ]..sort();
      stdout.writeln(
        '${session.id} 发送确认间隔 P50/P95/P99 ${_percentiles(intervals)} µs，'
        '累计确认 ${session.sentBytes} 字节，与对端接收相差 $delta 字节',
      );
    }
    if (Platform.environment['CLOVECOM_REQUIRE_NATIVE_SERIAL_LOOP'] == '1') {
      await _probeNativeHandoff(
        runtime,
        views.first,
        Duration(milliseconds: intervalMs),
        draftLength: payloadBytes,
      );
    }
    // 只记录采样时间窗，等收发和计时核验结束再请求并写出样本。
    if (cpuDirectory != null && cpuWindows != null) {
      final cpuPhase = Platform.environment['CLOVECOM_BENCH_CPU_PHASE'];
      for (final window in cpuWindows) {
        if (cpuPhase == null || cpuPhase == window.phase) {
          await _writeCpuSamples(cpuDirectory, window);
        }
      }
    }
  } finally {
    payloadChanges?.cancel();
    runApp(const SizedBox());
    await SchedulerBinding.instance.endOfFrame;
    await runtime.dispose();
    // 离开的视图可能仍有一页正在读，等待读句柄释放。
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        await root.delete(recursive: true);
        break;
      } on FileSystemException {
        if (!await root.exists()) break;
        if (attempt == 19) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }
}

List<Uint8List> _buildBenchmarkPayloads(int length, int count, int direction) {
  final random = Random(0x434c4f56 + direction);
  return List.generate(count, (index) {
    final bytes = Uint8List(length);
    if (count == 1) {
      for (var offset = 0; offset < length; offset++) {
        bytes[offset] = 0x30 + offset % 10;
      }
      return bytes;
    }
    bytes[0] = index;
    bytes[1] = direction;
    for (var offset = 2; offset < length; offset++) {
      bytes[offset] = random.nextInt(256);
    }
    return bytes;
  });
}

Stream<SessionRecord> _historyBackward(
  OpenCommunicationSession session, {
  required bool rotated,
}) async* {
  final history = session.history;
  final first = history.oldestPublishedSequence;
  final last = history.publishedSequence;
  if (first == null || last != session.latestSequence) {
    throw StateError('${session.id} 历史首尾与实时记录不一致');
  }
  if (rotated ? first <= 1 || !history.truncated : first != 1) {
    throw StateError('${session.id} 历史轮换状态不符合预期，首条 $first');
  }
  var expected = last;
  while (expected >= first) {
    final page = await history.readPage(before: expected + 1, limit: 4096);
    if (page.records.isEmpty) {
      throw StateError('${session.id} 历史分页没有推进到记录 $expected');
    }
    for (final row in page.records.reversed) {
      if (row.sequence != expected-- || row.packet == null) {
        throw StateError('${session.id} 历史记录 ${row.sequence} 存在缺口');
      }
      yield row;
    }
  }
}

Future<void> _verifyVariantHistory(
  OpenCommunicationSession sender,
  OpenCommunicationSession receiver,
  List<Uint8List> variants,
  int marker, {
  required bool rotated,
}) async {
  var receiveRemaining = receiver.receivedBytes;
  final incoming = StreamIterator(
    _historyBackward(
      receiver,
      rotated: rotated,
    ).where((record) => !record.sent).map((record) {
      final bytes = record.packet!.bytes;
      receiveRemaining -= bytes.length;
      return bytes;
    }),
  );
  final seen = <int>{};
  var remaining = sender.sentBytes;
  var compared = 0;
  List<int> bytes = const [];
  var end = 0;
  var hasIncoming = true;
  try {
    await for (final record in _historyBackward(sender, rotated: rotated)) {
      if (!record.sent) continue;
      final confirmed = record.packet!.bytes;
      if (remaining == sender.sentBytes) {
        if (confirmed.length != 1 || confirmed.single != marker) {
          throw StateError('${sender.id} 历史缺少结束标记');
        }
      } else {
        if (confirmed.length != variants.first.length ||
            confirmed.first >= variants.length ||
            !listEquals(confirmed, variants[confirmed.first])) {
          throw StateError('${sender.id} 历史记录 ${record.sequence} 与生成的负载不一致');
        }
        seen.add(confirmed.first);
      }
      remaining -= confirmed.length;
      for (var offset = confirmed.length; offset > 0 && hasIncoming;) {
        if (end == 0) {
          hasIncoming = await incoming.moveNext();
          if (!hasIncoming) break;
          bytes = incoming.current;
          end = bytes.length;
        }
        final count = min(offset, end);
        for (var index = 1; index <= count; index++) {
          if (confirmed[offset - index] != bytes[end - index]) {
            throw StateError(
              '${sender.id} 到 ${receiver.id} 字节 ${remaining + offset - index} 不一致',
            );
          }
        }
        offset -= count;
        end -= count;
        compared += count;
      }
    }
    if (remaining < 0 ||
        seen.length < 2 ||
        compared < 1 + variants.first.length * 2 ||
        (!rotated && (remaining != 0 || compared != sender.sentBytes))) {
      throw StateError('${sender.id} 到 ${receiver.id} 的变化负载核验未覆盖预期历史');
    }
    // 轮换时两端可能保留不同数量的字节，仍遍历较长一侧以检查记录连续性。
    if (hasIncoming) {
      while (await incoming.moveNext()) {}
    }
    if (receiveRemaining < 0 || (!rotated && receiveRemaining != 0)) {
      throw StateError('${receiver.id} 落盘接收量与实时统计不一致');
    }
  } finally {
    await incoming.cancel();
  }
  stdout.writeln(
    '${sender.id} 到 ${receiver.id} 逐字节核验 $compared 字节，'
    '尾部包含 ${seen.length} 种发送负载',
  );
}

Future<void> _verifyHistoryPayload(
  OpenCommunicationSession session,
  Uint8List payload,
  int sentMarker,
  int receivedMarker, {
  required bool rotated,
}) async {
  final history = session.history;
  // 从已知的收发字节总量向前回查，首个保留的接收包可从周期中间开始。
  final totalSent = session.sentBytes, totalReceived = session.receivedBytes;
  var sent = totalSent, received = totalReceived;
  await for (final row in _historyBackward(session, rotated: rotated)) {
    final marker = row.sent ? sentMarker : receivedMarker;
    final payloadBytes = (row.sent ? totalSent : totalReceived) - 1;
    final bytes = row.packet!.bytes;
    var offset = row.sent ? sent : received;
    for (var index = bytes.length - 1; index >= 0; index--) {
      offset--;
      if (offset < 0 ||
          bytes[index] !=
              (offset == payloadBytes
                  ? marker
                  : payload[offset % payload.length])) {
        throw StateError(
          '${session.id} ${row.sent ? '发送' : '接收'}字节 $offset 内容不一致',
        );
      }
    }
    if (row.sent) {
      sent = offset;
    } else {
      received = offset;
    }
  }
  if (sent == totalSent ||
      received == totalReceived ||
      (!rotated && (sent != 0 || received != 0))) {
    throw StateError('${session.id} 落盘字节数量与实时统计不一致');
  }
  stdout.writeln(
    '${session.id} 逐字节核验连续记录 ${history.oldestPublishedSequence}–${history.publishedSequence}，'
    '落盘发送 ${totalSent - sent}、接收 ${totalReceived - received} 字节',
  );
}

Future<void> _probeNativeHandoff(
  CommunicationRuntime runtime,
  OpenCommunicationSession session,
  Duration interval, {
  required int draftLength,
}) async {
  final id = session.id;
  final first = Uint8List(draftLength)..fillRange(0, draftLength, 0x78);
  final changed = Uint8List(draftLength)..fillRange(0, draftLength, 0x79);
  final manual = Uint8List.fromList([0x7a]);
  bool matches(SessionRecord row, Uint8List draft) {
    final bytes = row.packet?.bytes;
    return row.sent &&
        bytes != null &&
        bytes.length == draft.length &&
        bytes.every((byte) => byte == draft.first);
  }

  Future<void> waitFor(bool Function() condition) async {
    final elapsed = Stopwatch()..start();
    while (!condition()) {
      if (elapsed.elapsed > const Duration(seconds: 4)) {
        throw StateError('$id 未继续提交原生回执');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  runtime.startLoop(id, first, interval: interval);
  var baseline = session.sentPackets;
  await waitFor(
    () =>
        session.sentPackets > baseline + 8 &&
        runtime.loopFor(id)?.workerTiming?.usesNativeWriter == true,
  );
  final initialPayloads = [
    for (final row in session.latest)
      if (matches(row, first)) row.packet!.bytes,
  ];
  if (initialPayloads.isEmpty) throw StateError('$id 原生回执未保留初始草稿');
  if (interval == const Duration(milliseconds: 1) &&
      !initialPayloads.indexed.any(
        (entry) =>
            entry.$1 > 0 && identical(entry.$2, initialPayloads[entry.$1 - 1]),
      )) {
    throw StateError('$id 的批量原生回执未复用 TX 负载');
  }
  if (interval == const Duration(milliseconds: 1)) {
    // 暂停消费超过原生环的容量，验证满队列释放后能恢复且不追补过期轮次。
    baseline = session.sentPackets;
    final before = runtime.loopFor(id)!.workerTiming!.timerSkipped;
    sleep(const Duration(milliseconds: 230));
    await waitFor(() {
      final timing = runtime.loopFor(id)?.workerTiming;
      return session.sentPackets > baseline + 150 &&
          timing != null &&
          timing.timerSkipped > before + 20;
    });
    stdout.writeln('$id 回执环满载后恢复发送，通过背压回归');
  } else {
    final pausedAt = DateTime.now();
    sleep(const Duration(milliseconds: 240));
    final resumedAt = DateTime.now();
    bool confirmedDuringPause(SessionRecord row) {
      final timestamp = row.packet?.receivedAt;
      return timestamp != null &&
          timestamp.isAfter(pausedAt) &&
          timestamp.isBefore(resumedAt) &&
          matches(row, first);
    }

    await waitFor(
      () => session.latest.where(confirmedDuringPause).take(8).length == 8,
    );
    stdout.writeln('$id 界面 isolate 暂停期间仍确认至少 8 轮原生发送');
  }

  runtime.updateLoopData(id, Uint8List(0));
  await Future<void>.delayed(const Duration(milliseconds: 80));
  baseline = session.sentPackets;
  await Future<void>.delayed(const Duration(milliseconds: 80));
  if (session.sentPackets != baseline) throw StateError('$id 空草稿时仍在发送');

  runtime.updateLoopData(id, changed);
  await waitFor(() => session.sentPackets > baseline + 8);
  final result = await runtime.writeTo(id, manual);
  if (!result.succeeded || result.acceptedBytes != 1) {
    throw StateError('$id 手动写入未接过循环的发送权');
  }
  baseline = session.sentPackets;
  await waitFor(() => session.sentPackets > baseline + 8);
  await session.history.flush();
  final records = (await session.history.readPage(limit: 128)).records;
  int lastSent(Uint8List draft, {int before = 1 << 32}) => records
      .lastIndexWhere((row) => row.sequence < before && matches(row, draft));
  final manualIndex = lastSent(manual);
  final changedIndex = lastSent(changed);
  if (manualIndex < 0 ||
      changedIndex <= manualIndex ||
      lastSent(changed, before: records[manualIndex].sequence) < 0) {
    throw StateError('$id 的手动写入与循环恢复顺序错误');
  }

  await runtime.closeConnection(id).timeout(const Duration(seconds: 6));
  if (runtime.connection(id).connected) throw StateError('$id 关闭后仍保持连接');
  stdout.writeln('$id 原生循环空草稿、更新、手动发送交接和在途关闭均通过');
}

Future<void> _measure(
  String name,
  List<OpenCommunicationSession> views,
  CommunicationRuntime runtime,
  Duration duration, {
  int minimumFrames = 60,
  required ({double sentRounds, double receivedBytes}) throughput,
  required List<_CpuWindow>? cpuWindows,
}) async {
  final frames = <FrameTiming>[];
  final binding = SchedulerBinding.instance;
  final baseline = [
    for (final session in views)
      (
        session.sentPackets,
        session.receivedBytes,
        runtime.loopFor(session.id)?.workerTiming,
      ),
  ];
  final cpuStart = cpuWindows == null ? null : Timeline.now;
  final elapsed = Stopwatch()..start();
  binding.addTimingsCallback(frames.addAll);
  try {
    await Future<void>.delayed(duration);
  } finally {
    elapsed.stop();
    if (cpuStart != null) {
      cpuWindows?.add((phase: name, start: cpuStart, end: Timeline.now));
    }
    binding.removeTimingsCallback(frames.addAll);
  }
  if (frames.length < minimumFrames) throw StateError('$name 的帧样本不足');
  String timing(Duration Function(FrameTiming) metric) {
    final durations =
        frames.map((frame) => metric(frame).inMicroseconds).toList()..sort();
    return '${_percentiles(durations)} µs';
  }

  const budget = Duration(microseconds: 16667);
  final slowBuild = frames
      .where((frame) => frame.buildDuration > budget)
      .length;
  final slowRaster = frames
      .where((frame) => frame.rasterDuration > budget)
      .length;
  final slowFrames = frames
      .where(
        (frame) =>
            frame.buildDuration > budget || frame.rasterDuration > budget,
      )
      .length;
  final worstBuild = frames
      .map((frame) => frame.buildDuration.inMicroseconds)
      .reduce((a, b) => a > b ? a : b);
  final worstRaster = frames
      .map((frame) => frame.rasterDuration.inMicroseconds)
      .reduce((a, b) => a > b ? a : b);
  stdout.writeln(
    '$name ${frames.length} 帧，构建 P50/P95/P99 ${timing((frame) => frame.buildDuration)}，'
    '光栅化 ${timing((frame) => frame.rasterDuration)}，'
    '超过 16.67 ms 的帧 $slowFrames（构建 $slowBuild，光栅化 $slowRaster），'
    '最长构建/光栅化 $worstBuild/$worstRaster µs',
  );

  final overLatencyBudget = frames
      .where((frame) => frame.totalSpan > budget)
      .length;
  stdout.writeln(
    '$name 垂直同步至光栅化完成 P50/P95/P99 '
    '${timing((frame) => frame.totalSpan)}，超过 16.67 ms 的帧 $overLatencyBudget，'
    '垂直同步至开始构建 P50/P95/P99 ${timing((frame) => frame.vsyncOverhead)}',
  );
  final seconds = elapsed.elapsedMicroseconds / Duration.microsecondsPerSecond;
  for (final (index, session) in views.indexed) {
    if (!runtime.connection(session.id).connected) {
      throw StateError(
        '${session.id} 在测试期间断开：${runtime.connection(session.id).detail}',
      );
    }
    final sent = (session.sentPackets - baseline[index].$1) / seconds;
    final received = (session.receivedBytes - baseline[index].$2) / seconds;
    stdout.writeln(
      '${session.id}：${sent.toStringAsFixed(2)} 轮/秒，'
      '接收 ${received.toStringAsFixed(2)} 字节/秒',
    );
    if (sent < throughput.sentRounds || received < throughput.receivedBytes) {
      throw StateError('$name 中 ${session.id} 未达到设定的最低收发速率');
    }
    final before = baseline[index].$3;
    final after = runtime.loopFor(session.id)?.workerTiming;
    if (Platform.environment['CLOVECOM_REQUIRE_NATIVE_SERIAL_LOOP'] == '1' &&
        after?.usesNativeWriter != true) {
      throw StateError('${session.id} 未进入原生写入线程');
    }
    if (before != null && after != null) {
      stdout.writeln(
        '  ${after.usesNativeWriter ? '原生写入' : 'Dart 回调'}开始前跳过 ${after.timerSkipped - before.timerSkipped} 拍，'
        '查询原生终态时跳过 ${after.completionPollSkipped - before.completionPollSkipped} 拍，'
        '重新设定前跳过 ${after.rearmSkipped - before.rearmSkipped} 拍',
      );
    }
  }
}

Future<void> _writeCpuSamples(String directory, _CpuWindow window) async {
  final (:phase, :start, :end) = window;
  final server = (await Service.getInfo()).serverUri;
  final isolateId = Service.getIsolateId(Isolate.current);
  if (server == null || isolateId == null) {
    throw StateError('CPU 采样需要在已启用 Dart VM Service 的 Profile 模式运行');
  }
  final uri = server
      .resolve('getCpuSamples')
      .replace(
        queryParameters: {
          'isolateId': isolateId,
          'timeOriginMicros': '$start',
          'timeExtentMicros': '${end - start}',
        },
      );
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final response = await (await client.getUrl(uri)).close();
    final body = await response.transform(utf8.decoder).join();
    final rpc = jsonDecode(body) as Map<String, Object?>;
    final result = rpc['result'];
    if (response.statusCode != HttpStatus.ok ||
        result is! Map<String, Object?> ||
        result['type'] != 'CpuSamples' ||
        (result['sampleCount'] as int) == 0) {
      throw StateError('$phase 未采到 CPU 样本');
    }
    final folder = await Directory(directory).create(recursive: true);
    final file = File.fromUri(folder.absolute.uri.resolve('$phase.json'));
    await file.writeAsString(body);
    stdout.writeln('$phase CPU 样本 ${result['sampleCount']} 个');
  } finally {
    client.close(force: true);
  }
}

String _percentiles(List<int> sorted) {
  int percentile(double fraction) =>
      sorted[(sorted.length * fraction).ceil() - 1];
  return '${percentile(.50)}/${percentile(.95)}/${percentile(.99)}';
}
