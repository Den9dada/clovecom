import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/toolbox/toolbox_file_entry.dart';
import '../../../services/toolbox/hex_text_parser.dart';
import '../../../services/status_bar_service.dart';
import '../../../viewmodels/toolbox/hex_to_bin_viewmodel.dart';
import '../widgets/hex_ascii_viewer.dart';
import '../widgets/tool_status_panel.dart';

class HexToBinTool extends StatefulWidget {
  const HexToBinTool({super.key});

  @override
  State<HexToBinTool> createState() => _HexToBinToolState();
}

class _HexToBinToolState extends State<HexToBinTool>
    with AutomaticKeepAliveClientMixin {
  late final HexToBinViewModel _viewModel = HexToBinViewModel();
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
    final entry = _viewModel.selectedEntry;
    StatusBarService().updateToolboxStatus(
      0,
      StatusBarInfo(
        text: entry != null ? entry.path : '就绪 — 拖入或打开 HEX 文件',
        icon: entry != null ? Icons.insert_drive_file : null,
      ),
    );
  }

  bool get _isCurrentTab {
    final controller = DefaultTabController.of(context);
    return controller.index == 0;
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
              .where(
                (p) =>
                    p.isNotEmpty &&
                    (p.toLowerCase().endsWith('.hex') ||
                        p.toLowerCase().endsWith('.bin')),
              )
              .toList();
          if (paths.isNotEmpty) {
            await _viewModel.importPaths(paths);
            if (mounted) _showError();
          }
          if (mounted) setState(() => _dragging = false);
        },
        child: _HexToBinToolContent(
          dragging: _dragging,
          onImport: _importFiles,
        ),
      ),
    );
  }

  Future<void> _importFiles() async {
    final result = await FilePickerCompat.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['hex', 'bin'],
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}

class _HexToBinToolContent extends StatelessWidget {
  const _HexToBinToolContent({required this.dragging, required this.onImport});

  final bool dragging;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HexToBinViewModel>();
    final viewer = HexAsciiViewer(
      bytes: viewModel.selectedBytes,
      baseAddress: viewModel.selectedBaseAddress,
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
            if (dragging) _buildDragOverlay(context),
          ],
        );
      },
    );
  }

  Widget _buildToolBar(BuildContext context, HexToBinViewModel viewModel) {
    final cs = Theme.of(context).colorScheme;
    final btnStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      minimumSize: const Size(0, 28),
      textStyle: Theme.of(context).textTheme.titleSmall,
    );
    final btnStyleOutlined = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      minimumSize: const Size(0, 28),
      textStyle: Theme.of(context).textTheme.titleSmall,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_outlined, size: 20),
            label: const Text('导入文件'),
            style: btnStyle,
          ),
          const SizedBox(width: 8),
          // HEX → BIN
          FilledButton.icon(
            onPressed: viewModel.canExportCurrentBin
                ? () async {
                    await context.read<HexToBinViewModel>().exportCurrent();
                    if (context.mounted) _showError(context);
                  }
                : null,
            icon: const Icon(Icons.transform_outlined, size: 20),
            label: const Text('导出BIN'),
            style: btnStyle,
          ),
          const SizedBox(width: 8),
          // BIN → HEX
          FilledButton.icon(
            onPressed: viewModel.canExportCurrentHex
                ? () => _showHexExportDialog(context)
                : null,
            icon: const Icon(Icons.code_outlined, size: 20),
            label: const Text('导出HEX'),
            style: btnStyle,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: viewModel.canExportBatchBin
                ? () async {
                    await context.read<HexToBinViewModel>().exportBatch();
                    if (context.mounted) _showError(context);
                  }
                : null,
            icon: const Icon(Icons.drive_folder_upload_outlined, size: 20),
            label: const Text('批量BIN'),
            style: btnStyleOutlined,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: viewModel.canExportBatchHex
                ? () => _showHexExportDialog(context, batch: true)
                : null,
            icon: const Icon(Icons.drive_folder_upload_outlined, size: 20),
            label: const Text('批量HEX'),
            style: btnStyleOutlined,
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, HexToBinViewModel viewModel) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ToolStatusPanel(
              title: '转换状态',
              message: viewModel.entries.isEmpty
                  ? '等待导入文件'
                  : '已导入 ${viewModel.entries.length} 个文件',
              error: viewModel.lastError,
              onDismissError: () =>
                  context.read<HexToBinViewModel>().clearError(),
            ),
            const SizedBox(height: 10),
            Text('文件列表', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildFileList(context, viewModel),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(BuildContext context, HexToBinViewModel viewModel) {
    final entries = viewModel.entries;
    final colorScheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) {
      return Text(
        '尚未导入文件\n点击顶部"导入HEX/BIN"或拖入文件',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final failed = entry.status == ToolboxFileStatus.failed;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.read<HexToBinViewModel>().selectEntry(index),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: index == viewModel.selectedIndex
                  ? colorScheme.primaryContainer.withValues(alpha: 0.32)
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: failed ? colorScheme.error : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  entry.isHex
                      ? Icons.code_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: failed ? colorScheme.error : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.extension.toUpperCase()} · ${HexToBinViewModel.formatBytes(entry.size)} · ${_statusText(entry.status)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: failed
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      context.read<HexToBinViewModel>().removeEntry(index),
                  tooltip: '删除文件',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        );
      },
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
                '拖放HEX/BIN文件到此处导入',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(ToolboxFileStatus status) {
    return switch (status) {
      ToolboxFileStatus.idle => '未处理',
      ToolboxFileStatus.parsed => '解析成功',
      ToolboxFileStatus.failed => '解析失败',
      ToolboxFileStatus.exported => '已导出',
    };
  }

  void _showHexExportDialog(BuildContext context, {bool batch = false}) {
    final vm = context.read<HexToBinViewModel>();
    final entry = vm.selectedEntry;
    final initialAddr = entry?.baseAddress ?? 0;
    final addrCtrl = TextEditingController(
      text: '0x${initialAddr.toRadixString(16).toUpperCase()}',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(batch ? '批量导出HEX - 起始地址' : '导出HEX - 起始地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '设置HEX文件的起始地址（偏移量）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addrCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '起始地址',
                hintText: '支持十六进制(0x...)或十进制',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final addrText = addrCtrl.text;
              int baseAddr = 0;
              try {
                baseAddr = HexTextParser.parseNumber(addrText);
              } catch (_) {
                baseAddr = 0;
              }
              if (batch) {
                await vm.exportBatchHex(baseAddress: baseAddr);
              } else {
                await vm.exportCurrentHex(baseAddress: baseAddr);
              }
              if (context.mounted) _showError(context);
            },
            child: const Text('导出'),
          ),
        ],
      ),
    );
  }

  void _showError(BuildContext context) {
    final error = context.read<HexToBinViewModel>().lastError;
    if (error == null || error.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
