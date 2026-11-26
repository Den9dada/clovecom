import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../services/toolbox/hex_lookup_tables.dart';

class HexAsciiViewer extends StatefulWidget {
  const HexAsciiViewer({
    super.key,
    required this.bytes,
    this.baseAddress = 0,
    this.onByteChanged,
    this.onScrollChanged,
  });

  final List<int> bytes;
  final int baseAddress;
  final void Function(int index, int value)? onByteChanged;
  final void Function(double scrollOffset, double maxExtent)? onScrollChanged;

  @override
  State<HexAsciiViewer> createState() => _HexAsciiViewerState();
}

class _HexAsciiViewerState extends State<HexAsciiViewer> {
  static const _bytesPerLine = 16;
  static const _lineHeight = 26.0;
  static const _addressColWidth = 100.0;
  static const _asciiColWidth = 132.0;
  static const _gap = 6.0;
  static const _hPad = 12.0;

  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _editBuffer = <int, int>{};
  var _cursorOffset = -1;
  var _highNibble = true;
  var _addressRadix = 16;
  var _scrollOffset = 0.0;
  static const _navIntervalUs = 50000;
  static const _navInitialDelayMs = 1000;
  static const _doubleClickWindowUs = 400000;
  Timer? _navDelayTimer;
  Timer? _navRepeatTimer;
  LogicalKeyboardKey? _navDirection;
  LogicalKeyboardKey? _lastNavUpKey;
  var _lastNavUpMicros = 0;
  double? _cachedCharW;

  HexPainterCache? _cache;

