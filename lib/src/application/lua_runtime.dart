// 公开依赖参数映射到私有实现字段。
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../io/recording.dart';
import '../core/interaction_protocol.dart';
import '../io/connections.dart';
import 'firmware_upgrade.dart';

class LuaHostError implements Exception {
  const LuaHostError(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Object? details;
  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (details != null) 'details': details,
  };
  @override
  String toString() => '$code：$message';
}

/// 每次执行固定一个物理会话；测试可注入同样的字节、写入及运行时接口。
class LuaRunContext {
  LuaRunContext({
    required this.config,
    required this.inbound,
    required this.send,
    this.sendTo,
    this.lastPeer,
    Map<String, dynamic> runtimeSchema = const {},
    this.readRuntime,
    this.writeRuntime,
    this.isClosed,
    Uint8List? firmware,
    this.firmwareName = 'firmware.bin',
    Map<String, dynamic> target = const {},
    this.peerIsManaged = false,
  }) : firmware = _firmwareSnapshot(firmware),
       target = _frozenMap(target),
       runtimeSchema = _frozenMap(runtimeSchema);
  final ConnectionConfig config;
  final Stream<RawPacket> inbound;
  final Future<void> Function(Uint8List) send;
  final Future<void> Function(Uint8List, String, int)? sendTo;
  final String? lastPeer;
  final Map<String, dynamic> runtimeSchema;
  final Future<Map<String, dynamic>> Function()? readRuntime;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  writeRuntime;
  final bool Function()? isClosed;
  final Uint8List? firmware;
  final String firmwareName;
  final Map<String, dynamic> target;
  final bool peerIsManaged;
}

/// 发布版只使用应用随附的解释器，开发/测试允许使用本工作区构建产物。
class LuaRuntime {
  LuaRuntime({String? executable, String? sdk})
    : _executable = executable,
      _sdk = sdk;
  final String? _executable;
  final String? _sdk;
  static const limits = <String, int>{
    'max_frame_bytes': 65536,
    'max_rx_bytes': 1048576,
    'max_queued_frames': 4096,
    'max_write_bytes': 65536,
    'max_artifact_read_bytes': 65536,
    'max_log_entry_bytes': 4096,
    'max_processes': 4,
    'max_firmware_bytes': 16777216,
    'max_rx_packets': 4096,
  };

  static int _processes = 0;
  static bool _reserveProcess() {
    if (_processes >= limits['max_processes']!) return false;
    _processes++;
    return true;
  }

  ({String executable, String sdk}) get paths {
    final app = File(Platform.resolvedExecutable).parent.path;
    final executableCandidates = [
      ?_executable,
      '$app/lua/clovertls_lua_runner.exe',
      if (!const bool.fromEnvironment('dart.vm.product')) ...[
        '${Directory.current.path}/build/lua_runner/Release/clovertls_lua_runner.exe',
        '${Directory.current.path}/build/lua_runner/clovertls_lua_runner',
      ],
    ];
    final executable = executableCandidates
        .where((p) => File(p).existsSync())
        .firstOrNull;
    final sdkCandidates = [
      ?_sdk,
      if (executable != null) '${File(executable).parent.path}/host_sdk.lua',
      if (!const bool.fromEnvironment('dart.vm.product'))
        '${Directory.current.path}/native/lua_runner/host_sdk.lua',
    ];
    final sdk = sdkCandidates.where((p) => File(p).existsSync()).firstOrNull;
    if (executable == null || sdk == null) {
      throw const LuaHostError(
        'RuntimeUnavailable',
        'Lua 工作进程未随应用安装，请重新构建 Windows 应用',
      );
    }
    return (
      executable: File(executable).absolute.path,
      sdk: File(sdk).absolute.path,
    );
  }

