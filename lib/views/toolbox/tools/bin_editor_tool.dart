import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/status_bar_service.dart';
import '../toolbox_tool_registry.dart';
import '../../../ui/widgets/ds_toast.dart';
import '../../../viewmodels/toolbox/bin_editor_viewmodel.dart';
import '../widgets/hex_ascii_viewer.dart';
import '../widgets/tool_status_panel.dart';

class BinEditorTool extends StatefulWidget {
  const BinEditorTool({super.key});

  @override
  State<BinEditorTool> createState() => _BinEditorToolState();
}

class _BinEditorToolState extends State<BinEditorTool>
    with AutomaticKeepAliveClientMixin {
  late final BinEditorViewModel _viewModel = BinEditorViewModel();
  var _dragging = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_updateStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateStatus());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_updateStatus);
    _viewModel.dispose();
    super.dispose();
  }

  void _updateStatus() {
    final count = _viewModel.files.length;
    StatusBarService().updateToolboxStatus(
      ToolboxToolRegistry.binEditorId,
      StatusBarInfo(
        text: count > 0
            ? '$count 个文件 · ${_viewModel.fileName}'
            : '就绪 — 拖入或打开 BIN 文件',
        icon: count > 0 ? Icons.insert_drive_file : null,
      ),
    );
  }

  bool get _isCurrentTab {
    final controller = DefaultTabController.of(context);
    return controller.index ==
        ToolboxToolRegistry.slotOf(ToolboxToolRegistry.binEditorId);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: DropTarget(
        onDragEntered: (_) {
          if (_isCurrentTab) setState(() => _dragging = true);
        },
        onDragExited: (_) {
          if (_isCurrentTab) setState(() => _dragging = false);
        },
        onDragDone: (details) async {
          if (!_isCurrentTab) return;
          final paths = details.files
              .map((f) => f.path)
              .where((p) => p.isNotEmpty && p.toLowerCase().endsWith('.bin'))
              .toList();
          if (paths.isNotEmpty) {
            await _viewModel.importPaths(paths);
            if (mounted) _showError();
          }
          if (mounted) setState(() => _dragging = false);
        },
        child: _BinEditorToolContent(
          dragging: _dragging,
          onImport: _importFile,
        ),
      ),
    );
  }

  Future<void> _importFile() async {
    final result = await FilePickerCompat.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (result == null) return;
    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    await _viewModel.importPaths(paths);
    if (mounted) _showError();
  }

  void _showError() {
    final error = _viewModel.lastError;
    if (error == null || error.isEmpty) return;
    if (!mounted) return;
    showDsToast(error, kind: DsToastKind.error);
  }
}

class _BinEditorToolContent extends StatefulWidget {
  const _BinEditorToolContent({required this.dragging, required this.onImport});

  final bool dragging;
  final Future<void> Function() onImport;

  @override
  State<_BinEditorToolContent> createState() => _BinEditorToolContentState();
}

