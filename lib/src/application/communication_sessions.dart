import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/serial_port_model.dart';
import '../../services/serial/serial_write_result.dart';
import '../io/recording.dart';
import 'communication_configuration_store.dart';
import 'communication_runtime.dart';
import 'session_history.dart';
import 'session_layout.dart';

class SessionDisplay {
  SessionDisplay(DisplayConfig defaults)
    : hex = defaults.receiveHex,
      wrap = defaults.autoWrap,
      follow = defaults.autoScroll,
      hideReceive = defaults.hideReceive,
      sendHex = defaults.sendHex,
      appendCR = defaults.appendCR,
      appendLF = defaults.appendLF,
      loopMs = defaults.loopInterval;
  bool hex, wrap, follow, hideReceive, sendHex, appendCR, appendLF;
  int loopMs;
  double fontSize = 13;
  bool gutterPadding = true,
      lineNumbers = true,
      directionMarks = true,
      timestamps = true,
      timestampMillis = false,
      wideGutterPadding = false,
      directionArrows = false;

  void restore(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    hex = flag('hex', hex);
    wrap = flag('wrap', wrap);
    follow = flag('follow', follow);
    hideReceive = flag('hideReceive', hideReceive);
    sendHex = flag('sendHex', sendHex);
    appendCR = flag('appendCR', appendCR);
    appendLF = flag('appendLF', appendLF);
    if (json['loopMs'] case final int value) loopMs = value.clamp(1, 3600000);
    if (json['fontSize'] case final num value) {
      fontSize = value.toDouble().clamp(8, 32);
    }
    gutterPadding = flag('gutterPadding', gutterPadding);
    lineNumbers = flag('lineNumbers', lineNumbers);
    directionMarks = flag('directionMarks', directionMarks);
    timestamps = flag('timestamps', timestamps);
    timestampMillis = flag('timestampMillis', timestampMillis);
    wideGutterPadding = flag('wideGutterPadding', wideGutterPadding);
    directionArrows = flag('directionArrows', directionArrows);
  }

  Map<String, Object?> toJson() => {
    'hex': hex,
    'wrap': wrap,
    'follow': follow,
    'hideReceive': hideReceive,
    'sendHex': sendHex,
    'appendCR': appendCR,
    'appendLF': appendLF,
    'loopMs': loopMs,
    'fontSize': fontSize,
    'gutterPadding': gutterPadding,
    'lineNumbers': lineNumbers,
    'directionMarks': directionMarks,
    'timestamps': timestamps,
    'timestampMillis': timestampMillis,
    'wideGutterPadding': wideGutterPadding,
    'directionArrows': directionArrows,
  };
}

/// 每条连接只有一个会话读取游标。记录进入历史后立即释放待处理队列中的引用。
class _RecentInput {
  _RecentInput(this._resize);

  final void Function(int) _resize;
  final _packets = ListQueue<RawPacket>();
  int next = 0, _bytes = 0;
  int get first => next - _packets.length;
  RawPacket? get oldest => _packets.firstOrNull;

  RawPacket take() {
    final packet = _packets.removeFirst();
    final cost = packet.bytes.length + 128;
    _bytes -= cost;
    _resize(-cost);
    return packet;
  }

  void consume(int count, void Function(RawPacket) accept) {
    var cost = 0;
    try {
      for (var index = 0; index < count; index++) {
        final packet = _packets.removeFirst();
        cost += packet.bytes.length + 128;
        accept(packet);
      }
    } finally {
      _bytes -= cost;
      _resize(-cost);
    }
  }

  void add(RawPacket packet) {
    _packets.addLast(packet);
    next++;
    final cost = packet.bytes.length + 128;
    _bytes += cost;
    _resize(cost);
    while (_packets.length > 2048 || _bytes > 2 * 1024 * 1024) {
      take();
    }
  }

  void clear() {
    _packets.clear();
    _resize(-_bytes);
    _bytes = 0;
  }
}

/// 一个已经打开的会话。页面或扩展功能可直接使用有来源的接收和定向写入。
class OpenCommunicationSession extends ChangeNotifier {
  OpenCommunicationSession._(
    this.runtime,
    this.id,
    this._input,
    this.display,
    this._requestRefresh,
    Future<Directory> Function() historyRoot,
    int historyMaxBytes,
  ) : _cursor = _input.next {
    history = SessionHistory(
      historyRoot,
      _changed,
      connectionId: id,
      maxBytes: historyMaxBytes,
    );
    _stopObserving = runtime.observeTimedSessionWrites(id, _onWritten);
  }

