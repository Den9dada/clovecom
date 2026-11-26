import 'dart:io';

import 'package:path/path.dart' as path;

import 'dart:async';
import 'dart:typed_data';

import '../../protocols/transfer_protocol.dart';
import '../../protocols/ymodem_protocol.dart';
import 'communication_runtime.dart';

/// 协议结果与本地写入接受结果分开，释放中仍保留对应连接的独占。
enum FileTransferPhase { running, succeeded, failed, cancelled, notExecuted }

class FileTransferTarget {
  const FileTransferTarget({
    required this.connectionId,
    required this.name,
    required this.taskId,
    required this.kind,
    required this.phase,
    required this.progress,
    required this.transferredBytes,
    required this.totalBytes,
    required this.awaitingRelease,
    required this.logs,
    this.reason,
    this.outputPath,
  });
  final String connectionId, name, taskId;
  final ProtocolTaskKind kind;
  final FileTransferPhase phase;
  final double progress;
  final int transferredBytes, totalBytes;
  final bool awaitingRelease;
  final List<String> logs;
  final String? reason, outputPath;
}

class _FileRun {
  _FileRun(this.start, this.kind);
  final ProtocolTaskStart start;
  final ProtocolTaskKind kind;
  FileTransferPhase phase = FileTransferPhase.running;
  double progress = 0;
  int transferredBytes = 0, totalBytes = 0;
  String? reason, outputPath;
  bool released = false;
  final List<String> logs = [];
  int logBytes = 0;
  ProtocolTaskChannel? get channel => start.channel;
  FileTransferTarget get snapshot => FileTransferTarget(
    connectionId: start.connection.id,
    name: start.connection.name,
    taskId: channel?.taskId ?? '',
    kind: kind,
    phase: phase == FileTransferPhase.running && channel?.active == false
        ? FileTransferPhase.cancelled
        : phase,
    progress: progress,
    transferredBytes: transferredBytes,
    totalBytes: totalBytes,
    awaitingRelease: channel != null && !released,
    logs: List.unmodifiable(logs),
    reason: reason ?? channel?.reason,
    outputPath: outputPath,
  );
}

/// 生命周期属于对应连接；Widget销毁后任务与结果继续保留。
class FileTransferController {
  FileTransferController(this.runtime, this._changed);
  final CommunicationRuntime runtime;
  final void Function() _changed;
  final List<_FileRun> _runs = [];
  List<FileTransferTarget> get targets =>
      List.unmodifiable(_runs.map((r) => r.snapshot));
  bool get isBusy => _runs.any((r) => r.channel != null && !r.released);

  List<_FileRun> _begin(ProtocolTaskKind kind, String connectionId) {
    if (_runs.any(
      (run) =>
          run.start.connection.id == connectionId &&
          run.channel != null &&
          !run.released,
    )) {
      throw StateError('文件任务仍在执行或释放中');
    }
    final start = runtime.beginProtocolTask(connectionId, kind);
    if (start == null) return const [];
    final run = _FileRun(start, kind);
    if (run.channel == null) {
      run.phase = FileTransferPhase.notExecuted;
      run.reason = start.reason;
      run.released = true;
    }
    _runs.removeWhere((run) => run.start.connection.id == connectionId);
    _runs.add(run);
    _changed();
    return [run];
  }

  Future<void> startSend({
    required Future<Uint8List> Function() load,
    required String fileName,
    required String connectionId,
    int packetSize = 1024,
    int intervalMs = 0,
    TransferProtocol Function()? protocolFactory,
  }) async {
    final runs = _begin(ProtocolTaskKind.fileSend, connectionId);
    // 先登记任务输入，再异步读取文件。
    if (runs.every((r) => r.channel == null)) return;
    final data = Future<Uint8List>.sync(load)
        .then<({Uint8List? bytes, Object? error})>(
          (bytes) => (
            bytes: Uint8List.fromList(bytes).asUnmodifiableView(),
            error: null,
          ),
          onError: (Object error) => (bytes: null, error: error),
        );
    await Future.wait(
      runs
          .where((r) => r.channel != null)
          .map(
            (run) => _execute(run, () async {
              final loaded = await data;
              if (loaded.error != null) throw loaded.error!;
              final bytes = loaded.bytes!;
              if (!run.channel!.active) return;
              run.totalBytes = bytes.length;
              final protocol = (protocolFactory ?? YmodemProtocol.new)();
              await protocol.send(
                bytes,
                packetSize: packetSize,
                intervalMs: intervalMs,
                callbacks: _callbacks(run, fileName: fileName),
              );
            }),
          ),
    );
  }

