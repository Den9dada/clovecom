import 'dart:async';
import 'dart:typed_data';

import '../core/interaction_protocol.dart';
import 'communication_runtime.dart';
import 'firmware_upgrade.dart';
import 'lua_runtime.dart';

enum FirmwareUpgradePhase { running, succeeded, failed, cancelled, notExecuted }

/// 逐目标协议终态与资源释放状态分别展示，满进度并不表示成功。
class FirmwareUpgradeTarget {
  const FirmwareUpgradeTarget({
    required this.connectionId,
    required this.name,
    required this.taskId,
    required this.epoch,
    required this.protocolDigest,
    required this.phase,
    required this.progress,
    required this.awaitingRelease,
    this.logs = const [],
    this.reason,
    this.releaseFailure,
  });
  final String connectionId, name, taskId, protocolDigest;
  final int epoch;
  final FirmwareUpgradePhase phase;
  final double progress;
  final bool awaitingRelease;
  final String? reason, releaseFailure;
  final List<String> logs;
}

class _FirmwareRun {
  _FirmwareRun(this.start, this.protocol);
  final ProtocolTaskStart start;
  final InteractionProtocol protocol;
  final ownerReleased = Completer<void>();
  LuaRun? lua;
  final logs = <String>[];
  FirmwareUpgradePhase phase = FirmwareUpgradePhase.running;
  double progress = 0;
  String? reason, releaseFailure;
  bool released = false;
  ProtocolTaskChannel? get channel => start.channel;
  FirmwareUpgradeTarget get snapshot => FirmwareUpgradeTarget(
    connectionId: start.connection.id,
    name: start.connection.name,
    taskId: channel?.taskId ?? '',
    epoch: start.connection.epoch,
    protocolDigest: protocol.digest,
    phase: phase,
    progress: progress,
    awaitingRelease: channel != null && !released,
    reason: reason ?? channel?.reason,
    releaseFailure: releaseFailure,
    logs: List.unmodifiable(logs),
  );
}

/// 升级任务由连接持有，关闭升级弹窗后仍可观察进度。
class FirmwareUpgradeController {
  FirmwareUpgradeController(this.communication, this._changed);
  final CommunicationRuntime communication;
  final void Function() _changed;
  final List<_FirmwareRun> _runs = [];
  List<FirmwareUpgradeTarget> get targets =>
      List.unmodifiable(_runs.map((r) => r.snapshot));
  bool get isBusy => _runs.any((r) => r.channel != null && !r.released);

  Future<void> start({
    required String connectionId,
    required InteractionProtocol protocol,
    required LuaRuntime runtime,
    required Future<Uint8List> Function() load,
    required String firmwareName,
  }) async {
    if (_runs.any(
      (run) =>
          run.start.connection.id == connectionId &&
          run.channel != null &&
          !run.released,
    )) {
      throw StateError('升级任务仍在执行或释放中');
    }
    final start = communication.beginProtocolTask(
      connectionId,
      ProtocolTaskKind.firmware,
    );
    if (start == null) return;
    final runs = [_FirmwareRun(start, protocol)];
    _runs.removeWhere((run) => run.start.connection.id == connectionId);
    _runs.addAll(runs);
    // 在异步载入与run构造之前登记owner，堵住取消/启动之间的释放空窗。
    for (final run in runs) {
      final channel = run.channel;
      if (channel == null) {
        run.phase = FirmwareUpgradePhase.notExecuted;
        run.reason = run.start.reason;
        run.released = true;
      } else if (channel.active) {
        channel.holdUntil(run.ownerReleased.future);
        unawaited(
          channel.stopped.then((_) {
            if (run.phase == FirmwareUpgradePhase.running) {
              run.phase = FirmwareUpgradePhase.cancelled;
              run.reason = channel.reason;
              _changed();
            }
            // stopped是及时信号，不能先等待channel.released再取消进程。
            final lua = run.lua;
            if (lua != null) unawaited(lua.cancel().catchError((Object _) {}));
          }),
        );
      }
    }
    _changed();
    if (runs.every((r) => r.channel == null)) return;
    final data = Future<Uint8List>.sync(load)
        .then<({Uint8List? bytes, Object? error})>((bytes) {
          if (bytes.isEmpty) {
            return (bytes: null, error: StateError('固件文件不能为空'));
          }
          if (bytes.length > LuaRuntime.limits['max_firmware_bytes']!) {
            return (
              bytes: null,
              error: const LuaHostError('ResourceLimit', '单次固件超过16 MiB预算'),
            );
          }
          return (
            bytes: Uint8List.fromList(bytes).asUnmodifiableView(),
            error: null,
          );
        }, onError: (Object error) => (bytes: null, error: error));
    await Future.wait(
      runs
          .where((r) => r.channel != null)
          .map((run) => _execute(run, runtime, data, firmwareName)),
    );
  }

