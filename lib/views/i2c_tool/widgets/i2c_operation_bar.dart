// 批量操作栏
//
// 全部读取、全部写入、导出 Excel 按钮

import 'package:flutter/material.dart';
import '../../../ui/desktop_theme.dart';

class I2cOperationBar extends StatelessWidget {
  final bool isBusy;
  final bool hasMap;
  final VoidCallback? onReadAll;
  final VoidCallback? onWriteAll;
  final VoidCallback? onExport;

  const I2cOperationBar({
    super.key,
    required this.isBusy,
    required this.hasMap,
    this.onReadAll,
    this.onWriteAll,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            DesktopAction(
              label: '全部读取',
              icon: Icons.download_done,
              busy: isBusy,
              onPressed: hasMap ? onReadAll : null,
            ),
            const SizedBox(width: 8),
            DesktopAction(
              label: '全部写入',
              icon: Icons.upload,
              kind: DesktopActionKind.primary,
              busy: isBusy,
              onPressed: hasMap ? onWriteAll : null,
            ),
            if (onExport != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: isBusy || !hasMap ? null : onExport,
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('导出Excel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
