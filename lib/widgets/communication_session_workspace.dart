import 'package:material_ui/material_ui.dart';

import 'communication_session_list.dart';
import 'session_tag_picker.dart';
import '../ui/widgets/ds_toast.dart';

import '../src/application/communication_runtime.dart';
import '../src/application/communication_sessions.dart';
import '../src/application/session_layout.dart';

typedef SessionContentBuilder = Widget Function(
  BuildContext context,
  OpenCommunicationSession session,
  ConnectionSnapshot connection,
  List<Widget> layoutMenu,
);

/// 通用会话分组布局。业务页提供每个会话中的具体操作区。
class CommunicationSessionWorkspace extends StatefulWidget {
  const CommunicationSessionWorkspace({
    super.key,
    required this.sessions,
    required this.content,
  });

  final CommunicationSessions sessions;
  final SessionContentBuilder content;

  @override
  State<CommunicationSessionWorkspace> createState() =>
      _CommunicationSessionWorkspaceState();
}

class _CommunicationSessionWorkspaceState
    extends State<CommunicationSessionWorkspace> {
  static const _minListWidth = 150.0;
  static const _maxListWidth = 380.0;
  bool _listExpanded = true;
  double _listWidth = 224;
  final _selectedSessionId = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _selectedSessionId.dispose();
    super.dispose();
  }

  CommunicationSessions get sessions => widget.sessions;

  void _toggleList() => setState(() => _listExpanded = !_listExpanded);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessions,
    builder: (context, _) => sessions.initialized
        ? LayoutBuilder(builder: _buildWorkspace)
        : const Center(child: CircularProgressIndicator()),
  );

  Widget _buildWorkspace(BuildContext context, BoxConstraints constraints) {
    final maxWidth = (constraints.maxWidth * 0.38).clamp(
      _minListWidth,
      _maxListWidth,
    );
    final listWidth = _listWidth.clamp(_minListWidth, maxWidth);
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildNode(context, sessions.layout)),
        if (_listExpanded) ...[
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              key: const ValueKey('session-list-resize'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => setState(() {
                _listWidth =
                    (_listWidth.clamp(_minListWidth, maxWidth) -
                            details.delta.dx)
                        .clamp(_minListWidth, maxWidth);
              }),
              child: Center(
                child: SizedBox(
                  width: 6,
                  child: VerticalDivider(
                    width: 6,
                    color: colors.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: listWidth,
            child: ValueListenableBuilder<String?>(
              valueListenable: _selectedSessionId,
              builder: (context, selectedId, _) => CommunicationSessionList(
                sessions: sessions,
                onCollapse: _toggleList,
                selectedId: selectedId,
                onSelect: (id) => _selectedSessionId.value = id,
              ),
            ),
          ),
        ] else
          Align(
            alignment: Alignment.topCenter,
            child: IconButton(
              tooltip: '展开会话列表',
              onPressed: _toggleList,
              icon: const Icon(Icons.view_sidebar_outlined, size: 18),
            ),
          ),
      ],
    );
  }

  Widget _buildNode(BuildContext context, SessionLayout node) => switch (node) {
    final SessionGroup group => _GroupView(
      key: ObjectKey(group),
      group: group,
      sessions: sessions,
      content: widget.content,
    ),
    final SessionSplit split => LayoutBuilder(
      key: ObjectKey(split),
      builder: (context, constraints) {
        final size = split.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final handle = size < 12 ? 0.0 : 6.0;
        final extent = size - handle;
        final minFraction = extent > 0 ? (90 / extent).clamp(0.1, 0.45) : 0.45;
        final ratio = split.ratio.clamp(minFraction, 1 - minFraction);
        final colors = Theme.of(context).colorScheme;
        return Flex(
          direction: split.horizontal ? Axis.horizontal : Axis.vertical,
          children: [
            SizedBox(
              width: split.horizontal ? extent * ratio : constraints.maxWidth,
              height: split.horizontal ? constraints.maxHeight : extent * ratio,
              child: _buildNode(context, split.first),
            ),
            MouseRegion(
              key: const ValueKey('session-group-resize'),
              cursor: split.horizontal
                  ? SystemMouseCursors.resizeLeftRight
                  : SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: split.horizontal && extent > 0
                    ? (event) => sessions.resize(
                        split,
                        (split.ratio.clamp(minFraction, 1 - minFraction) +
                                event.delta.dx / extent)
                            .clamp(minFraction, 1 - minFraction),
                      )
                    : null,
                onVerticalDragUpdate: !split.horizontal && extent > 0
                    ? (event) => sessions.resize(
                        split,
                        (split.ratio.clamp(minFraction, 1 - minFraction) +
                                event.delta.dy / extent)
                            .clamp(minFraction, 1 - minFraction),
                      )
                    : null,
                child: SizedBox(
                  width: split.horizontal ? handle : constraints.maxWidth,
                  height: split.horizontal ? constraints.maxHeight : handle,
                  child: Center(
                    child: ColoredBox(
                      color: colors.outlineVariant,
                      child: SizedBox(
                        width: split.horizontal ? 1 : constraints.maxWidth,
                        height: split.horizontal ? constraints.maxHeight : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildNode(context, split.second)),
          ],
        );
      },
    ),
  };
}

class _GroupView extends StatelessWidget {
  const _GroupView({
    super.key,
    required this.group,
    required this.sessions,
    required this.content,
  });

  final SessionGroup group;
  final CommunicationSessions sessions;
  final SessionContentBuilder content;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = group.active;
    final session = active == null ? null : sessions[active];
    final connection = sessions.connections[active];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxHeight >= 32)
              DragTarget<String>(
                onAcceptWithDetails: (details) =>
                    sessions.move(details.data, group, SessionDrop.tabs),
                builder: (context, candidates, _) => ColoredBox(
                  color: candidates.isEmpty
                      ? colors.surfaceContainer
                      : colors.primaryContainer,
                  child: SizedBox(
                    height: 30,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final id in group.tabs) _tab(context, id),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Builder(
                builder: (dropContext) => DragTarget<String>(
                  onAcceptWithDetails: (details) {
                    final box = dropContext.findRenderObject()! as RenderBox;
                    final point = box.globalToLocal(details.offset);
                    final x = point.dx / box.size.width;
                    final y = point.dy / box.size.height;
                    final edges = {
                      SessionDrop.left: x,
                      SessionDrop.top: y,
                      SessionDrop.right: 1 - x,
                      SessionDrop.bottom: 1 - y,
                    };
                    final edge = edges.entries.reduce(
                      (a, b) => a.value < b.value ? a : b,
                    );
                    sessions.move(
                      details.data,
                      group,
                      edge.value < 0.28 ? edge.key : SessionDrop.tabs,
                    );
                  },
                  builder: (context, candidates, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (session != null && connection != null)
                        KeyedSubtree(
                          key: PageStorageKey('session-${session.id}'),
                          child: content(context, session, connection, [
                            MenuItemButton(
                              onPressed: group.tabs.length > 1
                                  ? () => sessions.move(
                                      session.id,
                                      group,
                                      SessionDrop.right,
                                    )
                                  : null,
                              child: const Text('向右拆分'),
                            ),
                            MenuItemButton(
                              onPressed: group.tabs.length > 1
                                  ? () => sessions.move(
                                      session.id,
                                      group,
                                      SessionDrop.bottom,
                                    )
                                  : null,
                              child: const Text('向下拆分'),
                            ),
                            MenuItemButton(
                              onPressed: sessions.layout.neighbor(group) != null
                                  ? () => sessions.merge(group)
                                  : null,
                              child: const Text('合并会话组'),
                            ),
                          ]),
                        )
                      else
                        const Center(child: Text('双击会话列表中的会话以打开')),
                      if (candidates.isNotEmpty)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: colors.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _close(BuildContext context, String id) async {
    try {
      await sessions.close(id);
    } catch (error) {
      if (context.mounted) {
        showDsToast(error.toString(), kind: DsToastKind.error);
      }
    }
  }

  Widget _tab(BuildContext context, String id) {
    final connection = sessions.connections[id];
    final colors = Theme.of(context).colorScheme;
    final title = connection?.name ?? id;
    final active = group.active == id;

    final labelColor = Color(sessions.tagColor(id));
    final status = switch (connection?.phase) {
      ConnectionPhase.open => '已连接',
      ConnectionPhase.opening => '正在连接',
      ConnectionPhase.reconnecting => '正在重新连接',
      ConnectionPhase.listening => '等待 TCP 客户端连接',
      ConnectionPhase.closing when connection!.disconnecting => '正在断开',
      ConnectionPhase.closing => '断开失败',
      ConnectionPhase.failed => '连接失败',
      ConnectionPhase.closed when !connection!.operationsSettled => '正在释放连接资源',
      _ => '未连接',
    };
    final detail = connection?.detail ?? connection?.availabilityDetail;
    return Draggable<String>(
      data: id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: colors.primaryContainer,
        child: Padding(padding: const EdgeInsets.all(8), child: Text(title)),
      ),
      child: Material(
        color: active ? colors.surface : colors.surfaceContainer,
        child: InkWell(
          onTap: () => sessions.activate(group, id),
          child: Ink(
            key: ValueKey('session-tab-stripe-$id'),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: labelColor, width: 2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                Icon(
                  sessionTagIconData(sessions.tagIcon(id)),
                  key: ValueKey('session-tab-label-$id'),
                  color: labelColor,
                  size: sessions.tagIcon(id) == 'square' ? 9 : 13,
                ),
                const SizedBox(width: 5),

                Tooltip(
                  message: detail == null ? status : '$status · $detail',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 146),
                    child: Text(
                      title,
                      key: ValueKey('session-tab-$id'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: connection?.connected == true
                            ? colors.onSurface
                            : colors.error,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('session-close-$id'),
                  tooltip: '关闭 $title',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  iconSize: 14,
                  onPressed: () => _close(context, id),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