  Future<List<ScriptDiagnostic>> validate(InteractionProtocol protocol) async {
    final diagnostics = <ScriptDiagnostic>[];
    try {
      protocol.metadata;
    } catch (error) {
      diagnostics.add(ScriptDiagnostic('$error', line: 1));
    }
    Process? process;
    var permit = false, exited = false;
    try {
      permit = _reserveProcess();
      if (!permit) throw const LuaHostError('ResourceLimit', 'Lua进程总量超过4个');
      final location = paths;
      process = await Process.start(location.executable, [
        location.sdk,
        '--check',
      ], runInShell: false);
      Future<({String? text, Object? error})> capture(
        Stream<List<int>> stream,
      ) => _boundedText(stream).then<({String? text, Object? error})>(
        (text) => (text: text, error: null),
        onError: (Object error) {
          process?.kill();
          return (text: null, error: error);
        },
      );
      final output = capture(process.stdout), errors = capture(process.stderr);
      process.stdin.writeln(jsonEncode({'source': protocol.source}));
      await process.stdin.close();
      final exit = await process.exitCode.timeout(const Duration(seconds: 5));
      exited = true;
      final stdout = await output, stderr = await errors;
      if (stdout.error != null) throw stdout.error!;
      if (stderr.error != null) throw stderr.error!;
      if (exit != 0) {
        throw LuaHostError(
          'RuntimeUnavailable',
          stderr.text!.isEmpty ? 'Lua校验进程异常退出' : stderr.text!,
        );
      }
      final result = jsonDecode(stdout.text!) as Map<String, dynamic>;
      if (result['valid'] != true) {
        final message = result['error'] as String? ?? 'Lua语法错误';
        final line = RegExp(r'protocol\.lua:(\d+):').firstMatch(message);
        diagnostics.add(
          ScriptDiagnostic(
            message,
            line: line == null ? null : int.parse(line.group(1)!),
          ),
        );
      }
    } catch (error) {
      diagnostics.add(ScriptDiagnostic('无法校验脚本：$error'));
    } finally {
      if (process != null && !exited) {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
          exited = true;
        } catch (_) {
          // 未确认退出时仍占进程预算，不能把kill请求当结束证明。
        }
      }
      if (permit && (process == null || exited)) _processes--;
    }
    return List.unmodifiable(diagnostics);
  }

  LuaRun start(InteractionProtocol protocol, LuaRunContext context) =>
      LuaRun._(this, protocol, context);
}

Map<String, dynamic> scriptSourceConfig(ConnectionConfig config) => {
  'source_id': config.id,
  'config_revision': jsonEncode(config.toJson()),
  'kind': config.kind.name,
  'interface': {
    if (config.kind == TransportKind.serial) ...{
      'serial_port': config.serialPort,
      'baud_rate': config.baudRate,
      'data_bits': config.dataBits,
      'stop_bits': config.stopBits,
      'parity': const ['none', 'odd', 'even', 'mark', 'space'][config.parity],
      'flow_control': config.flowControl,
    } else ...{
      'host': config.host,
      'port': config.port,
      if (config.remoteHost != null) 'remote_host': config.remoteHost,
      if (config.remotePort != null) 'remote_port': config.remotePort,
    },
  },
};

