import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../viewmodels/toolbox/bin_link_viewmodel.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/hex_ascii_viewer.dart';
import '../widgets/tool_status_panel.dart';

class BinLinkTool extends StatelessWidget {
  const BinLinkTool({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BinLinkViewModel(),
      child: const _BinLinkToolContent(),
    );
  }
}

class _BinLinkToolContent extends StatefulWidget {
  const _BinLinkToolContent();

  @override
  State<_BinLinkToolContent> createState() => _BinLinkToolContentState();
}

class _BinLinkToolContentState extends State<_BinLinkToolContent> {
  final TextEditingController _fillController = TextEditingController(
    text: 'FF',
  );
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _hexController = TextEditingController();

  @override
  void dispose() {
    _fillController.dispose();
    _addressController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<BinLinkViewModel>();
    final viewer = HexAsciiViewer(
      bytes: Uint8List.fromList(viewModel.previewBytes),
      baseAddress: viewModel.previewBaseAddress,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final controls = _buildControls(context, viewModel);

        if (compact) {
          return Column(
            children: [
              controls,
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

  Widget _buildControls(BuildContext context, BinLinkViewModel viewModel) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FileDropZone(
              title: '导入BIN片段',
              subtitle: '拖入或选择多个 .bin 文件作为拼接片段',
              allowedExtensions: const ['bin'],
              allowMultiple: true,
              onFilesSelected: (paths) async {
                await context.read<BinLinkViewModel>().importPaths(paths);
                _showError(context);
              },
            ),
            const SizedBox(height: 10),
            ToolStatusPanel(
              title: '拼接状态',
              message: viewModel.segments.isEmpty
                  ? '等待添加片段'
                  : '已添加 ${viewModel.segments.length} 个片段',
              error: viewModel.lastError,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _fillController,
              decoration: const InputDecoration(labelText: '填充值'),
              onSubmitted: (value) {
                context.read<BinLinkViewModel>().setFillByte(value);
                _showError(context);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: '片段地址'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hexController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '手动HEX数据'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                context.read<BinLinkViewModel>().addManualHex(
                  addressText: _addressController.text,
                  hexText: _hexController.text,
                );
                _showError(context);
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新增HEX片段'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                context.read<BinLinkViewModel>().setFillByte(
                  _fillController.text,
                );
                _showError(context);
              },
              icon: const Icon(Icons.preview_outlined, size: 16),
              label: const Text('预览拼接'),
            ),
            const SizedBox(height: 12),
            Text('片段列表', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildSegmentList(context, viewModel),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: viewModel.canExport
                  ? () async {
                      await context.read<BinLinkViewModel>().exportLinked();
                      _showError(context);
                    }
                  : null,
              icon: const Icon(Icons.save_alt_outlined, size: 16),
              label: const Text('导出拼接BIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentList(BuildContext context, BinLinkViewModel viewModel) {
    if (viewModel.segments.isEmpty) {
      return Text(
        '尚未添加片段',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < viewModel.segments.length; index++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  viewModel.segments[index].isManual
                      ? Icons.keyboard_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        viewModel.segments[index].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        '0x${viewModel.segments[index].address.toRadixString(16).toUpperCase()} · ${viewModel.segments[index].bytes.length} B',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      context.read<BinLinkViewModel>().removeSegment(index),
                  tooltip: '删除片段',
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showError(BuildContext context) {
    final error = context.read<BinLinkViewModel>().lastError;
    if (error == null || error.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
