import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/file_drop_zone.dart';
import '../widgets/hex_ascii_viewer.dart';
import '../widgets/tool_status_panel.dart';

class BinLinkTool extends StatelessWidget {
  const BinLinkTool({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final controls = _LinkControls();
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

class _LinkControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
              onFilesSelected: (_) async {},
            ),
            const SizedBox(height: 10),
            const ToolStatusPanel(title: '拼接状态', message: '等待添加片段'),
            const SizedBox(height: 10),
            const TextField(decoration: InputDecoration(labelText: '填充值')),
            const SizedBox(height: 8),
            const TextField(decoration: InputDecoration(labelText: '片段地址')),
            const SizedBox(height: 8),
            const TextField(
              maxLines: 3,
              decoration: InputDecoration(labelText: '手动HEX数据'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新增HEX片段'),
            ),
            const SizedBox(height: 12),
            Text('片段列表', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '尚未添加片段',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.save_alt_outlined, size: 16),
              label: const Text('导出拼接BIN'),
            ),
          ],
        ),
      ),
    );
  }
}