  @override
  void initState() {
    super.initState();

    _scrollCtrl.addListener(_onScroll);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _navDelayTimer?.cancel();
    _navRepeatTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _discardDraft();
      _navDelayTimer?.cancel();
      _navRepeatTimer?.cancel();
      _navDelayTimer = null;
      _navRepeatTimer = null;
      _navDirection = null;
      if (_cursorOffset >= 0) {
        _cursorOffset = -1;
        setState(() {});
      }
    }
  }

  @override
  void didUpdateWidget(HexAsciiViewer old) {
    super.didUpdateWidget(old);

    if (!identical(old.bytes, widget.bytes) ||
        old.baseAddress != widget.baseAddress) {
      _editBuffer.clear();
      _cache?.clear();
      if (_cursorOffset >= widget.bytes.length) {
        _cursorOffset = widget.bytes.isEmpty ? -1 : widget.bytes.length - 1;
      }
      _highNibble = true;
    }
  }

  void _onScroll() {
    final newOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    if ((newOffset - _scrollOffset).abs() > 1.0) {
      _scrollOffset = newOffset;
      setState(() {});
    }
    if (_scrollCtrl.hasClients) {
      widget.onScrollChanged?.call(
        _scrollCtrl.offset,
        _scrollCtrl.position.maxScrollExtent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final addrColor = cs.primary;
    final totalLines = (widget.bytes.length / _bytesPerLine).ceil();
    final totalH = totalLines * _lineHeight;

    final viewportH = MediaQuery.of(context).size.height - 200;
    final firstLine = (_scrollOffset / _lineHeight).floor().clamp(
      0,
      totalLines,
    );
    final lastLine =
        ((_scrollOffset + viewportH + _lineHeight * 2) / _lineHeight)
            .ceil()
            .clamp(0, totalLines);

    final style = _mono(context);
    final charW = _cachedCharW ??= () {
      final tp = TextPainter(
        text: TextSpan(text: '0', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }();

    _cache ??= HexPainterCache(
      hexColor: cs.onSurface,
      asciiColor: cs.onSurface,
      addressColor: addrColor,
      monoStyle: style,
    );

    return TapRegion(
      onTapOutside: (_) {
        _focusNode.unfocus();
        _cursorOffset = -1;
        setState(() {});
      },
      child: Card(
        child: Column(
          children: [
            _header(context, cs, addrColor),
            Expanded(
              child: widget.bytes.isEmpty
                  ? _empty(context, cs)
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (d) => _onTap(d, charW),
                      child: Focus(
                        focusNode: _focusNode,
                        onKeyEvent: _onKeyEvent,
                        child: Scrollbar(
                          controller: _scrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollCtrl,
                            child: CustomPaint(
                              size: Size(double.infinity, totalH),
                              painter: HexEditorPainter(
                                bytes: widget.bytes,
                                baseAddress: widget.baseAddress,
                                editBuffer: _editBuffer,
                                cursorOffset: _cursorOffset,
                                highNibble: _highNibble,
                                addressRadix: _addressRadix,
                                addressColWidth: _addressColWidth,
                                asciiColWidth: _asciiColWidth,
                                gap: _gap,
                                hPad: _hPad,
                                lineHeight: _lineHeight,
                                editable: widget.onByteChanged != null,
                                cursorColor: cs.primary,
                                charWidth: charW,
                                firstLine: firstLine,
                                lastLine: lastLine,
                                cache: _cache!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext c, ColorScheme cs, Color ac) {
    final r = _radixLabel;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _addressColWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: ac.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _cycleRadix,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    child: Text(
                      'offset($r)',
                      style: Theme.of(c).textTheme.labelSmall?.copyWith(
                        color: ac,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(child: _buildHeaderHexRow(c)),
          SizedBox(
            width: _asciiColWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: _gap),
              child: Text('ASCII', style: Theme.of(c).textTheme.labelSmall),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext c, ColorScheme cs) => Center(
    child: Text(
      '拖入或导入文件后显示 HEX/ASCII 数据',
      style: Theme.of(
        c,
      ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
    ),
  );

  Widget _buildHeaderHexRow(BuildContext c) {
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i > 0) b.write(' ');
      b.write(_fmtHdr(i));
    }
    return Text(
      b.toString(),
      style: _mono(c).copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant),
    );
  }

  String _fmtHdr(int i) => switch (_addressRadix) {
    8 => i.toRadixString(8).padLeft(2, '0').toUpperCase(),
    10 => i.toString().padLeft(2, '0'),
    _ => i.toRadixString(16).padLeft(2, '0').toUpperCase(),
  };
  String get _radixLabel => switch (_addressRadix) {
    8 => 'o',
    10 => 'd',
    _ => 'h',
  };

  void _cycleRadix() {
    const r = [16, 8, 10];
    final i = r.indexOf(_addressRadix);
    setState(() => _addressRadix = r[(i + 1) % 3]);
  }

  int _getByte(int o) => (o < 0 || o >= widget.bytes.length)
      ? 0
      : (_editBuffer[o] ?? widget.bytes[o]);

  void _discardDraft() {
    _editBuffer.clear();
    _highNibble = true;
    _cache?.clear();
  }

  void _onTap(TapDownDetails d, double cw) {
    _discardDraft();
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final w = box.size.width;
    final hexStart = _hPad + _addressColWidth + _gap;
    final aStart = w - _gap - _asciiColWidth;
    final dx = d.localPosition.dx;
    final dy =
        d.localPosition.dy + (_scrollCtrl.hasClients ? _scrollCtrl.offset : 0);

    final totalLines = (widget.bytes.length / _bytesPerLine).ceil();
    if (dy < 0 || dy >= totalLines * _lineHeight) return;

    final line = (dy / _lineHeight).floor();
    final pitch = cw * 3;

    // click in HEX area
    if (dx >= hexStart && dx < aStart) {
      final offX = dx - hexStart;
      final col = (offX / pitch).floor();
      if (col >= 0 && col < _bytesPerLine) {
        final cellStart = col * pitch;
        if (offX >= cellStart && offX < cellStart + cw * 2) {
          final off = line * _bytesPerLine + col;
          if (off < widget.bytes.length) {
            _cursorOffset = off;
            _highNibble = true;
            _focusNode.requestFocus();
            setState(() {});
          }
          return;
        }
      }
      return;
    }

    // click in ASCII area
    if (dx >= aStart && dx < aStart + _asciiColWidth) {
      final col = ((dx - aStart) / cw).floor();
      if (col >= 0 && col < _bytesPerLine) {
        final off = line * _bytesPerLine + col;
        if (off < widget.bytes.length) {
          _cursorOffset = off;
          _highNibble = true;
          _focusNode.requestFocus();
          setState(() {});
        }
        return;
      }
      return;
    }

    // click elsewhere (address column, gaps) -> deselect
    if (_cursorOffset >= 0) {
      _cursorOffset = -1;
      _focusNode.unfocus();
      setState(() {});
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;

    // Only respond when a byte is selected
    if (_cursorOffset < 0) return KeyEventResult.ignored;

    // --- Arrow key navigation (common: preview + edit) ---
    final isArrow =
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown;

    if (isArrow && e is KeyDownEvent) {
      _highNibble = true;
      _doNav(k); // always move one step

      _navDelayTimer?.cancel();
      _navRepeatTimer?.cancel();

      final now = e.timeStamp.inMicroseconds;
      final isDoubleClick =
          _lastNavUpKey == k && now - _lastNavUpMicros < _doubleClickWindowUs;

      if (isDoubleClick) {
        _navDirection = k;
        _navDelayTimer = Timer(
          const Duration(milliseconds: _navInitialDelayMs),
          () {
            _navRepeatTimer = Timer.periodic(
              const Duration(microseconds: _navIntervalUs),
              (_) {
                final dir = _navDirection;
                if (dir != null) _doNav(dir);
              },
            );
          },
        );
      }

      return KeyEventResult.handled;
    }

    if (isArrow && e is KeyUpEvent) {
      _lastNavUpKey = k;
      _lastNavUpMicros = e.timeStamp.inMicroseconds;
      _navDelayTimer?.cancel();
      _navRepeatTimer?.cancel();
      _navDelayTimer = null;
      _navRepeatTimer = null;
      _navDirection = null;
      return KeyEventResult.handled;
    }

    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final isRepeat = e is KeyRepeatEvent;

    // --- Preview mode: enter + escape ---
    if (widget.onByteChanged == null) {
      // Enter: move focus to next byte
      if (k == LogicalKeyboardKey.enter) {
        _discardDraft();
        if (_cursorOffset < widget.bytes.length - 1) _cursorOffset++;
        _scrollToCursor();
        setState(() {});
        return KeyEventResult.handled;
      }

      // Escape: cancel selection
      if (k == LogicalKeyboardKey.escape) {
        _discardDraft();
        _cursorOffset = -1;
        _highNibble = true;
        _focusNode.unfocus();
        setState(() {});
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    // --- Edit mode: hex input ---
    // Escape: cancel selection
    if (k == LogicalKeyboardKey.escape) {
      _discardDraft();
      _cursorOffset = -1;
      _highNibble = true;
      _focusNode.unfocus();
      setState(() {});
      return KeyEventResult.handled;
    }

    // Enter: commit and move to next byte
    if (k == LogicalKeyboardKey.enter) {
      _discardDraft();
      _highNibble = true;
      if (_cursorOffset < widget.bytes.length - 1) _cursorOffset++;
      _scrollToCursor();
      setState(() {});
      return KeyEventResult.handled;
    }

    // Hex input: nibble-mode entry
    if (!isRepeat) {
      final h = _keyHex(k);
      if (h != null) {
        _inputHex(h);
        _scrollToCursor();
        setState(() {});
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _doNav(LogicalKeyboardKey k) {
    _discardDraft();
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (_cursorOffset > 0) _cursorOffset--;
    } else if (k == LogicalKeyboardKey.arrowRight) {
      if (_cursorOffset < widget.bytes.length - 1) _cursorOffset++;
    } else if (k == LogicalKeyboardKey.arrowUp) {
      if (_cursorOffset >= _bytesPerLine) _cursorOffset -= _bytesPerLine;
    } else if (k == LogicalKeyboardKey.arrowDown) {
      if (_cursorOffset + _bytesPerLine < widget.bytes.length) {
        _cursorOffset += _bytesPerLine;
      }
    }
    _scrollToCursor();
    setState(() {});
  }

  void _inputHex(int hv) {
    if (_highNibble) {
      _editBuffer[_cursorOffset] =
          (hv << 4) | (widget.bytes[_cursorOffset] & 0x0F);
      _highNibble = false;
    } else {
      final value = (_getByte(_cursorOffset) & 0xF0) | hv;
      _discardDraft();
      widget.onByteChanged?.call(_cursorOffset, value);
    }
    _cache?.clear();
  }

  int? _keyHex(LogicalKeyboardKey k) => switch (k) {
    LogicalKeyboardKey.digit0 => 0,
    LogicalKeyboardKey.digit1 => 1,
    LogicalKeyboardKey.digit2 => 2,
    LogicalKeyboardKey.digit3 => 3,
    LogicalKeyboardKey.digit4 => 4,
    LogicalKeyboardKey.digit5 => 5,
    LogicalKeyboardKey.digit6 => 6,
    LogicalKeyboardKey.digit7 => 7,
    LogicalKeyboardKey.digit8 => 8,
    LogicalKeyboardKey.digit9 => 9,
    LogicalKeyboardKey.keyA => 0xA,
    LogicalKeyboardKey.keyB => 0xB,
    LogicalKeyboardKey.keyC => 0xC,
    LogicalKeyboardKey.keyD => 0xD,
    LogicalKeyboardKey.keyE => 0xE,
    LogicalKeyboardKey.keyF => 0xF,
    _ => null,
  };

  void _scrollToCursor() {
    if (_cursorOffset < 0) return;
    final y = (_cursorOffset ~/ _bytesPerLine) * _lineHeight;
    if (!_scrollCtrl.hasClients) return;
    final vp = _scrollCtrl.position;
    if (y < vp.pixels) {
      _scrollCtrl.jumpTo(y);
      _scrollOffset = y;
    } else if (y + _lineHeight > vp.pixels + vp.viewportDimension) {
      final t = y + _lineHeight - vp.viewportDimension;
      _scrollCtrl.jumpTo(t);
      _scrollOffset = t;
    }
  }

  TextStyle _mono(BuildContext c) =>
      Theme.of(c).textTheme.bodySmall?.copyWith(
        fontFamily: 'Consolas',
        fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
        fontSize: 14,
        height: 1.35,
      ) ??
      const TextStyle(
        fontFamily: 'Consolas',
        fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
        fontSize: 14,
        height: 1.35,
      );
}

class HexPainterCache {
  final Color hexColor, asciiColor, addressColor;
  final TextStyle monoStyle;
  final List<TextPainter> hexTP, ascTP;
  final Map<int, TextPainter> _addrCache = {};

  HexPainterCache({
    required this.hexColor,
    required this.asciiColor,
    required this.addressColor,
    required this.monoStyle,
  }) : hexTP = List<TextPainter>.generate(256, (i) {
         final tp = TextPainter(
           text: TextSpan(
             text: HexLookupTables.hexTable[i],
             style: monoStyle.copyWith(color: hexColor),
           ),
           textDirection: TextDirection.ltr,
         )..layout();
         return tp;
       }),
       ascTP = List<TextPainter>.generate(256, (i) {
         final tp = TextPainter(
           text: TextSpan(
             text: HexLookupTables.asciiTable[i],
             style: monoStyle.copyWith(color: asciiColor),
           ),
           textDirection: TextDirection.ltr,
         )..layout();
         return tp;
       });

  void clear() => _addrCache.clear();
}

class HexEditorPainter extends CustomPainter {
  static const _bpl = 16;
  final List<int> bytes;
  final int baseAddress;
  final Map<int, int> editBuffer;
  final int cursorOffset;
  final bool highNibble;
  final int addressRadix;
  final double addressColWidth, asciiColWidth, gap, hPad, lineHeight;
  final bool editable;
  final Color cursorColor;
  final double charWidth;
  final int firstLine, lastLine;
  final HexPainterCache cache;

  HexEditorPainter({
    required this.bytes,
    required this.baseAddress,
    required this.editBuffer,
    required this.cursorOffset,
    required this.highNibble,
    required this.addressRadix,
    required this.addressColWidth,
    required this.asciiColWidth,
    required this.gap,
    required this.hPad,
    required this.lineHeight,
    required this.editable,
    required this.cursorColor,
    required this.charWidth,
    required this.firstLine,
    required this.lastLine,
    required this.cache,
  });

  double get _cw => charWidth;
  double get _cellW => _cw * 2;

  int _byte(int o) =>
      (o < 0 || o >= bytes.length) ? 0 : (editBuffer[o] ?? bytes[o]);

  @override
  void paint(Canvas cv, Size sz) {
    if (sz.width <= 0 || bytes.isEmpty) return;
    final aStart =
        hPad +
        addressColWidth +
        gap +
        (sz.width - hPad - addressColWidth - gap * 2 - asciiColWidth);
    final hStart = hPad + addressColWidth + gap;
    final addrX = hPad;

    for (var ln = firstLine; ln < lastLine; ln++) {
      final y = ln * lineHeight;
      final bo = ln * _bpl;
      final end = (bo + _bpl).clamp(0, bytes.length);

      final addr = baseAddress + bo;
      final atp = cache._addrCache.putIfAbsent(addr, () {
        final t = _fmtAddr(addr);
        final tp = TextPainter(
          text: TextSpan(
            text: t,
            style: cache.monoStyle.copyWith(color: cache.addressColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        return tp;
      });
      atp.paint(cv, Offset(addrX, y + (lineHeight - atp.height) / 2));

      var x = hStart;
      for (var i = bo; i < end; i++) {
        final b = _byte(i);
        if (i == cursorOffset && editable) {
          cv.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y + 2, _cellW, lineHeight - 4),
              const Radius.circular(4),
            ),
            Paint()..color = cursorColor.withValues(alpha: 0.28),
          );
          final no = highNibble ? 0.0 : _cw;
          cv.drawLine(
            Offset(x + no + 1, y + 2),
            Offset(x + no + 1, y + lineHeight - 2),
            Paint()
              ..color = cursorColor
              ..strokeWidth = 1.5,
          );
        }
        final tp = cache.hexTP[b];
        tp.paint(
          cv,
          Offset(x + (_cellW - tp.width) / 2, y + (lineHeight - tp.height) / 2),
        );
        x += _cellW + _cw;
      }

      x = aStart;
      for (var i = bo; i < end; i++) {
        if (i == cursorOffset && editable) {
          cv.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y + 2, _cw, lineHeight - 4),
              const Radius.circular(4),
            ),
            Paint()..color = cursorColor.withValues(alpha: 0.28),
          );
        }
        final tp = cache.ascTP[_byte(i)];
        tp.paint(cv, Offset(x, y + (lineHeight - tp.height) / 2));
        x += _cw;
      }
    }
  }

  String _fmtAddr(int a) => switch (addressRadix) {
    8 => a.toRadixString(8).padLeft(8, '0').toUpperCase(),
    10 => a.toString().padLeft(8, '0'),
    _ => a.toRadixString(16).padLeft(8, '0').toUpperCase(),
  };

  @override
  bool shouldRepaint(HexEditorPainter o) =>
      bytes != o.bytes ||
      editBuffer != o.editBuffer ||
      cursorOffset != o.cursorOffset ||
      highNibble != o.highNibble ||
      addressRadix != o.addressRadix ||
      firstLine != o.firstLine ||
      lastLine != o.lastLine ||
      baseAddress != o.baseAddress;
}
