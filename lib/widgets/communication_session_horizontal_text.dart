part of 'communication_session_data_view.dart';

/// 完整段落负责布局、选择和读屏，只替换无选区时的字形绘制与常规排版。
class _HorizontalTextPaint extends SingleChildRenderObjectWidget {
  const _HorizontalTextPaint({
    required this.selection,
    required this.layouts,
    required super.child,
  });

  final _SessionSelectionDelegate selection;
  final _VisibleTextLayouts layouts;

  @override
  _RenderHorizontalTextPaint createRenderObject(BuildContext context) =>
      _RenderHorizontalTextPaint(
        Scrollable.of(context, axis: Axis.horizontal).position,
        selection,
        layouts,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHorizontalTextPaint renderObject,
  ) {
    renderObject
      ..position = Scrollable.of(context, axis: Axis.horizontal).position
      ..selection = selection
      ..layouts = layouts
      ..invalidateApproximateLayout();
  }
}

class _RenderHorizontalTextPaint extends RenderProxyBox {
  _RenderHorizontalTextPaint(this.position, this._selection, this._layouts);

  ScrollPosition position;
  _SessionSelectionDelegate _selection;
  bool _hasSelection = false;
  _VisibleTextLayouts _layouts;
  _VisibleTextLayout? _visibleLayout;
  Object? _paintKey;
  double _paintX = 0;
  BoxConstraints? _lastConstraints;
  BoxConstraints? _lastChildConstraints;
  bool _deferredChildLayout = false;
  String? _deferredText;
  _VisibleTextRun? _measuredRun;
  int _measuredRevision = -1;
  Size? _measuredSize;

  void invalidateApproximateLayout() {
    if (_deferredChildLayout) {
      _paintKey = null;
      _measuredRevision = -1;
      markNeedsLayout();
    }
  }

  set layouts(_VisibleTextLayouts value) {
    if (identical(_layouts, value)) return;
    _releaseLayout();
    if (attached) _layouts.detachNode(this);
    _layouts = value;
    if (attached) _layouts.attachNode(this);
    _paintKey = null;
    markNeedsLayout();
  }

  void _releaseLayout() {
    if (_visibleLayout case final layout?) _layouts.release(layout);
    _visibleLayout = null;
  }

  set selection(_SessionSelectionDelegate value) {
    if (identical(_selection, value)) return;
    if (attached) _selection.removeListener(_updateSelection);
    _selection = value;
    if (attached) _selection.addListener(_updateSelection);
    _updateSelection();
  }

  void _updateSelection() {
    final hasSelection = _selection.value.hasSelection;
    if (_hasSelection == hasSelection) return;
    _hasSelection = hasSelection;
    if (hasSelection && _deferredChildLayout) ensureChildLaidOut();
    // 未绘制完整段落时，不能依赖段落传播下一次重绘通知。
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _layouts.attachNode(this);
    _selection.addListener(_updateSelection);
    _updateSelection();
  }

  @override
  void detach() {
    _layouts.detachNode(this);
    _selection.removeListener(_updateSelection);
    super.detach();
  }

  RenderParagraph? _eligibleParagraph() {
    var node = child;
    while (node is RenderProxyBox) {
      node = node.child;
    }
    if (node is! RenderParagraph ||
        node.textDirection != TextDirection.ltr ||
        node.softWrap ||
        node.textAlign != TextAlign.start ||
        node.maxLines != null ||
        node.text is! TextSpan) {
      return null;
    }
    final span = node.text as TextSpan;
    final data = span.text;
    if (data == null || span.children?.isNotEmpty == true) return null;
    return node;
  }

  _VisibleTextRun _runFor(RenderParagraph node, TextSpan span) => (
    text: span,
    scaler: node.textScaler,
    locale: node.locale,
    strut: node.strutStyle,
    height: node.textHeightBehavior,
  );