  Future<void> _execute(
    _FirmwareRun run,
    LuaRuntime runtime,
    Future<({Uint8List? bytes, Object? error})> data,
    String firmwareName,
  ) async {
    final channel = run.channel!;
    StreamSubscription<UpgradeRunEvent>? subscription;
    Object? releaseError;
    try {
      if (run.phase == FirmwareUpgradePhase.notExecuted) return;
      final loaded = await data;
      await channel.ready;
      if (!channel.active) {
        run.phase = FirmwareUpgradePhase.cancelled;
        run.reason = channel.reason;
        return;
      }
      if (loaded.error != null) throw loaded.error!;
      final lua = runtime.start(
        run.protocol,
        LuaRunContext(
          config: channel.connection.definition.serial!,
          inbound: channel.rawPackets,
          firmware: loaded.bytes!,
          firmwareName: firmwareName,
          target: {
            'connection_id': channel.connection.id,
            'name': channel.connection.name,
            'epoch': channel.connection.epoch,
            'task_id': channel.taskId,
          },
          isClosed: () => !channel.active,
          send: (bytes) async {
            final result = await channel.write(bytes, timeoutMs: 5000);
            if (!result.succeeded) {
              final count = result.acceptedBytes;
              throw LuaHostError(
                count == null ? 'OutcomeUnknown' : 'WriteFailed',
                '${result.reason ?? '本地写入未完整接受'}；${count == null ? '接受数量未知' : '本地接受 $count/${bytes.length} 字节'}',
                {
                  'write_state': count == null
                      ? 'unknown'
                      : count == 0
                      ? 'none'
                      : 'partial',
                  'accepted_bytes': count,
                },
              );
            }
            // 成功回应也必须等待真实native结束；失败由channel独立保留屏障。
            await result.settled;
          },
        ),
      );
      run.lua = lua;
      subscription = lua.events.listen((event) {
        if (run.phase != FirmwareUpgradePhase.running) return;
        if (event.percent != null) run.progress = event.percent! / 100;
        if (event.message != null) _log(run, event.message!);
        if (event.terminal != null) {
          run.phase = switch (event.terminal!) {
            UpgradeTerminal.done => FirmwareUpgradePhase.succeeded,
            UpgradeTerminal.failed => FirmwareUpgradePhase.failed,
            UpgradeTerminal.cancelled => FirmwareUpgradePhase.cancelled,
          };
          run.reason = event.error;
          // raw关闭可同步产生失联终态，外部停止原因在事件回调内已有权威值。
          if (!channel.active && channel.reason != null) {
            run.phase = FirmwareUpgradePhase.cancelled;
            run.reason = channel.reason;
          }
          if (run.phase == FirmwareUpgradePhase.succeeded) {
            run.progress = 1;
            _log(run, 'Lua 协议升级完成');
          }
          unawaited(channel.finish());
        }
        _changed();
      });
      if (!channel.active) unawaited(lua.cancel().catchError((Object _) {}));
      try {
        await lua.released;
      } catch (error) {
        releaseError = error;
        rethrow;
      }
    } catch (error) {
      if (run.phase == FirmwareUpgradePhase.running) {
        run.phase = channel.active
            ? FirmwareUpgradePhase.failed
            : FirmwareUpgradePhase.cancelled;
        run.reason = channel.active ? '$error' : channel.reason;
      }
    } finally {
      await subscription?.cancel();
      run.lua = null;
      if (releaseError == null) {
        run.ownerReleased.complete();
      } else {
        run.releaseFailure = '$releaseError';
        run.ownerReleased.completeError(releaseError);
      }
      unawaited(channel.finish());
      await Future.any([
        channel.released.then((_) => run.released = true),
        channel.releaseFailure.then((error) => run.releaseFailure = '$error'),
      ]);
      _changed();
    }
  }

  void _log(_FirmwareRun run, String message) {
    if (run.logs.length >= 200) run.logs.removeAt(0);
    run.logs.add(message);
  }

  void discard(String id) {
    cancel(connectionId: id);
    _runs.removeWhere((run) => run.start.connection.id == id);
  }

  void cancel({String? connectionId}) {
    for (final run in _runs) {
      if (connectionId != null && run.start.connection.id != connectionId) {
        continue;
      }
      final channel = run.channel;
      if (channel?.active == true) unawaited(channel!.cancel());
    }
  }
}
