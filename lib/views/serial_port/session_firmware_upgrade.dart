import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/firmware_protocol_binding.dart';
import '../../services/protocol_library.dart';
import '../../src/application/communication_runtime.dart';
import '../../src/application/communication_sessions.dart';
import '../../src/application/lua_runtime.dart';
import '../../ui/widgets/ds_dialog.dart';
import '../../widgets/app_dropdown.dart';

Future<void> showSessionFirmwareUpgrade(
  BuildContext context, {
  required OpenCommunicationSession session,
  required ProtocolLibrary library,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SessionFirmwareUpgrade(session: session, library: library),
);

class _SessionFirmwareUpgrade extends StatefulWidget {
  const _SessionFirmwareUpgrade({required this.session, required this.library});

  final OpenCommunicationSession session;
  final ProtocolLibrary library;

  @override
  State<_SessionFirmwareUpgrade> createState() =>
      _SessionFirmwareUpgradeState();
}

class _SessionFirmwareUpgradeState extends State<_SessionFirmwareUpgrade> {
  late final _binding = FirmwareProtocolBinding(widget.library);
  late final _listenables = Listenable.merge([_binding, _runtime]);
  CommunicationRuntime get _runtime => widget.session.runtime;
  String get _id => widget.session.id;
  FirmwareUpgradeController get _controller => _runtime.firmwareUpgrades;
  FirmwareUpgradeTarget? get _target => _controller.targets
      .where((target) => target.connectionId == _id)
      .firstOrNull;

  String? _protocolId;
  String? _fileName;
  Uint8List? _firmware;
  String? _error;
  bool _reading = false;

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }

  Future<void> _selectFile() async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final selected = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: '固件文件',
            extensions: ['bin', 'hex', 'img', 'fw'],
          ),
        ],
      );
      if (selected?.path case final path?) {
        final limit = LuaRuntime.limits['max_firmware_bytes']!;
        final file = File(path);
        if (await file.length() > limit) {
          throw const FormatException('固件文件超过 16 MiB');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in file.openRead(0, limit + 1)) {
          if (bytes.length + chunk.length > limit) {
            throw const FormatException('固件文件超过 16 MiB');
          }
          bytes.add(chunk);
        }
        if (bytes.length == 0) throw const FormatException('固件文件不能为空');
        if (!mounted) return;
        setState(() {
          _fileName = selected!.name;
          _firmware = bytes.takeBytes();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _loadProtocol(String id) async {
    setState(() {
      _protocolId = id;
      _error = null;
    });
    try {
      await _binding.load(id, locked: () => _runtime.taskFor(_id) != null);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _start() async {
    final bytes = _firmware;
    final protocol = _binding.loaded;
    if (bytes == null || protocol == null || widget.session.closed) return;
    setState(() => _error = null);
    try {
      await _controller.start(
        connectionId: _id,
        protocol: protocol,
        runtime: widget.library.runtime,
        load: () async => bytes,
        firmwareName: _fileName!,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _listenables,
    builder: (context, _) {
      final connection = _runtime.connectionFor(_id);
      final target = _target;
      final busy =
          _runtime.taskFor(_id) != null || target?.awaitingRelease == true;
      final canStart =
          connection?.writable == true &&
          !busy &&
          !_reading &&
          _firmware != null &&
          !_binding.loading &&
          _binding.loaded != null;
      final available = _binding.available;
      return DsDialog(
        title: Text('${connection?.name ?? _id} · 固件升级'),
        error: _error,
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (connection?.writable != true) const Text('请先连接串口。'),
                OutlinedButton(
                  key: const ValueKey('select-firmware-file'),
                  onPressed: busy || _reading ? null : _selectFile,
                  child: Text(_reading ? '读取中…' : _fileName ?? '选择固件文件'),
                ),
                const SizedBox(height: 12),
                AppDropdownFormField<String>(
                  key: const ValueKey('session-firmware-protocol'),
                  value: _protocolId,
                  decoration: const InputDecoration(labelText: '升级脚本'),
                  items: [
                    for (final protocol in available)
                      DropdownMenuItem(
                        value: protocol.id,
                        child: Text(protocol.name),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (id) {
                          if (id != null) unawaited(_loadProtocol(id));
                        },
                ),
                if (available.isEmpty) const Text('请先在协议编辑页保存串口升级脚本。'),
                if (_binding.loading) const LinearProgressIndicator(),
                if (_binding.hasNewVersion && _protocolId != null)
                  TextButton(
                    onPressed: busy ? null : () => _loadProtocol(_protocolId!),
                    child: const Text('载入已保存的新版本'),
                  ),
                if (_binding.configSuggestion.isNotEmpty)
                  Text(
                    '接口参数建议：${_binding.configSuggestion.entries.map((item) => '${item.key}=${item.value}').join('，')}',
                  ),
                if (target != null) ...[
                  const SizedBox(height: 12),
                  Text(switch (target.phase) {
                    FirmwareUpgradePhase.running => '升级中',
                    FirmwareUpgradePhase.succeeded => '升级成功',
                    FirmwareUpgradePhase.failed => '升级失败',
                    FirmwareUpgradePhase.cancelled => '升级已停止',
                    FirmwareUpgradePhase.notExecuted => '升级未执行',
                  }),
                  LinearProgressIndicator(value: target.progress),
                  if (target.reason case final reason?) Text(reason),
                  if (target.releaseFailure case final failure?)
                    Text('资源释放失败：$failure'),
                  for (final line in target.logs) Text(line),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (target?.phase == FirmwareUpgradePhase.running)
            OutlinedButton(
              onPressed: () => _controller.cancel(connectionId: _id),
              child: const Text('停止升级'),
            ),
          FilledButton(
            onPressed: canStart ? _start : null,
            child: const Text('开始升级'),
          ),
        ],
      );
    },
  );
}
