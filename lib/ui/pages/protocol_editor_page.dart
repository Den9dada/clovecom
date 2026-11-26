/// 协议编辑器页：协议列表 + 字段库 + 帧结构 + 属性面板 + 二进制预览。
///
/// 设计稿：`.design/clovertls-ui/pages/protocol-editor.html` 的 workspace 区域。
/// 后端：[ProtocolDraft] 提供 set/addField/updateField/removeField/moveField
/// 与 testHex/generateSampleHex；通过 [ProtocolLibrary] 持久化。
library;

import 'dart:convert';
import 'interaction_editor.dart';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../protocol_editor.dart';
import '../controllers/app_controller.dart';
import '../layout/responsive.dart';
import '../theme/traework_theme.dart';
import '../widgets/ds_toast.dart';
import '../widgets/list_delete_menu.dart';
import '../widgets/desktop_scroll.dart';
import '../widgets/ds_widgets.dart';

/// 协议编辑器页面。
class ProtocolEditorPage extends StatefulWidget {
  const ProtocolEditorPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProtocolEditorPage> createState() => _ProtocolEditorPageState();
}

class _ProtocolEditorPageState extends State<ProtocolEditorPage> {
  bool _interactionMode = false;
  int _panelTab = 0; // 0=帧结构 1=二进制预览
  Object? _selectedFieldIdentity;
  String? _activeDraftId;
  bool _fieldLibraryCollapsed = false;
  bool _transferring = false;
  final Set<String> _collapsedProtocols = {};

  AppController get _c => widget.controller;

  ProtocolDraft? get _draft =>
      _c.protocolDrafts.where((d) => d.id == _c.selectedProtocolId).firstOrNull;