class LuaRun implements UpgradeRun {
  LuaRun._(this.runtime, this.protocol, this.context) {
    _subscription = context.inbound.listen(
      _receive,
      onError: (Object error) =>
          _finish(UpgradeTerminal.failed, error: 'Disconnected：$error'),
      onDone: () =>
          _finish(UpgradeTerminal.failed, error: 'SessionLost：物理会话已关闭'),
    );
    _hasProcessPermit = LuaRuntime._reserveProcess();
    _pin = _configuredPeer();
    // 返回句柄后再启动，订阅者不会错过同步失败或第一个进度事件。
    unawaited(Future<void>.delayed(Duration.zero, _start));
  }
  final LuaRuntime runtime;
  late final bool _hasProcessPermit;
  final InteractionProtocol protocol;
  final LuaRunContext context;
  final _events = StreamController<UpgradeRunEvent>.broadcast(sync: true);
  final _released = Completer<void>();
  final _interruptions = StreamController<void>.broadcast(sync: true);
  final _clock = Stopwatch()..start();
  final Queue<Map<String, dynamic>> _incoming = Queue();
  final Set<Future<void>> _writes = {};
  late final StreamSubscription<RawPacket> _subscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  Completer<void>? _available;
  Process? _process;
  Future<Process>? _spawning;
  Timer? _watchdog;
  String _stderr = '';
  bool _revoked = false;
  bool _cancelled = false;
  int _queuedBytes = 0;
  int _sequence = 0;
  int _operationCount = 0;
  int _runLimit = 3600000;
  Map<String, dynamic>? _pin;
  Map<String, dynamic>? _baseline;
  Map<String, dynamic>? resultData;
  Map<String, dynamic>? progress;
  final String sessionId = 'run-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Stream<UpgradeRunEvent> get events => Stream.multi((controller) {
    final subscription = _events.stream.listen(
      controller.addSync,
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    controller.onCancel = subscription.cancel;
    controller.onPause = () {
      // 立刻脱离事件源；只保留关闭通知，暂停不能变成无界Stream邮箱。
      unawaited(subscription.cancel());
      controller.closeSync();
      scheduleMicrotask(
        () =>
            _finish(UpgradeTerminal.failed, error: 'ResourceLimit：Lua事件观察已暂停'),
      );
    };
  }, isBroadcast: true);
  @override
  Future<void> get released => _released.future;

  Map<String, dynamic>? _configuredPeer() {
    final c = context.config;
    if (c.kind != TransportKind.udp) return null;
    if (c.remoteHost != null) {
      return {'host': c.remoteHost, 'port': c.remotePort};
    }
    final peer = context.lastPeer;
    if (peer == null) return null;
    final split = peer.lastIndexOf(':');
    if (split < 0) return null;
    final port = int.tryParse(peer.substring(split + 1));
    return port == null
        ? null
        : {'host': peer.substring(0, split), 'port': port};
  }

  void _receive(RawPacket packet) {
    if (_revoked) return;
    if (!context.peerIsManaged && packet.datagram && packet.peer != null) {
      final split = packet.peer!.lastIndexOf(':');
      if (split >= 0) {
        final peer = {
          'host': packet.peer!.substring(0, split),
          'port': int.tryParse(packet.peer!.substring(split + 1)),
        };
        _pin ??= peer;
        if (peer['host'] != _pin!['host'] || peer['port'] != _pin!['port']) {
          return;
        }
      }
    }
    if (_queuedBytes + packet.bytes.length >
            LuaRuntime.limits['max_rx_bytes']! ||
        _incoming.length >= LuaRuntime.limits['max_rx_packets']!) {
      _finish(UpgradeTerminal.failed, error: 'BufferOverflow：脚本接收队列超限');
      return;
    }
    _queuedBytes += packet.bytes.length;
    _incoming.add({
      'hex': _hex(packet.bytes),
      'connection_id': packet.connectionId,
      'epoch': packet.epoch,
      'source_sequence': packet.sequence,
      'received_at': packet.receivedAt.toUtc().toIso8601String(),
      'byte_length': packet.bytes.length,
      'datagram': packet.datagram,
      'peer': packet.peer,
      'rx_seq': ++_sequence,
      'session_id': sessionId,
      'first_received_at': _clock.elapsedMilliseconds,
      'last_received_at': _clock.elapsedMilliseconds,
    });
    _available?.complete();
    _available = null;
  }

  Future<void> _start() async {
    try {
      _ensureActive();
      if (!_hasProcessPermit) {
        throw const LuaHostError('ResourceLimit', 'Lua进程总量超过4个，请等待其他运行释放');
      }
      if ((context.firmware?.length ?? 0) >
          LuaRuntime.limits['max_firmware_bytes']!) {
        throw const LuaHostError('ResourceLimit', '单次固件超过16 MiB预算');
      }
      final metadata = protocol.metadata;
      if (!metadata.transports.contains(context.config.kind.name)) {
        throw const LuaHostError('CapabilityDenied', '脚本不支持当前数据源类型');
      }
      final limit = metadata.limits['run_timeout_ms'];
      if (limit != null) _runLimit = _int(limit, 'run_timeout_ms', 1, 86400000);
      _watchdog = Timer(
        Duration(milliseconds: _runLimit),
        () => _finish(UpgradeTerminal.failed, error: 'ResourceLimit：脚本总运行期限已到'),
      );
      final capabilities = <String, bool>{
        'link.channel': true,
        'link.raw': true,
        'data_source.config.read': true,
        'data_source.runtime.read': true,
        'data_source.runtime.serial.lines': context.runtimeSchema.isNotEmpty,
        'input.firmware': context.firmware != null,
      };
      for (final required in metadata.requiredCapabilities) {
        if (capabilities[required] != true) {
          throw LuaHostError('CapabilityDenied', '缺少必需能力：$required');
        }
      }
      final initial = metadata.dataSource['runtime_initial'];
      if (initial is Map && initial.isNotEmpty) {
        await _setRuntime(Map<String, dynamic>.from(initial), _runLimit);
      }
      _ensureActive();
      final location = runtime.paths;
      _spawning = Process.start(location.executable, [
        location.sdk,
      ], runInShell: false);
      final process = await _spawning!;
      _process = process;
      if (_revoked) {
        process.kill();
        return;
      }
      _stderrSubscription = process.stderr.listen((data) {
        if (_stderr.length < 16384) {
          final text = utf8.decode(data, allowMalformed: true);
          final remaining = 16384 - _stderr.length;
          _stderr += text.length <= remaining
              ? text
              : text.substring(0, remaining);
        }
      });
      process.stdin.writeln(
        jsonEncode({
          'source': protocol.source,
          'limits': LuaRuntime.limits,
          'capabilities': capabilities,
          'source_config': scriptSourceConfig(context.config),
          'link': {
            'transport': context.config.kind.name,
            'datagram': context.config.kind == TransportKind.udp,
            'session_id': sessionId,
            'peer': _pin,
          },
          'target': context.target,
          if (context.firmware != null)
            'firmware': {
              'id': 'firmware',
              'display_name': context.firmwareName,
              'size': context.firmware!.length,
            },
        }),
      );
      _log('[Lua ${protocol.name} ${protocol.digest.substring(0, 8)}] 开始执行');
      var buffer = '';
      await for (final chunk in process.stdout.transform(utf8.decoder)) {
        buffer += chunk;
        if (buffer.length > 1048576 || utf8.encode(buffer).length > 1048576) {
          throw const LuaHostError('ResourceLimit', '工作进程输出行超限');
        }
        while (buffer.contains('\n')) {
          final end = buffer.indexOf('\n');
          final line = buffer.substring(0, end);
          buffer = buffer.substring(end + 1);
          if (line.isNotEmpty) await _handleLine(line);
        }
      }
      final exit = await process.exitCode;
      if (!_revoked) {
        _finish(
          UpgradeTerminal.failed,
          error: 'ScriptError：脚本未提供终态，退出码 $exit $_stderr',
        );
      }
    } catch (error) {
      _finish(
        _cancelled ? UpgradeTerminal.cancelled : UpgradeTerminal.failed,
        error: '$error',
      );
    }
  }

  void _log(String message) {
    final bytes = utf8.encode(message);
    var clipped = message;
    if (bytes.length > LuaRuntime.limits['max_log_entry_bytes']!) {
      // 留出截断提示及半个UTF8字符的替换空间，最终仍不超过4KiB。
      final prefix = utf8.decode(bytes.sublist(0, 4064), allowMalformed: true);
      clipped = '$prefix…（截断）';
    }
    _events.add(UpgradeRunEvent.log(clipped));
  }

  void _ensureActive() {
    if (_revoked || _cancelled) {
      throw const LuaHostError('Cancelled', '运行权限已撤销');
    }
    if (context.isClosed?.call() == true) {
      throw const LuaHostError('SessionLost', '物理会话已关闭');
    }
  }

  int _deadline(Map<String, dynamic> args) {
    final value = args['deadline'];
    return value == null
        ? _runLimit
        : _int(value, 'deadline', 0, 9007199254740991).clamp(0, _runLimit);
  }

  Future<T> _wait<T>(
    Future<T> operation,
    int deadline, {
    bool write = false,
  }) async {
    _ensureActive();
    final result = Completer<T>();
    final left = deadline - _clock.elapsedMilliseconds;
    if (left <= 0) {
      throw LuaHostError(write ? 'OutcomeUnknown' : 'Timeout', '操作期限已到');
    }
    final timer = Timer(Duration(milliseconds: left), () {
      if (!result.isCompleted) {
        result.completeError(
          LuaHostError(
            write ? 'OutcomeUnknown' : 'Timeout',
            '操作超时',
            write ? {'write_state': 'unknown'} : null,
          ),
        );
      }
    });
    final subscription = _interruptions.stream.listen((_) {
      if (!result.isCompleted) {
        result.completeError(const LuaHostError('Cancelled', '运行已停止'));
      }
    });
    unawaited(
      operation.then(
        (value) {
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    try {
      return await result.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<void> _handleLine(String line) async {
    if (_revoked) return;
    final message = jsonDecode(line) as Map<String, dynamic>;
    if (message['event'] == 'result') {
      if (message['ok'] == true && !_cancelled) {
        resultData = _frozenMap(
          Map<String, dynamic>.from(message['value'] as Map),
        );
        if (jsonEncode(resultData).length > 65536) {
          throw const LuaHostError('ResourceLimit', '流程结果超过 64 KiB');
        }
        _finish(UpgradeTerminal.done);
      } else {
        _finish(
          _cancelled ? UpgradeTerminal.cancelled : UpgradeTerminal.failed,
          error: jsonEncode(message['error']),
        );
      }
      return;
    }
    final id = message['id'];
    if (id is! int || id != ++_operationCount) {
      throw const LuaHostError('ProtocolViolation', 'IPC 请求编号无效');
    }
    final args = Map<String, dynamic>.from(message['args'] as Map? ?? const {});
    try {
      final value = await _dispatch(message['op'] as String, args);
      if (!_revoked) {
        _process!.stdin.writeln(
          jsonEncode({'id': id, 'ok': true, 'value': value}),
        );
        await _process!.stdin.flush();
      }
    } catch (error) {
      if (!_revoked) {
        final detail = error is LuaHostError
            ? error.toJson()
            : {
                'code': error is UnsupportedError
                    ? 'UnsupportedSetting'
                    : 'HostError',
                'message': '$error',
              };
        _process!.stdin.writeln(
          jsonEncode({'id': id, 'ok': false, 'error': detail}),
        );
        await _process!.stdin.flush();
      }
    }
  }

  Future<Object?> _dispatch(String op, Map<String, dynamic> args) async {
    _ensureActive();
    final deadline = _deadline(args);
    switch (op) {
      case 'now':
        return _clock.elapsedMilliseconds;
      case 'check':
        return true;
      case 'mark':
        return _sequence;
      case 'sleep':
        final ms = _int(args['ms'], '延时', 0, 86400000);
        final done = Completer<void>();
        final timer = Timer(Duration(milliseconds: ms), done.complete);
        try {
          await _wait(done.future, deadline);
        } finally {
          timer.cancel();
        }
        return null;
      case 'receive':
        while (_incoming.isEmpty) {
          _available ??= Completer<void>();
          await _wait(_available!.future, deadline);
        }
        final packet = _incoming.removeFirst();
        _queuedBytes -= packet['byte_length'] as int;
        return packet;
      case 'discard':
        final count = _incoming.length, bytes = _queuedBytes;
        _incoming.clear();
        _queuedBytes = 0;
        _log('脚本主动丢弃 $count 个接收块：${args['reason']}');
        return {'bytes': bytes, 'packets': count};
      case 'send':
        if (deadline <= _clock.elapsedMilliseconds) {
          throw const LuaHostError('Timeout', '发送前期限已到', {
            'write_state': 'none',
          });
        }
        final data = _unhex(args['hex'] as String);
        if (data.length > LuaRuntime.limits['max_write_bytes']!) {
          throw const LuaHostError('ResourceLimit', '发送块超过上限');
        }
        if (args['peer'] != null) {
          throw const LuaHostError('CapabilityDenied', '首期只允许向固定对端发送');
        }
        final Future<void> sending;
        if (context.config.kind == TransportKind.udp &&
            !context.peerIsManaged) {
          if (_pin == null || context.sendTo == null) {
            throw const LuaHostError(
              'DestinationUnavailable',
              'UDP 无固定对端，请先配置远端地址或等待设备上报',
            );
          }
          sending = Future.sync(
            () => context.sendTo!(
              data,
              _pin!['host'] as String,
              _pin!['port'] as int,
            ),
          );
        } else {
          sending = Future.sync(() => context.send(data));
        }
        _writes.add(sending);
        unawaited(
          sending.then(
            (_) => _writes.remove(sending),
            onError: (Object _) => _writes.remove(sending),
          ),
        );
        await _wait(sending, deadline, write: true);
        return {
          'write_id': _operationCount,
          'accepted_bytes': data.length,
          'completion_layer': 'transport_write',
          'completed_at': _clock.elapsedMilliseconds,
        };
      case 'drain':
        await _wait(Future.wait(_writes.toList()), deadline);
        return {'completion_layer': 'host_queue'};
      case 'firmware_read':
        final data = context.firmware;
        if (data == null) {
          throw const LuaHostError('CapabilityDenied', '本流程没有固件输入');
        }
        final offset = _int(args['offset'], '固件偏移', 0, data.length);
        final count = _int(
          args['length'],
          '固件块长度',
          0,
          LuaRuntime.limits['max_artifact_read_bytes']!,
        );
        if (count > data.length - offset) {
          throw const LuaHostError('RangeError', '固件读取越界');
        }
        return _hex(Uint8List.sublistView(data, offset, offset + count));
      case 'progress':
        final done = args['completed'], total = args['total'];
        if ((done == null) != (total == null)) {
          throw const LuaHostError('InvalidArgument', '进度需同时提供完成量和总量');
        }
        if (total != null) {
          final n = _int(total, '总量', 0, 9007199254740991);
          final d = _int(done, '完成量', 0, n);
          if (n > 0) {
            _events.add(
              UpgradeRunEvent.progress((d * 100 / n).round().clamp(0, 100)),
            );
          }
        }
        progress = _frozenMap(args);
        if (args['message'] != null) {
          _log('${args['stage'] ?? ''}：${args['message']}');
        }
        return null;
      case 'log':
        if (_operationCount > 500 &&
            _operationCount * 1000 >
                (_clock.elapsedMilliseconds + 1000) * 1000) {
          throw const LuaHostError('ResourceLimit', '宿主请求速率过高，请减少逐字节日志并合并操作');
        }
        final text =
            '${args['level'] ?? 'info'} ${args['message'] ?? ''}'
            '${args['fields'] == null ? '' : ' ${jsonEncode(args['fields'])}'}';
        _log(text);
        return null;
      case 'source_describe':
        return {
          'source_id': context.config.id,
          'kind': context.config.kind.name,
          'runtime_schema': context.runtimeSchema,
          'config_access': 'read',
          'persistent_writes': false,
        };
      case 'source_get':
        final values = await _wait(
          context.readRuntime?.call().then(_frozenMap) ??
              Future.value(<String, dynamic>{}),
          deadline,
        );
        return {
          'session_id': sessionId,
          'observed_at': _clock.elapsedMilliseconds,
          'values': values,
          'provenance': {
            'serial.rts': 'configured',
            'serial.dtr': 'configured',
          },
          'unavailable': [
            for (final key in ['cts', 'dsr', 'ri', 'cd', 'rts', 'dtr'])
              if (!((values['serial'] as Map?)?.containsKey(key) ?? false))
                'serial.$key',
          ],
        };
      case 'source_set':
        return _setRuntime(
          Map<String, dynamic>.from(args['patch'] as Map),
          deadline,
        );
      case 'fail':
        // 失败不可被脚本 pcall 吞掉；先锁存宿主终态并撤销发送权。
        _finish(
          UpgradeTerminal.failed,
          error: '${args['code']}：${args['message']}',
        );
        return null;
      default:
        throw LuaHostError('CapabilityDenied', '不支持的宿主操作：$op');
    }
  }

  Future<Map<String, dynamic>> _setRuntime(
    Map<String, dynamic> patch,
    int deadline,
  ) async {
    if (context.writeRuntime == null || context.readRuntime == null) {
      throw const LuaHostError('UnsupportedSetting', '当前数据源不支持运行时设置');
    }
    if (patch.keys.any((key) => key != 'serial') || patch['serial'] is! Map) {
      throw const LuaHostError('ConfigReadOnly', '只能修改运行时控制，接口参数只读');
    }
    final fields = Map<String, dynamic>.from(patch['serial'] as Map);
    for (final entry in fields.entries) {
      if (!['rts', 'dtr'].contains(entry.key)) {
        throw const LuaHostError('SettingReadOnly', '输入信号不可写');
      }
      if (entry.value is! bool) {
        throw const LuaHostError('InvalidArgument', '控制线必须为布尔值');
      }
      final schema = context.runtimeSchema['serial.${entry.key}'] as Map?;
      if (schema == null || schema['supported'] != true) {
        throw const LuaHostError('UnsupportedSetting', '当前设备不支持该控制线');
      }
      if (schema['access'] != 'read_write') {
        throw const LuaHostError('SettingManagedByDriver', '控制线由流控管理');
      }
    }
    if (_baseline == null) {
      final values = await _wait(
        context.readRuntime!.call().then(_frozenMap),
        deadline,
      );
      _ensureActive();
      final serial = values['serial'] as Map? ?? const {};
      _baseline = {
        'serial': {
          for (final key in ['rts', 'dtr'])
            if (serial[key] is bool &&
                (context.runtimeSchema['serial.$key'] as Map?)?['access'] ==
                    'read_write')
              key: serial[key],
        },
      };
    }
    if (fields.keys.any(
      (key) => !(_baseline!['serial'] as Map).containsKey(key),
    )) {
      throw const LuaHostError('UnsupportedSetting', '无法读取控制线基线，不能保证运行后恢复');
    }
    _ensureActive();
    final operation = context.writeRuntime!(_frozenMap(patch)).then(_frozenMap);
    final tracked = operation.then<void>((_) {});
    _writes.add(tracked);
    unawaited(
      tracked.then(
        (_) => _writes.remove(tracked),
        onError: (Object _) => _writes.remove(tracked),
      ),
    );
    final receipt = await _wait(operation, deadline, write: true);
    return {
      ...receipt,
      'session_id': sessionId,
      'observed_at': _clock.elapsedMilliseconds,
    };
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    _finish(UpgradeTerminal.cancelled);
    await released;
  }

  void _finish(UpgradeTerminal terminal, {String? error}) {
    if (_revoked) return;
    _revoked = true;
    _watchdog?.cancel();
    _interruptions.add(null);
    _events.add(UpgradeRunEvent.finished(terminal, error: error));
    unawaited(_release());
  }

  Future<void> _release() async {
    Object? failure;
    StackTrace? failureStack;
    Future<void> clean(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await clean(() async {
      Process? process = _process;
      if (process == null && _spawning != null) {
        try {
          process = await _spawning;
        } catch (_) {
          // Process.start失败没有创建进程；继续清理订阅与host操作。
        }
      }
      if (process != null) {
        unawaited(process.stdin.close().catchError((Object _) {}));
        try {
          await process.exitCode.timeout(const Duration(milliseconds: 250));
        } on TimeoutException {
          process.kill();
          await process.exitCode.timeout(const Duration(seconds: 3));
        }
      }
      if (_hasProcessPermit) LuaRuntime._processes--;
    });
    await clean(_subscription.cancel);
    _incoming.clear();
    _queuedBytes = 0;
    // 写结果期限不是资源结束证明，真实清理完成前不释放owner。
    await clean(
      () =>
          Future.wait(_writes.toList().map((f) => f.catchError((Object _) {}))),
    );
    if (_baseline != null &&
        context.isClosed?.call() != true &&
        (_baseline!['serial'] as Map).isNotEmpty) {
      await clean(() => context.writeRuntime!(_frozenMap(_baseline!)));
    }
    await clean(() async {
      await _stderrSubscription?.cancel();
    });
    await clean(_interruptions.close);
    await clean(_events.close);
    if (failure == null) {
      _released.complete();
    } else {
      // 每项清理至多尝试一次；异常必须通知owner，保留任务独占；未退出的进程继续占预算。
      _released.completeError(failure!, failureStack);
    }
  }
}

int _int(Object? value, String name, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw LuaHostError('RangeError', '$name 超出范围');
  }
  return value;
}

String _hex(List<int> data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Uint8List _unhex(String value) {
  if (value.length.isOdd ||
      value.length > 131072 ||
      !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw const LuaHostError('InvalidArgument', '无效或过长的字节内容');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

/// 先跨JSON边界复制，再递归冻结；嵌套对象不借用调用方或其他目标状态。
Map<String, dynamic> _frozenMap(Map<String, dynamic> value) =>
    _freezeJson(jsonDecode(jsonEncode(value))) as Map<String, dynamic>;
Object? _freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, item) => MapEntry(key as String, _freezeJson(item))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeJson));
  return value;
}

Uint8List? _firmwareSnapshot(Uint8List? bytes) {
  if (bytes == null) return null;
  if (bytes.length > LuaRuntime.limits['max_firmware_bytes']!) {
    throw const LuaHostError('ResourceLimit', '单次固件超过16 MiB预算');
  }
  return Uint8List.fromList(bytes).asUnmodifiableView();
}

Future<String> _boundedText(Stream<List<int>> stream) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > 1048576) {
      throw const LuaHostError('ResourceLimit', '工作进程输出超过1 MiB');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}
