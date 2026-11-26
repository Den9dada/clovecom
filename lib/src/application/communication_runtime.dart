import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min;

import 'communication_configuration_store.dart';
import 'communication_configuration_codec.dart';
import '../io/interface_scan.dart';
import '../io/interface_params.dart';
import 'communication_send.dart';
import 'communication_file_transfer.dart';
import 'communication_firmware_upgrade.dart';
export 'communication_firmware_upgrade.dart';
export 'communication_file_transfer.dart';
export 'communication_send.dart';

import 'package:flutter/foundation.dart';

import '../io/recording.dart';
import '../io/windows_async_wait.dart';
import 'communication_transport.dart';
export 'communication_transport.dart' show ConnectionDefinition;

part 'communication_loop.dart';
part 'communication_task.dart';

enum ConnectionPhase {
  closed,
  opening,
  open,
  listening,
  reconnecting,
  closing,
  failed,
}

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.definition,
    required this.phase,
    required this.epoch,
    required this.writable,
    this.detail,
    this.peer,
    this.operationsSettled = true,
    this.disconnecting = false,
    this.interfaceAvailable,
    this.availabilityDetail,
  });
  final ConnectionDefinition definition;
  String get id => definition.id;
  String get name => definition.name;
  final ConnectionPhase phase;
  final int epoch;
  final bool writable;
  final String? detail;
  final String? peer;
  final bool? interfaceAvailable;
  final String? availabilityDetail;
  final bool operationsSettled;
  final bool disconnecting;
  bool get connected => phase == ConnectionPhase.open;
  bool get completelyClosed =>
      operationsSettled &&
      (phase == ConnectionPhase.closed || phase == ConnectionPhase.failed);
}

class CommunicationSnapshot {
  CommunicationSnapshot(Iterable<ConnectionSnapshot> connections)
    : connections = List.unmodifiable(connections);
  final List<ConnectionSnapshot> connections;
}

/// 应用根拥有并释放此对象；视图收起不改变连接寿命。
class CommunicationRuntime extends ChangeNotifier {
  CommunicationRuntime({
    CommunicationTransportFactory? transportFactory,
    this.configurationStore,
    this.interfaceScanner,
    this.sendBudget = const SendBudget(),
    this.taskInputBudget = const TaskInputBudget(),
    this.retryBase = const Duration(seconds: 1),
    Stopwatch Function()? createLoopStopwatch,
  }) : _factory = transportFactory,
       _createLoopStopwatch = createLoopStopwatch ?? Stopwatch.new,
       _nativeLoopTimer = Platform.isWindows && createLoopStopwatch == null;

  final bool _nativeLoopTimer;

  final Stopwatch Function() _createLoopStopwatch;
  final Future<InterfaceScanResult> Function()? interfaceScanner;
  InterfaceScanResult? _interfaceScan;

  /// 管理编辑器与可用性判断共享最近一次本机接口扫描，不另外枚举或替换目标。
  InterfaceScanResult? get interfaceScan => _interfaceScan;
  Future<void>? _interfaceRefresh;
  Future<void> refreshInterfaceAvailability() =>
      _interfaceRefresh ??= _refreshInterfaceAvailability().whenComplete(
        () => _interfaceRefresh = null,
      );

