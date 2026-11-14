// USB通信视图文件
//
// 该文件实现了USB通信模块的占位页面。

import 'package:flutter/material.dart';
import '../../services/status_bar_service.dart';

/// USB通信视图组件
///
/// 作为USB通信模块的占位页面，显示功能开发中的提示。
class UsbView extends StatelessWidget {
  const UsbView({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    StatusBarService().update(1, const StatusBarInfo(text: 'USB通信 — 功能开发中'));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.usb, size: 36, color: colorScheme.primary),
                ),
                const SizedBox(height: 18),
                Text(
                  'USB通信模块',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '功能开发中...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