  final CommunicationRuntime runtime;
  final String id;
  final _RecentInput _input;
  final SessionDisplay display;
  late final SessionHistory history;
  late final VoidCallback _stopObserving;
  static const _receiveBatch = 128;
  static const _boundaryByteLimit = 2 * 1024 * 1024;
  final _recordBoundaries = ListQueue<({int through, SessionRecord record})>();
  int _boundaryBytes = 0;
  final _latest = ListQueue<SessionRecord>();
  List<SessionRecord>? _latestSnapshot;
  int _latestBytes = 0;
  int _cursor;
  int receivedBytes = 0, sentBytes = 0;
  int receivedPackets = 0, sentPackets = 0;
  int missedInputPackets = 0;
  int serialReceiveOverruns = 0;
  bool _closed = false;
  bool get closed => _closed;
  ConnectionSnapshot? get connection => runtime.connectionFor(id);
  String draft = '';
  final void Function(OpenCommunicationSession) _requestRefresh;
  ({int sequence, int byteOffset, double offset})? historyAnchor;
  int? get firstLatestSequence => _latest.firstOrNull?.sequence;
  int? get latestSequence => _latest.lastOrNull?.sequence;
  List<SessionRecord> get latest =>
      _latestSnapshot ??= List.unmodifiable(_latest);

  final _stopPacketObservers = <VoidCallback>{};

  /// 观察本会话的新输入。关闭或暂停时撤销观察，避免在订阅内隐式积压。
  Stream<RawPacket> get packets => Stream.multi((controller) {
    if (_closed) {
      unawaited(controller.close());
      return;
    }
    late final StreamSubscription<RawPacket> subscription;
    late final VoidCallback stop;
    Future<void> cancel() {
      _stopPacketObservers.remove(stop);
      return subscription.cancel();
    }

    stop = () {
      unawaited(cancel());
      unawaited(controller.close());
    };

    subscription = runtime.packets.listen((packet) {
      if (!_closed && packet.connectionId == id) controller.addSync(packet);
    }, onDone: stop);
    _stopPacketObservers.add(stop);
    controller.onCancel = cancel;
    controller.onPause = stop;
  }, isBroadcast: true);

  Future<SerialWriteResult> write(Uint8List bytes) => _closed
      ? Future.value(SerialWriteResult.failure('会话已关闭', acceptedBytes: 0))
      : runtime.writeTo(id, bytes);

  void startLoop(Uint8List bytes) {
    if (_closed) return;
    runtime.startLoop(
      id,
      bytes,
      interval: Duration(milliseconds: display.loopMs),
    );
  }

  void updateLoop(Uint8List bytes) {
    if (!_closed) runtime.updateLoopData(id, bytes);
  }

  void stopLoop() => runtime.stopLoop(id);

  ProtocolTaskStart? beginTask(ProtocolTaskKind kind) {
    if (_closed) return null;
    return runtime.beginProtocolTask(id, kind);
  }

  Future<void> sendFile(
    File file,
    String name, {
    int packetSize = 1024,
    int intervalMs = 0,
  }) async {
    if (_closed) return;
    await runtime.fileTransfers.startSend(
      load: file.readAsBytes,
      fileName: name,
      connectionId: id,
      packetSize: packetSize,
      intervalMs: intervalMs,
    );
  }

  Future<void> receiveFile({
    String directory = '',
    String savePath = '',
  }) async {
    if (_closed) return;
    await runtime.fileTransfers.startReceive(
      defaultDirectory: directory,
      savePath: savePath,
      connectionId: id,
    );
  }

  void _changed() {
    if (!_closed && hasListeners) _requestRefresh(this);
  }

  void _publish() {
    if (!_closed) notifyListeners();
  }

  void _onWritten(Uint8List bytes, int epoch, DateTime timestamp) {
    if (_closed) return;
    sentPackets++;
    sentBytes += bytes.length;
    _recordAtReceiveBoundary(
      sentPacket: RawPacket.fromInput(
        TransportInput.takeOwned(bytes),
        connectionId: id,
        receivedAt: timestamp,
        epoch: epoch,
        sequence: 0,
      ),
    );
    _changed();
  }

