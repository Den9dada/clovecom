import 'package:flutter/material.dart';

import '../../../models/toolbox/bin_link_segment.dart';

class BinLinkSegmentLayout extends StatelessWidget {
  const BinLinkSegmentLayout({
    super.key,
    required this.segments,
    required this.previewBaseAddress,
    required this.previewEndAddress,
    required this.overlappingPairs,
    this.onScrollTo,
  });

  final List<BinLinkSegment> segments;
  final int previewBaseAddress;
  final int previewEndAddress;
  final List<({int i, int j})> overlappingPairs;
  final void Function(int address)? onScrollTo;

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
    final enabled = segments.where((s) => s.enabled).toList();

    return Card(
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.map_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Segment Layout',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                Text(
                  '0x${previewBaseAddress.toRadixString(16).toUpperCase()}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const [
                      'Menlo',
                      'Courier New',
                      'MiSans',
                    ],
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  ' ~ ',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  '0x${previewEndAddress.toRadixString(16).toUpperCase()}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const [
                      'Menlo',
                      'Courier New',
                      'MiSans',
                    ],
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _SegmentLayoutPainter(
                      segments: enabled,
                      baseAddress: previewBaseAddress,
                      endAddress: previewEndAddress,
                      overlappingPairs: overlappingPairs,
                      bgColor: cs.surface,
                      textColor: cs.onSurface,
                      subtleColor: cs.onSurfaceVariant,
                      errorColor: cs.error,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentLayoutPainter extends CustomPainter {
  _SegmentLayoutPainter({
    required this.segments,
    required this.baseAddress,
    required this.endAddress,
    required this.overlappingPairs,
    required this.bgColor,
    required this.textColor,
    required this.subtleColor,
    required this.errorColor,
  });

  final List<BinLinkSegment> segments;
  final int baseAddress;
  final int endAddress;
  final List<({int i, int j})> overlappingPairs;
  final Color bgColor;
  final Color textColor;
  final Color subtleColor;
  final Color errorColor;

  static const _barH = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) {
      _drawEmpty(canvas, size);
      return;
    }

    final totalRange = endAddress - baseAddress;
    if (totalRange <= 0) return;

    final centerY = size.height / 2;

    // 绘制轴线
    final axisPaint = Paint()
      ..color = subtleColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), axisPaint);

    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final x = (s.address - baseAddress) / totalRange * size.width;
      final w = ((s.alignedEndAddress - s.address) / totalRange * size.width)
          .clamp(2.0, size.width);
      final dataW = (s.bytes.length / (s.alignedEndAddress - s.address) * w)
          .clamp(1.0, w);
      final y = centerY - _barH / 2;

      final isOverlapping = overlappingPairs.any(
        (p) => segments.indexOf(s) == p.i || segments.indexOf(s) == p.j,
      );
      final color = isOverlapping
          ? errorColor
          : BinLinkSegmentLayout._palette[(segments.indexOf(s)) %
                BinLinkSegmentLayout._palette.length];

      // 间隙区域 (填充)
      if (dataW < w - 1) {
        final gapRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + dataW, y, w - dataW, _barH),
          const Radius.circular(3),
        );
        canvas.drawRRect(
          gapRect,
          Paint()..color = subtleColor.withValues(alpha: 0.15),
        );
        // 间隙斜线
        final gapPaint = Paint()
          ..color = subtleColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        for (var gx = x + dataW + 2; gx < x + w - 2; gx += 3) {
          canvas.drawLine(
            Offset(gx, y + 2),
            Offset(gx + 2, y + _barH - 2),
            gapPaint,
          );
        }
      }

      // 分段数据块
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, dataW, _barH),
        const Radius.circular(3),
      );
      canvas.drawRRect(barRect, Paint()..color = color);

      // 地址标注 (在块上方或内部)
      final addrText = '0x${s.address.toRadixString(16).toUpperCase()}';
      final addrTP = TextPainter(
        text: TextSpan(
          text: addrText,
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'Consolas',
            fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
            color: dataW > 50 ? textColor : subtleColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: (dataW - 4).clamp(20.0, double.infinity));
      if (dataW > 30) {
        addrTP.paint(canvas, Offset(x + 4, y + (_barH - addrTP.height) / 2));
      } else {
        // 块太窄，标注画在上方
        addrTP.paint(
          canvas,
          Offset(x - addrTP.width / 2 + dataW / 2, y - addrTP.height - 2),
        );
      }
    }
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: '暂无启用的分段',
        style: TextStyle(color: subtleColor, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(_SegmentLayoutPainter old) =>
      segments != old.segments ||
      baseAddress != old.baseAddress ||
      endAddress != old.endAddress ||
      overlappingPairs != old.overlappingPairs;
}