  void ensureChildLaidOut() {
    final child = this.child;
    final constraints = _lastConstraints;
    if (child == null || constraints == null) return;
    if (_deferredChildLayout ||
        child.debugNeedsLayout ||
        _lastChildConstraints != constraints) {
      _deferredChildLayout = false;
      _deferredText = null;
      _lastChildConstraints = constraints;
      child.layout(constraints, parentUsesSize: true);
      markNeedsSemanticsUpdate();
    }
  }

  ({Size size, String text})? _approximateSize() {
    if (_hasSelection || _layouts.selecting) return null;
    final node = _eligibleParagraph();
    if (node == null) return null;
    final span = node.text as TextSpan;
    final data = span.text!;
    final run = _runFor(node, span);
    final revision = _layouts.revision;
    if (_measuredRevision == revision && _measuredRun == run) {
      if (_measuredSize case final cached?) {
        return (size: cached, text: data);
      }
      return null;
    }
    final measured = _layouts.measure(run, data);
    _measuredRun = run;
    _measuredRevision = revision;
    _measuredSize = measured;
    if (measured == null) return null;
    return (size: measured, text: data);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    if (_approximateSize() case final approx?) {
      return constraints.constrain(approx.size);
    }
    return super.computeDryLayout(constraints);
  }

  @override
  void performLayout() {
    _lastConstraints = constraints;
    if (_approximateSize() case final approx?) {
      size = constraints.constrain(approx.size);
      _deferredChildLayout = true;
      _deferredText = approx.text;
      return;
    }
    _deferredChildLayout = false;
    _deferredText = null;
    _lastChildConstraints = constraints;
    super.performLayout();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_deferredChildLayout) return false;
    return super.hitTestChildren(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_deferredChildLayout) return;
    super.visitChildrenForSemantics(visitor);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_deferredChildLayout) {
      final text = _deferredText;
      if (text != null) {
        config
          ..textDirection = TextDirection.ltr
          ..attributedLabel = AttributedString(text);
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!position.hasViewportDimension || !position.hasPixels) {
      if (_deferredChildLayout) ensureChildLaidOut();
      super.paint(context, offset);
      return;
    }
    final node = _eligibleParagraph();
    if (node == null) {
      if (_deferredChildLayout) ensureChildLaidOut();
      super.paint(context, offset);
      return;
    }
    if (!_deferredChildLayout && position.viewportDimension >= node.size.width) {
      super.paint(context, offset);
      return;
    }
    if (_hasSelection) {
      // 会话可同时绘制多条长报文。只有自身选中的段落需要绘制选区和手柄。
      final Object? registrar = node.registrar;
      if (registrar is! SelectionHandler || registrar.value.hasSelection) {
        ensureChildLaidOut();
        super.paint(context, offset);
        return;
      }
    }
    final span = node.text as TextSpan;
    final data = span.text!;
    final window = (
      run: _runFor(node, span),
      left: math.max(0.0, position.pixels),
      width: position.viewportDimension,
      paragraphSize: size,
      maxLines: node.maxLines,
      overflow: node.overflow,
      widthBasis: node.textWidthBasis,
      hyphens: node.hyphens,
    );
    final key = (window, _layouts.revision);
    if (_paintKey != key) {
      final clip = _layouts.clip(
        window,
        _deferredChildLayout ? null : node,
        data,
      );
      if (clip == null) {
        if (_deferredChildLayout) ensureChildLaidOut();
        super.paint(context, offset);
        return;
      }
      _releaseLayout();
      _visibleLayout = _layouts.acquire(clip.run);
      _paintX = clip.x;
      _paintKey = key;
    }
    _visibleLayout!.painter.paint(context.canvas, offset.translate(_paintX, 0));
  }

  @override
  void dispose() {
    _releaseLayout();
    super.dispose();
  }
}

typedef _VisibleTextRun = ({
  TextSpan text,
  TextScaler scaler,
  Locale? locale,
  StrutStyle? strut,
  TextHeightBehavior? height,
});

typedef _HexMetricsKey = ({
  TextStyle? style,
  TextScaler scaler,
  Locale? locale,
  StrutStyle? strut,
  TextHeightBehavior? height,
});