  Future<void> _refreshInterfaceAvailability() async {
    final scan = interfaceScanner;
    if (scan == null || _disposed) return;
    try {
      final interfaces = await scan();
      if (_disposed) return;
      _interfaceScan = InterfaceScanResult(
        serialPorts: List.unmodifiable(interfaces.serialPorts),
        nics: List.unmodifiable(interfaces.nics),
        serialWarning: interfaces.serialWarning,
        nicWarning: interfaces.nicWarning,
      );
      for (final c in _connections.values) {
        // 扫描期间实际打开成功的链路，不被迟到的枚举快照降为不可用。
        if (c.transport != null && c.phase != ConnectionPhase.closing) {
          c.interfaceAvailable = true;
          c.availabilityDetail = null;
          continue;
        }
        final d = c.definition;
        final serial = d.serial?.serialPort;
        final key =
            serial ??
            switch (d.protocol!) {
              InterfaceProtocol.tcpClient => d.tcpClient.nicKey,
              InterfaceProtocol.tcpServer => d.tcpServer.nicKey,
              InterfaceProtocol.udp => d.udp.nicKey,
            };
        final found = serial != null
            ? interfaces.serialPorts.any(
                (p) => p.portName.toUpperCase() == key.toUpperCase(),
              )
            : key.isEmpty ||
                  key == '0.0.0.0' ||
                  key.startsWith('127.') ||
                  interfaces.containsNic(key);
        final warning = serial != null
            ? interfaces.serialWarning
            : interfaces.nicWarning;
        c.interfaceAvailable = found
            ? true
            : warning == null
            ? false
            : null;
        c.availabilityDetail = found ? null : warning ?? '通信接口 $key 不可用，保留原配置';
      }
    } catch (error) {
      if (_disposed) return;
      _interfaceScan = InterfaceScanResult(
        serialPorts: _interfaceScan?.serialPorts ?? const [],
        nics: _interfaceScan?.nics ?? const [],
        serialWarning: '接口扫描失败：$error',
        nicWarning: '接口扫描失败：$error',
      );
      for (final c in _connections.values) {
        c.interfaceAvailable = null;
        c.availabilityDetail = '接口扫描失败：$error';
      }
    }
    notifyListeners();
  }

  final CommunicationConfigurationStore? configurationStore;
  Future<void>? _initializing;
  bool _configurationReady = false, _restoringConfiguration = false;
  int _configurationRevision = 0;
  String? _configurationError;
  String? get configurationError => _configurationError;
  bool get configurationReady => _configurationReady;
  String? _lastConfiguration, _pendingConfiguration;
  Timer? _configurationTimer;
  Future<void>? _configurationWriter;

  /// 可重复等待；晚到载入绝不覆盖用户已经提交的管理命令。
  Future<void> initialize() => _initializing ??= _loadConfiguration();
  Future<void> _loadConfiguration() async {
    final revision = _configurationRevision;
    var upgradeFormat = false;
    try {
      final contents = await configurationStore?.read();
      if (_disposed) return;
      if (contents != null &&
          (revision > 0 || revision != _configurationRevision)) {
        _configurationError = '配置载入期间已有新操作，保留当前配置';
      } else if (contents != null) {
        final root = jsonDecode(contents) as Map<String, dynamic>;
        if (![1, 2].contains(root['version']) || root['connections'] is! List) {
          throw const FormatException('不支持的通信配置版本或缺少连接列表');
        }
        final warnings = <String>[];
        _restoringConfiguration = true;
        try {
          for (final item in root['connections'] as List) {
            try {
              final row = Map<String, dynamic>.from(item as Map);
              final definition = decodeConnectionDefinition(row);
              addConnection(definition);
            } catch (error) {
              warnings.add('已跳过无效通信配置：$error');
            }
          }
        } finally {
          _restoringConfiguration = false;
        }
        if (warnings.isNotEmpty) {
          _configurationError = warnings.join('；');
        } else {
          upgradeFormat = root['version'] == 1;
        }
      }
    } catch (error) {
      _configurationError = '通信配置载入失败：$error';
    } finally {
      _configurationReady = true;
      _lastConfiguration = _encodeConfiguration();
      if (upgradeFormat || revision > 0 || revision != _configurationRevision) {
        _lastConfiguration = null;
        _configurationChanged();
      }
      await refreshInterfaceAvailability();
      if (!_disposed) notifyListeners();
    }
  }

  String _encodeConfiguration() => jsonEncode({
    'version': 2,
    'connections': [
      for (final c in _connections.values)
        encodeConnectionDefinition(c.definition),
    ],
  });

  void _configurationChanged() {
    if (_restoringConfiguration || _disposed) return;
    _configurationRevision++;
    if (!_configurationReady || configurationStore == null) return;
    final contents = _encodeConfiguration();
    if (contents == _lastConfiguration) return;
    _lastConfiguration = contents;
    _pendingConfiguration = contents;
    // 固定首个变更期限；运行态通知和后续编辑不会无限推迟保存。
    _configurationTimer ??= Timer(const Duration(milliseconds: 200), () {
      _configurationTimer = null;
      unawaited(flushConfiguration().catchError((Object _) {}));
    });
  }

