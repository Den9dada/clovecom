import 'package:material_ui/material_ui.dart';

class BinLinkStatusBar extends StatelessWidget {
  const BinLinkStatusBar({
    super.key,
    required this.segmentCount,
    required this.enabledCount,
    required this.usedFormatted,
    required this.paddingFormatted,
    required this.outputCrc32Hex,
    required this.hasConflict,
    this.errorMessage,
  });

  final int segmentCount;
  final int enabledCount;
  final String usedFormatted;
  final String paddingFormatted;
  final String outputCrc32Hex;
  final bool hasConflict;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = errorMessage != null && errorMessage!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.check_circle_outline,
              size: 14,
              color: hasError ? cs.error : cs.primary,
            ),
            const SizedBox(width: 6),
            Text(
              hasError ? '错误' : '就绪',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 12),
            Text(
              '分段: $enabledCount/$segmentCount',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 12),
            Text(
              '已用: $usedFormatted',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 12),
            Text(
              '填充: $paddingFormatted',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 12),
            Text(
              'CRC32: $outputCrc32Hex',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hasConflict
                    ? cs.errorContainer.withValues(alpha: 0.5)
                    : cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                hasConflict ? '检测到重叠' : '无冲突',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: hasConflict ? cs.error : cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