  Future<void> startReceive({
    String savePath = '',
    required String connectionId,
    String defaultDirectory = '',
    TransferProtocol Function()? protocolFactory,
  }) async {
    if (savePath.isEmpty && defaultDirectory.isEmpty) {
      throw StateError('请先选择保存路径或默认存储目录');
    }
    final runs = _begin(ProtocolTaskKind.fileReceive, connectionId);
    final multiple = runs.where((r) => r.channel != null).length > 1;
    await Future.wait(
      runs
          .where((r) => r.channel != null)
          .map(
            (run) => _execute(run, () async {
              final channel = run.channel!;
              final root = savePath.isEmpty
                  ? defaultDirectory
                  : path.dirname(savePath);
              final safeId = Uri.encodeComponent(run.start.connection.id);
              await Directory(root).create(recursive: true);
              final folder = await Directory(root)
                  .createTemp('$safeId-${channel.taskId}-');
              final completed = await Directory(
                path.join(folder.path, 'completed'),
              ).create();
              if (!channel.active) return;
              final temporary = path.join(folder.path, 'receiving.tmp');
              String senderName = 'received.bin';
              final protocol = (protocolFactory ?? YmodemProtocol.new)();
              try {
                await protocol.receive(
                  savePath: temporary,
                  callbacks: _callbacks(
                    run,
                    onFileInfo: (name, _) {
                      final clean = name.split(RegExp(r'[\\/]')).last;
                      if (clean.isNotEmpty && clean != '.' && clean != '..') {
                        senderName = clean;
                      }
                    },
                  ),
                );
                if (!channel.active ||
                    run.phase != FileTransferPhase.succeeded) {
                  return;
                }
                var output = savePath.isEmpty
                    ? path.join(completed.path, senderName)
                    : multiple
                    ? path.join(completed.path, path.basename(savePath))
                    : savePath;
                // 同一目标再次接收或手选现有文件，也不能覆盖已经公布的输出。
                if (await File(output).exists()) {
                  output = path.join(completed.path, path.basename(output));
                }
                if (!channel.active) return;
                await File(temporary).rename(output);
                if (channel.active) run.outputPath = output;
              } finally {
                final file = File(temporary);
                if (await file.exists()) await file.delete();
              }
            }),
          ),
    );
  }

  TransferCallbacks _callbacks(
    _FileRun run, {
    String fileName = '',
    void Function(String, int)? onFileInfo,
  }) {
    final channel = run.channel!;
    bool canUpdate() =>
        channel.active && run.phase == FileTransferPhase.running;
    return TransferCallbacks(
      fileName: fileName,
      isCancelled: () =>
          !channel.active || run.phase == FileTransferPhase.failed,
      onWaitByte: channel.readByte,
      onWaitData: channel.readData,
      onWrite: (bytes, timeout) async {
        final result = await channel.write(bytes, timeoutMs: timeout);
        if (!result.succeeded && run.phase == FileTransferPhase.running) {
          run.phase = FileTransferPhase.failed;
          final count = result.acceptedBytes;
          run.reason =
              (result.reason ?? '本地写入未完整接受') +
              (count == null ? '；接受数量未知' : '；本地接受 $count/${bytes.length} 字节');
          _changed();
        }
        await result.settled;
        return channel.active && result.succeeded;
      },
      onProgress: (value) {
        if (!canUpdate()) return;
        run.progress = value.clamp(0, 1);
        run.transferredBytes = (run.totalBytes * run.progress).toInt();
        _changed();
      },
      onFileInfo: (name, size) {
        if (!canUpdate()) return;
        run.totalBytes = size;
        onFileInfo?.call(name, size);
        _changed();
      },
      onLog: (message) {
        if (!channel.active) return;
        final line = message.length > 2048
            ? message.substring(0, 2048)
            : message;
        run.logs.add(line);
        run.logBytes += line.length * 2;
        while (run.logs.length > 128 || run.logBytes > 32768) {
          run.logBytes -= run.logs.removeAt(0).length * 2;
        }
        _changed();
      },
      onError: (reason) {
        if (!canUpdate()) return;
        run.phase = FileTransferPhase.failed;
        run.reason ??= reason;
        _changed();
      },
      onComplete: (total) {
        if (!canUpdate()) return;
        run.phase = FileTransferPhase.succeeded;
        run.transferredBytes = total;
        run.totalBytes = total;
        run.progress = 1;
        _changed();
      },
    );
  }

  Future<void> _execute(_FileRun run, Future<void> Function() action) async {
    final channel = run.channel!;
    final ownerReleased = Completer<void>();
    if (channel.active) channel.holdUntil(ownerReleased.future);
    try {
      await channel.ready;
      if (channel.active) await action();
      if (run.phase == FileTransferPhase.running &&
          !channel.active &&
          channel.reason != null) {
        run.phase = FileTransferPhase.cancelled;
        run.reason = channel.reason;
      } else if (run.phase == FileTransferPhase.running) {
        run.phase = channel.active
            ? FileTransferPhase.failed
            : FileTransferPhase.cancelled;
        run.reason = channel.reason ?? '协议未报告完成';
      }
    } catch (error) {
      if (channel.active) {
        run.phase = FileTransferPhase.failed;
        run.reason = '$error';
      } else {
        run.phase = FileTransferPhase.cancelled;
        run.reason = channel.reason;
      }
    } finally {
      ownerReleased.complete();
      await channel.finish();
      run.released = true;
      _changed();
    }
  }

  void discard(String connectionId) {
    cancel(connectionId: connectionId);
    _runs.removeWhere((run) => run.start.connection.id == connectionId);
    _changed();
  }

  void cancel({String? connectionId, ProtocolTaskKind? kind}) {
    for (final run in _runs) {
      if ((connectionId == null || run.start.connection.id == connectionId) &&
          (kind == null || run.kind == kind)) {
        unawaited(run.channel?.cancel() ?? Future<void>.value());
      }
    }
    _changed();
  }
}