class _BinEditorToolContentState extends State<_BinEditorToolContent> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _hexController = TextEditingController();
  final TextEditingController _deleteLengthController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    _hexController.dispose();
    _deleteLengthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<BinEditorViewModel>();
    final viewer = HexAsciiViewer(
      key: ValueKey(viewModel.activeFile),
      bytes: viewModel.bytes,
      onByteChanged: (index, value) {
        context.read<BinEditorViewModel>().replaceByte(
          index,
          value.toRadixString(16).padLeft(2, '0'),
        );
        _showError(context);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        return Stack(
          children: [
            Column(
              children: [
                _buildToolBar(context, viewModel),
                Expanded(
                  child: compact
                      ? Column(
                          children: [
                            Expanded(child: _buildControls(context, viewModel)),
                            const SizedBox(height: 8),
                            Expanded(child: viewer),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 320,
                              child: _buildControls(context, viewModel),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: viewer),
                          ],
                        ),
                ),
              ],
            ),
            if (widget.dragging) _buildDragOverlay(context),
          ],
        );
      },
    );
  }

  Widget _buildToolBar(BuildContext context, BinEditorViewModel viewModel) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: widget.onImport,
            icon: const Icon(Icons.upload_file_outlined, size: 20),
            label: const Text('导入BIN'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 28),
              textStyle: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: viewModel.hasFile
                ? () async {
                    await context.read<BinEditorViewModel>().exportEdited();
                    if (context.mounted) _showError(context);
                  }
                : null,
            icon: const Icon(Icons.save_alt_outlined, size: 20),
            label: const Text('导出BIN'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 28),
              textStyle: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, BinEditorViewModel viewModel) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (viewModel.files.isNotEmpty) ...[
              _buildFileList(context, viewModel),
              const SizedBox(height: 8),
            ],
            ToolStatusPanel(
              title: '编辑状态',
              message: viewModel.hasFile
                  ? '${viewModel.fileName} · ${viewModel.bytes.length} B${viewModel.hasUnsavedChanges ? ' · 未保存' : ''}'
                  : '等待导入 BIN 文件',
              error: viewModel.lastError,
              onDismissError: () =>
                  context.read<BinEditorViewModel>().clearError(),
            ),
            const SizedBox(height: 10),
            Text('编辑操作', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: '地址'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hexController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'HEX数据'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _deleteLengthController,
              decoration: const InputDecoration(labelText: '删除长度'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: viewModel.hasFile
                      ? () {
                          context.read<BinEditorViewModel>().applyInsert(
                            _addressController.text,
                            _hexController.text,
                          );
                          _showError(context);
                        }
                      : null,
                  child: const Text('插入'),
                ),
                FilledButton(
                  onPressed: viewModel.hasFile
                      ? () {
                          context.read<BinEditorViewModel>().applyReplace(
                            _addressController.text,
                            _hexController.text,
                          );
                          _showError(context);
                        }
                      : null,
                  child: const Text('修改'),
                ),
                OutlinedButton(
                  onPressed: viewModel.hasFile
                      ? () {
                          context.read<BinEditorViewModel>().applyDelete(
                            _addressController.text,
                            _deleteLengthController.text,
                          );
                          _showError(context);
                        }
                      : null,
                  child: const Text('删除'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: viewModel.history.isNotEmpty
                  ? () => context.read<BinEditorViewModel>().undoLast()
                  : null,
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('撤销'),
            ),
            const SizedBox(height: 12),
            Text('操作历史', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (viewModel.history.isEmpty)
              Text(
                '暂无编辑操作',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final operation in viewModel.history.reversed.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${operation.label} @ 0x${operation.address.toRadixString(16).toUpperCase()} · ${operation.length} B',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.15),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.upload_file,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '拖放BIN文件到此处导入',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(BuildContext context) {
    final error = context.read<BinEditorViewModel>().lastError;
    if (error == null || error.isEmpty) return;
    showDsToast(error, kind: DsToastKind.error);
  }

  Widget _buildFileList(BuildContext context, BinEditorViewModel vm) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < vm.files.length; i++)
            _buildFileRow(context, vm, i),
        ],
      ),
    );
  }

  Widget _buildFileRow(BuildContext context, BinEditorViewModel vm, int index) {
    final file = vm.files[index];
    final isActive = vm.activeFileIndex == index;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => vm.switchToFile(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          borderRadius: index == 0 && vm.files.length == 1
              ? BorderRadius.circular(8)
              : null,
          border: index < vm.files.length - 1
              ? Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 16,
              color: isActive ? theme.colorScheme.primary : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${file.name} · ${file.currentBytes.length} B${file.hasUnsavedChanges ? ' *' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? theme.colorScheme.primary : null,
                ),
              ),
            ),
            SizedBox(
              height: 24,
              width: 24,
              child: IconButton(
                onPressed: () => vm.removeFile(index),
                icon: const Icon(Icons.close, size: 14),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tooltip: '移除',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