  bool _hasPendingRecords() =>
      _cursor != _input.next || _recordBoundaries.isNotEmpty;

  void _recordAtReceiveBoundary({RawPacket? sentPacket, String? notice}) {
    // 短接收队列立即处理。发送回执只在确实需要排队时才包装为记录。
    if (_recordBoundaries.isEmpty &&
        _input.next - _input.first <= _receiveBatch) {
      _drain(notify: false);
      if (sentPacket != null) {
        _remember(history.appendPacket(sentPacket, sent: true));
      } else {
        _record(SessionRecord(null, notice: notice));
      }
      return;
    }
    final record = SessionRecord(
      sentPacket,
      sent: sentPacket != null,
      notice: notice,
    );
    final cost = record.cost;
    // 超出回执内存预算时先消费积压，保留原有的收发顺序。
    if (_boundaryBytes + cost > _boundaryByteLimit) {
      _drain(notify: false);
      _record(record);
      return;
    }
    _recordBoundaries.addLast((through: _input.next, record: record));
    _boundaryBytes += cost;
  }

  bool _drain({int? limit, bool notify = true}) {
    if (_closed || !_hasPendingRecords()) return false;
    var remaining = limit;
    while (remaining == null || remaining > 0) {
      final boundary = _recordBoundaries.firstOrNull;
      final through = boundary?.through ?? _input.next;
      if (_cursor == through) {
        if (boundary == null) break;
        _recordBoundaries.removeFirst();
        _boundaryBytes -= boundary.record.cost;
        _record(boundary.record);
      } else if (_cursor < _input.first) {
        // 覆盖范围可能跨过发送确认。分段报告缺口，保留原来的收发顺序。
        final lostUntil = through < _input.first ? through : _input.first;
        final count = lostUntil - _cursor;
        _cursor = lostUntil;
        missedInputPackets += count;
        _record(SessionRecord(null, notice: '历史缺口：页内缓冲覆盖了 $count 条记录'));
      } else {
        // 同一发送回执或缺口之前连续消费，批次内无需重复检查边界。
        final span = through - _cursor;
        final count = remaining == null || remaining >= span ? span : remaining;
        _input.consume(count, _acceptReceived);
        if (remaining != null) remaining -= count;
        continue;
      }
      if (remaining != null) remaining--;
    }
    if (notify) _changed();
    return _hasPendingRecords();
  }

  void _acceptReceived(RawPacket packet) {
    _cursor++;
    receivedPackets++;
    receivedBytes += packet.bytes.length;
    _remember(history.appendPacket(packet));
  }

  void _record(SessionRecord record) => _remember(history.append(record));

  void _remember(SessionRecord record) {
    _latestSnapshot = null;
    _latest.add(record);
    _latestBytes += record.cost;
    while (_latest.length > 400 || _latestBytes > 2 * 1024 * 1024) {
      _latestBytes -= _latest.removeFirst().cost;
    }
  }

  Future<void> exportTo(File destination) {
    _drain();
    return history.exportTo(destination);
  }

  Future<void> clear() async {
    _cursor = _input.next;
    _input.clear();
    _recordBoundaries.clear();
    _boundaryBytes = 0;
    missedInputPackets = 0;
    serialReceiveOverruns = 0;
    _latest.clear();
    _latestSnapshot = null;
    _latestBytes = 0;
    historyAnchor = null;
    _changed();
    await history.clear();
  }

  Future<void> _close({required bool stopTasks}) async {
    if (_closed) return;
    _closed = true;
    _input.clear();
    _recordBoundaries.clear();
    _boundaryBytes = 0;
    _stopObserving();
    for (final stop in _stopPacketObservers.toList()) {
      stop();
    }
    if (stopTasks) {
      runtime.discardLoop(id);
      final task = runtime.taskFor(id);
      if (task != null) unawaited(task.cancel('会话已关闭'));
      runtime.fileTransfers.discard(id);
      runtime.firmwareUpgrades.discard(id);
    }
    _latest.clear();
    _latestSnapshot = null;
    draft = '';
    dispose();
    await history.close();
  }
}

/// 会话与连接一一对应，分组移动不会重建会话记录器。
class CommunicationSessions extends ChangeNotifier {
  CommunicationSessions({
    required this.runtime,
    required this.defaults,
    this.store,
    Future<Directory> Function()? historyRoot,
    this.historyMaxBytes = SessionHistory.defaultMaxBytes,
  }) : _historyRoot = historyRoot ?? SessionHistoryDirectory.open {
    _detachReceiver = runtime.attachSessionWorkspace(
      _shutdown,
      onReceiveGap: _onReceiveGap,
    );
    _receive = runtime.packets.listen(_onReceive);
    runtime.workspaceChanges.addListener(_sync);
    ready = _restore();
  }

