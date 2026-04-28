import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../viewmodels/toolbox/bin_editor_viewmodel.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/hex_ascii_viewer.dart';
import '../widgets/tool_status_panel.dart';

class BinEditorTool extends StatelessWidget {
  const BinEditorTool({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BinEditorViewModel(),
      child: const _BinEditorToolContent(),
    );
  }
}

class _BinEditorToolContent extends StatefulWidget {
  const _BinEditorToolContent();

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
    final viewer = HexAsciiViewer(bytes: Uint8List.fromList(viewModel.bytes));

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

  Widget _buildControls(BuildContext context, BinEditorViewModel viewModel) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FileDropZone(
              title: '导入BIN',
              subtitle: '拖入或选择一个 .bin 文件后进行编辑',
              allowedExtensions: const ['bin'],
              allowMultiple: false,
              onFilesSelected: (paths) async {
                await context.read<BinEditorViewModel>().importPaths(paths);
                _showError(context);
              },
            ),
            const SizedBox(height: 10),
            ToolStatusPanel(
              title: '编辑状态',
              message: viewModel.hasFile
                  ? '${viewModel.fileName} · ${viewModel.bytes.length} B${viewModel.hasUnsavedChanges ? ' · 未保存' : ''}'
                  : '等待导入 BIN 文件',
              error: viewModel.lastError,
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
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: viewModel.hasFile
                  ? () async {
                      await context.read<BinEditorViewModel>().exportEdited();
                      _showError(context);
                    }
                  : null,
              icon: const Icon(Icons.save_alt_outlined, size: 16),
              label: const Text('导出BIN'),
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

  void _showError(BuildContext context) {
    final error = context.read<BinEditorViewModel>().lastError;
    if (error == null || error.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