  Future<void> flushConfiguration() async {
    if (!_configurationReady) await initialize();
    _configurationTimer?.cancel();
    _configurationTimer = null;
    if (_configurationWriter != null) {
      await _configurationWriter;
      if (_pendingConfiguration != null) await flushConfiguration();
      return;
    }
    if (_pendingConfiguration == null || configurationStore == null) return;
    final writer = _writeConfiguration();
    _configurationWriter = writer;
    try {
      await writer;
    } finally {
      _configurationWriter = null;
    }
  }

  Future<void> _writeConfiguration() async {
    while (_pendingConfiguration != null) {
      final contents = _pendingConfiguration!;
      _pendingConfiguration = null;
      try {
        await configurationStore!.write(contents);
        if (_configurationError != null) {
          _configurationError = null;
          if (!_disposed) notifyListeners();
        }
      } catch (error) {
        _pendingConfiguration ??= contents;
        _configurationError = '通信配置保存失败：$error';
        if (!_disposed) notifyListeners();
        rethrow;
      }
    }
  }

  final Duration retryBase;
  final SendBudget sendBudget;
  final TaskInputBudget taskInputBudget;
  final _sessionWriters = <String, _SessionWriteObserver>{};
  Future<void> Function()? _closeSessions;
  void Function(String id, String reason)? _receiveGap;

  VoidCallback attachSessionWorkspace(
    Future<void> Function() close, {
    required void Function(String id, String reason) onReceiveGap,
  }) {
    if (_closeSessions != null) throw StateError('通信工作台已绑定');
    _closeSessions = close;
    _receiveGap = onReceiveGap;
    return () {
      if (identical(_closeSessions, close)) {
        _closeSessions = null;
        _receiveGap = null;
      }
    };
  }

  // 入队时保留当时的记录器，旧写入不会进入重新打开的会话。
  VoidCallback observeSessionWrites(
    String id,
    void Function(Uint8List, int) onWritten,
  ) => observeTimedSessionWrites(
    id,
    (bytes, epoch, _) => onWritten(bytes, epoch),
  );

  VoidCallback observeTimedSessionWrites(
    String id,
    void Function(Uint8List, int, DateTime) onWritten,
  ) {
    _sessionWriters[id] = onWritten;
    return () {
      if (identical(_sessionWriters[id], onWritten)) _sessionWriters.remove(id);
    };
  }

  Stream<RawPacket> get packets => _packets.stream;

  late final fileTransfers = FileTransferController(this, _bindingsChanged);
  late final firmwareUpgrades = FirmwareUpgradeController(
    this,
    _bindingsChanged,
  );
  final _loops = <String, _LoopRun>{};
  int _nextTaskId = 0;

  LoopTargetSnapshot? loopFor(String id) => _loops[id]?.snapshot;

  void startLoop(
    String id,
    Uint8List bytes, {
    required Duration interval,
    int timeoutMs = 5000,
    bool immediate = true,
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval');
    }
    final c = _connections[id];
    if (_disposed || c == null || !_canWrite(c) || c.task != null) return;
    stopLoop(id, reason: '重新启动循环');
    final run = _LoopRun(
      c.snapshot,
      interval,
      timeoutMs,
      Uint8List.fromList(bytes).asUnmodifiableView(),
      _createLoopStopwatch()..start(),
    );
    _loops[id] = run;
    _beginLoop(c, run, immediate: immediate);
    _bindingsChanged();
  }

  void updateLoopData(String id, Uint8List bytes) {
    if (_loops[id] case final run?) {
      run.bytes = Uint8List.fromList(bytes).asUnmodifiableView();
      if (run.worker case final worker?) {
        final connection = _connections[id];
        final extra = max(0, bytes.length - run.workerReservedBytes);
        if (connection == null ||
            bytes.length > _workerLoopBudget ||
            connection.sendBytes + extra > sendBudget.bytes) {
          worker.stop(cancelInFlight: false);
        } else {
          connection.sendBytes += extra;
          run.workerReservedBytes += extra;
          worker.update(run.bytes);
          if (run.active) {
            run.phase = bytes.isEmpty ? LoopPhase.waiting : LoopPhase.running;
            run.reason = bytes.isEmpty ? '草稿为空，等待有效内容' : null;
            _notifyLoopProgress();
          }
        }
      }
    }
  }

