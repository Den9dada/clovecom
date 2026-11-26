import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/serial_port_model.dart';
import '../../services/protocol_library.dart';
import '../../services/status_bar_service.dart';
import '../../src/application/communication_configuration_store.dart';
import '../../src/application/communication_runtime.dart';
import '../../src/application/communication_sessions.dart';
import '../../ui/widgets/ds_toast.dart';
import '../../utils/file_picker_compat.dart';
import '../../widgets/communication_session_data_view.dart';
import '../../widgets/communication_session_workspace.dart';
import 'session_firmware_upgrade.dart';

class SerialPortView extends StatefulWidget {
  const SerialPortView({super.key, this.runtime, this.protocolLibrary});

  final CommunicationRuntime? runtime;
  final ProtocolLibrary? protocolLibrary;

  @override
  State<SerialPortView> createState() => _SerialPortViewState();
}

class _SerialPortViewState extends State<SerialPortView> {
  late final CommunicationRuntime _runtime;
  late final bool _ownsRuntime;
  late final CommunicationSessions _sessions;
  @override
  void initState() {
    super.initState();
    final external = widget.runtime ?? context.read<CommunicationRuntime?>();
    _ownsRuntime = external == null;
    final runtime = _runtime = external ?? CommunicationRuntime();
    _sessions = CommunicationSessions(
      runtime: runtime,
      defaults: DisplayConfig.new,
      store: runtime.configurationStore == null
          ? null
          : FileCommunicationConfigurationStore(
              filename: 'interface_communication_sessions.json',
            ),
    );
    _sessions.addListener(_updateStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateStatus();
    });
  }

  void _updateStatus() {
    final connected = _sessions.connections.values
        .where((connection) => connection.connected)
        .length;
    final open = _sessions.layout.groups.fold<int>(
      0,
      (count, group) => count + group.tabs.length,
    );
    StatusBarService().update(
      0,
      StatusBarInfo(
        text: '接口通信 · $open 个会话 · $connected 个连接已打开',
        icon: connected > 0 ? Icons.check_circle : Icons.circle_outlined,
        color: connected > 0 ? Colors.green : null,
      ),
    );
  }

  @override
  void dispose() {
    _sessions.removeListener(_updateStatus);
    _sessions.dispose();
    if (_ownsRuntime) unawaited(_runtime.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListenableBuilder(
        listenable: _sessions,
        builder: (context, _) => _sessions.outputError == null
            ? const SizedBox.shrink()
            : Text(
                _sessions.outputError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
      ),
      Expanded(
        child: CommunicationSessionWorkspace(
          sessions: _sessions,
          content: (context, session, connection, layoutMenu) =>
              _InterfaceSessionPane(
                key: ObjectKey(session),
                session: session,
                connection: connection,
                saveDisplay: _sessions.saveDisplay,
                layoutMenu: layoutMenu,
                protocolLibrary: widget.protocolLibrary,
              ),
        ),
      ),
    ],
  );
}

class _InterfaceSessionPane extends StatefulWidget {
  const _InterfaceSessionPane({
    super.key,
    required this.session,
    required this.connection,
    required this.saveDisplay,
    required this.layoutMenu,
    this.protocolLibrary,
  });
  final OpenCommunicationSession session;
  final ConnectionSnapshot connection;
  final VoidCallback saveDisplay;
  final List<Widget> layoutMenu;
  final ProtocolLibrary? protocolLibrary;

  @override
  State<_InterfaceSessionPane> createState() => _InterfaceSessionPaneState();
}

class _InterfaceSessionPaneState extends State<_InterfaceSessionPane> {
  final _sendBar = GlobalKey<_SessionSendBarState>();
  OpenCommunicationSession get session => widget.session;
  ConnectionSnapshot get connection => widget.connection;