  final CommunicationRuntime runtime;
  final DisplayConfig Function() defaults;
  final CommunicationConfigurationStore? store;
  final Future<Directory> Function() _historyRoot;
  final int historyMaxBytes;
  late final Future<void> ready;
  late final StreamSubscription<RawPacket> _receive;
  late final VoidCallback _detachReceiver;
  final _pendingInput = <String>{};
  int _inputBytes = 0;
  int get pendingInputBytes => _inputBytes;
  final _opened = <String, OpenCommunicationSession>{};
  final _display = <String, SessionDisplay>{};
  final _tagColors = <String, int>{};
  final _tagIcons = <String, String>{};
  Timer? _draining, _persisting, _refreshing;
  bool _drainScheduledSoon = false;
  Set<OpenCommunicationSession> _dirty = {};
  Future<void> _write = Future.value();
  bool _disposed = false, _ready = false, _syncing = false;
  bool get initialized => _ready;
  String? outputError;
  SessionLayout layout = SessionGroup();
  Map<String, ConnectionSnapshot> connections = {};
  OpenCommunicationSession? operator [](String id) => _opened[id];
  Iterable<ConnectionSnapshot> get unopened => runtime.snapshot.connections
      .where((connection) => !_opened.containsKey(connection.id));

  static const _tagPalette = [
    0xff008b9a,
    0xff3975d5,
    0xff9256c8,
    0xffcf6824,
    0xff288854,
    0xffc44777,
    0xff7251bf,
    0xffa47c15,
    0xff486b9f,
    0xffaa4f3c,
  ];

  static const defaultTagIcon = 'square';

  int tagColor(String id) => _tagColors[id] ?? _tagPalette.first;

  String tagIcon(String id) => _tagIcons[id] ?? defaultTagIcon;

  int nextTagColor() {
    final used = _tagColors.values.toSet();
    for (final color in _tagPalette) {
      if (!used.contains(color)) return color;
    }
    // 调色板用尽后继续分配不同的 RGB 颜色。
    var rgb = 0x39858c;
    while (used.contains(0xff000000 | rgb)) {
      rgb = (rgb + 0x5b3d29) & 0xffffff;
    }
    return 0xff000000 | rgb;
  }

  void setTagColor(String id, int color) {
    if (!connections.containsKey(id) || _tagColors[id] == color) return;
    _tagColors[id] = color;
    _changed();
  }

  void setTagIcon(String id, String iconKey) {
    if (!connections.containsKey(id) || tagIcon(id) == iconKey) return;
    if (iconKey == defaultTagIcon) {
      _tagIcons.remove(id);
    } else {
      _tagIcons[id] = iconKey;
    }
    _changed();
  }

