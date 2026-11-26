import 'dart:convert';
import 'dart:io';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_sessions.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/interface_params.dart';
import 'package:clovecom/ui/desktop_theme.dart';
import 'package:clovecom/ui/theme/app_theme_controller.dart';
import 'package:clovecom/views/serial_port/serial_port_view.dart';
import 'package:clovecom/widgets/communication_session_data_view.dart';
import 'package:clovecom/widgets/desktop_title_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show
        ClearSelectionEvent,
        RenderParagraph,
        SelectionHandler,
        SelectParagraphSelectionEvent,
        SelectWordSelectionEvent;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'src/application/communication_runtime_test.dart' show eventually;
import 'support/communication_transports.dart' show add, RecordingTransport;
import 'support/session_list_actions.dart';

Future<void> _mount(WidgetTester tester, CommunicationRuntime runtime) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.runAsync(runtime.dispose));
  await tester.pumpWidget(
    ChangeNotifierProvider<CommunicationRuntime>.value(
      value: runtime,
      child: const MaterialApp(home: Scaffold(body: SerialPortView())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeHistoryFixture(
  WidgetTester tester,
  CommunicationRuntime runtime,
  CommunicationSessions sessions,
  Directory root,
) async {
  // 部分清理回调在测试的虚拟时钟中，文件删除仍需真实 I/O。
  var cleaned = false;
  final cleanup = runtime.dispose().then((_) async {
    sessions.dispose();
    await root.delete(recursive: true);
    cleaned = true;
  });
  for (var retry = 0; retry < 80 && !cleaned; retry++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(cleaned, isTrue);
  await cleanup;
}

Future<void> _openDataMenu(WidgetTester tester, Finder dataView) async {
  final bounds = tester.getRect(dataView);
  await tester.tapAt(
    Offset(bounds.right - bounds.width * 0.25, bounds.center.dy),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Finder _input(String id) => find.byKey(ValueKey('session-send-input-$id'));
Finder _send(String id) => find.byKey(ValueKey('session-send-$id'));
Finder _tab(String id) => find.byKey(ValueKey('session-tab-$id'));
Finder _tabLabel(String id) => find.byKey(ValueKey('session-tab-label-$id'));
Finder _close(String id) => find.byKey(ValueKey('session-close-$id'));

void main() {
  testWidgets('双击打开会话，可直接收发并从会话断开', (tester) async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    add(runtime, 'b');
    await _mount(tester, runtime);
    expect(find.byTooltip('通信管理'), findsNothing);
    await openSessionFromList(tester, 'a');
    expect(_tab('a'), findsOneWidget);
    expect(runtime.connection('a').connected, isTrue);
    final theme = Theme.of(tester.element(_tab('a')));
    final label = tester.widget<Icon>(_tabLabel('a'));
    expect(label.icon, Icons.square);
    expect(
      tester.widget<Text>(_tab('a')).style!.color,
      theme.colorScheme.onSurface,
    );
    expect(find.byTooltip('已连接'), findsOneWidget);
    expect(find.text('已连接'), findsNothing);

    final toolbar = tester.getRect(
      find.byKey(const ValueKey('session-toolbar-a')),
    );
    final button = tester.getRect(find.byKey(const ValueKey('session-link-a')));
    final statistics = find.byKey(const ValueKey('session-statistics-a'));
    final counters = tester.getRect(statistics);
    expect(button.left, toolbar.left);
    expect(toolbar.right - counters.right, closeTo(8, 1));
    expect(button.center.dy, counters.center.dy);
    expect(tester.getRect(_tabLabel('a')).left - toolbar.left, closeTo(8, 1));
    transport.input.add(TransportInput([0x41, 0x42]));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Text>(statistics).data, 'RX 2 B · TX 0 B');
    await tester.enterText(_input('a'), 'CD');
    await tester.tap(_send('a'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Text>(statistics).data, 'RX 2 B · TX 2 B');
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      final receive = find.semantics.byLabel(
        RegExp(r"\[\d\d:\d\d:\d\d\] 1 RX\nAB"),
      );
      final send = find.semantics.byLabel(
        RegExp(r"\[\d\d:\d\d:\d\d\] 2 TX\nCD"),
      );
      expect(receive, findsOne);
      expect(send, findsOne);
      expect(receive.evaluate().single.id, isNot(send.evaluate().single.id));
    } finally {
      semantics.dispose();
    }

    expect(runtime.connection('b').completelyClosed, isTrue);
    expect(tester.widget<IconButton>(_send('a')).onPressed, isNotNull);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('session-link-a')));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(runtime.connection('a').completelyClosed, isTrue);
    expect(_tab('a'), findsOneWidget);
    expect(tester.widget<Icon>(_tabLabel('a')).color, label.color);
    expect(
      tester.widget<Text>(_tab('a')).style!.color,
      theme.colorScheme.error,
    );
    expect(tester.widget<IconButton>(_send('a')).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('真实 TCP 持续接收后可跳到保留历史首条并返回实时尾部', (tester) async {
    late Socket peer;
    final session = (await tester.runAsync(() async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = server.first;
      final root = await Directory.systemTemp.createTemp('tcp-view-history-');
      final runtime = CommunicationRuntime();
      final sessions = CommunicationSessions(
        runtime: runtime,
        defaults: DisplayConfig.new,
        historyRoot: () async => root,
        historyMaxBytes: 3 * 1024 * 1024,
      );
      addTearDown(
        () => tester.runAsync(() async {
          await runtime.dispose();
          sessions.dispose();
          peer.destroy();
          await server.close();
          await root.delete(recursive: true);
        }),
      );
      await sessions.ready;
      runtime.addConnection(
        ConnectionDefinition.network(
          id: 'tcp',
          name: 'TCP',
          protocol: InterfaceProtocol.tcpClient,
          tcpClient: TcpClientPrefs(
            remoteHost: '127.0.0.1',
            remotePort: server.port,
          ),
        ),
      );
      await sessions.connect('tcp', sessions.layout.groups.first);
      peer = await accepted;
      return sessions['tcp']!;
    }))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunicationSessionDataView(
            session: session,
            saveDisplay: () {},
            layoutMenu: const [],
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final payload = List<int>.filled(64 * 1024, 65);
      for (var burst = 1; burst <= 64; burst++) {
        peer.add(payload);
        await peer.flush();
        await eventually(() => session.receivedBytes == burst * payload.length);
      }
      peer.write('TCP tail');
      await peer.flush();
      await eventually(() => session.receivedBytes == 64 * payload.length + 8);
      await session.history.flush();
    });
    expect(session.latest.last.packet!.bytes, utf8.encode('TCP tail'));
    final tail = find.textContaining('TCP tail');
    for (var attempt = 0; attempt < 20 && tail.evaluate().isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    final list = find.byKey(const PageStorageKey('data-tcp'));
    final position = tester.widget<CustomScrollView>(list).controller!.position;
    expect(
      tail,
      findsOneWidget,
      reason:
          '位置 ${position.pixels} / ${position.maxScrollExtent}，最小 ${position.minScrollExtent}，锚点 ${session.historyAnchor}，挂载文本 ${find.byType(Text).evaluate().length}',
    );
    expect(session.missedInputPackets, 0);
    final oldest = session.history.oldestPublishedSequence!;
    expect(oldest, greaterThan(1));
    expect(session.firstLatestSequence, greaterThan(oldest));
    final scrollbar = find.byKey(
      const ValueKey('session-history-scrollbar-tcp'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(scrollbar));
    await tester.pump();
    expect(session.historyAnchor, isNull);
    expect(tail, findsOneWidget);
    await mouse.removePointer();

    await tester.tapAt(
      tester.getRect(scrollbar).topCenter + const Offset(0, 1),
    );
    for (
      var attempt = 0;
      attempt < 100 && session.historyAnchor?.sequence != oldest;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(session.historyAnchor?.sequence, oldest);
    await tester.tap(find.text('回到最新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TCP tail'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('滚轮和滚动条可以一次到达整段通信历史的边界', (tester) async {
    late final RecordingTransport transport;
    late final CommunicationRuntime runtime;
    late final CommunicationSessions sessions;
    late final Directory root;
    final session = (await tester.runAsync(() async {
      transport = RecordingTransport()..finish();
      runtime = CommunicationRuntime(transportFactory: (_) async => transport);
      root = await Directory.systemTemp.createTemp('continuous-history-');
      sessions = CommunicationSessions(
        runtime: runtime,
        defaults: DisplayConfig.new,
        historyRoot: () async => root,
      );
      await sessions.ready;
      add(runtime, 'a');
      await sessions.connect('a', sessions.layout.groups.first);
      final session = sessions['a']!;
      for (var index = 1; index <= 750; index++) {
        final message = index == 3 ? '记录 3\n续行\n续行' : '记录 $index';
        transport.input.add(TransportInput(utf8.encode(message)));
      }
      await eventually(() => session.receivedPackets == 750);
      await session.history.flush();
      return session;
    }))!;
    var menuBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunicationSessionDataView(
            session: session,
            saveDisplay: () {},
            layoutMenu: const [],
            sendSettings: (_) {
              menuBuilds++;
              return const [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const PageStorageKey('data-a'));
    final controller = tester.widget<CustomScrollView>(list).controller!;
    expect(find.text('记录 750'), findsOneWidget);
    expect(session.latest.first.sequence, 351);
    Future<void> untilVisible(String text) async {
      final finder = find.text(text);
      bool visible() =>
          finder.evaluate().isNotEmpty &&
          tester.getRect(list).overlaps(tester.getRect(finder));
      for (var retry = 0; retry < 100 && !visible(); retry++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        visible(),
        isTrue,
        reason:
            '$text 未进入视口，位置 ${controller.offset}，'
            '范围 ${controller.position.minScrollExtent}..${controller.position.maxScrollExtent}，'
            '锚点 ${session.historyAnchor}',
      );
    }

    // 滚动条定位到未挂载的实时记录，首帧布局完成即可确认锚点。
    final beforeSeekBuilds = menuBuilds;
    final directTarget = session.latest.first.sequence + 60;
    expect(find.text('记录 $directTarget'), findsNothing);
    final directTrack = tester.getRect(
      find.byKey(const ValueKey('session-history-scrollbar-a')),
    );
    final directThumb = tester.getSize(
      find.byKey(const ValueKey('session-history-thumb-a')),
    );
    final first = session.history.oldestPublishedSequence!;
    final last = session.latestSequence!;
    final directDy =
        directThumb.height / 2 +
        (directTrack.height - directThumb.height) *
            (directTarget - first) /
            (last - first);
    await tester.tapAt(
      Offset(directTrack.center.dx, directTrack.top + directDy),
    );
    await tester.pump();
    expect(session.historyAnchor?.sequence, directTarget);
    expect(menuBuilds, beforeSeekBuilds, reason: '滚动条定位无需重建右键菜单');
    expect(find.text('记录 $directTarget'), findsOneWidget);

    // 按住滑块时，近处的定位也应在第一帧显示。
    final dragTarget = directTarget + 140;
    final dragDy =
        directThumb.height / 2 +
        (directTrack.height - directThumb.height) *
            (dragTarget - first) /
            (last - first);
    final heldDrag = await tester.startGesture(
      Offset(directTrack.center.dx, directTrack.top + directTrack.height * 0.9),
    );
    await heldDrag.moveTo(
      Offset(directTrack.center.dx, directTrack.top + dragDy),
    );
    await tester.pump();
    expect(session.historyAnchor?.sequence, dragTarget);
    expect(find.text('记录 $dragTarget'), findsOneWidget);
    await heldDrag.up();

    await tester.tap(find.text('回到最新'));
    await tester.pumpAndSettle();

    // 向视口上方持续拖选时，外层滚动器仍可自动向历史移动。
    final visibleRow = find.text('记录 744');
    final start = tester.getTopLeft(visibleRow) + const Offset(4, 6);
    final selectionDrag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await selectionDrag.moveBy(const Offset(50, 0));
    await tester.pump();
    final viewBounds = tester.getRect(list);
    final firstVisible = Iterable.generate(750, (index) => index + 1)
        .firstWhere((sequence) {
          final record = find.text('记录 $sequence');
          return record.evaluate().isNotEmpty &&
              viewBounds.overlaps(tester.getRect(record));
        });
    await selectionDrag.moveTo(Offset(start.dx + 50, viewBounds.top - 100));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(session.historyAnchor?.sequence, lessThan(firstVisible));
    await selectionDrag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到最新'));
    await tester.pumpAndSettle();
    await untilVisible('记录 744');

    // 转入回看时，仍在视口中的行保留原来的文本组件。
    final liveRow = find.text('记录 744');
    final liveElement = tester.element(liveRow);
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -12),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('回到最新'), findsOneWidget);
    expect(tester.element(liveRow), same(liveElement));

    // 一个大滚轮增量跨过所有未载入的历史页。
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -100000),
      ),
    );
    await untilVisible('记录 1');
    for (final delta in [55.0, 30.0, -20.0]) {
      controller.jumpTo(controller.offset + delta);
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(list).dy;
      int? firstVisible;
      for (var sequence = 1; sequence <= 18; sequence++) {
        final row = find.text(sequence == 3 ? '记录 3\n续行\n续行' : '记录 $sequence');
        if (row.evaluate().isNotEmpty &&
            tester.getBottomLeft(row).dy + 1 > top) {
          firstVisible = sequence;
          break;
        }
      }
      expect(firstVisible, isNotNull);
      expect(session.historyAnchor?.sequence, firstVisible);
    }
    // 首条滚轮立即推进，后续同向位移在本帧合并。
    final wheelStart = controller.offset;
    var wheelUpdates = 0;
    void countWheelUpdate() => wheelUpdates++;
    controller.addListener(countWheelUpdate);
    try {
      final position = tester.getCenter(list);
      for (var sample = 0; sample < 4; sample++) {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, 8),
          ),
        );
      }
      expect(controller.offset, closeTo(wheelStart + 8, 0.01));
      await tester.pump();
      expect(controller.offset, closeTo(wheelStart + 32, 0.01));
      expect(wheelUpdates, 2);
    } finally {
      controller.removeListener(countWheelUpdate);
    }

    // 同一帧转向时保留两段位移，新滚动条定位会接管尚未提交的滚轮动作。
    for (final dy in [32.0, 32.0, -24.0, -8.0]) {
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: tester.getCenter(list),
          scrollDelta: Offset(0, dy),
        ),
      );
    }
    await tester.pump();
    expect(controller.offset, closeTo(wheelStart + 64, 0.01));
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 24),
      ),
    );

    final historyTrack = find.byKey(
      const ValueKey('session-history-scrollbar-a'),
    );
    await tester.tapAt(
      tester.getRect(historyTrack).topCenter + const Offset(0, 1),
    );
    await untilVisible('记录 1');
    await tester.pumpAndSettle();
    expect(session.historyAnchor?.sequence, 1);
    final anchor = find.text('记录 1');
    final anchorTop = tester.getTopLeft(anchor).dy;
    await tester.runAsync(() async {
      for (var index = 751; index <= 1200; index++) {
        transport.input.add(TransportInput(utf8.encode('记录 $index')));
      }
      await eventually(() => session.receivedPackets == 1200);
      await session.history.flush();
    });
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor).dy, closeTo(anchorTop, 1));
    expect(find.text('记录 1200'), findsNothing);
    expect(find.text('回到最新'), findsOneWidget);
    final statistics = find.byKey(const ValueKey('session-statistics-a'));
    final updatedBytes = 'RX ${session.receivedBytes} B · TX 0 B';
    for (var retry = 0; retry < 12; retry++) {
      if (tester.widget<Text>(statistics).data == updatedBytes) break;
      // 工作区计时器由真实收发启动，视图自己的刷新计时器由测试帧推进。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.widget<Text>(statistics).data, updatedBytes);
    expect(tester.getTopLeft(anchor).dy, closeTo(anchorTop, 1));

    // 750 和实时缓冲首条之间的记录只能从磁盘顺序补齐。
    expect(session.latest.first.sequence, 801);
    final beforePageBuilds = menuBuilds;
    final oldTail = controller.position.maxScrollExtent;
    controller.jumpTo(oldTail);
    await tester.pump();
    for (
      var retry = 0;
      retry < 80 && controller.position.maxScrollExtent <= oldTail;
      retry++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(controller.position.maxScrollExtent, greaterThan(oldTail));
    // 混合行高会改变 SliverList 估算的偏移，以当前可见序号逼近分页边界。
    for (var attempt = 0; attempt < 32; attempt++) {
      final target = find.text('记录 751');
      if (target.evaluate().isNotEmpty &&
          tester.getRect(list).overlaps(tester.getRect(target))) {
        break;
      }
      final first = session.historyAnchor?.sequence ?? 0;
      controller.jumpTo(controller.offset + (first > 751 ? -180 : 180));
      await tester.pumpAndSettle();
    }
    await untilVisible('记录 751');
    expect(menuBuilds, beforePageBuilds, reason: '历史补页只需刷新数据和滚动范围');
    expect(find.text('记录 1200'), findsNothing);
    await tester.tap(find.text('回到最新'));
    await tester.pumpAndSettle();
    expect(find.text('记录 1200'), findsOneWidget);

    // 一次拖动从实时区直达磁盘最早记录，不逐页扩大滚动范围。
    final track = find.byKey(const ValueKey('session-history-scrollbar-a'));
    final thumb = find.byKey(const ValueKey('session-history-thumb-a'));
    var bounds = tester.getRect(track);
    final drag = await tester.startGesture(tester.getCenter(thumb));
    for (final fraction in [0.75, 0.25, 0.9, 0.15, 0.6]) {
      await drag.moveTo(
        Offset(bounds.center.dx, bounds.top + bounds.height * fraction),
      );
    }
    await drag.moveTo(bounds.topCenter - const Offset(0, 10));
    await drag.up();
    await untilVisible('记录 1');
    expect(tester.getTopLeft(thumb).dy, closeTo(bounds.top, 1));

    // 首个历史页已在窗口中，但这条记录尚未建立视口组件。
    expect(find.text('记录 80'), findsNothing);
    final localTrack = tester.getRect(track);
    final localThumbHeight = tester.getSize(thumb).height;
    final targetY =
        localThumbHeight / 2 +
        (localTrack.height - localThumbHeight) * 79 / 1199;
    await tester.tapAt(Offset(localTrack.center.dx, localTrack.top + targetY));
    await tester.pump();
    expect(session.historyAnchor?.sequence, 80);
    expect(find.text('记录 80'), findsOneWidget);

    // 全历史滑块按记录序号定位，同一记录内的像素移动无需重建手势组件。
    controller.jumpTo(controller.offset + 2);
    await tester.pumpAndSettle();
    final trackBeforeSameRecordScroll = tester.widget<GestureDetector>(track);
    controller.jumpTo(controller.offset + 1);
    await tester.pumpAndSettle();
    expect(session.historyAnchor?.sequence, 80);
    expect(
      tester.widget<GestureDetector>(track),
      same(trackBeforeSameRecordScroll),
    );

    bounds = tester.getRect(track);
    await tester.drag(thumb, Offset(0, bounds.height + 10));
    await untilVisible('记录 1200');
    expect(tester.getBottomLeft(thumb).dy, closeTo(bounds.bottom, 1));
    final idleMenuBuilds = menuBuilds;
    for (var batch = 0; batch < 4; batch++) {
      final last = 1200 + (batch + 1) * 20;
      await tester.runAsync(() async {
        for (var index = last - 19; index <= last; index++) {
          transport.input.add(TransportInput(utf8.encode('记录 $index')));
        }
        await eventually(() => session.receivedPackets == last);
      });
      await tester.pump(const Duration(milliseconds: 40));
      await untilVisible('记录 $last');
    }
    expect(menuBuilds, idleMenuBuilds, reason: '实时数据刷新无需重建右键菜单');
    await tester.runAsync(() async {
      await session.write(Uint8List.fromList(utf8.encode('历史中的发送')));
      for (var index = 1281; index <= 1700; index++) {
        transport.input.add(TransportInput(utf8.encode('记录 $index')));
      }
      await eventually(() => session.receivedPackets == 1700);
      await session.write(Uint8List.fromList(utf8.encode('最新的发送')));
      await session.history.flush();
    });
    await tester.pump(const Duration(milliseconds: 50));
    await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
    await tester.tap(find.text('会话数据选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏接收'));
    await tester.pumpAndSettle();
    final dataBounds = tester.getRect(list);
    await tester.tapAt(dataBounds.topLeft + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text('历史中的发送'), findsNothing);
    final top = tester.getRect(track).topCenter;
    await tester.tapAt(top + const Offset(0, 1));
    await untilVisible('历史中的发送');
    final firstSentAnchor = session.historyAnchor?.sequence;
    // 首屏只找到一条可见发送时，主动把后面的发送记录补进当前视口。
    await untilVisible('最新的发送');
    expect(session.historyAnchor?.sequence, firstSentAnchor);
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 100000),
      ),
    );
    await untilVisible('最新的发送');
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -100000),
      ),
    );
    await untilVisible('历史中的发送');
    await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
    await tester.tap(find.text('会话数据选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏接收'));
    await untilVisible('记录 1281');
    await untilVisible('历史中的发送');

    await tester.pumpWidget(const SizedBox());
    await _disposeHistoryFixture(tester, runtime, sessions, root);
  });

  testWidgets('完整历史窗口的滚动条随同一记录内的像素移动', (tester) async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    await _mount(tester, runtime);
    await openSessionFromList(tester, 'a');

    for (var index = 1; index <= 110; index++) {
      transport.input.add(TransportInput(utf8.encode('记录 $index')));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('记录 110'), findsOneWidget);
    final view = find.byKey(const PageStorageKey('data-a'));
    final controller = tester.widget<CustomScrollView>(view).controller!;
    final thumb = find.byKey(const ValueKey('session-history-thumb-a'));
    expect(thumb, findsOneWidget);

    controller.jumpTo(controller.position.maxScrollExtent - 104);
    await tester.pumpAndSettle();
    final session = tester
        .widget<CommunicationSessionDataView>(
          find.byType(CommunicationSessionDataView),
        )
        .session;
    final sequence = session.historyAnchor?.sequence;
    expect(sequence, isNotNull);
    final before = tester.getTopLeft(thumb).dy;
    controller.jumpTo(controller.offset + 1);
    await tester.pumpAndSettle();
    expect(session.historyAnchor?.sequence, sequence);
    expect(tester.getTopLeft(thumb).dy, greaterThan(before));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('不换行的长 HEX 历史可在首帧定位到未挂载行', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fixed-hex-history-'),
    ))!;
    final sessions = CommunicationSessions(
      historyRoot: () async => root,
      runtime: runtime,
      defaults: DisplayConfig.new,
    );
    final session = (await tester.runAsync(() async {
      await sessions.ready;
      add(runtime, 'a');
      await sessions.connect('a', sessions.layout.groups.first);
      final session = sessions['a']!;
      session.display
        ..hex = true
        ..wrap = false;
      final bytes = Uint8List(4096);
      for (var index = 0; index < 430; index++) {
        await session.write(bytes);
      }
      expect(session.sentPackets, 430);
      expect(session.latest.first.sequence, 31);
      await session.history.flush();
      return session;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunicationSessionDataView(
            session: session,
            saveDisplay: () {},
            layoutMenu: const [],
            sendSettings: (_) => const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final track = find.byKey(const ValueKey('session-history-scrollbar-a'));
    final thumb = find.byKey(const ValueKey('session-history-thumb-a'));
    final viewport = find.byKey(const PageStorageKey('data-a'));
    await tester.tapAt(tester.getTopLeft(track) + const Offset(2, 1));
    for (
      var attempts = 0;
      attempts < 100 && session.historyAnchor?.sequence != 1;
      attempts++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(session.historyAnchor?.sequence, 1);

    Future<void> seek(int target) async {
      final row = find.byKey(ValueKey((target, 0)));
      expect(row, findsNothing);
      final bounds = tester.getRect(track);
      final thumbHeight = tester.getSize(thumb).height;
      final extent = session.latestSequence! - 1;
      final y =
          thumbHeight / 2 +
          (bounds.height - thumbHeight) * (target - 1) / extent;
      await tester.tapAt(Offset(bounds.center.dx, bounds.top + y));
      await tester.pump();
      expect(session.historyAnchor?.sequence, target);
      expect(
        tester.getTopLeft(row).dy,
        closeTo(tester.getTopLeft(viewport).dy, 0.01),
      );
    }

    await seek(11);
    await seek(2);

    // 长 HEX 行保留局部选区和横向滚动，附近行仍保留完整读屏文本。
    final row = find.byKey(const ValueKey((2, 0)));
    final line = find.descendant(
      of: row,
      matching: find.byType(SingleChildScrollView),
    );
    final scrollViewport = tester.element(
      find.descendant(of: viewport, matching: find.byType(Viewport)),
    );
    final selection = scrollViewport
        .findAncestorWidgetOfExactType<SelectionContainer>()!
        .delegate!;
    await tester.pumpAndSettle();
    final origin = tester.getCenter(viewport);
    for (var shift = 0; shift < 16; shift++) {
      selection.dispatchSelectionEvent(
        SelectWordSelectionEvent(
          globalPosition: origin.translate(shift.toDouble(), 0),
        ),
      );
      if (selection.getSelectedContent()?.plainText == '00') break;
      selection.dispatchSelectionEvent(const ClearSelectionEvent());
    }
    await tester.pump();
    expect(selection.getSelectedContent()?.plainText, '00');
    final visibleParagraphs = find
        .descendant(of: viewport, matching: find.byType(RichText))
        .evaluate()
        .map((element) => element.findRenderObject())
        .whereType<RenderParagraph>();
    final selectedParagraphs = visibleParagraphs.where((paragraph) {
      final Object? registrar = paragraph.registrar;
      return registrar is SelectionHandler && registrar.value.hasSelection;
    });
    expect(selectedParagraphs, hasLength(1));

    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      final fullLine = List.filled(1024, '00').join(' ');
      expect(find.semantics.byLabel(fullLine), findsWidgets);
    } finally {
      semantics.dispose();
    }
    selection.dispatchSelectionEvent(const ClearSelectionEvent());
    await tester.pump();
    expect(selection.getSelectedContent(), isNull);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: line, matching: find.byType(Scrollable)),
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    selection.dispatchSelectionEvent(
      SelectParagraphSelectionEvent(globalPosition: tester.getCenter(line)),
    );
    await tester.pump();
    expect(
      selection.getSelectedContent()?.plainText,
      List.filled(1024, '00').join(' '),
    );
    selection.dispatchSelectionEvent(const ClearSelectionEvent());
    await tester.pump();
    await seek(11);
    final newLine = find.descendant(
      of: find.byKey(const ValueKey((11, 0))),
      matching: find.byType(Scrollable),
    );
    expect(tester.state<ScrollableState>(newLine).position.pixels, 0);
    await tester.pumpWidget(const SizedBox());
    await _disposeHistoryFixture(tester, runtime, sessions, root);
  });

  testWidgets('双会话拆分、拉伸、定向收发和合并保留各自草稿', (tester) async {
    final a = RecordingTransport()..finish();
    final b = RecordingTransport()
      ..answer = SerialWriteResult.failure('驱动短写', acceptedBytes: 1)
      ..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => d.id == 'a' ? a : b,
    );
    for (final id in ['a', 'b']) {
      add(runtime, id);
    }
    await _mount(tester, runtime);
    for (final id in ['a', 'b']) {
      await openSessionFromList(tester, id);
    }
    expect(find.byType(CommunicationSessionDataView), findsOneWidget);
    expect(_tab('a'), findsOneWidget);
    expect(_tab('b'), findsOneWidget);
    await tester.tap(_tab('b'));
    await tester.pump();
    await tester.enterText(_input('b'), 'BB');
    await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
    await tester.tap(find.text('会话组布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('向右拆分'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunicationSessionDataView), findsNWidgets(2));
    final initialWidth = tester
        .getSize(find.byType(CommunicationSessionDataView).first)
        .width;
    final divider = find.byKey(const ValueKey('session-group-resize'));
    await tester.drag(divider, const Offset(120, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byType(CommunicationSessionDataView).first).width,
      greaterThan(initialWidth + 30),
    );

    a.input.add(TransportInput([65, 49]));
    b.input.add(TransportInput([66, 50]));
    a.input.add(TransportInput([0xe4, 0xb8]));
    a.input.add(TransportInput([0xad]));
    a.input.add(TransportInput(utf8.encode('首行\n末行')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.textContaining('A1'), findsOneWidget);
    expect(find.textContaining('B2'), findsOneWidget);
    expect(find.textContaining('中'), findsOneWidget);
    expect(find.textContaining('�'), findsNothing);
    expect(
      tester.getTopLeft(find.text('A1')).dy,
      lessThan(tester.getTopLeft(find.textContaining('首行')).dy),
    );
    final original = tester.widget<Text>(find.text('A1'));
    a.input.add(TransportInput(utf8.encode('A2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('A2'), findsOneWidget);
    expect(tester.widget<Text>(find.text('A1')), same(original));
    expect(tester.widget<Text>(find.text('A2')).style, same(original.style));

    final aDataView = find.byType(CommunicationSessionDataView).first;
    expect(
      find.descendant(of: aDataView, matching: find.textContaining('B2')),
      findsNothing,
    );

    await tester.tap(_send('b'));
    await tester.pump();
    expect(a.written, isEmpty);
    expect(b.written, [
      [66, 66],
    ]);
    expect(find.textContaining('驱动短写'), findsNothing);
    await tester.enterText(_input('a'), 'AA');
    await tester.tap(_send('a'));
    await tester.pump();
    expect(a.written, [
      [65, 65],
    ]);
    expect(b.written, hasLength(1));
    expect(find.textContaining('已发送'), findsNothing);

    final bounds = tester.getRect(aDataView);
    final pointer = Offset(bounds.center.dx, bounds.bottom - 2);
    await tester.tapAt(
      pointer,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('发送配置')).bottom,
      lessThanOrEqualTo(pointer.dy),
    );
    await tester.tapAt(
      Offset(bounds.left + 5, pointer.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('发送配置'), findsNothing);

    await _openDataMenu(tester, aDataView);
    expect(find.text('向前回看历史'), findsNothing);
    expect(find.text('回到实时数据'), findsNothing);
    await tester.tap(find.text('会话数据选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放大数据字号'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.textContaining('A1')).style!.fontSize, 14);
    expect(tester.widget<Text>(find.textContaining('B2')).style!.fontSize, 13);

    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _openDataMenu(tester, find.byType(CommunicationSessionDataView).last);
    await tester.tap(find.text('会话组布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合并会话组'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunicationSessionDataView), findsOneWidget);
    expect(tester.widget<TextField>(_input('b')).controller!.text, 'BB');
    await tester.tap(_tab('a'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_input('a')).controller!.text, 'AA');

    final dataView = find.byType(CommunicationSessionDataView);
    final start = tester.getCenter(_tab('b'));
    final target = tester.getRect(dataView).bottomCenter - const Offset(0, 8);
    await tester.dragFrom(start, target - start, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(dataView, findsNWidgets(2));
    expect(
      tester.getTopLeft(dataView.first).dy,
      lessThan(tester.getTopLeft(dataView.last).dy),
    );
    await _openDataMenu(tester, dataView.first);
    expect(find.text('发送配置'), findsOneWidget);
    final gutter = find.byKey(const ValueKey('session-gutter-a'));
    await tester.tapAt(
      tester.getCenter(gutter),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('会话组布局'), findsNothing);
    expect(find.text('发送配置'), findsNothing);
    expect(find.text('行号'), findsOneWidget);
    expect(find.text('折叠标记'), findsNothing);
    expect(find.text('时间戳'), findsOneWidget);
    final previousGutterWidth = tester.getSize(gutter).width;
    final otherGutter = find.byKey(const ValueKey('session-gutter-b'));
    final otherGutterWidth = tester.getSize(otherGutter).width;
    await tester.tap(find.text('行号'));
    await tester.pumpAndSettle();
    expect(tester.getSize(gutter).width, lessThan(previousGutterWidth));
    expect(tester.getSize(otherGutter).width, otherGutterWidth);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final multiline = find.textContaining('末行');
    expect(multiline, findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tapAt(
      tester.getTopLeft(multiline) + const Offset(6, 7),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await _openDataMenu(tester, dataView.first);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, contains('A1'));
    expect(copied, contains('首行\n末行'));
    expect(copied!.indexOf('A1'), lessThan(copied!.indexOf('首行')));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('关闭自动换行时，重复短行在缩窄后仍可横向滚动', (tester) async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    await _mount(tester, runtime);
    await openSessionFromList(tester, 'a');
    await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
    await tester.tap(find.text('会话数据选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动换行'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final repeated = 'W' * 40;
    final long = '0123456789' * 44;
    for (final data in [repeated, repeated, long, long]) {
      transport.input.add(TransportInput(utf8.encode(data)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 40));
    }
    Finder horizontalScroll(String data) => find.ancestor(
      of: find.text(data),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );

    expect(find.text(repeated), findsNWidgets(2));
    expect(horizontalScroll(repeated), findsOneWidget);
    expect(horizontalScroll(long), findsNWidgets(2));
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(find.semantics.byLabel(long), findsNWidgets(2));
      final horizontalNodes = find.semantics
          .scrollable(axis: Axis.horizontal)
          .evaluate();
      expect(
        horizontalNodes.where(
          (node) => (node.getSemanticsData().scrollExtentMax ?? 0) > 0,
        ),
        hasLength(2),
      );
    } finally {
      semantics.dispose();
    }

    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();
    expect(horizontalScroll(repeated), findsNWidgets(2));
    final scroller = horizontalScroll(long).last;
    final scrollable = find.descendant(
      of: scroller,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    final other = tester.state<ScrollableState>(
      find.descendant(
        of: horizontalScroll(long).first,
        matching: find.byType(Scrollable),
      ),
    );
    expect(other.position.pixels, 0);

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage({'type': 'fontsChange'}),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    expect(other.position.pixels, 0);

    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tapAt(
      tester.getCenter(scroller),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, contains(long));
  });

  testWidgets('双会话突发接收在相邻帧显示各自的最新数据', (tester) async {
    final a = RecordingTransport()..finish();
    final b = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (d) async => d.id == 'a' ? a : b,
    );
    for (final id in ['a', 'b']) {
      add(runtime, id);
    }
    await _mount(tester, runtime);
    for (final id in ['a', 'b']) {
      await openSessionFromList(tester, id);
    }
    await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
    await tester.tap(find.text('会话组布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('向右拆分'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunicationSessionDataView), findsNWidgets(2));

    // 先显示少量数据，进入已建立的实时窗口再测试持续突发。
    a.input.add(TransportInput([65]));
    b.input.add(TransportInput([66]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    for (var index = 1; index <= 24; index++) {
      a.input.add(TransportInput(utf8.encode('分屏甲 $index')));
      b.input.add(TransportInput(utf8.encode('分屏乙 $index')));
    }
    final tailA = find.text('分屏甲 24');
    final tailB = find.text('分屏乙 24');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tailA.evaluate().length + tailB.evaluate().length, 1);
    await tester.pump();
    expect(tailA, findsOneWidget);
    expect(tailB, findsOneWidget);

    for (final view in tester.widgetList<CommunicationSessionDataView>(
      find.byType(CommunicationSessionDataView),
    )) {
      view.session.display.wrap = false;
    }
    final first = 'A' * 2048;
    final second = 'B' * 2048;
    a.input.add(TransportInput(utf8.encode(first)));
    b.input.add(TransportInput(utf8.encode(second)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(find.text('A' * 1024).evaluate(), isNotEmpty);
    expect(find.text('B' * 1024).evaluate(), isNotEmpty);

    a.input.add(TransportInput(utf8.encode('C' * 2048 + '长包末尾甲')));
    b.input.add(TransportInput(utf8.encode('D' * 2048 + '长包末尾乙')));
    final lastA = find.textContaining('长包末尾甲');
    final lastB = find.textContaining('长包末尾乙');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 40));
    expect(lastA.evaluate().length + lastB.evaluate().length, 1);
    await tester.pump();
    expect(lastA, findsOneWidget);
    expect(lastB, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('隐藏接收时更新统计，收包不重建数据视口', (tester) async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    await _mount(tester, runtime);
    await openSessionFromList(tester, 'a');
    await tester.enterText(_input('a'), '发送一');
    await tester.tap(_send('a'));
    await tester.pump(const Duration(milliseconds: 50));
    final view = find.byType(CommunicationSessionDataView);
    Finder dataText(String text) =>
        find.descendant(of: view, matching: find.text(text));
    expect(dataText('发送一'), findsOneWidget);

    await _openDataMenu(tester, view);
    await tester.tap(find.text('会话数据选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏接收'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final scroll = find.descendant(
      of: view,
      matching: find.byKey(const PageStorageKey('data-a')),
    );
    final original = tester.widget<CustomScrollView>(scroll);
    for (var i = 0; i < 10; i++) {
      transport.input.add(TransportInput([0x41]));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('RX 10 B · TX 9 B'), findsOneWidget);
    expect(tester.widget<CustomScrollView>(scroll), same(original));

    await tester.enterText(_input('a'), '发送二');
    await tester.tap(_send('a'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(dataText('发送二'), findsOneWidget);
    expect(tester.widget<CustomScrollView>(scroll), isNot(same(original)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('会话循环发送使用当前 HEX 与换行配置，空负载时暂停', (tester) async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      createLoopStopwatch: tester.binding.clock.stopwatch,
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    await _mount(tester, runtime);
    await openSessionFromList(tester, 'a');

    Future<void> openSendSettings() async {
      await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
      await tester.tap(find.text('发送配置'));
      await tester.pumpAndSettle();
    }

    await openSendSettings();
    await tester.tap(find.text('HEX 发送'));
    await tester.tap(find.text('追加 CR'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.enterText(_input('a'), '0A FF');
    await openSendSettings();
    await tester.tap(find.text('开始循环发送'));
    await tester.pumpAndSettle();
    expect(transport.written.first, orderedEquals([10, 255, 13]));

    await openSendSettings();
    await tester.tap(find.text('追加 LF'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(transport.written.last, orderedEquals([10, 255, 13, 10]));

    await tester.enterText(_input('a'), '');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(transport.written.last, orderedEquals([13, 10]));
    await openSendSettings();
    await tester.tap(find.text('追加 CR'));
    await tester.tap(find.text('追加 LF'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final writeCount = transport.written.length;
    await tester.pump(const Duration(milliseconds: 1100));
    expect(transport.written, hasLength(writeCount));
    await openSendSettings();
    await tester.tap(find.text('停止循环发送'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('关闭会话仅断开自身连接并停止循环，配置可重新打开', (tester) async {
    final transports = {
      'a': RecordingTransport()..finish(),
      'b': RecordingTransport()..finish(),
    };
    final runtime = CommunicationRuntime(
      createLoopStopwatch: tester.binding.clock.stopwatch,
      transportFactory: (d) async {
        final previous = transports[d.id]!;
        return previous.closed
            ? (transports[d.id] = RecordingTransport()..finish())
            : previous;
      },
    );
    for (final id in transports.keys) {
      add(runtime, id);
    }
    await _mount(tester, runtime);
    for (final id in transports.keys) {
      await openSessionFromList(tester, id);
      await tester.pump();
      await tester.enterText(_input(id), id);
      await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
      await tester.tap(find.text('发送配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始循环发送'));
      await tester.pumpAndSettle();
    }
    expect(
      ['a', 'b']
          .map(runtime.loopFor)
          .where(
            (target) => target != null && target.phase != LoopPhase.stopped,
          ),
      hasLength(2),
    );
    await tester.runAsync(() async {
      await tester.tap(_close('a'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    for (
      var retry = 0;
      retry < 30 && _tab('a').evaluate().isNotEmpty;
      retry++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(runtime.connection('a').completelyClosed, isTrue);
    expect(runtime.loopFor('a'), isNull);
    final aPrevious = transports['a']!.written.length;
    final bPrevious = transports['b']!.written.length;
    await tester.pump(const Duration(milliseconds: 1100));
    expect(transports['a']!.written.length, aPrevious);
    expect(transports['b']!.written.length, greaterThan(bPrevious));
    expect(_tab('a'), findsNothing);
    await openSessionFromList(tester, 'a');
    expect(_tab('a'), findsOneWidget);
    expect(tester.widget<TextField>(_input('a')).controller!.text, isEmpty);
    expect(runtime.loopFor('a') != null, isFalse);
    await tester.enterText(_input('a'), '保留草稿');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('session-link-a')));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(_tab('a'), findsOneWidget);
    expect(find.text('未连接'), findsNothing);
    expect(find.byTooltip('未连接'), findsOneWidget);
    expect(tester.widget<IconButton>(_send('a')).onPressed, isNull);
    expect(tester.widget<TextField>(_input('a')).controller!.text, '保留草稿');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('session-link-a')));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip('未连接'), findsNothing);
    expect(tester.widget<IconButton>(_send('a')).onPressed, isNotNull);
    runtime.stopLoop('b');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('实时日志少量时从上往下显示，满屏后自动跟随并在清空后恢复顶部对齐', (tester) async {
    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    await _mount(tester, runtime);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    await openSessionFromList(tester, 'a');

    Future<void> pushLines(Iterable<String> lines) async {
      for (final line in lines) {
        transport.input.add(TransportInput(utf8.encode(line)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await pushLines(['TOP-1', 'TOP-2']);
    final viewport = find.descendant(
      of: find.byType(CommunicationSessionDataView),
      matching: find.byType(Viewport),
    );
    final viewportTop = tester.getTopLeft(viewport).dy;
    final firstTop = tester.getTopLeft(find.text('TOP-1')).dy;
    final secondTop = tester.getTopLeft(find.text('TOP-2')).dy;
    expect(firstTop, closeTo(viewportTop, 2.0));
    expect(secondTop, greaterThan(firstTop));

    await pushLines([for (var i = 1; i <= 50; i++) 'FILL-$i']);
    await tester.pumpAndSettle();
    expect(find.text('FILL-50'), findsOneWidget);
    expect(find.text('TOP-1'), findsNothing);
    expect(
      tester.getBottomLeft(find.text('FILL-50')).dy,
      closeTo(tester.getBottomLeft(viewport).dy, 2.0),
    );

    await _openDataMenu(tester, find.byType(CommunicationSessionDataView));
    await tester.tap(find.text('清空会话历史'));
    await tester.pumpAndSettle();

    await pushLines(['AFTER-CLEAR-1', 'AFTER-CLEAR-2']);
    final afterFirstTop = tester.getTopLeft(find.text('AFTER-CLEAR-1')).dy;
    final afterSecondTop = tester.getTopLeft(find.text('AFTER-CLEAR-2')).dy;
    expect(afterFirstTop, closeTo(viewportTop, 2.0));
    expect(afterSecondTop, greaterThan(afterFirstTop));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('应用主题统一切换并同步更新会话终端背景、工具栏与文本着色', (tester) async {
    final themeController = AppThemeController(persist: false);
    addTearDown(themeController.dispose);

    final transport = RecordingTransport()..finish();
    final runtime = CommunicationRuntime(
      transportFactory: (_) async => transport,
    );
    add(runtime, 'a');
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.runAsync(runtime.dispose));

    await tester.pumpWidget(
      AppThemeScope(
        controller: themeController,
        child: ListenableBuilder(
          listenable: themeController,
          builder: (context, _) => MaterialApp(
            theme: buildDesktopTheme(scheme: themeController.scheme),
            themeAnimationDuration: Duration.zero,
            home: ChangeNotifierProvider<CommunicationRuntime>.value(
              value: runtime,
              child: Scaffold(
                body: Column(
                  children: [
                    DesktopTitleBar(navigationExpanded: true, onMenu: () {}),
                    const Expanded(child: SerialPortView()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openSessionFromList(tester, 'a');

    expect(find.byKey(const ValueKey('session-color-scheme-a')), findsNothing);

    transport.input.add(
      TransportInput(utf8.encode('[I/USB] Clock: 72000000 Hz')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 40));

    final initialBg = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('session-terminal-bg-a')),
    );
    expect(initialBg.color, const Color(0xfffafafa));

    await tester.tap(find.byKey(const ValueKey('app-theme-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-scheme-dracula')));
    await tester.pumpAndSettle();

    final bg = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('session-terminal-bg-a')),
    );
    expect(bg.color, const Color(0xff282a36));
    final toolbarDecoration = tester
        .widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('session-toolbar-a')),
            matching: find.byType(DecoratedBox),
          ).first,
        )
        .decoration as BoxDecoration;
    expect(toolbarDecoration.color, const Color(0xff21222c));

    final rxText = tester.widget<Text>(find.text('[I/USB] Clock: 72000000 Hz'));
    expect(rxText.style?.color, const Color(0xfff8f8f2));
    final spans = (rxText.textSpan! as TextSpan).children!.cast<TextSpan>().toList();
    expect(spans[0].style?.color, const Color(0xff69ff94));
    expect(spans[2].style?.color, const Color(0xffff92df));

    await tester.tap(find.byKey(const ValueKey('app-theme-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-scheme-one-half-light')));
    await tester.pumpAndSettle();

    final resetBg = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('session-terminal-bg-a')),
    );
    expect(resetBg.color, const Color(0xfffafafa));
    final resetRxText = tester.widget<Text>(
      find.text('[I/USB] Clock: 72000000 Hz'),
    );
    expect(resetRxText.style?.color, const Color(0xff383a42));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