typedef _ParagraphWindow = ({
  _VisibleTextRun run,
  double left,
  double width,
  Size paragraphSize,
  int? maxLines,
  TextOverflow overflow,
  TextWidthBasis widthBasis,
  Hyphens hyphens,
});

typedef _ParagraphClip = ({_VisibleTextRun run, double x});

class _HexGlyphMetrics {
  _HexGlyphMetrics(_HexMetricsKey key) : _advances = Float64List(128 * 128) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: key.style),
      textDirection: TextDirection.ltr,
      textScaler: key.scaler,
      locale: key.locale,
      strutStyle: key.strut,
      textHeightBehavior: key.height,
    )..layout();
    try {
      height = painter.height;
      for (final left in _alphabet.codeUnits) {
        _supported[left] = 1;
        painter
          ..text = TextSpan(text: String.fromCharCode(left), style: key.style)
          ..layout();
        _advances[left * 128] = painter.width;
        for (final right in _alphabet.codeUnits) {
          painter
            ..text = TextSpan(
              text: String.fromCharCodes([left, right, 48]),
              style: key.style,
            )
            ..layout();
          _advances[left * 128 + right] =
              painter.getOffsetForCaret(const TextPosition(offset: 1), Rect.zero).dx -
              painter.getOffsetForCaret(const TextPosition(offset: 0), Rect.zero).dx;
        }
      }
    } finally {
      painter.dispose();
    }
  }

  static const _alphabet = '0123456789 ABCDEF';
  final Uint8List _supported = Uint8List(128);
  final Float64List _advances;
  late final double height;

  double? widthOf(String data) {
    final length = data.length;
    if (length == 0) return 0.0;
    var total = 0.0;
    var left = data.codeUnitAt(0);
    if (left >= 128 || _supported[left] == 0) return null;
    for (var index = 0; index < length - 1; index++) {
      final right = data.codeUnitAt(index + 1);
      if (right >= 128 || _supported[right] == 0) return null;
      total += _advances[left * 128 + right];
      left = right;
    }
    total += _advances[left * 128];
    return total;
  }

  ({int start, int end, double x})? rangeForWindow(
    String data,
    double leftEdge,
    double viewportWidth,
  ) {
    final length = data.length;
    if (length == 0) return null;
    var cursor = 0.0;
    var start = 0;
    var paintX = 0.0;
    var foundStart = leftEdge <= 0;
    final rightEdge = leftEdge + viewportWidth;
    var end = length;
    var prev = data.codeUnitAt(0);
    if (prev >= 128 || _supported[prev] == 0) return null;

    if (!foundStart) {
      // 保留前 4 个字符的绘制余量，记录起始字符的准确横坐标。
      final ringX = Float64List(5);
      for (var index = 0; index < length; index++) {
        ringX[index % 5] = cursor;
        final next = index + 1 < length ? data.codeUnitAt(index + 1) : 0;
        if (next >= 128 || (next != 0 && _supported[next] == 0)) return null;
        final nextCursor = cursor + _advances[prev * 128 + next];
        if (!foundStart && nextCursor >= leftEdge) {
          start = math.max(0, index - 4);
          paintX = ringX[start % 5];
          foundStart = true;
        }
        cursor = nextCursor;
        if (foundStart && cursor >= rightEdge) {
          end = math.min(length, index + 5);
          break;
        }
        prev = next;
      }
      if (!foundStart) return null;
      return (start: start, end: end, x: paintX);
    }

    for (var index = 0; index < length; index++) {
      final next = index + 1 < length ? data.codeUnitAt(index + 1) : 0;
      if (next >= 128 || (next != 0 && _supported[next] == 0)) return null;
      cursor += _advances[prev * 128 + next];
      if (cursor >= rightEdge) {
        end = math.min(length, index + 5);
        break;
      }
      prev = next;
    }
    return (start: 0, end: end, x: 0.0);
  }
}

class _VisibleTextLayout {
  _VisibleTextLayout(this.run, this.painter);
  final _VisibleTextRun run;
  final TextPainter painter;
  int users = 0;
}

