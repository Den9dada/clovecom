import 'package:material_ui/material_ui.dart';

class ToolStatusPanel extends StatelessWidget {
  const ToolStatusPanel({
    super.key,
    required this.title,
    required this.message,
    this.error,
    this.onDismissError,
  });

  final String title;
  final String message;
  final String? error;
  final VoidCallback? onDismissError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasError = error != null && error!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasError
            ? colorScheme.errorContainer.withValues(alpha: 0.35)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError ? colorScheme.error : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasError ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: hasError ? colorScheme.error : colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  hasError ? error! : message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: hasError
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (hasError && onDismissError != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDismissError,
              tooltip: '关闭错误提示',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}