  void stopLoop(String id, {String reason = '用户停止'}) {
    if (_loops[id] case final run?) _stopLoopRun(run, reason);
    _bindingsChanged();
  }

  void discardLoop(String id) {
    final run = _loops.remove(id);
    if (run == null) return;
    _stopLoopRun(run, '会话已关闭');
    _bindingsChanged();
  }

  Future<SerialWriteResult> writeTo(
    String id,
    Uint8List bytes, {
    int timeoutMs = 5000,
  }) => _enqueue(id, bytes, timeoutMs);

  ConnectionSnapshot? connectionFor(String id) => _connections[id]?.snapshot;

  void _ingress(RawPacket packet) {
    _connections[packet.connectionId]?.task?._offer(packet);
    _packets.add(packet);
  }

  final CommunicationTransportFactory? _factory;
  final Map<String, _Connection> _connections = {};
  final Map<String, String> _physicalOwners = {};
  final _packets = StreamController<RawPacket>.broadcast(sync: true);
  void _bindingsChanged() {
    if (!_disposed) notifyListeners();
  }

  final _workspaceChanges = ValueNotifier(0);

  /// 会话工作区只处理连接和任务等状态变化，循环的单轮进度另行通知。
  Listenable get workspaceChanges => _workspaceChanges;

  void _notifyLoopProgress() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void notifyListeners() {
    _validateLoops();
    _validateTasks();
    super.notifyListeners();
    _workspaceChanges.value++;
  }

  bool _disposed = false;
  CommunicationSnapshot get snapshot =>
      CommunicationSnapshot(_connections.values.map((c) => c.snapshot));
  ConnectionSnapshot connection(String id) => _connections[id]!.snapshot;
  void addConnection(ConnectionDefinition definition) {
    if (_disposed || _connections.containsKey(definition.id)) {
      throw StateError('连接标识已存在或内核已释放');
    }
    _connections[definition.id] = _Connection(definition);
    _configurationChanged();
    if (_configurationReady) unawaited(refreshInterfaceAvailability());
    notifyListeners();
  }

  void updateConnection(ConnectionDefinition definition) {
    final c = _connections[definition.id]!;
    if (!c.snapshot.completelyClosed) throw StateError('请先完全断开连接');
    c.definition = definition;
    c.epoch++;
    c.interfaceAvailable = null;
    c.availabilityDetail = null;
    _configurationChanged();
    if (_configurationReady) unawaited(refreshInterfaceAvailability());
    notifyListeners();
  }

  void removeConnection(String id) {
    if (!connection(id).completelyClosed) throw StateError('请先完全断开连接');
    discardLoop(id);
    fileTransfers.discard(id);
    firmwareUpgrades.discard(id);
    _connections.remove(id);
    _configurationChanged();
    notifyListeners();
  }

