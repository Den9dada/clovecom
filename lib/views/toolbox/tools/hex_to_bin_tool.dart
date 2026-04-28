import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/toolbox/toolbox_file_entry.dart';
import '../../../viewmodels/toolbox/hex_to_bin_viewmodel.dart';
import '../widgets/file_drop_zone.dart';
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

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: const _HexToBinToolContent(),
    );
  }
}

class _HexToBinToolContent extends StatelessWidget {
  const _HexToBinToolContent();

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
        final controls = _buildControls(context, viewModel);

        if (compact) {
          return Column(
            children: [
              Expanded(child: controls),
              const SizedBox(height: 10),
              Expanded(child: viewer),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 320, child: controls),
            const SizedBox(width: 10),
            Expanded(child: viewer),
          ],
        );
      },
    );
  }

  Widget _buildControls(BuildContext context, HexToBinViewModel viewModel) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FileDropZone(
              title: '导入HEX/BIN',
              subtitle: '拖入或选择 .hex / .bin 文件，支持批量导入',
              allowedExtensions: const ['hex', 'bin'],
              allowMultiple: true,
              onFilesSelected: (paths) async {
                await context.read<HexToBinViewModel>().importPaths(paths);
                if (!context.mounted) return;
                _showError(context);
              },
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: viewModel.canExportCurrent
                  ? () async {
                      await context.read<HexToBinViewModel>().exportCurrent();
                      if (!context.mounted) return;
                      _showError(context);
                    }
                  : null,
              icon: const Icon(Icons.transform_outlined, size: 16),
              label: const Text('转换当前'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: viewModel.canExportBatch
                  ? () async {
                      await context.read<HexToBinViewModel>().exportBatch();
                      if (!context.mounted) return;
                      _showError(context);
                    }
                  : null,
              icon: const Icon(Icons.drive_folder_upload_outlined, size: 16),
              label: const Text('批量导出'),
            ),
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
        '尚未导入文件',
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

  String _statusText(ToolboxFileStatus status) {
    return switch (status) {
      ToolboxFileStatus.idle => '未处理',
      ToolboxFileStatus.parsed => '解析成功',
      ToolboxFileStatus.failed => '解析失败',
      ToolboxFileStatus.exported => '已导出',
    };
  }

  void _showError(BuildContext context) {
    final error = context.read<HexToBinViewModel>().lastError;
    if (error == null || error.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