  Future<void> _restore() async {
    try {
      await runtime.initialize();
      final data = await store?.read();
      if (_disposed) return;
      final parsed = data == null ? null : jsonDecode(data);
      if (parsed case final Map<String, dynamic> json) {
        layout = SessionLayout.fromJson(json['layout']) ?? SessionGroup();
        if (json['tagColors'] case final Map<String, dynamic> colors) {
          for (final entry in colors.entries) {
            if (entry.value case final int color
                when color >= 0xff000000 && color <= 0xffffffff) {
              _tagColors[entry.key] = color;
            }
          }
        }
        if (json['tagIcons'] case final Map<String, dynamic> icons) {
          for (final entry in icons.entries) {
            if (entry.value case final String iconKey when iconKey.isNotEmpty) {
              _tagIcons[entry.key] = iconKey;
            }
          }
        }
        if (json['display'] case final Map<String, dynamic> settings) {
          for (final entry in settings.entries) {
            if (entry.value case final Map<String, dynamic> display) {
              _display[entry.key] = SessionDisplay(defaults())
                ..restore(display);
            }
          }
        }
      }
    } catch (error) {
      outputError = '会话布局读取失败：$error';
    }
    if (_disposed) return;
    _ready = true;
    _refreshConnections();
    final restored = <String>{};
    for (final group in layout.groups.toList()) {
      for (final id in group.tabs.toList()) {
        if (!connections.containsKey(id) || !restored.add(id)) {
          group.remove(id);
        } else {
          _create(id);
        }
      }
    }
    _normalize();
    _sync();
    unawaited(
      _historyRoot().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void _refreshConnections() {
    connections = {
      for (final connection in runtime.snapshot.connections)
        connection.id: connection,
    };
  }

  void _sync() {
    if (_disposed || !_ready || _syncing) return;
    _syncing = true;
    try {
      _refreshConnections();
      final inactive = {
        ..._display.keys,
        ..._tagColors.keys,
        ..._tagIcons.keys,
        ..._opened.keys,
      }.difference(connections.keys.toSet());
      for (final id in inactive) {
        unawaited(_removeTab(id));
        _display.remove(id);
        _tagColors.remove(id);
        _tagIcons.remove(id);
      }
      var assigned = false;
      for (final id in connections.keys) {
        if (_tagColors.containsKey(id)) continue;
        _tagColors[id] = nextTagColor();
        assigned = true;
      }
      if (assigned || inactive.isNotEmpty) _save();
    } finally {
      _syncing = false;
    }
    notifyListeners();
  }

  void _onReceiveGap(String id, String reason) {
    final session = _opened[id];
    if (session == null || session.closed) return;
    // 缺口排在已经收到的包之后，恢复数据仍由正常的接收队列写入。
    session.serialReceiveOverruns++;
    session._recordAtReceiveBoundary(notice: '历史缺口：$reason');
    session._changed();
  }

  void _resizeInputs(int delta) => _inputBytes += delta;

  void _onReceive(RawPacket packet) {
    final session = _opened[packet.connectionId];
    if (session == null || session.closed) return;
    session._input.add(packet);
    while (_inputBytes > 8 * 1024 * 1024) {
      final oldest = _opened.values
          .map((session) => session._input)
          .where((buffer) => buffer.oldest != null)
          .reduce(
            (first, second) =>
                first.oldest!.receivedAt.isBefore(second.oldest!.receivedAt)
                ? first
                : second,
          );
      oldest.take();
    }
    _pendingInput.add(packet.connectionId);
    final input = session._input;
    _scheduleInputDrain(
      soon:
          _inputBytes >= 256 * 1024 ||
          input.next - input.first >= OpenCommunicationSession._receiveBatch,
    );
  }

  void _scheduleInputDrain({required bool soon}) {
    if (_draining != null && (_drainScheduledSoon || !soon)) return;
    _draining?.cancel();
    _drainScheduledSoon = soon;
    // 低流量延迟合批，突发积压在下一事件轮开始轮转。
    _draining = Timer(
      soon ? Duration.zero : const Duration(milliseconds: 12),
      _drainInput,
    );
  }

  void _drainInput() {
    _draining = null;
    _drainScheduledSoon = false;
    // 每轮处理有限的会话和记录，给界面帧及其他事件留出执行机会。
    for (var round = 0; round < 4 && _pendingInput.isNotEmpty; round++) {
      final id = _pendingInput.first;
      _pendingInput.remove(id);
      if (_opened[id]?._drain(limit: OpenCommunicationSession._receiveBatch) ??
          false) {
        _pendingInput.add(id);
      }
    }
    if (_pendingInput.isNotEmpty) {
      _scheduleInputDrain(soon: true);
    }
  }

  void _requestRefresh(OpenCommunicationSession session) {
    if (_disposed) return;
    _dirty.add(session);
    // 同一批可见会话在同一帧节拍内发布，避免双倍攒批引发单帧尖刺。
    _refreshing ??= Timer(const Duration(milliseconds: 16), () {
      _refreshing = null;
      final batch = _dirty;
      _dirty = {};
      for (final item in batch) {
        item._publish();
      }
    });
  }

  void _create(String id) {
    _opened[id] = OpenCommunicationSession._(
      runtime,
      id,
      _RecentInput(_resizeInputs),
      _display.putIfAbsent(id, () => SessionDisplay(defaults())),
      _requestRefresh,
      _historyRoot,
      historyMaxBytes,
    );
  }

  void _normalize() => layout = layout.pruneEmpty() ?? SessionGroup();

  void open(String id, SessionGroup group) {
    if (_disposed || !layout.groups.contains(group)) return;
    final connection = runtime.connectionFor(id);
    if (connection == null) return;
    if (_opened.containsKey(id)) {
      activate(
        layout.groups.firstWhere((element) => element.tabs.contains(id)),
        id,
      );
      return;
    }
    connections[id] = connection;
    _create(id);
    group.add(id);
    _changed();
  }

  void activate(SessionGroup group, String id) {
    if (!group.tabs.contains(id) || group.active == id) return;
    group.active = id;
    _changed();
  }

  Future<void> connect(String id, SessionGroup group) async {
    open(id, group);
    if (_opened.containsKey(id) &&
        runtime.connectionFor(id)?.completelyClosed == true) {
      await runtime.openConnection(id);
    }
  }

  Future<void> close(String id) async {
    if (!_opened.containsKey(id)) return;
    if (runtime.connectionFor(id) case final connection?
        when !connection.completelyClosed) {
      await runtime.closeConnection(id);
    }
    await _removeTab(id);
  }

  Future<void> _removeTab(String id) async {
    final session = _opened.remove(id);
    if (session == null) return;
    _pendingInput.remove(id);
    for (final group in layout.groups) {
      group.remove(id);
    }
    _normalize();
    final released = _release(session, stopTasks: true);
    _changed();
    await released;
  }

  Future<void> _release(
    OpenCommunicationSession session, {
    required bool stopTasks,
  }) async {
    try {
      _dirty.remove(session);
      await session._close(stopTasks: stopTasks);
    } catch (error) {
      if (_disposed) return;
      outputError = '会话历史清理失败：$error';
      notifyListeners();
    }
  }

  void move(String id, SessionGroup target, SessionDrop drop) {
    if (!_opened.containsKey(id) || !layout.groups.contains(target)) return;
    final source = layout.groups.firstWhere((group) => group.tabs.contains(id));
    if (drop == SessionDrop.tabs && identical(source, target)) {
      activate(target, id);
      return;
    }
    if (identical(source, target) && source.tabs.length == 1) return;
    source.remove(id);
    if (drop == SessionDrop.tabs) {
      target.add(id);
    } else {
      final newGroup = SessionGroup([id]);
      final before = drop == SessionDrop.left || drop == SessionDrop.top;
      layout = layout.replace(
        target,
        SessionSplit(
          before ? newGroup : target,
          before ? target : newGroup,
          horizontal: drop == SessionDrop.left || drop == SessionDrop.right,
        ),
      );
    }
    _normalize();
    _changed();
  }

  void merge(SessionGroup group) {
    final target = layout.neighbor(group);
    if (target == null) return;
    final active = group.active;
    for (final id in group.tabs.toList()) {
      target.add(id);
      group.remove(id);
    }
    target.active = active ?? target.active;
    _normalize();
    _changed();
  }

  void resize(SessionSplit split, double ratio) {
    split.ratio = ratio.clamp(0.1, 0.9);
    _changed();
  }

  void saveDisplay() => _save();

  void _changed() {
    _save();
    if (!_disposed && !_syncing) notifyListeners();
  }

  void _save() {
    if (store == null || !_ready || _disposed) return;
    _persisting?.cancel();
    _persisting = Timer(const Duration(milliseconds: 350), () {
      _persisting = null;
      _writeLayout();
    });
  }

  void _writeLayout() {
    final contents = jsonEncode({
      'layout': layout.toJson(),
      'tagColors': _tagColors,
      'tagIcons': _tagIcons,
      'display': _display.map((id, display) => MapEntry(id, display.toJson())),
    });
    _write = _write.then((_) => store!.write(contents)).catchError((
      Object error,
    ) {
      if (_disposed) return;
      outputError = '会话布局保存失败：$error';
      notifyListeners();
    });
  }

  Future<void> flushLayout() async {
    if (_persisting?.isActive == true) {
      _persisting!.cancel();
      _writeLayout();
    }
    await _write;
  }

  Future<void> _shutdown() async {
    await flushLayout();
    await Future.wait(
      _opened.values.map((session) => _release(session, stopTasks: false)),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(flushLayout());
    _draining?.cancel();
    _refreshing?.cancel();
    _dirty.clear();
    _pendingInput.clear();
    runtime.workspaceChanges.removeListener(_sync);
    _detachReceiver();
    unawaited(_receive.cancel());
    for (final session in _opened.values) {
      unawaited(_release(session, stopTasks: false));
    }
    _opened.clear();
    super.dispose();
  }
}