  static const _protocolFileType = XTypeGroup(
    label: '协议 JSON',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  Future<void> _importProtocol() async {
    setState(() => _transferring = true);
    try {
      final file = await openFile(acceptedTypeGroups: [_protocolFileType]);
      if (file == null || !mounted) return;
      final content = await file.readAsString();
      if (!mounted) return;
      final draft = _c.application.importProtocol(content);
      _c.selectProtocol(draft.id);
      showDsToast('协议已导入为新草稿，请保存后生效', kind: DsToastKind.success);
    } catch (error) {
      if (mounted) showDsToast('导入协议失败：$error', kind: DsToastKind.error);
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _exportProtocol() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _transferring = true);
    try {
      // 在打开文件对话框前校验并固定导出快照。
      final content = _c.application.exportProtocol(draft.id);
      final name = (draft.values['name'] as String).replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
        '_',
      );
      final location = await getSaveLocation(
        suggestedName: '$name.json',
        acceptedTypeGroups: [_protocolFileType],
      );
      if (location == null || !mounted) return;
      await XFile.fromData(
        utf8.encode(content),
        mimeType: 'application/json',
        name: '$name.json',
      ).saveTo(location.path);
      if (mounted) showDsToast('协议导出成功', kind: DsToastKind.success);
    } catch (error) {
      if (mounted) showDsToast('导出协议失败：$error', kind: DsToastKind.error);
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _c.protocolSelectionNotifier,
        _c, // 主通道用于草稿变化等
      ]),
      builder: (context, _) {
        final selector = Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              DsButton(
                label: '解析协议编辑',
                size: DsButtonSize.sm,
                active: !_interactionMode,
                onPressed: () => setState(() => _interactionMode = false),
              ),
              const SizedBox(width: 8),
              DsButton(
                label: '交互协议编辑',
                size: DsButtonSize.sm,
                active: _interactionMode,
                onPressed: () => setState(() => _interactionMode = true),
              ),
            ],
          ),
        );
        if (_interactionMode) {
          return InteractionEditor(
            application: _c.application,
            header: selector,
          );
        }
        if (_activeDraftId != _draft?.id) {
          _activeDraftId = _draft?.id;
          _selectedFieldIdentity = null;
        }
        final selectedIndex = _draft == null || _selectedFieldIdentity == null
            ? -1
            : List.generate(
                _draft!.fieldCount,
                _draft!.fieldIdentity,
              ).indexOf(_selectedFieldIdentity!);
        return Column(
          children: [
            selector,
            _FieldLibrary(
              draft: _draft,
              collapsed: _fieldLibraryCollapsed,
              onToggle: () => setState(
                () => _fieldLibraryCollapsed = !_fieldLibraryCollapsed,
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  _ProtocolTreePanel(
                    controller: _c,
                    onImport: _transferring ? null : _importProtocol,
                    onExport: _transferring || _draft == null
                        ? null
                        : _exportProtocol,
                    collapsedProtocols: _collapsedProtocols,
                    onToggle: (id) => setState(() {
                      if (!_collapsedProtocols.add(id)) {
                        _collapsedProtocols.remove(id);
                      }
                    }),
                  ),
                  Expanded(
                    child: _draft == null
                        ? _emptyState()
                        : _ProtocolEditorArea(
                            key: ValueKey(
                              '${_draft!.id}:${_draft!.selectedMessageIndex}',
                            ),
                            controller: _c,
                            draft: _draft!,
                            panelTab: _panelTab,
                            selectedFieldIndex: selectedIndex < 0
                                ? null
                                : selectedIndex,
                            onPanelTab: (index) =>
                                setState(() => _panelTab = index),
                            onSelectField: (index) {
                              Tooltip.dismissAllToolTips();
                              FocusManager.instance.primaryFocus?.unfocus();
                              setState(
                                () => _selectedFieldIdentity = index == null
                                    ? null
                                    : _draft!.fieldIdentity(index),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 48,
            color: TraeWorkColors.iconTertiary,
          ),
          const SizedBox(height: TraeWorkSpacers.s12),
          Text(
            '暂无协议，点击左侧新建协议',
            style: traeworkText(
              size: TraeWorkFontSizes.bodyMd,
              color: TraeWorkColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 左侧协议树：协议为一级节点，消息类型为二级节点。
class _ProtocolTreePanel extends StatelessWidget {
  const _ProtocolTreePanel({
    required this.controller,
    required this.collapsedProtocols,
    required this.onToggle,
    required this.onImport,
    required this.onExport,
  });

  final AppController controller;
  final Set<String> collapsedProtocols;
  final ValueChanged<String> onToggle;
  final VoidCallback? onImport;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final drafts = controller.protocolDrafts;
    final width = Responsive.densityOf(context) == AppLayoutDensity.compact
        ? 220.0
        : 260.0;
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('protocol-tree-panel'),
      width: width,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(child: Text('协议列表')),
                DsButton(
                  label: '新建协议',
                  icon: Icons.add,
                  size: DsButtonSize.sm,
                  onPressed: () => _showCreateDialog(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: DsButton(
                    key: const ValueKey('protocol-import'),
                    label: '导入协议',
                    icon: Icons.file_upload_outlined,
                    size: DsButtonSize.sm,
                    onPressed: onImport,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DsButton(
                    key: const ValueKey('protocol-export'),
                    label: '导出协议',
                    icon: Icons.file_download_outlined,
                    size: DsButtonSize.sm,
                    onPressed: onExport,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                if (drafts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('暂无匹配协议'),
                  ),
                for (final draft in drafts) ...[
                  _ProtocolListItem(
                    draft: draft,
                    active: controller.selectedProtocolId == draft.id,
                    expanded: !collapsedProtocols.contains(draft.id),
                    onToggle: () => onToggle(draft.id),
                    onTap: () => controller.selectProtocol(draft.id),
                    onDelete: () => controller.deleteProtocol(draft.id),
                    onRename: () => _showRenameDialog(context, draft),
                  ),
                  if (!collapsedProtocols.contains(draft.id))
                    for (var i = 0; i < draft.messageCount; i++)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 24,
                          top: 2,
                          bottom: 2,
                        ),
                        child: DsInteraction(
                          key: ValueKey('protocol-message-${draft.id}-$i'),
                          selected:
                              controller.selectedProtocolId == draft.id &&
                              draft.selectedMessageIndex == i,
                          onTap: () {
                            draft.selectMessage(i);
                            controller.selectProtocol(draft.id);
                          },
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.subdirectory_arrow_right,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  draft.messageName(i),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: traeworkText(size: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final initialName = nextDraftName(
      '新建协议',
      controller.protocolDrafts.map((d) => d.values['name'] as String),
    );
    showDialog<void>(
      context: context,
      builder: (_) => DsNameDialog(
        emptyMessage: '请输入协议名称',
        title: '新建协议',
        initialName: initialName,
        onConfirm: (name) {
          final draft = controller.application.createProtocol(name);
          controller.selectProtocol(draft.id);
        },
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ProtocolDraft draft) {
    showDialog<void>(
      context: context,
      builder: (_) => DsNameDialog(
        emptyMessage: '请输入协议名称',
        title: '重命名协议',
        initialName: draft.values['name'] as String? ?? '',
        onConfirm: (name) => draft.set('name', name),
      ),
    );
  }
}

class _ProtocolListItem extends StatelessWidget {
  const _ProtocolListItem({
    required this.draft,
    required this.active,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  final ProtocolDraft draft;
  final bool active;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return ListDeleteMenu(
      onDelete: onDelete,
      child: DsInteraction(
        key: ValueKey('protocol-node-${draft.id}'),
        selected: active,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            DsButton.icon(
              key: ValueKey('protocol-node-toggle-${draft.id}'),
              icon: expanded ? Icons.expand_more : Icons.chevron_right,
              tooltip: expanded ? '折叠消息列表' : '展开消息列表',
              size: DsButtonSize.sm,
              onPressed: onToggle,
            ),
            Icon(
              draft.isDirty ? Icons.circle : Icons.description_outlined,
              size: draft.isDirty ? 8 : 16,
              color: draft.isDirty
                  ? TraeWorkColors.statusWarning
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: TraeWorkSpacers.s8),
            Expanded(
              child: Text(
                draft.values['name'] as String? ?? draft.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: traeworkText(
                  size: TraeWorkFontSizes.bodyMd,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            ...[_iconBtn(Icons.edit_outlined, '重命名', onRename)],
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return DsButton.icon(
      icon: icon,
      tooltip: tooltip,
      size: DsButtonSize.sm,
      variant: danger ? DsButtonVariant.danger : DsButtonVariant.ghost,
      onPressed: onTap,
    );
  }
}

/// 当前消息的编辑区：帧结构/二进制 + 属性面板。
class _ProtocolEditorArea extends StatelessWidget {
  const _ProtocolEditorArea({
    super.key,
    required this.controller,
    required this.draft,
    required this.panelTab,
    required this.selectedFieldIndex,
    required this.onPanelTab,
    required this.onSelectField,
  });

  final AppController controller;
  final ProtocolDraft draft;
  final int panelTab;
  final int? selectedFieldIndex;
  final ValueChanged<int> onPanelTab;
  final ValueChanged<int?> onSelectField;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MessageTypeBar(draft: draft),
        if (draft.messageCount == 0)
          const Expanded(child: Center(child: Text('请新增消息类型后编辑协议')))
        else
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _PanelTabs(active: panelTab, onChanged: onPanelTab),
                      Expanded(
                        child: panelTab == 0
                            ? _FrameStructure(
                                draft: draft,
                                selectedIndex: selectedFieldIndex,
                                onSelect: onSelectField,
                              )
                            : _BinaryPreview(draft: draft),
                      ),
                      if (panelTab == 0)
                        Container(
                          width: double.infinity,
                          height: 78,
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: TraeWorkColors.bgBaseSecondary,
                            border: Border(
                              top: BorderSide(
                                color: TraeWorkColors.borderNeutralL1,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('二进制预览', style: traeworkText(size: 12)),
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SelectableText(
                                    draft.sampleHex,
                                    style: traeworkMono(size: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                _FieldPropsPanel(
                  draft: draft,
                  selectedIndex: selectedFieldIndex,
                ),
              ],
            ),
          ),
        _EditorFooter(controller: controller, draft: draft),
      ],
    );
  }
}

/// 消息类型切换不保存草稿；所有消息随整份协议统一保存。
class _MessageTypeBar extends StatelessWidget {
  const _MessageTypeBar({required this.draft});
  final ProtocolDraft draft;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: TraeWorkColors.borderNeutralL1)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '消息类型：${draft.selectedMessageName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        DsButton(
          label: '新增消息',
          size: DsButtonSize.sm,
          variant: DsButtonVariant.secondary,
          onPressed: draft.addMessage,
        ),
        const SizedBox(width: 8),
        DsButton(
          label: '复制消息',
          size: DsButtonSize.sm,
          variant: DsButtonVariant.secondary,
          onPressed: draft.messageCount == 0
              ? null
              : () => draft.addMessage(copySelected: true),
        ),
        DsButton.icon(
          icon: Icons.edit_outlined,
          tooltip: '重命名消息类型',
          onPressed: draft.messageCount == 0
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => DsNameDialog(
                    title: '重命名消息类型',
                    emptyMessage: '请输入消息类型名称',
                    initialName: draft.selectedMessageName,
                    onConfirm: draft.renameMessage,
                  ),
                ),
        ),
        DsButton.icon(
          icon: Icons.delete_outline,
          tooltip: '删除消息类型',
          onPressed: draft.messageCount == 0
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('删除消息类型'),
                    content: Text(
                      '确认删除“${draft.selectedMessageName}”？此修改将在保存整份协议后生效。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          draft.removeMessage();
                        },
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class _KindSelector extends StatelessWidget {
  const _KindSelector({required this.draft});
  final ProtocolDraft draft;

  @override
  Widget build(BuildContext context) {
    final current = draft.values['kind'] as String? ?? 'position';
    return DsSelect<String>(
      value: current,
      items: const [
        DropdownMenuItem(value: 'position', child: Text('坐标')),
        DropdownMenuItem(value: 'observation', child: Text('观测')),
        DropdownMenuItem(value: 'display', child: Text('仅解析展示')),
      ],
      onChanged: (v) => v != null ? draft.set('kind', v) : null,
    );
  }
}

/// 页面上方横向字段库，折叠把手与固件配置区保持一致。
class _FieldLibrary extends StatefulWidget {
  const _FieldLibrary({
    required this.draft,
    required this.collapsed,
    required this.onToggle,
  });
  final ProtocolDraft? draft;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<_FieldLibrary> createState() => _FieldLibraryState();
}

class _FieldLibraryState extends State<_FieldLibrary> {
  final _fieldScroll = ScrollController();
  bool _hasBefore = false;
  bool _hasAfter = false;

  @override
  void initState() {
    super.initState();
    _fieldScroll.addListener(_updateHints);
  }

  void _updateHints() {
    if (_fieldScroll.hasClients && _fieldScroll.position.hasContentDimensions) {
      _setHints(_fieldScroll.position);
    }
  }

  void _setHints(ScrollMetrics metrics) {
    if (metrics.axis != Axis.horizontal) return;
    final before = metrics.extentBefore > 0.5;
    final after = metrics.extentAfter > 0.5;
    if (before == _hasBefore && after == _hasAfter) return;
    setState(() {
      _hasBefore = before;
      _hasAfter = after;
    });
  }

  @override
  void dispose() {
    _fieldScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('protocol-field-library'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
    child: Stack(
      children: [
        if (widget.collapsed)
          const SizedBox(height: 16, width: double.infinity)
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        '字段库',
                        style: traeworkText(size: 12, weight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '点击字段添加到当前消息',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: traeworkText(
                            size: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _fieldRows(),
              ],
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Center(
            child: Opacity(
              opacity: 0.6,
              child: Tooltip(
                message: widget.collapsed ? '展开字段库' : '折叠字段库',
                child: SizedBox(
                  width: 56,
                  height: 16,
                  child: Material(
                    color: colors.surfaceContainerLowest,
                    elevation: 4,
                    shadowColor: const Color(0x33000000),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    child: DsInteraction(
                      key: const ValueKey('field-library-toggle'),
                      onTap: widget.onToggle,
                      child: Icon(
                        widget.collapsed
                            ? Icons.expand_more
                            : Icons.expand_less,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    );
  }

  Widget _fieldRows() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Column(
            children: [
              for (final title in ['基础类型', '协议字段'])
                SizedBox(
                  height: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: traeworkText(
                        size: 11,
                        color: TraeWorkColors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  _updateHints();
                  return false;
                },
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) {
                    _updateHints();
                    return false;
                  },
                  child: KeyedSubtree(
                    key: const PageStorageKey('field-library-offset'),
                    child: DesktopHScroll(
                      key: const ValueKey('field-library-scroll'),
                      controller: _fieldScroll,
                      wheelRequiresModifier: false,
                      showScrollbar: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final items in [_basicTypes, _protocolFields])
                            SizedBox(
                              height: 40,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final item in items) _buildItem(item),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_hasBefore) _overflowHint(left: true),
              if (_hasAfter) _overflowHint(left: false),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _overflowHint({required bool left}) => Positioned(
    left: left ? 0 : null,
    right: left ? null : 0,
    top: 0,
    bottom: 0,
    child: IgnorePointer(
      child: Container(
        key: ValueKey(
          left ? 'field-library-more-left' : 'field-library-more-right',
        ),
        width: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              Theme.of(context).colorScheme.surfaceContainerLow,
              Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0),
            ],
          ),
        ),
        child: Align(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: Icon(
            left ? Icons.chevron_left : Icons.chevron_right,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
      ),
    ),
  );

  Widget _buildItem(_LibraryItem item) {
    return SizedBox(
      width: item.type == 'message-type' ? 160 : 128,
      height: 36,
      child: Tooltip(
        message: item.attributes,
        waitDuration: const Duration(milliseconds: 400),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: DsInteraction(
            variant: DsInteractionVariant.secondary,
            key: ValueKey('library-item-${item.type}'),
            onTap: widget.draft == null || widget.draft!.messageCount == 0
                ? null
                : () {
                    final draft = widget.draft!;
                    try {
                      final field = item.toField();
                      var name = field.name;
                      var suffix = 2;
                      while (List.generate(
                        draft.fieldCount,
                        (i) => draft.field(i)['name'],
                      ).contains(name)) {
                        name = '${field.name}_${suffix++}';
                      }
                      draft.addConfiguredField(
                        ProtocolField.fromJson({
                          ...field.toJson(),
                          'name': name,
                        }),
                        semantic: item.semantic,
                      );
                    } catch (error) {
                      showDsToast('字段添加失败：$error');
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: TraeWorkSpacers.s8,
                vertical: TraeWorkSpacers.s6,
              ),

              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: TraeWorkSpacers.s6),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: traeworkText(
                        size: TraeWorkFontSizes.bodySm,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.add,
                    size: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_LibraryItem> get _basicTypes => const [
    _LibraryItem(label: 'Header', icon: Icons.first_page, type: 'header'),
    _LibraryItem(label: 'Tail', icon: Icons.last_page, type: 'tail'),
    _LibraryItem(label: 'U8', icon: Icons.data_array, type: 'u8'),
    _LibraryItem(label: 'U16', icon: Icons.data_array, type: 'u16'),
    _LibraryItem(label: 'U32', icon: Icons.data_array, type: 'u32'),
    _LibraryItem(label: 'Float', icon: Icons.numbers, type: 'float'),
    _LibraryItem(label: 'Double', icon: Icons.numbers, type: 'double'),
    _LibraryItem(label: 'Length', icon: Icons.straighten, type: 'length'),
    _LibraryItem(label: 'Checksum', icon: Icons.verified, type: 'checksum'),
    _LibraryItem(label: 'Skip', icon: Icons.block, type: 'skip'),
  ];

  List<_LibraryItem> get _protocolFields => const [
    _LibraryItem(label: 'Tag ID', icon: Icons.tag, type: 'tag-id'),
    _LibraryItem(
      label: 'Anchor ID',
      icon: Icons.access_time,
      type: 'anchor-id',
    ),
    _LibraryItem(label: 'X', icon: Icons.align_horizontal_left, type: 'x'),
    _LibraryItem(label: 'Y', icon: Icons.align_horizontal_right, type: 'y'),
    _LibraryItem(label: 'Z', icon: Icons.height, type: 'z'),
    _LibraryItem(label: 'Angle', icon: Icons.rotate_right, type: 'angle'),
    _LibraryItem(label: 'Distance', icon: Icons.straighten, type: 'distance'),
    _LibraryItem(label: 'Timestamp', icon: Icons.schedule, type: 'timestamp'),
    _LibraryItem(label: 'Slot', icon: Icons.grid_on, type: 'slot'),
    _LibraryItem(
      label: 'Message Type',
      icon: Icons.category,
      type: 'message-type',
    ),
  ];
}

class _LibraryItem {
  const _LibraryItem({
    required this.label,
    required this.icon,
    required this.type,
  });

  final String label;
  final IconData icon;
  final String type;

  String? get semantic => switch (type) {
    'tag-id' => 'tagId',
    'anchor-id' => 'anchorId',
    'timestamp' => 'timestamp',
    'slot' => 'slot',
    'message-type' => 'messageType',
    'x' || 'y' || 'z' || 'angle' || 'distance' => type,
    _ => null,
  };

  String get attributes {
    final field = toField();
    final role = switch (field.role) {
      FieldRole.header => '帧头',
      FieldRole.frameId => '帧标识',
      FieldRole.length => '长度',
      FieldRole.data => '数据',
      FieldRole.checksum => '校验',
      FieldRole.tail => '帧尾',
      FieldRole.skip => '跳过',
    };
    final dataType = switch (field.type) {
      FieldType.uint => '无符号整数',
      FieldType.sint => '有符号整数',
      FieldType.float => '浮点数',
      FieldType.bytes => '字节数据',
    };
    final fixed = field.fixed
        ?.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    return [
      '$label 字段属性',
      '默认名称：${field.name}',
      '角色：$role',
      '数据类型：$dataType',
      '长度：${field.size} 字节',
      if (field.type != FieldType.bytes) ...[
        '字节序：${field.littleEndian ? '小端' : '大端'}',
        '缩放：${field.scale}，偏移：${field.bias}',
      ],
      if (fixed != null) '固定字节：$fixed',
      '定位方式：${field.fromEnd ? '从帧末尾定位' : '按字段顺序定位'}',
      if (semantic != null) '领域映射：$semantic',
    ].join('\n');
  }

  ProtocolField toField() {
    switch (type) {
      case 'header':
        return ProtocolField(
          name: 'header',
          size: 2,
          role: FieldRole.header,
          type: FieldType.bytes,
          fixed: [0x55, 0xaa],
        );
      case 'tail':
        return ProtocolField(
          name: 'tail',
          size: 2,
          role: FieldRole.tail,
          type: FieldType.bytes,
          fromEnd: true,
          fixed: [0x0d, 0x0a],
        );
      case 'u8':
        return ProtocolField(name: 'u8', size: 1);
      case 'u16':
        return ProtocolField(name: 'u16', size: 2);
      case 'u32':
        return ProtocolField(name: 'u32', size: 4);
      case 'float':
        return ProtocolField(name: 'float', size: 4, type: FieldType.float);
      case 'double':
        return ProtocolField(name: 'double', size: 8, type: FieldType.float);
      case 'length':
        return ProtocolField(name: 'length', size: 1, role: FieldRole.length);
      case 'checksum':
        return ProtocolField(
          name: 'checksum',
          size: 1,
          role: FieldRole.checksum,
        );
      case 'skip':
        return ProtocolField(name: 'skip', size: 1, role: FieldRole.skip);
      case 'tag-id':
        return ProtocolField(name: 'tagId', size: 4);
      case 'anchor-id':
        return ProtocolField(name: 'anchorId', size: 4);
      case 'x':
        return ProtocolField(name: 'x', size: 4, type: FieldType.float);
      case 'y':
        return ProtocolField(name: 'y', size: 4, type: FieldType.float);
      case 'z':
        return ProtocolField(name: 'z', size: 4, type: FieldType.float);
      case 'angle':
        return ProtocolField(name: 'angle', size: 4, type: FieldType.float);
      case 'distance':
        return ProtocolField(name: 'distance', size: 4, type: FieldType.float);
      case 'timestamp':
        return ProtocolField(name: 'timestamp', size: 4);
      case 'slot':
        return ProtocolField(name: 'slot', size: 2);
      case 'message-type':
        return ProtocolField(name: 'messageType', size: 1);
      default:
        return ProtocolField(name: type, size: 1);
    }
  }
}

class _PanelTabs extends StatelessWidget {
  const _PanelTabs({required this.active, required this.onChanged});
  final int active;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Row(children: [_tab(context, 0, '帧结构'), _tab(context, 1, '二进制预览')]),
    );
  }

  Widget _tab(BuildContext context, int index, String label) {
    final colors = Theme.of(context).colorScheme;
    final isActive = active == index;
    return DsInteraction(
      onTap: () => onChanged(index),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: TraeWorkSpacers.s16,
          vertical: TraeWorkSpacers.s8,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: traeworkText(
            size: TraeWorkFontSizes.bodySm,
            color: isActive ? colors.primary : colors.onSurfaceVariant,
            weight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FrameStructure extends StatelessWidget {
  const _FrameStructure({
    required this.draft,
    required this.selectedIndex,
    required this.onSelect,
  });

  final ProtocolDraft draft;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    if (draft.fieldCount == 0) {
      return _empty('从左侧字段库点击添加字段');
    }
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(TraeWorkSpacers.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '字段结构（${draft.fieldCount}）',
                style: traeworkText(
                  size: TraeWorkFontSizes.bodySm,
                  weight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              DsButton(
                label: '添加字段',
                icon: Icons.add,
                size: DsButtonSize.sm,
                variant: DsButtonVariant.secondary,
                onPressed: () {
                  var i = 1;
                  while (true) {
                    final name = 'field_$i';
                    final exists = (draft.values['fields'] as List<dynamic>)
                        .any(
                          (f) => (f as Map<String, dynamic>)['name'] == name,
                        );
                    if (!exists) {
                      draft.addField(ProtocolField(name: name, size: 1));
                      return;
                    }
                    i++;
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: TraeWorkSpacers.s8),
          Expanded(
            child: ReorderableListView.builder(
              // 为滚动条预留独立空间，避免遮住字段行右侧的操作按钮。
              padding: const EdgeInsets.only(right: 16),
              // 拖动浮层只绘制快照，避免把带 Tooltip 的交互组件迁入 Overlay。
              proxyDecorator: (child, index, animation) => Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: TraeWorkColors.bgBrandPopup,
                child: SizedBox(
                  height: 50,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.drag_indicator, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${draft.field(index)['name']}',
                            style: traeworkText(size: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) {
                draft.moveField(oldIndex, newIndex);
                onSelect(newIndex);
              },
              itemCount: draft.fieldCount,
              itemBuilder: (context, index) {
                final field = draft.field(index);
                final offset = _safeByteOffset(draft, index);
                final active = index == selectedIndex;
                final coverage = draft.coverageOf(index);
                final highlighted =
                    coverage != null &&
                    selectedIndex != null &&
                    draft.field(selectedIndex!)['name'] == coverage.lengthField;
                final coverageError = coverage == null
                    ? null
                    : draft
                          .coverageEditor(coverage.lengthField)
                          .issues
                          .firstOrNull;
                const colors = [
                  Colors.blue,
                  Colors.teal,
                  Colors.deepPurple,
                  Colors.orange,
                  Colors.pink,
                  Colors.indigo,
                ];
                final colorIndex = coverage == null
                    ? 0
                    : draft.lengthCoverages.indexWhere(
                        (r) => r.lengthField == coverage.lengthField,
                      );
                return _FieldRow(
                  key: ObjectKey(draft.fieldIdentity(index)),
                  dragHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Tooltip(
                      message: '拖拽调整字段顺序',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: ColoredBox(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(Icons.drag_indicator, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                  offset: offset,
                  field: field,
                  active: active,
                  covered: coverage != null,
                  coverageFormula: coverage?.derivedField == field['name']
                      ? draft.lengthFormula(coverage!)
                      : null,
                  coverageColor: coverageError != null
                      ? TraeWorkColors.statusError
                      : colors[colorIndex % colors.length],
                  coverageHighlighted: highlighted,
                  canMoveUp: index > 0,
                  canMoveDown: index < draft.fieldCount - 1,
                  onTap: () => onSelect(active ? null : index),
                  onMoveUp: () {
                    draft.moveField(index, index - 1);
                    onSelect(index - 1);
                  },
                  onMoveDown: () {
                    draft.moveField(index, index + 1);
                    onSelect(index + 1);
                  },
                  onDelete: () {
                    draft.removeField(index);
                    if (index == selectedIndex) {
                      onSelect(null);
                    } else if (selectedIndex != null &&
                        index < selectedIndex!) {
                      onSelect(selectedIndex! - 1);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.dragHandle,
    required this.offset,
    required this.field,
    required this.active,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    this.covered = false,
    this.coverageFormula,
    this.coverageColor = Colors.blue,
    this.coverageHighlighted = false,
  });

  final int? offset;
  final Widget dragHandle;
  final Map<String, dynamic> field;
  final bool active;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onTap;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final bool covered;
  final String? coverageFormula;
  final Color coverageColor;
  final bool coverageHighlighted;

  @override
  Widget build(BuildContext context) {
    final name = field['name'] as String;
    final size = int.tryParse('${field['size']}');
    final sample = field['sampleValue'] as String? ?? '';
    final type = field['type'] == 'bytes'
        ? 'bytes'
        : field['type'] == 'float'
        ? (size == 8 ? 'double' : 'float')
        : '${field['type'] == 'sint' ? 'i' : 'u'}${size == null ? '?' : size * 8}';
    return DsInteraction(
      selected: active,
      selectionBorderOnly: true,
      onTap: onTap,
      child: Container(
        height: coverageFormula == null ? 50 : 70,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(
          horizontal: TraeWorkSpacers.s10,
          vertical: TraeWorkSpacers.s8,
        ),

        child: Row(
          children: [
            dragHandle,
            SizedBox(
              width: 50,
              child: Text(
                offset == null
                    ? '—'
                    : '0x${offset!.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                style: traeworkMono(
                  size: TraeWorkFontSizes.bodySm,
                  color: TraeWorkColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: TraeWorkSpacers.s12),
            SizedBox(
              width: 72,
              child: DsTag(label: type, variant: DsTagVariant.neutral),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: const ValueKey('protocol-field-name-highlight'),
                    padding: !covered
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                    decoration: !covered
                        ? null
                        : BoxDecoration(
                            color: coverageColor.withValues(
                              alpha: coverageHighlighted ? 0.16 : 0.07,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                    child: Text(
                      name,
                      style: traeworkText(
                        size: TraeWorkFontSizes.bodyMd,
                        weight: FontWeight.w500,
                        color: TraeWorkColors.textDefault,
                      ),
                    ),
                  ),
                  if (coverageFormula != null)
                    Tooltip(
                      message: coverageFormula!,
                      child: Text(
                        coverageFormula!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: traeworkText(size: 10, color: coverageColor),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: TraeWorkSpacers.s12),
            SizedBox(
              width: 100,
              child: Text(
                sample.isEmpty ? '—' : sample,
                style: traeworkMono(
                  size: TraeWorkFontSizes.bodySm,
                  color: TraeWorkColors.textSecondary,
                ),
              ),
            ),
            _action(Icons.arrow_upward, '上移', canMoveUp ? onMoveUp : null),
            _action(
              Icons.arrow_downward,
              '下移',
              canMoveDown ? onMoveDown : null,
            ),
            _action(Icons.delete_outline, '删除', onDelete, danger: true),
          ],
        ),
      ),
    );
  }

  Widget _action(
    IconData icon,
    String tooltip,
    VoidCallback? onTap, {
    bool danger = false,
  }) {
    return DsButton.icon(
      icon: icon,
      tooltip: tooltip,
      size: DsButtonSize.sm,
      variant: danger ? DsButtonVariant.danger : DsButtonVariant.ghost,
      onPressed: onTap,
    );
  }
}

class _FieldPropsPanel extends StatelessWidget {
  const _FieldPropsPanel({required this.draft, required this.selectedIndex});

  final ProtocolDraft draft;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    // 紧凑密度下属性面板收窄，为帧结构编辑区保留空间。
    final width = Responsive.densityOf(context) == AppLayoutDensity.compact
        ? 240.0
        : 280.0;
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: selectedIndex == null || selectedIndex! >= draft.fieldCount
          ? ListView(
              padding: const EdgeInsets.all(28),
              children: [
                _empty(context, '选择字段查看属性'),
                const SizedBox(height: 24),
                _ProtocolSettings(draft: draft),
              ],
            )
          : _FieldProps(
              // 切换字段只更新数据，保留表单和滚动容器的语义节点。
              key: ObjectKey(draft),
              draft: draft,
              index: selectedIndex!,
            ),
    );
  }

  Widget _empty(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TraeWorkSpacers.s16),
        child: Text(
          message,
          style: traeworkText(
            size: TraeWorkFontSizes.bodySm,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FieldProps extends StatefulWidget {
  const _FieldProps({super.key, required this.draft, required this.index});
  final ProtocolDraft draft;
  final int index;

  @override
  State<_FieldProps> createState() => _FieldPropsState();
}

class _FieldPropsState extends State<_FieldProps> {
  final ScrollController _scrollController = ScrollController();
  late Map<String, dynamic> _field;
  late TextEditingController _nameController;
  late TextEditingController _sizeController;
  late TextEditingController _sampleController;
  late TextEditingController _descController;
  late TextEditingController _fixedController;
  String? _editError;

  @override
  void initState() {
    super.initState();
    _field = widget.draft.field(widget.index);
    _nameController = TextEditingController(
      text: _field['name'] as String? ?? '',
    );
    _sizeController = TextEditingController(text: '${_field['size'] ?? 1}');
    _sampleController = TextEditingController(
      text: _field['sampleValue'] as String? ?? '',
    );
    _descController = TextEditingController(
      text: _field['description'] as String? ?? '',
    );
    _fixedController = TextEditingController(text: _fixedHex(_field));
  }

  @override
  void didUpdateWidget(covariant _FieldProps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _editError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    if (oldWidget.index != widget.index ||
        _field.toString() != widget.draft.field(widget.index).toString()) {
      _field = widget.draft.field(widget.index);
      for (final pair in [
        (_nameController, '${_field['name'] ?? ''}'),
        (_sizeController, '${_field['size'] ?? 1}'),
        (_sampleController, '${_field['sampleValue'] ?? ''}'),
        (_descController, '${_field['description'] ?? ''}'),
        (_fixedController, _fixedHex(_field)),
      ]) {
        if (pair.$1.text != pair.$2) pair.$1.text = pair.$2;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fixedController.dispose();
    _nameController.dispose();
    _sizeController.dispose();
    _sampleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _update(String key, Object? value) {
    try {
      widget.draft.updateField(widget.index, {key: value});
      setState(() {
        _field = widget.draft.field(widget.index);
        _editError = null;
      });
    } catch (error) {
      setState(() => _editError = error.toString());
      if (key == 'name') _nameController.text = '${_field['name']}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final coverage = widget.draft.coverageOf(widget.index);
    final derived = coverage?.derivedField == _field['name'];
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(28),
      children: [
        _sectionTitle('字段属性'),
        if (_editError != null)
          Text(
            _editError!,
            style: traeworkText(size: 12, color: TraeWorkColors.statusError),
          ),
        Text(
          '字节偏移：${_safeByteOffset(widget.draft, widget.index) ?? '待完善'}',
          style: traeworkMono(size: 12),
        ),
        const SizedBox(height: 12),
        _formRow(
          '字段名称',
          DsInput(
            key: const ValueKey('protocol-field-name'),
            controller: _nameController,
            expand: true,
            onChanged: (v) => _update('name', v),
          ),
        ),
        _formRow(
          '数据类型',
          DsSelect<String>(
            key: const ValueKey('protocol-field-type'),
            value: _field['type'] as String? ?? 'uint',
            items: const [
              DropdownMenuItem(value: 'uint', child: Text('uint')),
              DropdownMenuItem(value: 'sint', child: Text('sint')),
              DropdownMenuItem(value: 'float', child: Text('float')),
              DropdownMenuItem(value: 'bytes', child: Text('bytes')),
            ],
            onChanged: (v) => v != null ? _update('type', v) : null,
            expand: true,
          ),
        ),
        _formRow(
          '字段角色',
          DsSelect<String>(
            key: const ValueKey('protocol-field-role'),
            value: _field['role'] as String? ?? 'data',
            items: const [
              DropdownMenuItem(value: 'data', child: Text('data')),
              DropdownMenuItem(value: 'header', child: Text('header')),
              DropdownMenuItem(value: 'frameId', child: Text('frameId')),
              DropdownMenuItem(value: 'length', child: Text('length')),
              DropdownMenuItem(value: 'checksum', child: Text('checksum')),
              DropdownMenuItem(value: 'tail', child: Text('tail')),
              DropdownMenuItem(value: 'skip', child: Text('skip')),
            ],
            onChanged: (v) => v != null ? _update('role', v) : null,
            expand: true,
          ),
        ),
        _formRow(
          '长度（字节）',
          DsInput(
            key: const ValueKey('protocol-field-size'),
            controller: _sizeController,
            enabled: !derived,
            keyboardType: TextInputType.number,
            expand: true,
            onChanged: (v) {
              final n = int.tryParse(v);
              _update('size', n ?? v);
            },
          ),
        ),
        if (derived)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '自动长度：${widget.draft.lengthFormula(coverage!)}',
              style: traeworkText(size: 12, color: TraeWorkColors.textBrand),
            ),
          ),
        if (widget.draft.usesLengthCoverage && _field['role'] == 'length')
          _LengthCoverageEditor(
            draft: widget.draft,
            source: _field['name'] as String,
          ),
        _formRow(
          '样例值',
          DsInput(
            controller: _sampleController,
            expand: true,
            onChanged: (v) => _update('sampleValue', v),
          ),
        ),
        if (_field['role'] == 'header' || _field['role'] == 'tail')
          _formRow(
            '固定字节（HEX）',
            DsInput(
              key: const ValueKey('protocol-field-fixed'),
              controller: _fixedController,
              expand: true,
              placeholder: '55 AA',
              onChanged: (value) {
                try {
                  final bytes = parseHexBytes(value);
                  _update('fixed', bytes.isEmpty ? null : bytes);
                } on FormatException {
                  _update('fixed', null);
                }
              },
            ),
          ),
        const SizedBox(height: TraeWorkSpacers.s8),
        Text(
          '字节序',
          style: traeworkText(
            size: TraeWorkFontSizes.bodySm,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Row(
          children: [
            _radio('little', '小端', _field['littleEndian'] == true),
            _radio('big', '大端', _field['littleEndian'] != true),
          ],
        ),
        const SizedBox(height: TraeWorkSpacers.s12),
        if (!widget.draft.usesLengthCoverage)
          Row(
            children: [
              const Expanded(child: Text('从帧末尾定位')),
              DsSwitch(
                value: _field['fromEnd'] == true,
                onChanged: (value) => _update('fromEnd', value),
              ),
            ],
          ),
        for (final item in [('scale', '缩放'), ('bias', '偏移量')])
          _formRow(
            item.$2,
            DsInput(
              initialValue: '${_field[item.$1]}',
              expand: true,
              onChanged: (value) => _update(item.$1, value),
            ),
          ),
        Text(
          '描述',
          style: traeworkText(
            size: TraeWorkFontSizes.bodySm,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: TraeWorkSpacers.s4),
        DsInput(
          controller: _descController,
          expand: true,
          maxLines: 3,
          onChanged: (value) => _update('description', value),
        ),
        const SizedBox(height: 24),
        const DsDivider(),
        const SizedBox(height: 20),
        _ProtocolSettings(draft: widget.draft),
        _formRow(
          '字段映射',
          DsSelect<String?>(
            value: (widget.draft.values['mapping'] as Map<String, dynamic>)
                .entries
                .where((e) => e.value == _field['name'])
                .firstOrNull
                ?.key,
            groupHeaders: true,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('不映射')),
              // 分组标题：value 用空串哨兵（永不匹配选中态），不可选。
              for (final group in [
                ('设备标识（谁发出）', ['tagId', 'anchorId']),
                ('定位解算', ['x', 'y', 'z', 'angle', 'distance', 'timestamp']),
                ('基站标定', ['anchorX', 'anchorY', 'anchorZ', 'anchorHeading']),
                (
                  '设备状态',
                  [
                    'battery',
                    'temperature',
                    'pressure',
                    'rssi',
                    'successRate',
                    'sos',
                    'ack',
                  ],
                ),
                ('指令下行', ['command']),
                ('UWB 嗅探', ['slot', 'messageType']),
              ]) ...[
                DropdownMenuItem<String?>(
                  value: '',
                  enabled: false,
                  child: Text(group.$1),
                ),
                for (final key in group.$2)
                  DropdownMenuItem(value: key, child: Text(key)),
              ],
            ],
            expand: true,
            onChanged: (v) {
              widget.draft.assignFieldSemantic(
                widget.draft.fieldIdentity(widget.index),
                v,
              );
            },
          ),
        ),
        if ((widget.draft.values['mapping']
                as Map<String, dynamic>)['distance'] ==
            _field['name'])
          _formRow(
            '距离单位',
            DsSelect<String>(
              key: const ValueKey('protocol-distance-unit'),
              value:
                  widget.draft.values['distanceUnit'] as String? ??
                  DistanceUnit.meters.name,
              items: [
                for (final unit in DistanceUnit.values)
                  DropdownMenuItem(
                    value: unit.name,
                    child: Text('${unit.label}（${unit.symbol}）'),
                  ),
              ],
              expand: true,
              onChanged: (v) =>
                  v != null ? widget.draft.set('distanceUnit', v) : null,
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TraeWorkSpacers.s8),
      child: Text(
        title,
        style: traeworkText(
          size: TraeWorkFontSizes.bodySm,
          weight: FontWeight.w600,
          color: TraeWorkColors.textDefault,
        ),
      ),
    );
  }

  Widget _formRow(String label, Widget input) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TraeWorkSpacers.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: TraeWorkSpacers.s4),
            child: Text(
              label,
              style: traeworkText(
                size: TraeWorkFontSizes.bodySm,
                color: TraeWorkColors.textTertiary,
              ),
            ),
          ),
          input,
        ],
      ),
    );
  }

  Widget _radio(String value, String label, bool selected) {
    return DsRadioChoice(
      label: label,
      selected: selected,
      onTap: () => _update('littleEndian', value == 'little'),
    );
  }
}

class _LengthCoverageEditor extends StatelessWidget {
  const _LengthCoverageEditor({required this.draft, required this.source});
  final ProtocolDraft draft;
  final String source;

  @override
  Widget build(BuildContext context) {
    final state = draft.coverageEditor(source);
    final rule = draft.lengthCoverages
        .where((r) => r.lengthField == source)
        .firstOrNull;
    Widget select(
      String key,
      String label,
      String? value,
      ValueChanged<String> update,
    ) {
      final options = switch (key) {
        'start' => state.startOptions,
        'end' => state.endOptions,
        _ => [const CoverageOption(''), ...state.derivedOptions],
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: traeworkText(size: 12)),
            const SizedBox(height: 6),
            DsSelect<String?>(
              key: ValueKey('coverage-$key'),
              value: key == 'derived'
                  ? value ?? ''
                  : (value?.isEmpty == true ? null : value),
              expand: true,
              items: [
                for (final option in options)
                  DropdownMenuItem(
                    value: option.name,
                    child: Text(
                      option.name.isEmpty ? '无需自动计算（全部定长）' : option.label,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) update(v);
              },
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('长度覆盖范围', style: traeworkText(size: 14)),
        const SizedBox(height: 12),
        for (final issue in state.issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              issue.message,
              style: traeworkText(size: 11, color: TraeWorkColors.statusError),
            ),
          ),
        select(
          'start',
          '覆盖起始字段',
          rule?.startField,
          (v) => draft.setLengthCoverage(source, startField: v),
        ),
        select(
          'end',
          '覆盖结束字段',
          rule?.endField,
          (v) => draft.setLengthCoverage(source, endField: v),
        ),
        select(
          'derived',
          '自动长度字段（bytes，可选）',
          rule?.derivedField,
          (v) => draft.setLengthCoverage(source, derivedField: v),
        ),
        Text(
          '全部定长时无需自动计算；选择一个变长数据段后，其类型设为 bytes，长度由 Length 减去范围内其余字段长度得到。样例值填写 HEX 字节。',
          style: traeworkText(size: 11),
        ),
        if (rule != null) ...[
          Text(state.formula, style: traeworkText(size: 12)),
          DsButton(
            label: '移除覆盖规则',
            size: DsButtonSize.sm,
            variant: DsButtonVariant.secondary,
            onPressed: () => draft.removeLengthCoverage(source),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ProtocolSettings extends StatelessWidget {
  const _ProtocolSettings({required this.draft});
  final ProtocolDraft draft;

  @override
  Widget build(BuildContext context) {
    final values = draft.values;
    final variable = !draft.usesLengthCoverage && values['lengthField'] != null;
    final mode = draft.usesLengthCoverage
        ? 'coverage'
        : variable
        ? 'length'
        : values['fixedLength'] != null
        ? 'fixed'
        : 'tail';
    Widget form(String label, Widget input) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: traeworkText(size: 12)),
          const SizedBox(height: 6),
          input,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('协议设置', style: traeworkText(size: 14)),
        const SizedBox(height: 16),
        form('数据语义', _KindSelector(draft: draft)),
        form(
          '帧类型',
          DsSelect<String>(
            key: const ValueKey('protocol-frame-mode'),
            value: mode,
            expand: true,
            items: const [
              DropdownMenuItem(value: 'fixed', child: Text('固定长度')),
              DropdownMenuItem(value: 'length', child: Text('长度字段')),
              DropdownMenuItem(value: 'tail', child: Text('帧尾定界')),
              DropdownMenuItem(value: 'coverage', child: Text('按长度覆盖范围确定帧长')),
            ],
            onChanged: (value) {
              if (value != null) {
                draft.setFrameMode(ProtocolFrameMode.values.byName(value));
              }
            },
          ),
        ),
        if (mode == 'fixed')
          form(
            '长度（字节）',
            DsInput(
              initialValue: '${values['fixedLength'] ?? ''}',
              expand: true,
              onChanged: (v) => draft.set('fixedLength', v),
            ),
          )
        else if (variable) ...[
          form(
            '长度字段',
            DsSelect<String>(
              value: values['lengthField'] as String,
              expand: true,
              items: [
                for (var i = 0; i < draft.fieldCount; i++)
                  if (draft.field(i)['role'] == 'length')
                    DropdownMenuItem(
                      value: draft.field(i)['name'] as String,
                      child: Text(draft.field(i)['name'] as String),
                    ),
              ],
              onChanged: (v) => draft.set('lengthField', v),
            ),
          ),
          for (final item in [
            ('lengthMultiplier', '长度乘数'),
            ('lengthAdjustment', '长度调整'),
          ])
            form(
              item.$2,
              DsInput(
                initialValue: '${values[item.$1]}',
                expand: true,
                onChanged: (v) => draft.set(item.$1, v),
              ),
            ),
        ],
        if (draft.usesLengthCoverage) ...[
          Text(
            '选中 length 字段配置各自的覆盖范围；其他字段保持固定长度。',
            style: traeworkText(size: 12),
          ),
          for (final rule in draft.lengthCoverages)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${rule.lengthField}：${rule.startField} → ${rule.endField}',
                      style: traeworkText(size: 11),
                    ),
                  ),
                  DsButton.icon(
                    icon: Icons.close,
                    tooltip: '移除 ${rule.lengthField} 覆盖规则',
                    size: DsButtonSize.sm,
                    onPressed: () =>
                        draft.removeLengthCoverage(rule.lengthField),
                  ),
                ],
              ),
            ),
        ],
        form(
          '最大帧长（字节）',
          DsInput(
            key: const ValueKey('protocol-max-frame-length'),
            initialValue: '${values['maxFrameLength']}',
            expand: true,
            keyboardType: TextInputType.number,
            onChanged: (v) => draft.set('maxFrameLength', v),
          ),
        ),
        form(
          '校验规则',
          DsSelect<String?>(
            value: values['checksum'] as String?,
            expand: true,
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('无')),
              DropdownMenuItem(value: 'sum8', child: Text('SUM8')),
              DropdownMenuItem(value: 'xor8', child: Text('XOR8')),
              DropdownMenuItem(
                value: 'crc16Modbus',
                child: Text('CRC16 Modbus'),
              ),
            ],
            onChanged: (v) => draft.set('checksum', v),
          ),
        ),
      ],
    );
  }
}

class _BinaryPreview extends StatelessWidget {
  const _BinaryPreview({required this.draft});

  final ProtocolDraft draft;
  @override
  Widget build(BuildContext context) {
    final preview = draft.preview;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(TraeWorkSpacers.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 200,
            child: DsSelect<bool>(
              value: draft.testSelectedOnly,
              items: const [
                DropdownMenuItem(value: false, child: Text('整份协议混合测试')),
                DropdownMenuItem(value: true, child: Text('所选消息类型测试')),
              ],
              onChanged: (value) {
                if (value != null) draft.testSelectedOnly = value;
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Hex 测试',
                style: traeworkText(
                  size: TraeWorkFontSizes.bodySm,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: TraeWorkSpacers.s12),
              Expanded(
                child: DsInput(
                  initialValue: draft.inputHex,
                  placeholder: '55 AA 00 19 12 34 56 78 ...',
                  expand: true,
                  mono: true,
                  onChanged: (value) => draft.inputHex = value,
                ),
              ),
              const SizedBox(width: TraeWorkSpacers.s8),
              DsButton(
                label: '测试解析',
                variant: DsButtonVariant.secondary,
                size: DsButtonSize.sm,
                onPressed:
                    draft.inputHex.isEmpty ||
                        (draft.testSelectedOnly
                                ? draft.validateSelected()
                                : draft.validate())
                            .isNotEmpty
                    ? null
                    : () {
                        try {
                          draft.testHex(
                            draft.inputHex,
                            selectedOnly: draft.testSelectedOnly,
                          );
                        } catch (error) {
                          _showSnack(error.toString());
                        }
                      },
              ),
              const SizedBox(width: TraeWorkSpacers.s8),
              DsButton(
                label: '生成样例',
                variant: DsButtonVariant.secondary,
                size: DsButtonSize.sm,
                onPressed: draft.refreshSample,
              ),
            ],
          ),
          const SizedBox(height: TraeWorkSpacers.s12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(TraeWorkSpacers.s12),
              decoration: BoxDecoration(
                color: TraeWorkColors.bgInvert,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '样例帧：',
                      style: traeworkMono(
                        size: TraeWorkFontSizes.bodySm,
                        color: TraeWorkColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: TraeWorkSpacers.s4),
                    Text(
                      draft.sampleHex,
                      style: traeworkMono(
                        size: TraeWorkFontSizes.bodySm,
                        color: TraeWorkColors.textOnBrand,
                      ),
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: TraeWorkSpacers.s16),
                      Text(
                        '解析结果：${preview.succeeded ? "成功（${preview.frames.length} 帧）" : "失败（${preview.errorCount} 错误）"}',
                        style: traeworkMono(
                          size: TraeWorkFontSizes.bodySm,
                          color: preview.succeeded
                              ? TraeWorkColors.statusSuccess
                              : TraeWorkColors.statusError,
                        ),
                      ),
                      if (preview.errors.isNotEmpty) ...[
                        const SizedBox(height: TraeWorkSpacers.s4),
                        for (final error in preview.errors.take(8))
                          Text(
                            error,
                            style: traeworkMono(
                              size: TraeWorkFontSizes.bodyXs,
                              color: TraeWorkColors.statusError,
                            ),
                          ),
                      ],
                      for (var i = 0; i < preview.frames.length; i++) ...[
                        const SizedBox(height: 12),
                        Text(
                          '第 ${i + 1} 帧 · ${preview.frames[i].messageTypeName} · ${preview.frames[i].bytes.length} 字节',
                          style: traeworkMono(
                            size: 12,
                            color: TraeWorkColors.textOnBrand,
                          ),
                        ),
                        for (final entry in preview.frames[i].values.entries)
                          Text(
                            '${entry.key}=${entry.value}',
                            style: traeworkMono(
                              size: 12,
                              color: TraeWorkColors.textOnBrand,
                            ),
                          ),
                        for (final entry
                            in preview.frames[i].messageType?.mapping.entries ??
                                <MapEntry<String, String>>[])
                          Text(
                            '${entry.key} ← ${entry.value}：${preview.frames[i].values[entry.value]}',
                            style: traeworkMono(
                              size: 12,
                              color: TraeWorkColors.textOnBrand,
                            ),
                          ),
                        if (preview.frames[i].layout != null) ...[
                          for (final rule
                              in preview
                                      .frames[i]
                                      .messageType
                                      ?.lengthCoverages ??
                                  <LengthCoverage>[])
                            Text(
                              '${rule.lengthField}=${preview.frames[i].layout!.lengthValues[rule.lengthField]} · ${rule.startField} → ${rule.endField} · ${rule.derivedField.isEmpty ? '全部定长' : '${rule.derivedField}=${preview.frames[i].layout!.sizes[rule.derivedField]}B'}',
                              style: traeworkMono(
                                size: 12,
                                color: TraeWorkColors.textOnBrand,
                              ),
                            ),
                          for (final entry
                              in preview.frames[i].layout!.offsets.entries)
                            Text(
                              '${entry.key}：偏移 ${entry.value}，长度 ${preview.frames[i].layout!.sizes[entry.key]}B，值 ${preview.frames[i].values[entry.key] ?? '跳过'}',
                              style: traeworkMono(
                                size: 11,
                                color: TraeWorkColors.textOnBrand,
                              ),
                            ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) => showDsToast(message);
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({required this.controller, required this.draft});

  final AppController controller;
  final ProtocolDraft draft;

  @override
  Widget build(BuildContext context) {
    final busy = controller.snapshot.operation != null;
    final validation = draft.validate().firstOrNull;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(
        horizontal: TraeWorkSpacers.s12,
        vertical: TraeWorkSpacers.s8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          DsTag(
            label: draft.isDirty ? '未保存' : '已保存',
            variant: draft.isDirty
                ? DsTagVariant.warning
                : DsTagVariant.success,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                controller.lastError ?? validation ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: traeworkText(
                  size: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
          DsButton(
            label: '复制为副本',
            icon: Icons.copy,
            variant: DsButtonVariant.secondary,
            onPressed: busy
                ? null
                : () {
                    final newDraft = controller.application.duplicateProtocol(
                      draft.id,
                      '${draft.values['name']} 副本',
                    );
                    controller.selectProtocol(newDraft.id);
                  },
          ),
          const SizedBox(width: TraeWorkSpacers.s8),
          DsButton(
            label: '丢弃修改',
            variant: DsButtonVariant.secondary,
            onPressed: draft.isDirty && !busy ? () => draft.discard() : null,
          ),
          const SizedBox(width: TraeWorkSpacers.s8),
          DsButton(
            label: busy ? '保存中…' : '保存协议',
            icon: Icons.save,
            variant: DsButtonVariant.brand,
            onPressed: busy || validation != null
                ? null
                : () => controller.saveProtocol(draft.id),
          ),
          const SizedBox(width: 8),
          DsButton(
            label: '测试解析',
            icon: Icons.play_arrow_outlined,
            variant: DsButtonVariant.brand,
            onPressed:
                (draft.testSelectedOnly
                    ? draft.validateSelected().isNotEmpty
                    : validation != null)
                ? null
                : () {
                    try {
                      draft.testHex(
                        draft.inputHex.isEmpty
                            ? draft.generateSampleHex()
                            : draft.inputHex,
                        selectedOnly: draft.testSelectedOnly,
                      );
                    } catch (error) {
                      showDsToast(error.toString());
                    }
                  },
          ),
          if (draft.preview != null) ...[
            const SizedBox(width: 12),
            DsTag(
              label: draft.preview!.succeeded ? '解析成功' : '解析失败',
              variant: draft.preview!.succeeded
                  ? DsTagVariant.success
                  : DsTagVariant.error,
            ),
          ],
        ],
      ),
    );
  }
}

String _fixedHex(Map<String, dynamic> field) =>
    ((field['fixed'] as List<dynamic>?) ?? [])
        .map(
          (value) =>
              (value as int).toRadixString(16).padLeft(2, '0').toUpperCase(),
        )
        .join(' ');

int? _safeByteOffset(ProtocolDraft draft, int index) {
  try {
    return draft.byteOffset(index);
  } on FormatException {
    return null;
  }
}

Widget _empty(String message) {
  return Center(
    child: Text(
      message,
      style: traeworkText(
        size: TraeWorkFontSizes.bodySm,
        color: TraeWorkColors.textTertiary,
      ),
    ),
  );
}