  Future<void> openConnection(String id) {
    final c = _connections[id]!;
    return c.opening ??= _openConnection(id).whenComplete(() {
      c.opening = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _openConnection(String id) async {
    if (_disposed) throw StateError('内核已释放');
    final c = _connections[id]!;
    if (!c.snapshot.completelyClosed &&
        c.phase != ConnectionPhase.reconnecting) {
      return;
    }
    final port = c.definition.serial?.serialPort.toUpperCase();
    if (port != null) {
      if (_physicalOwners.containsKey(port)) {
        throw StateError('串口 $port 已被连接 ${_physicalOwners[port]} 占用');
      }
      _physicalOwners[port] = id;
    }
    final generation = ++c.generation;
    c.phase = ConnectionPhase.opening;
    c.detail = null;
    notifyListeners();
    try {
      final cancellation = c.openCancellation = TcpConnectCancellation();
      final transport = await (_factory != null
          ? _factory(c.definition)
          : openCommunicationTransport(
              c.definition,
              cancellation: cancellation,
            ));
      c.closedTransport = null;
      c.transport = transport;
      if (generation != c.generation || _disposed) {
        await _teardown(c);
        return;
      }
      if (transport.state.closed || transport.state.error != null) {
        throw StateError(transport.state.error ?? '链路在打开期间结束');
      }
      c.inputSub = transport.incoming.listen(
        (input) {
          if (!identical(c.transport, transport) ||
              c.generation != generation) {
            return;
          }
          _ingress(
            RawPacket.fromInput(
              input,
              connectionId: id,
              receivedAt: DateTime.now(),
              epoch: c.epoch,
              sequence: ++c.sequence,
              peer: c.peer,
            ),
          );
        },
        onError: (Object error) {
          if (error is SerialReceiveOverrun) {
            if (identical(c.transport, transport) &&
                c.generation == generation &&
                !_disposed) {
              final reason = error.toString();
              if (c.task case final task?) unawaited(task.cancel(reason));
              _receiveGap?.call(id, reason);
            }
            return;
          }
          unawaited(_transportFailed(c, transport, '$error'));
        },
        onDone: () => _transportFailed(c, transport, '接收已结束'),
      );
      c.stateSub = transport.states.listen((state) {
        if (!identical(c.transport, transport) || c.generation != generation) {
          return;
        }
        if (state.closed || state.error != null) {
          unawaited(_transportFailed(c, transport, state.error ?? '链路已断开'));
          return;
        }
        if (c.peer != state.peer || c.writable != state.writable) {
          c.epoch++;
          _clearQueue(c, '链路轮次已变化，未执行');
        }
        c.peer = state.peer;
        c.writable = state.writable;
        c.phase = state.listening && !state.writable
            ? ConnectionPhase.listening
            : ConnectionPhase.open;
        c.detail = state.detail ?? state.peer;
        notifyListeners();
      });
      c.interfaceAvailable = true;
      c.availabilityDetail = null;
      c.retryAttempt = 0;
      c.epoch++;
      c.peer = transport.state.peer;
      c.detail = transport.state.detail ?? transport.state.peer;
      c.writable = transport.state.writable;
      c.phase = transport.state.listening && !c.writable
          ? ConnectionPhase.listening
          : ConnectionPhase.open;
      notifyListeners();
    } catch (error) {
      if (generation != c.generation) return;
      c.writable = false;
      c.phase = ConnectionPhase.closing;
      try {
        await _teardown(c);
      } catch (closeError) {
        c.detail = '关闭未完成：$closeError';
        notifyListeners();
        rethrow;
      }
      if (generation != c.generation || _disposed) return;
      c.detail = '$error';
      if (c.definition.autoReconnect) {
        _scheduleRetry(c);
        return;
      }
      c.phase = ConnectionPhase.failed;
      c.detail = '$error';
      _releasePhysical(c);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _teardown(_Connection c) =>
      c.teardown ??= _performTeardown(c).whenComplete(() => c.teardown = null);
  Future<void> _performTeardown(_Connection c) async {
    _clearQueue(c, '连接已断开，未执行');
    final transport = c.transport;
    c.transport = null;
    try {
      await c.inputSub?.cancel();
      await c.stateSub?.cancel();
      c.inputSub = null;
      c.stateSub = null;
      await transport?.close();
      // close 成功是独立的结束证明，settled 异常会保留写入屏障。
      c.closedTransport = transport;
      for (final item in c.activeWrites.entries.toList()) {
        final entry = item.value;
        entry.deadline?.cancel();
        if (!entry.result.isCompleted) {
          entry.result.complete(
            SerialWriteResult.failure('连接已关闭，接受数量未知', settled: item.key.future),
          );
        }
        _finishWrite(c, item.key);
      }
      await Future.wait(c.writes.toList());
    } catch (_) {
      c.transport = transport;
      rethrow;
    }
  }

  Future<void> _transportFailed(
    _Connection c,
    CommunicationTransport transport,
    String reason,
  ) async {
    if (!identical(c.transport, transport)) return;
    final generation = c.generation;
    c.writable = false;
    c.detail = reason;
    c.phase = ConnectionPhase.closing;
    notifyListeners();
    try {
      await _teardown(c);
    } catch (error) {
      c.detail = '关闭未完成：$error';
      notifyListeners();
      return;
    }
    if (generation != c.generation || _disposed) return;
    if (c.definition.autoReconnect) {
      _scheduleRetry(c);
    } else {
      c.phase = ConnectionPhase.failed;
      _releasePhysical(c);
      notifyListeners();
    }
  }

  void _releasePhysical(_Connection c) {
    final port = c.definition.serial?.serialPort.toUpperCase();
    if (port != null && _physicalOwners[port] == c.definition.id) {
      _physicalOwners.remove(port);
    }
  }

  Future<SerialWriteResult> _enqueue(
    String id,
    Uint8List bytes,
    int timeoutMs, {
    VoidCallback? onStarted,
    int? expectedEpoch,
    Object? scope,
  }) {
    final c = _connections[id];
    if (c == null ||
        _disposed ||
        (expectedEpoch != null && expectedEpoch != c.epoch)) {
      return Future.value(
        SerialWriteResult.failure('连接或链路轮次已失效', acceptedBytes: 0),
      );
    }
    if (c.task != null && !identical(c.task, scope)) {
      return Future.value(
        SerialWriteResult.failure('连接正在执行协议任务', acceptedBytes: 0),
      );
    }
    if (!_canWrite(c)) {
      return Future.value(
        SerialWriteResult.failure('连接当前不可发送', acceptedBytes: 0),
      );
    }
    if (c.sendEntries >= sendBudget.entries ||
        c.sendBytes + bytes.length > sendBudget.bytes ||
        bytes.length > sendBudget.maxWriteBytes) {
      return Future.value(
        SerialWriteResult.failure('发送队列已满或内容超出预算', acceptedBytes: 0),
      );
    }
    final entry = _QueuedWrite(
      c.epoch,
      scope is _LoopRun ? bytes : Uint8List.fromList(bytes),
      timeoutMs,
      onStarted,
      scope,
      _sessionWriters[id],
    );
    c.sendEntries++;
    c.sendBytes += entry.bytes.length;
    final queued = c.writes.isNotEmpty || c.queue.isNotEmpty;
    c.queue.add(entry);
    if (queued) {
      entry.timer = Timer(sendBudget.queueTimeout, () {
        if (!c.queue.remove(entry)) return;
        _retire(c, entry);
        entry.result.complete(
          SerialWriteResult.failure('排队等待超时，未执行', acceptedBytes: 0),
        );
      });
    }
    _pump(c);
    return entry.result.future;
  }

  bool _canWrite(_Connection c) =>
      c.transport != null && c.writable && c.phase == ConnectionPhase.open;

  void _retire(_Connection c, _QueuedWrite entry) {
    entry.timer?.cancel();
    c.sendEntries--;
    c.sendBytes -= entry.bytes.length;
  }

  void _clearQueue(_Connection c, String reason) {
    while (c.queue.isNotEmpty) {
      final entry = c.queue.removeFirst();
      _retire(c, entry);
      entry.result.complete(
        SerialWriteResult.failure(reason, acceptedBytes: 0),
      );
    }
  }

  void _pump(_Connection c) {
    if (c.writes.isNotEmpty) {
      if (c.queue.isNotEmpty) c.workerLoop?.stop(cancelInFlight: false);
      return;
    }
    if (c.queue.isEmpty) {
      final run = _loops[c.definition.id];
      if (run != null && run.active && run.waitingForWorker) {
        _startWorkerLoop(c, run);
      }
      return;
    }
    final entry = c.queue.removeFirst();
    entry.timer?.cancel();
    if (!_canWrite(c) ||
        c.epoch != entry.epoch ||
        (c.task != null && !identical(c.task, entry.scope)) ||
        (entry.scope is ProtocolTaskChannel &&
            !(entry.scope as ProtocolTaskChannel).active)) {
      _retire(c, entry);
      entry.result.complete(
        SerialWriteResult.failure('连接或链路轮次已失效，未执行', acceptedBytes: 0),
      );
      _pump(c);
      return;
    }
    final transport = c.transport!;
    entry.onStarted?.call();
    final finished = Completer<void>();
    c.writes.add(finished.future);
    c.activeWrites[finished] = entry;
    unawaited(
      finished.future.then((_) {
        _retire(c, entry);
        _pump(c);
      }),
    );
    final deadline = entry.deadline = Timer(
      Duration(milliseconds: entry.timeoutMs),
      () {
        if (!entry.result.isCompleted) {
          entry.result.complete(
            SerialWriteResult.failure(
              '写入等待超时，接受数量未知',
              settled: finished.future,
            ),
          );
        }
      },
    );
    unawaited(() async {
      var confirmed = false;
      try {
        final result = await transport.write(entry.bytes, entry.timeoutMs);
        deadline.cancel();
        final accepted = result.acceptedBytes;
        _recordAccepted(entry.onWritten, entry.bytes, entry.epoch, accepted);
        if (!entry.result.isCompleted) {
          final full =
              result.succeeded && result.acceptedBytes == entry.bytes.length;
          entry.result.complete(
            SerialWriteResult(
              succeeded: full,
              acceptedBytes: result.acceptedBytes,
              reason: result.reason ?? (full ? null : '未完整写入'),
              settled: finished.future,
            ),
          );
        }
        if (result.needsSettlement) await result.settled;
        confirmed = true;
      } catch (error) {
        deadline.cancel();
        if (!entry.result.isCompleted) {
          entry.result.complete(
            SerialWriteResult.failure('$error', settled: finished.future),
          );
        }
      } finally {
        if (confirmed || identical(c.closedTransport, transport)) {
          _finishWrite(c, finished);
        } else if (!finished.isCompleted) {
          c.unknownWrites.add(finished);
          c.detail = '写入结束无法确认，请明确断开连接';
          _bindingsChanged();
        }
      }
    }());
  }

  void _recordAccepted(
    _SessionWriteObserver? observer,
    Uint8List bytes,
    int epoch,
    int? accepted, {
    int? timestampMicros,
    bool takeOwnedPayload = false,
  }) {
    if (observer == null ||
        accepted == null ||
        accepted <= 0 ||
        accepted > bytes.length) {
      return;
    }
    try {
      final prefix = accepted == bytes.length
          ? bytes
          : Uint8List.sublistView(bytes, 0, accepted);
      // worker 回执由独立 isolate 交付。普通适配器的缓冲可能被重用，仍须取快照。
      final snapshot = takeOwnedPayload ? prefix : Uint8List.fromList(prefix);
      observer(
        snapshot.asUnmodifiableView(),
        epoch,
        timestampMicros == null
            ? DateTime.now()
            : DateTime.fromMicrosecondsSinceEpoch(timestampMicros),
      );
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
  }

  void _finishWrite(_Connection c, Completer<void> finished) {
    c.writes.remove(finished.future);
    c.unknownWrites.remove(finished);
    c.activeWrites.remove(finished);
    if (!finished.isCompleted) finished.complete();
  }

  void _scheduleRetry(_Connection c) {
    c.phase = ConnectionPhase.reconnecting;
    c.writable = false;
    final delay = Duration(
      milliseconds:
          (retryBase.inMilliseconds * (1 << c.retryAttempt.clamp(0, 16))).clamp(
            retryBase.inMilliseconds,
            30000,
          ),
    );
    c.retryAttempt++;
    c.retry?.cancel();
    c.retry = Timer(delay, () {
      c.retry = null;
      unawaited(openConnection(c.definition.id));
    });
    notifyListeners();
  }

  Future<void> closeConnection(String id) {
    final c = _connections[id]!;
    return c.closing ??= _closeConnection(id).whenComplete(() {
      c.closing = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _closeConnection(String id) async {
    final c = _connections[id]!;
    if (c.phase == ConnectionPhase.closed) return;
    c.retry?.cancel();
    c.retry = null;
    ++c.generation;
    c.openCancellation?.cancel();
    _clearQueue(c, '连接已断开，未执行');
    c.phase = ConnectionPhase.closing;
    c.writable = false;
    notifyListeners();
    try {
      await c.opening;
    } catch (_) {
      /* 打开失败仍继续回收残留资源。 */
    }
    try {
      await _teardown(c);
    } catch (error) {
      c.detail = '关闭未完成：$error';
      notifyListeners();
      rethrow;
    }
    _releasePhysical(c);
    c.phase = ConnectionPhase.closed;
    notifyListeners();
  }

  Future<void>? _disposing;
  @override
  Future<void> dispose() async {
    if (_disposing != null) {
      await _disposing;
      return;
    }
    _disposing = _disposeRuntime();
    await _disposing;
    _workspaceChanges.dispose();
    super.dispose();
  }

  Future<void> _disposeRuntime() async {
    if (!_configurationReady) await initialize();
    _disposed = true;
    try {
      await _disposeResources();
    } catch (_) {
      // 关闭或刷盘失败仍可重试；不能让一次失败永久跳过资源回收。
      _disposed = false;
      _disposing = null;
      rethrow;
    }
  }

  Future<void> _disposeResources() async {
    final tasks = _connections.values
        .map((c) => c.task)
        .whereType<ProtocolTaskChannel>()
        .toList();
    await flushConfiguration();
    for (final run in _loops.values.toList()) {
      _stopLoopRun(run, '应用已关闭');
    }
    await Future.wait(_connections.keys.map(closeConnection));
    await Future.wait(tasks.map((task) => task._waitReleasedOrFailure()));
    await _closeSessions?.call();
    await _packets.close();
  }
}

class SendBudget {
  const SendBudget({
    this.bytes = 1024 * 1024,
    this.entries = 128,
    this.maxWriteBytes = 1024 * 1024,
    this.queueTimeout = const Duration(seconds: 5),
  });
  final int bytes, entries, maxWriteBytes;
  final Duration queueTimeout;
}

typedef _SessionWriteObserver = void Function(Uint8List, int, DateTime);

class _QueuedWrite {
  _QueuedWrite(
    this.epoch,
    this.bytes,
    this.timeoutMs,
    this.onStarted,
    this.scope,
    this.onWritten,
  );
  final _SessionWriteObserver? onWritten;
  final Object? scope;
  final int epoch, timeoutMs;
  final VoidCallback? onStarted;
  final Uint8List bytes;
  final result = Completer<SerialWriteResult>();
  Timer? timer, deadline;
}

class _Connection {
  _Connection(this.definition);
  ConnectionDefinition definition;
  ProtocolTaskChannel? task;
  SerialWorkerLoop? workerLoop;
  ConnectionPhase phase = ConnectionPhase.closed;
  final Queue<_QueuedWrite> queue = Queue();
  int sendBytes = 0, sendEntries = 0;
  int epoch = 0;
  int sequence = 0;
  String? peer;
  StreamSubscription<TransportInput>? inputSub;
  StreamSubscription<CommunicationTransportState>? stateSub;
  final Set<Future<void>> writes = {};
  final Set<Completer<void>> unknownWrites = {};
  final Map<Completer<void>, _QueuedWrite> activeWrites = {};
  CommunicationTransport? closedTransport;
  int generation = 0;
  int retryAttempt = 0;
  Timer? retry;
  Future<void>? opening;
  TcpConnectCancellation? openCancellation;
  Future<void>? closing;
  Future<void>? teardown;
  bool writable = false;
  String? detail;
  bool? interfaceAvailable;
  String? availabilityDetail;
  CommunicationTransport? transport;
  ConnectionSnapshot get snapshot => ConnectionSnapshot(
    definition: definition,
    phase: phase,
    epoch: epoch,
    writable: writable,
    detail: detail,
    peer: peer,
    interfaceAvailable: interfaceAvailable,
    availabilityDetail: availabilityDetail,
    disconnecting: closing != null || teardown != null,
    operationsSettled:
        opening == null &&
        closing == null &&
        teardown == null &&
        retry == null &&
        transport == null &&
        writes.isEmpty &&
        task == null,
  );
}
