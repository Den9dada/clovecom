import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../viewmodels/toolbox/bin_link_viewmodel.dart';
import '../../../ui/widgets/ds_toast.dart';
import 'bin_link_segment_card.dart';

class BinLinkSegmentList extends StatelessWidget {
  const BinLinkSegmentList({super.key});

  static const _palette = [
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFE91E63),
    Color(0xFF3F51B5),
    Color(0xFF009688),
  ];

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<BinLinkViewModel>();
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'BIN Segments',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${viewModel.segments.length}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (viewModel.segments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    '尚未添加片段\n点击顶部"导入BIN"或拖入文件',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else ...[
              const Divider(),
              for (var i = 0; i < viewModel.segments.length; i++) ...[
                BinLinkSegmentCard(
                  segment: viewModel.segments[i],
                  index: i,
                  color: _palette[i % _palette.length],
                  hasOverlap: viewModel.overlappingPairs.any(
                    (p) => p.i == i || p.j == i,
                  ),
                  overlapName: _overlapName(viewModel, i),
                  onToggleEnabled: () =>
                      context.read<BinLinkViewModel>().toggleSegmentEnabled(i),
                  onRemove: () =>
                      context.read<BinLinkViewModel>().removeSegment(i),
                  onEditAddress: (text) {
                    context.read<BinLinkViewModel>().updateSegmentAddress(
                      i,
                      text,
                    );
                    _showError(context);
                  },
                  onEditName: (name) {
                    context.read<BinLinkViewModel>().updateSegmentName(i, name);
                  },
                  onAlignmentChanged: (align) {
                    context.read<BinLinkViewModel>().updateSegmentAlignment(
                      i,
                      align,
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String? _overlapName(BinLinkViewModel viewModel, int index) {
    final pair = viewModel.overlappingPairs.firstWhere(
      (p) => p.i == index || p.j == index,
      orElse: () => (i: -1, j: -1),
    );
    if (pair.i == -1) return null;
    final otherIdx = pair.i == index ? pair.j : pair.i;
    if (otherIdx < 0 || otherIdx >= viewModel.segments.length) return null;
    return viewModel.segments[otherIdx].name;
  }

  void _showError(BuildContext context) {
    final error = context.read<BinLinkViewModel>().lastError;
    if (error == null || error.isEmpty) return;
    showDsToast(error, kind: DsToastKind.error);
  }
}
