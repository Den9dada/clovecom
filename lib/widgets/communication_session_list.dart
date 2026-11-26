import 'dart:async';

import 'package:flutter/gestures.dart'
    show kDoubleTapSlop, kDoubleTapTimeout, kSecondaryMouseButton;
import 'package:material_ui/material_ui.dart';

import '../src/application/communication_runtime.dart';
import '../src/application/communication_sessions.dart';
import '../src/io/connections.dart';
import '../ui/widgets/ds_dialog.dart';
import '../ui/widgets/ds_toast.dart';
import 'connection_editor.dart';
import 'session_tag_picker.dart';

enum _SessionAction { open, duplicate, delete, create, configure }

/// 已保存的会话列表，包含尚未打开的会话。
class CommunicationSessionList extends StatefulWidget {
  const CommunicationSessionList({
    super.key,
    required this.sessions,
    required this.onCollapse,
    required this.selectedId,
    required this.onSelect,
  });

  final CommunicationSessions sessions;
  final VoidCallback onCollapse;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<CommunicationSessionList> createState() =>
      _CommunicationSessionListState();
}

class _CommunicationSessionListState extends State<CommunicationSessionList> {
  String? _lastTapId;
  Duration _lastTapStamp = Duration.zero;
  Offset _lastTapPosition = Offset.zero;

  CommunicationSessions get sessions => widget.sessions;
  VoidCallback get onCollapse => widget.onCollapse;
  String? get selectedId => widget.selectedId;
  ValueChanged<String> get onSelect => widget.onSelect;
  CommunicationRuntime get _runtime => sessions.runtime;

