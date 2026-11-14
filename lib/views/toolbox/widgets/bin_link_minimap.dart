import 'package:flutter/material.dart';

import '../../../models/toolbox/bin_link_segment.dart';

class BinLinkMinimap extends StatelessWidget {
  const BinLinkMinimap({
    super.key,
    required this.segments,
    required this.previewBaseAddress,
    required this.previewEndAddress,
    required this.layoutRevision,
    this.scrollRatio = 0,
    this.viewportRatio = 1,
    this.width = 28,
  });

  final List<BinLinkSegment> segments;
  final int previewBaseAddress;
  final int previewEndAddress;
  final int layoutRevision;
  final double scrollRatio;
  final double viewportRatio;
  final double width;

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
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: Column(
        children: [
          Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Text(
              'M',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(7),
                ),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _MinimapPainter(
                    segments: segments,
                    previewBaseAddress: previewBaseAddress,
                    previewEndAddress: previewEndAddress,
                    layoutRevision: layoutRevision,
                    scrollRatio: scrollRatio,
                    viewportRatio: viewportRatio,
                    bgColor: cs.surfaceContainerLow,
                    accentColor: cs.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.segments,
    required this.previewBaseAddress,
    required this.previewEndAddress,
    required this.layoutRevision,
    required this.scrollRatio,
    required this.viewportRatio,
    required this.bgColor,
    required this.accentColor,
  });

  final List<BinLinkSegment> segments;
  final int previewBaseAddress;
  final int previewEndAddress;
  final int layoutRevision;
  final double scrollRatio;
  final double viewportRatio;
  final Color bgColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final enabled = segments.where((s) => s.enabled).toList();

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );

    if (enabled.isEmpty) return;

    final totalRange = previewEndAddress - previewBaseAddress;
    if (totalRange <= 0) return;

    for (var i = 0; i < enabled.length; i++) {
      final s = enabled[i];
      final color = BinLinkMinimap._palette[i % BinLinkMinimap._palette.length];
      final y = (s.address - previewBaseAddress) / totalRange * size.height;
      final alignedH =
          (s.alignedEndAddress - s.address) / totalRange * size.height;
      final dataH =
          (s.bytes.length / (s.alignedEndAddress - s.address) * alignedH).clamp(
            1.0,
            size.height,
          );
      canvas.drawRect(
        Rect.fromLTWH(2, y, size.width - 4, dataH),
        Paint()..color = color,
      );
    }

    // 定位线：表示 HEX 预览的当前可视区域
    if (scrollRatio > 0 || viewportRatio < 1) {
      final viewportH = (viewportRatio * size.height).clamp(4.0, size.height);
      final viewportY = (scrollRatio * size.height).clamp(
        0.0,
        size.height - viewportH,
      );

      final linePaint = Paint()
        ..color = accentColor
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(0, viewportY),
        Offset(size.width, viewportY),
        linePaint,
      );
      canvas.drawLine(
        Offset(0, viewportY + viewportH),
        Offset(size.width, viewportY + viewportH),
        linePaint,
      );
      // 可视区半透明填充
      canvas.drawRect(
        Rect.fromLTWH(0, viewportY, size.width, viewportH),
        Paint()..color = accentColor.withValues(alpha: 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      layoutRevision != old.layoutRevision ||
      previewBaseAddress != old.previewBaseAddress ||
      previewEndAddress != old.previewEndAddress ||
      scrollRatio != old.scrollRatio ||
      viewportRatio != old.viewportRatio;
}
