part of 'communication_session_data_view.dart';

typedef _GutterCell = ({double width, String? label, Color? color});
typedef _SessionRowSummary = ({
  List<_GutterCell> cells,
  String data,
  TextDirection direction,
});
typedef _GutterStyle = ({
  TextStyle text,
  TextDirection direction,
  TextScaler scaler,
  Locale? locale,
});

class _SessionRowListener extends Listener {
  const _SessionRowListener({
    required this.summary,
    required super.onPointerSignal,
    required super.child,
  }) : super(behavior: HitTestBehavior.translucent);

  final _SessionRowSummary? summary;

  @override
  _RenderSessionRowListener createRenderObject(BuildContext context) =>
      _RenderSessionRowListener(
        onPointerSignal: onPointerSignal,
        behavior: behavior,
      )..summary = summary;

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSessionRowListener renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.summary = summary;
  }
}

class _RenderSessionRowListener extends RenderPointerListener
    with _SessionRowSemantics {
  _RenderSessionRowListener({super.onPointerSignal, required super.behavior});
}

mixin _SessionRowSemantics on RenderBox {
  _SessionRowSummary? _summary;
  String? _label;

  set summary(_SessionRowSummary? value) {
    if (_summary == value) return;
    _summary = value;
    _label = null;
    markNeedsSemanticsUpdate();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    // 横向滚动行保留原有子节点及其滚动操作。
    if (_summary == null) super.visitChildrenForSemantics(visitor);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final summary = _summary;
    if (summary == null) return;
    config.label = _label ??= _describe(summary);
    config.textDirection = summary.direction;
  }

  static String _describe(_SessionRowSummary summary) {
    final header = summary.cells.map((cell) => cell.label).nonNulls.join(' ');
    if (header.isEmpty) return summary.data;
    if (summary.data.isEmpty) return header;
    return '$header\n${summary.data}';
  }
}

typedef _ContinuationGutter = ({
  double width,
  double height,
  TextDirection direction,
});

/// 续行只保留栏位占位尺寸，直接布局报文。
class _SessionContinuationLine extends SingleChildRenderObjectWidget {
  const _SessionContinuationLine({
    required this.gutter,
    required this.summary,
    required this.onPointerSignal,
    required super.child,
  });

  final _ContinuationGutter gutter;
  final _SessionRowSummary? summary;
  final PointerSignalEventListener onPointerSignal;

  @override
  _RenderSessionContinuationLine createRenderObject(BuildContext context) =>
      _RenderSessionContinuationLine(gutter, onPointerSignal)
        ..summary = summary;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSessionContinuationLine renderObject,
  ) {
    renderObject
      ..gutter = gutter
      ..summary = summary
      ..onPointerSignal = onPointerSignal;
  }
}

class _RenderSessionContinuationLine extends RenderShiftedBox
    with _SessionRowSemantics {
  _RenderSessionContinuationLine(this._gutter, this.onPointerSignal)
    : super(null);

  _ContinuationGutter _gutter;
  PointerSignalEventListener onPointerSignal;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final hit = hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return hit;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerSignalEvent) onPointerSignal(event);
  }

  set gutter(_ContinuationGutter value) {
    if (_gutter == value) return;
    _gutter = value;
    markNeedsLayout();
  }

  BoxConstraints _contentConstraints(BoxConstraints constraints) {
    final width = math.max(0.0, constraints.maxWidth - _gutter.width);
    return BoxConstraints.tightFor(width: width)
        .copyWith(maxHeight: constraints.maxHeight);
  }

  Size _lineSize(BoxConstraints constraints, Size content) =>
      constraints.constrain(
        Size(
          content.width + _gutter.width,
          math.max(content.height, _gutter.height),
        ),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) => _lineSize(
    constraints,
    child!.getDryLayout(_contentConstraints(constraints)),
  );

  @override
  void performLayout() {
    final content = child!;
    content.layout(_contentConstraints(constraints), parentUsesSize: true);
    size = _lineSize(constraints, content.size);
    final data = content.parentData! as BoxParentData;
    data.offset = Offset(
      _gutter.direction == TextDirection.ltr ? _gutter.width : 0,
      0,
    );
  }
}

/// 文本布局跨行复用，尤其是每秒重复出现的时间戳和收发标记。
class _GutterTextCache {
  final _layout = <(String, _GutterStyle, int?), TextPainter>{};

  TextPainter layout(String label, _GutterStyle style, Color? color) {
    final colorValue = color?.toARGB32();
    final key = (label, style, colorValue);
    final text =
        _layout.remove(key) ??
        (TextPainter(
          text: TextSpan(
            text: label,
            style: color == null ? style.text : style.text.copyWith(color: color),
          ),
          textDirection: style.direction,
          textScaler: style.scaler,
          locale: style.locale,
        )..layout());
    _layout[key] = text;
    if (_layout.length > 256) _layout.remove(_layout.keys.first)!.dispose();
    return text;
  }

  void dispose() {
    for (final entry in _layout.values) {
      entry.dispose();
    }
    _layout.clear();
  }
}

class _GutterPainter extends CustomPainter {
  const _GutterPainter(
    this.cells,
    this.style,
    this.cache, {
    required this.height,
    required this.padding,
    required this.contentWidth,
    required this.scale,
  });
  final List<_GutterCell> cells;
  final _GutterStyle style;
  final _GutterTextCache cache;
  final double height, padding, contentWidth, scale;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = size.width - contentWidth * scale;
    final transformed = offset != 0 || scale != 1;
    if (transformed) {
      canvas.save();
      canvas.translate(offset, 0);
      canvas.scale(scale);
    }
    final rtl = style.direction == TextDirection.rtl;
    var left = rtl ? contentWidth : 0.0;
    for (final (:width, :label, :color) in cells) {
      if (rtl) left -= width;
      if (label != null) {
        final text = cache.layout(label, style, color);
        final fit = math.min(
          1.0,
          math.min(width / text.width, height / text.height),
        );
        final x = left + (width - text.width * fit) / 2;
        final y = 1 + (height - text.height * fit) / 2;
        if (fit == 1) {
          text.paint(canvas, Offset(x, y));
        } else {
          canvas.save();
          canvas.translate(x, y);
          canvas.scale(fit);
          text.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
      left += rtl ? -padding : width + padding;
    }
    if (transformed) canvas.restore();
  }

  // 只在 Flutter 生成辅助功能树时拼接时间戳、行号和方向标记。
  @override
  SemanticsBuilderCallback get semanticsBuilder => _buildSemantics;

  List<CustomPainterSemantics> _buildSemantics(Size size) {
    final label = cells.map((cell) => cell.label).nonNulls.join(' ');
    if (label.isEmpty) return const [];
    return [
      CustomPainterSemantics(
        rect: Offset.zero & size,
        properties: SemanticsProperties(
          label: label,
          textDirection: style.direction,
        ),
      ),
    ];
  }

  @override
  bool shouldRepaint(_GutterPainter oldDelegate) =>
      style != oldDelegate.style ||
      height != oldDelegate.height ||
      padding != oldDelegate.padding ||
      contentWidth != oldDelegate.contentWidth ||
      scale != oldDelegate.scale ||
      !listEquals(cells, oldDelegate.cells);
}