  Future<void> _toggleConnection() async {
    try {
      if (connection.completelyClosed) {
        await session.runtime.openConnection(session.id);
      } else {
        await session.runtime.closeConnection(session.id);
      }
    } catch (error) {
      if (mounted) showDsToast(error.toString(), kind: DsToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: CommunicationSessionDataView(
              session: session,
              saveDisplay: widget.saveDisplay,
              layoutMenu: widget.layoutMenu,
              connectionAction: IconButton(
                key: ValueKey('session-link-${session.id}'),
                tooltip: connection.completelyClosed ? '连接' : '断开',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                onPressed:
                    connection.disconnecting ||
                        (connection.phase == ConnectionPhase.closed &&
                            !connection.operationsSettled)
                    ? null
                    : _toggleConnection,
                icon: Icon(
                  connection.completelyClosed ? Icons.link : Icons.link_off,
                  size: 16,
                ),
              ),
              sendSettings: (refresh) =>
                  _sendBar.currentState?._settingsMenu(refresh) ?? const [],
            ),
          ),
          Offstage(
            offstage: constraints.maxHeight < 115,
            child: _SessionSendBar(
              key: _sendBar,
              session: session,
              connection: connection,
              protocolLibrary: widget.protocolLibrary,
              saveDisplay: widget.saveDisplay,
              compact: constraints.maxWidth < 245,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionSendBar extends StatefulWidget {
  const _SessionSendBar({
    super.key,
    required this.session,
    required this.connection,
    required this.saveDisplay,
    required this.compact,
    this.protocolLibrary,
  });

  final OpenCommunicationSession session;
  final ConnectionSnapshot connection;
  final VoidCallback saveDisplay;
  final bool compact;
  final ProtocolLibrary? protocolLibrary;

  @override
  State<_SessionSendBar> createState() => _SessionSendBarState();
}

class _SessionSendBarState extends State<_SessionSendBar> {
  late final TextEditingController _draft;
  bool _sending = false;
  OpenCommunicationSession get session => widget.session;
  SessionDisplay get display => session.display;
  bool get _canSend =>
      !session.closed &&
      widget.connection.writable &&
      session.runtime.taskFor(session.id) == null;
  bool get _canTransfer => _canSend && widget.connection.definition.isSerial;
  bool get _loop {
    final run = session.runtime.loopFor(session.id);
    return run != null && run.phase != LoopPhase.stopped;
  }

  FileTransferTarget? get _task => session.runtime.fileTransfers.targets
      .where((target) => target.connectionId == session.id)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(text: session.draft);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Uint8List _wire() {
    final String draft = session.draft;
    final List<int> bytes;
    if (display.sendHex) {
      final hex = draft.replaceAll(RegExp(r'\s+'), '');
      if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
        throw const FormatException('HEX 发送需要完整的十六进制字节');
      }
      bytes = [
        for (var index = 0; index < hex.length; index += 2)
          int.parse(hex.substring(index, index + 2), radix: 16),
      ];
    } else {
      bytes = utf8.encode(draft);
    }
    if (bytes.isEmpty && !display.appendCR && !display.appendLF) {
      throw const FormatException('请输入要发送的数据');
    }
    return Uint8List.fromList([
      ...bytes,
      if (display.appendCR) 0x0d,
      if (display.appendLF) 0x0a,
    ]);
  }

  void _toggleSendFormat() {
    String? converted;
    if (display.sendHex) {
      final parts = session.draft.trim().split(RegExp(r'\s+'));
      try {
        converted = utf8.decode([
          for (final part in parts)
            if (part.isNotEmpty) int.parse(part.padRight(2, "0"), radix: 16),
        ], allowMalformed: true);
      } on FormatException {
        converted = null;
      }
    } else {
      converted = utf8
          .encode(session.draft)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
    }
    if (converted != null) {
      _draft.text = converted;
      session.draft = converted;
    }
    setState(() => display.sendHex = !display.sendHex);
    _refreshLoopDraft();
    widget.saveDisplay();
  }

  void _refreshLoopDraft() {
    if (!_loop) return;
    try {
      session.updateLoop(_wire());
    } on FormatException {
      session.updateLoop(Uint8List(0));
    }
  }

  Future<void> _send() async {
    if (_sending || !_canSend) return;
    try {
      final bytes = _wire();
      setState(() => _sending = true);
      final result = await session.write(bytes);
      if (!mounted || result.succeeded) return;
      final count = result.acceptedBytes;
      showDsToast(
        '${result.reason ?? '发送失败'} · ${count == null ? '写入量未知' : '已写入 $count B'}',
        kind: DsToastKind.error,
      );
    } on FormatException catch (error) {
      if (mounted) showDsToast(error.message, kind: DsToastKind.error);
    } finally {
      if (mounted && _sending) setState(() => _sending = false);
    }
  }

  Future<void> _fileSend() async {
    final selection = await FilePickerCompat.pickFiles();
    final file = selection?.files.firstOrNull;
    if (file?.path == null || !mounted || session.closed) return;
    await session.sendFile(File(file!.path!), file.name);
  }

  Future<void> _fileReceive() async {
    final directory = await FilePickerCompat.getDirectoryPath(
      dialogTitle: '选择接收文件目录',
    );
    if (directory == null || !mounted || session.closed) return;
    await session.receiveFile(directory: directory);
  }

  Future<void> _fileReceiveAs() async {
    final destination = await file_selector.getSaveLocation(
      suggestedName: 'received.bin',
    );
    if (destination == null || !mounted || session.closed) return;
    await session.receiveFile(savePath: destination.path);
  }

  Future<void> _loopInterval() async {
    final controller = TextEditingController(text: '${display.loopMs}');
    try {
      final value = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('循环发送间隔'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '毫秒'),
            onSubmitted: (text) => Navigator.pop(context, int.tryParse(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(controller.text)),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (!mounted || value == null) return;
      if (value < 1 || value > 3600000) {
        showDsToast('请输入 1 到 3600000 毫秒', kind: DsToastKind.error);
        return;
      }
      display.loopMs = value;
      widget.saveDisplay();
    } finally {
      controller.dispose();
    }
  }

  void _details() {
    final task = _task;
    if (task == null) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('文件任务'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: SelectableText(
                [
                  _taskStatus(task),
                  if (task.outputPath != null) task.outputPath!,
                  ...task.logs,
                ].join('\n'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  String _taskStatus(FileTransferTarget task) {
    final label = switch (task.phase) {
      FileTransferPhase.running => '传输中',
      FileTransferPhase.succeeded => '传输完成',
      FileTransferPhase.failed => '传输失败',
      FileTransferPhase.cancelled => '已停止',
      FileTransferPhase.notExecuted => '未执行',
    };
    return '${task.kind == ProtocolTaskKind.fileSend ? '文件发送' : '文件接收'} · $label'
        ' · ${(task.progress * 100).round()}%${task.reason == null ? '' : ' · ${task.reason}'}';
  }

  Future<void> _action(String action) async {
    try {
      if (!mounted || session.closed) return;
      switch (action) {
        case 'hex':
          _toggleSendFormat();
        case 'cr':
          setState(() => display.appendCR = !display.appendCR);
          _refreshLoopDraft();
          widget.saveDisplay();
        case 'lf':
          setState(() => display.appendLF = !display.appendLF);
          _refreshLoopDraft();
          widget.saveDisplay();
        case 'loop':
          if (_loop) {
            session.stopLoop();
          } else if (_canSend) {
            session.startLoop(_wire());
          }
        case 'interval':
          await _loopInterval();
        case 'fileSend':
          await _fileSend();
        case 'fileReceive':
          await _fileReceive();
        case 'fileReceiveAs':
          await _fileReceiveAs();
        case 'stopFile':
          session.runtime.fileTransfers.cancel(connectionId: session.id);
        case 'fileDetails':
          _details();
        case 'firmware':
          final library = widget.protocolLibrary;
          if (library != null) {
            await showSessionFirmwareUpgrade(
              context,
              session: session,
              library: library,
            );
          }
      }
    } catch (error) {
      if (mounted) showDsToast('$error', kind: DsToastKind.error);
    }
  }

  List<Widget> _settingsMenu(VoidCallback refresh) {
    if (!mounted || session.closed) return const [];
    final task = _task;
    final canTransfer = _canTransfer && task?.awaitingRelease != true;

    Widget toggle(String label, String action, bool value) =>
        CheckboxMenuButton(
          closeOnActivate: false,
          value: value,
          onChanged: (_) {
            unawaited(_action(action));
            refresh();
          },
          child: Text(label),
        );
    Widget command(String label, String action, {bool enabled = true}) =>
        MenuItemButton(
          onPressed: enabled ? () => unawaited(_action(action)) : null,
          child: Text(label),
        );

    return [
      toggle('HEX 发送', 'hex', display.sendHex),
      toggle('追加 CR', 'cr', display.appendCR),
      toggle('追加 LF', 'lf', display.appendLF),
      const Divider(),
      command(_loop ? '停止循环发送' : '开始循环发送', 'loop', enabled: _canSend || _loop),
      command('循环间隔 · ${display.loopMs} ms', 'interval'),
      const Divider(),
      command('发送文件', 'fileSend', enabled: canTransfer),
      command('接收文件', 'fileReceive', enabled: canTransfer),
      command('接收文件并另存为', 'fileReceiveAs', enabled: canTransfer),
      if (task?.awaitingRelease == true) command('停止文件任务', 'stopFile'),
      if (task != null) command('文件任务详情', 'fileDetails'),
      if (widget.connection.definition.isSerial &&
          widget.protocolLibrary != null)
        command('固件升级', 'firmware'),
    ];
  }

  Future<void> _openComposer() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('向 ${widget.connection.name} 发送'),
      content: SizedBox(width: 440, child: _input()),
      actions: [
        TextButton(
          onPressed: _canSend
              ? () {
                  Navigator.pop(context);
                  unawaited(_send());
                }
              : null,
          child: const Text('发送'),
        ),
      ],
    ),
  );

  Widget _input() => TextField(
    key: ValueKey('session-send-input-${session.id}'),
    controller: _draft,
    onChanged: (text) {
      session.draft = text;
      _refreshLoopDraft();
    },
    minLines: 1,
    maxLines: 3,
    decoration: InputDecoration(
      hintText: display.sendHex ? '输入 HEX 字节' : '输入发送内容',
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      isDense: true,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final result = task == null ? null : _taskStatus(task);
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: result,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    result,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: widget.compact
                    ? IconButton(
                        tooltip: '打开发送输入框',
                        onPressed: _openComposer,
                        icon: const Icon(Icons.edit, size: 17),
                      )
                    : _input(),
              ),
              if (!widget.compact)
                IconButton(
                  key: ValueKey('session-send-${session.id}'),
                  tooltip: '发送',
                  icon: const Icon(Icons.send_outlined, size: 17),
                  onPressed: _canSend && !_sending ? _send : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
