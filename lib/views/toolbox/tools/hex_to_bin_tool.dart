import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/file_drop_zone.dart';
import '../widgets/hex_ascii_viewer.dart';
import '../widgets/tool_status_panel.dart';

class HexToBinTool extends StatelessWidget {
  const HexToBinTool({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final controls = _Controls(
          children: [
            FileDropZone(
              title: '导入HEX/BIN',
              subtitle: '拖入或选择 .hex / .bin 文件，支持批量导入',
              allowedExtensions: const ['hex', 'bin'],
              allowMultiple: true,
              onFilesSelected: (_) async {},
            ),
            const SizedBox(height: 10),
            const ToolStatusPanel(
              title: '转换状态',
              message: '等待导入文件',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.transform_outlined, size: 16),
              label: const Text('转换当前'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.drive_folder_upload_outlined, size: 16),
              label: const Text('批量导出'),
            ),
          ],
        );
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

class _Controls extends StatelessWidget {
  const _Controls({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