  void _handlePointerDown(PointerDownEvent event, String id) {
    if ((event.buttons & kSecondaryMouseButton) != 0) return;
    onSelect(id);
    final elapsed = event.timeStamp - _lastTapStamp;
    final sameTarget =
        _lastTapId == id &&
        elapsed >= Duration.zero &&
        elapsed <= kDoubleTapTimeout &&
        (event.position - _lastTapPosition).distance <= kDoubleTapSlop;
    if (sameTarget) {
      _lastTapId = null;
      unawaited(_open(context, id));
      return;
    }
    _lastTapId = id;
    _lastTapStamp = event.timeStamp;
    _lastTapPosition = event.position;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final savedSessions = sessions.connections.values.toList();
    return Material(
      key: const ValueKey('communication-session-list'),
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Expanded(child: Text('会话', style: theme.textTheme.labelLarge)),
                IconButton(
                  tooltip: '新建会话',
                  onPressed: () => _configure(context),
                  icon: const Icon(Icons.add, size: 17),
                ),
                IconButton(
                  tooltip: '折叠会话列表',
                  onPressed: onCollapse,
                  icon: const Icon(Icons.chevron_right, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: GestureDetector(
              key: const ValueKey('session-list-body'),
              behavior: HitTestBehavior.opaque,
              onSecondaryTapUp: (event) =>
                  _showMenu(context, event.globalPosition),
              child: ListView.builder(
                key: const PageStorageKey('session-list-scroll'),
                primary: false,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: savedSessions.length,
                itemBuilder: (context, index) {
                  final connection = savedSessions[index];
                  final selected = selectedId == connection.id;
                  return Material(
                    key: ValueKey('session-list-${connection.id}'),
                    animationDuration: Duration.zero,
                    color: selected
                        ? colors.secondaryContainer
                        : colors.surfaceContainerLow,
                    child: Semantics(
                      selected: selected,
                      onTap: () => onSelect(connection.id),
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (event) =>
                            _handlePointerDown(event, connection.id),
                        child: InkWell(
                          onTap: () {},
                          onSecondaryTapUp: (event) => _showMenu(
                            context,
                            event.globalPosition,
                            connection,
                          ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: SizedBox(
                            height: 30,
                            child: Row(
                              children: [
                                SizedBox.square(
                                  dimension: 14,
                                  child: Center(
                                    child:
                                        sessions.tagIcon(connection.id) ==
                                            CommunicationSessions.defaultTagIcon
                                        ? SizedBox.square(
                                            dimension: 7,
                                            child: ColoredBox(
                                              key: ValueKey(
                                                'session-list-label-${connection.id}',
                                              ),
                                              color: Color(
                                                sessions.tagColor(
                                                  connection.id,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Icon(
                                            sessionTagIconData(
                                              sessions.tagIcon(connection.id),
                                            ),
                                            key: ValueKey(
                                              'session-list-label-${connection.id}',
                                            ),
                                            size: 13,
                                            color: Color(
                                              sessions.tagColor(connection.id),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    connection.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String id) async {
    onSelect(id);
    try {
      await sessions.connect(id, sessions.layout.groups.first);
    } catch (error) {
      if (context.mounted) {
        showDsToast(error.toString(), kind: DsToastKind.error);
      }
    }
  }

  Future<void> _showMenu(
    BuildContext context,
    Offset pointer, [
    ConnectionSnapshot? connection,
  ]) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final anchor = overlay.globalToLocal(pointer);
    final action = await showMenu<_SessionAction>(
      context: context,
      position: RelativeRect.fromSize(anchor & const Size(1, 1), overlay.size),
      items: [
        if (connection != null) ...[
          const PopupMenuItem(value: _SessionAction.open, child: Text('打开会话')),
          const PopupMenuItem(
            value: _SessionAction.duplicate,
            child: Text('复制会话'),
          ),
          PopupMenuItem(
            value: _SessionAction.delete,
            enabled: connection.completelyClosed,
            child: Tooltip(
              message: connection.completelyClosed ? '删除会话' : '请先断开连接',
              child: const Text('删除会话'),
            ),
          ),
        ],
        const PopupMenuItem(value: _SessionAction.create, child: Text('新建会话')),
        if (connection != null)
          const PopupMenuItem(
            value: _SessionAction.configure,
            child: Text('会话配置'),
          ),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == _SessionAction.create) {
      await _configure(context);
      return;
    }
    final current = _find(connection!.id);
    if (current == null) return;
    switch (action) {
      case _SessionAction.open:
        await _open(context, current.id);
      case _SessionAction.duplicate:
        _duplicate(current.definition);
      case _SessionAction.delete:
        await _delete(context, current);
      case _SessionAction.configure:
        await _configure(context, current);
      case _SessionAction.create:
        break;
    }
  }

  ConnectionSnapshot? _find(String id) =>
      _runtime.snapshot.connections.where((item) => item.id == id).firstOrNull;

  void _duplicate(ConnectionDefinition source) {
    final id = 'connection-${DateTime.now().microsecondsSinceEpoch}';
    final name = '${source.name}（副本）';
    final serial = source.serial;
    final copy = serial == null
        ? ConnectionDefinition.network(
            id: id,
            name: name,
            protocol: source.protocol!,
            tcpClient: source.tcpClient,
            tcpServer: source.tcpServer,
            udp: source.udp,
          )
        : ConnectionDefinition.serial(
            ConnectionConfig.fromJson({
              ...serial.toJson(),
              'id': id,
              'name': name,
            }),
          );
    _runtime.addConnection(copy);
  }

  int? _parseTagColor(String text) {
    final hex = text.trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return 0xff000000 | int.parse(hex, radix: 16);
  }

  Future<void> _configure(
    BuildContext context, [
    ConnectionSnapshot? connection,
  ]) {
    unawaited(_runtime.refreshInterfaceAvailability());
    final initialColor = connection == null
        ? sessions.nextTagColor()
        : sessions.tagColor(connection.id);
    final initialIcon = connection == null
        ? CommunicationSessions.defaultTagIcon
        : sessions.tagIcon(connection.id);
    final initialHex = formatTagColorHex(initialColor);
    String? colorDraft;
    String iconDraft = initialIcon;
    String? error;
    return showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final definition = connection?.definition;
          final editable = connection?.completelyClosed ?? true;
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          return ConnectionEditor(
            definition: definition,
            runtime: _runtime,
            tagColorField: SessionTagField(
              initialColor: initialColor,
              initialIcon: initialIcon,
              defaultIconKey: CommunicationSessions.defaultTagIcon,
              onColorChanged: (value) => colorDraft = value,
              onIconChanged: (value) => iconDraft = value,
            ),
            onError: (failure) =>
                setDialogState(() => error = failure.toString()),
            onSubmit: (value) {
              final color = _parseTagColor(colorDraft ?? initialHex);
              if (color == null) {
                throw const FormatException('请输入六位十六进制颜色，例如 #3A78D4');
              }
              if (definition == null) {
                _runtime.addConnection(value);
              } else {
                final current = _find(definition.id);
                if (current == null) throw StateError('会话已删除');
                if (!identical(current.definition, definition)) {
                  throw StateError('会话配置已变更，请重新打开');
                }
                _runtime.updateConnection(value);
              }
              if (colorDraft != null) sessions.setTagColor(value.id, color);
              if (iconDraft != initialIcon) {
                sessions.setTagIcon(value.id, iconDraft);
              }
              Navigator.pop(context);
            },

            builder: (save, fields) => Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                key: const ValueKey('session-configuration-dialog'),
                width: 620,
                height: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              definition == null ? '新建会话' : '会话配置',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 28,
                            ),
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!editable)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '请在会话中断开连接后再编辑。',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: AbsorbPointer(
                                absorbing: !editable,
                                child: ExcludeFocus(
                                  excluding: !editable,
                                  child: fields,
                                ),
                              ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 60,
                                ),
                                child: SingleChildScrollView(
                                  child: DsErrorMessage(error!),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(editable ? '取消' : '关闭'),
                          ),
                          if (editable) ...[
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () {
                                if (error != null) {
                                  setDialogState(() => error = null);
                                }
                                save();
                              },
                              child: const Text('保存'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    ConnectionSnapshot connection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DsDialog(
        title: const Text('删除会话'),
        content: Text('删除「${connection.name}」及其连接配置？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true || _find(connection.id) == null) {
      return;
    }
    try {
      _runtime.removeConnection(connection.id);
    } catch (error) {
      showDsToast('$error', kind: DsToastKind.error);
    }
  }
}
