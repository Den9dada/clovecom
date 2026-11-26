import 'package:clovecom/widgets/app_dropdown.dart';
import 'package:material_ui/material_ui.dart';

class BinLinkToolBar extends StatelessWidget {
  const BinLinkToolBar({
    super.key,
    required this.fillByte,
    required this.canExport,
    required this.onImportBin,
    required this.onAddHexSegment,
    required this.onAutoArrange,
    required this.onCheckConflicts,
    required this.onExport,
    required this.onFillByteChanged,
  });

  final int fillByte;
  final bool canExport;
  final VoidCallback onImportBin;
  final VoidCallback onAddHexSegment;
  final VoidCallback onAutoArrange;
  final VoidCallback onCheckConflicts;
  final VoidCallback onExport;
  final ValueChanged<int> onFillByteChanged;

  static const _fillPresets = [0xFF, 0x00, 0xAA, 0x55];
  static const _fillLabels = ['FF', '00', 'AA', '55'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compact = MediaQuery.of(context).size.width < 700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          if (compact)
            _compactMenu(context)
          else ...[
            _toolButton(
              context,
              Icons.upload_file_outlined,
              '导入BIN',
              onImportBin,
            ),
            const SizedBox(width: 6),
            _toolButton(context, Icons.add, '新增HEX段', onAddHexSegment),
            const SizedBox(width: 6),
            _toolButton(
              context,
              Icons.sort,
              '自动排列',
              onAutoArrange,
              isSecondary: true,
            ),
            const SizedBox(width: 6),
            _toolButton(
              context,
              Icons.warning_amber_outlined,
              '检查冲突',
              onCheckConflicts,
              isSecondary: true,
            ),
            const SizedBox(width: 6),
            _toolButton(
              context,
              Icons.save_alt_outlined,
              '导出BIN',
              canExport ? onExport : null,
            ),
          ],
          const Spacer(),
          Text(
            '填充:',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          _fillDropdown(context),
        ],
      ),
    );
  }

  Widget _compactMenu(BuildContext context) {
    return AppPopupMenuButton<String>(
      tooltip: '操作',
      icon: Icon(
        Icons.menu,
        size: 24,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      onSelected: (v) {
        switch (v) {
          case 'import':
            onImportBin();
          case 'add':
            onAddHexSegment();
          case 'arrange':
            onAutoArrange();
          case 'check':
            onCheckConflicts();
          case 'export':
            if (canExport) onExport();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'import',
          child: Text('导入BIN', style: Theme.of(context).textTheme.titleSmall),
        ),
        PopupMenuItem(
          value: 'add',
          child: Text('新增HEX段', style: Theme.of(context).textTheme.titleSmall),
        ),
        PopupMenuItem(
          value: 'arrange',
          child: Text('自动排列', style: Theme.of(context).textTheme.titleSmall),
        ),
        PopupMenuItem(
          value: 'check',
          child: Text('检查冲突', style: Theme.of(context).textTheme.titleSmall),
        ),
        if (canExport)
          PopupMenuItem(
            value: 'export',
            child: Text('导出BIN', style: Theme.of(context).textTheme.titleSmall),
          ),
      ],
    );
  }

  Widget _toolButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool isSecondary = false,
  }) {
    final commonStyle =
        (isSecondary ? OutlinedButton.styleFrom : FilledButton.styleFrom)(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minimumSize: const Size(0, 28),
          textStyle: Theme.of(context).textTheme.titleSmall,
        );
    if (isSecondary) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: commonStyle,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: commonStyle,
    );
  }

  Widget _fillDropdown(BuildContext context) {
    return AppPopupMenuButton<int>(
      initialValue: fillByte,
      onSelected: onFillByteChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fillByte.toRadixString(16).padLeft(2, '0').toUpperCase(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<int>>[];
        for (var i = 0; i < _fillPresets.length; i++) {
          items.add(
            PopupMenuItem<int>(
              value: _fillPresets[i],
              height: 32,
              child: Text(
                _fillLabels[i],
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
                ),
              ),
            ),
          );
        }
        items.add(const PopupMenuDivider());
        items.add(
          PopupMenuItem<int>(
            value: -1,
            height: 32,
            child: Text(
              '自定义...',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
        return items;
      },
    );
  }
}