/// 仅淘汰已释放的排版，已挂载的行直接复用其绘制对象。
class _VisibleTextLayouts {
  final _active = <_VisibleTextRun, _VisibleTextLayout>{};
  final _idle = <_VisibleTextRun, TextPainter>{};
  final _clips = <_ParagraphWindow, _ParagraphClip>{};
  final _metrics = <_HexMetricsKey, _HexGlyphMetrics>{};
  final _nodes = <_RenderHorizontalTextPaint>{};
  int revision = 0;
  bool selecting = false;

  void attachNode(_RenderHorizontalTextPaint node) => _nodes.add(node);
  void detachNode(_RenderHorizontalTextPaint node) => _nodes.remove(node);

  void ensureAllLaidOut() {
    selecting = true;
    for (final node in _nodes) {
      node.ensureChildLaidOut();
    }
  }

  void clearSelectionMode() {
    selecting = false;
  }

  _HexGlyphMetrics _metricsFor(_VisibleTextRun run) {
    final key = (
      style: run.text.style,
      scaler: run.scaler,
      locale: run.locale,
      strut: run.strut,
      height: run.height,
    );
    return _metrics.putIfAbsent(key, () => _HexGlyphMetrics(key));
  }

  Size? measure(_VisibleTextRun run, String data) {
    final metrics = _metricsFor(run);
    final width = metrics.widthOf(data);
    if (width == null) return null;
    return Size(width, metrics.height);
  }

  _ParagraphClip? clip(
    _ParagraphWindow window,
    RenderParagraph? node,
    String data,
  ) {
    if (_clips.remove(window) case final cached?) {
      _clips[window] = cached;
      return cached;
    }
    final int start;
    final int end;
    final double x;
    final range = _metricsFor(window.run).rangeForWindow(
      data,
      window.left,
      window.width,
    );
    if (range != null) {
      start = range.start;
      end = range.end;
      x = range.x;
    } else if (node != null) {
      // 复用完整段落确认过的裁剪位置。两侧留字形绘制余量。
      // 左对齐的整行从零开始，首屏可直接保留原始起点。
      start = window.left == 0
          ? 0
          : math.max(
              0,
              node.getPositionForOffset(Offset(window.left, 0)).offset - 4,
            );
      end = math.min(
        data.length,
        node.getPositionForOffset(Offset(window.left + window.width, 0)).offset +
            4,
      );
      x = start == 0
          ? 0.0
          : node.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dx;
    } else {
      return null;
    }
    if (start >= end) return null;
    final run = window.run;
    final clip = (
      run: (
        text: TextSpan(
          text: data.substring(start, end),
          style: run.text.style,
          locale: run.text.locale,
        ),
        scaler: run.scaler,
        locale: run.locale,
        strut: run.strut,
        height: run.height,
      ),
      x: x,
    );
    _clips[window] = clip;
    if (_clips.length > 2048) _clips.remove(_clips.keys.first);
    return clip;
  }

  _VisibleTextLayout acquire(_VisibleTextRun run) {
    final layout = _active[run] ??= _VisibleTextLayout(
      run,
      _idle.remove(run) ??
          (TextPainter(
            text: run.text,
            textDirection: TextDirection.ltr,
            textScaler: run.scaler,
            locale: run.locale,
            strutStyle: run.strut,
            textHeightBehavior: run.height,
          )..layout()),
    );
    layout.users++;
    return layout;
  }

  void release(_VisibleTextLayout layout) {
    if (--layout.users != 0) return;
    if (!identical(_active[layout.run], layout)) {
      layout.painter.dispose();
      return;
    }
    _active.remove(layout.run);
    _idle[layout.run] = layout.painter;
    if (_idle.length > 2048) _idle.remove(_idle.keys.first)!.dispose();
  }

  void invalidate() {
    revision++;
    _clips.clear();
    _metrics.clear();
    _active.clear();
    for (final painter in _idle.values) {
      painter.dispose();
    }
    _idle.clear();
    for (final node in _nodes) {
      node.markNeedsLayout();
    }
  }
}
