import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/file_drop_zone.dart';
import '../widgets/hex_ascii_viewer.dart';
import '../widgets/tool_status_panel.dart';

class BinEditorTool extends StatelessWidget {
  const BinEditorTool({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final controls = _EditorControls();
        final viewer = HexAsciiViewer(bytes: Uint8List(0));

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
}

class _EditorControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
              onFilesSelected: (_) async {},
            ),
            const SizedBox(height: 10),
            const ToolStatusPanel(title: '编辑状态', message: '等待导入 BIN 文件'),
            const SizedBox(height: 10),
            Text('编辑操作', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            const TextField(decoration: InputDecoration(labelText: '地址')),
            const SizedBox(height: 8),
            const TextField(
              maxLines: 3,
              decoration: InputDecoration(labelText: 'HEX数据'),
            ),
            const SizedBox(height: 8),
            const TextField(decoration: InputDecoration(labelText: '删除长度')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: null, child: const Text('插入')),
                FilledButton(onPressed: null, child: const Text('修改')),
                OutlinedButton(onPressed: null, child: const Text('删除')),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('撤销'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.save_alt_outlined, size: 16),
              label: const Text('导出BIN'),
            ),
          ],
        ),
      ),
    );
  }
}
