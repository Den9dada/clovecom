import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../services/toolbox/hex_ascii_line_formatter.dart';

class HexAsciiViewer extends StatefulWidget {
  const HexAsciiViewer({
    super.key,
    required this.bytes,
    this.baseAddress = 0,
    this.onByteChanged,
  });

  final List<int> bytes;
  final int baseAddress;
  final void Function(int index, int value)? onByteChanged;

  @override
  State<HexAsciiViewer> createState() => _HexAsciiViewerState();
}

class _HexAsciiViewerState extends State<HexAsciiViewer> {
  static const int _bytesPerLine = 16;
  static const double _lineExtent = 22;
  static const int _maxCachedLines = 4096;
  static const double _hexCellWidth = 26;
  static const double _hexCellGap = 3;

  final LinkedHashMap<int, HexAsciiLine> _lineCache = LinkedHashMap();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _editController = TextEditingController();
  List<int>? _lastBytes;
  int? _lastBaseAddress;
  int? _hoveredByteIndex;
  int? _editingByteIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    _editController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HexAsciiViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_lastBytes, widget.bytes) ||
        _lastBaseAddress != widget.baseAddress) {
      _lineCache.clear();
      _lastBytes = widget.bytes;
      _lastBaseAddress = widget.baseAddress;
    }
  }

  @override
  Widget build(BuildContext context) {
    _lastBytes ??= widget.bytes;
    _lastBaseAddress ??= widget.baseAddress;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Text('地址', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 78),
                Text('HEX', style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                Text('ASCII', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          Expanded(
            child: widget.bytes.isEmpty
                ? Center(
                    child: Text(
                      '拖入或导入文件后显示 HEX/ASCII 数据',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scrollController,
                      primary: false,
                      itemExtent: _lineExtent,
                      cacheExtent: _lineExtent * 32,
                      itemCount: (widget.bytes.length / _bytesPerLine).ceil(),
                      itemBuilder: (context, index) {
                        final line = _lineFor(index);
                        final start = index * _bytesPerLine;
                        final end = (start + _bytesPerLine).clamp(
                          0,
                          widget.bytes.length,
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 82,
                                child: Text(line.offset, style: _mono(context)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildHexArea(context, line, start, end),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 132,
                                child: Text(line.ascii, style: _mono(context)),
                              ),
                            ],
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

  HexAsciiLine _lineFor(int lineIndex) {
    final cached = _lineCache.remove(lineIndex);
    if (cached != null) {
      _lineCache[lineIndex] = cached;
      return cached;
    }

    final start = lineIndex * _bytesPerLine;
    final end = (start + _bytesPerLine).clamp(0, widget.bytes.length);
    final line = HexAsciiLineFormatter.formatLine(
      bytes: widget.bytes,
      start: start,
      end: end,
      address: widget.baseAddress + start,
    );
    _lineCache[lineIndex] = line;
    if (_lineCache.length > _maxCachedLines) {
      _lineCache.remove(_lineCache.keys.first);
    }
    return line;
  }

  Widget _buildHexArea(
    BuildContext context,
    HexAsciiLine line,
    int start,
    int end,
  ) {
    final editable = widget.onByteChanged != null;
    if (!editable) {
      return Text(line.hex, style: _mono(context));
    }

    final active =
        _containsIndex(start, end, _hoveredByteIndex) ||
        _containsIndex(start, end, _editingByteIndex);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (event) {
        final index = _byteIndexForDx(event.localPosition.dx, start, end);
        if (_hoveredByteIndex != index) {
          setState(() => _hoveredByteIndex = index);
        }
      },
      onExit: (_) {
        if (_containsIndex(start, end, _hoveredByteIndex)) {
          setState(() => _hoveredByteIndex = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final index = _byteIndexForDx(details.localPosition.dx, start, end);
          if (index != null) {
            _startEdit(index);
          }
        },
        child: active
            ? _buildHexCells(context, start, end)
            : Text(line.hex, style: _mono(context)),
      ),
    );
  }

  Widget _buildHexCells(BuildContext context, int start, int end) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = start; index < end; index++) ...[
          _buildByteCell(context, index),
          if (index < end - 1) const SizedBox(width: _hexCellGap),
        ],
      ],
    );
  }

  Widget _buildByteCell(BuildContext context, int index) {
    final hovered = _hoveredByteIndex == index;
    final editing = _editingByteIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final hex = _hexByte(widget.bytes[index]);

    final child = editing
        ? SizedBox(
            width: 28,
            height: 20,
            child: TextField(
              controller: _editController,
              autofocus: true,
              maxLength: 2,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              style: _mono(context),
              decoration: const InputDecoration(
                counterText: '',
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onSubmitted: (_) => _commitEdit(index),
            ),
          )
        : Text(hex, style: _mono(context));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredByteIndex = index),
      onExit: (_) {
        if (_hoveredByteIndex == index) {
          setState(() => _hoveredByteIndex = null);
        }
      },
      child: GestureDetector(
        onTap: () => _startEdit(index),
        child: Container(
          key: ValueKey('hex-byte-$index-${hovered ? 'hovered' : 'normal'}'),
          width: _hexCellWidth,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered || editing
                ? colorScheme.primaryContainer.withValues(alpha: 0.42)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hovered || editing
                  ? colorScheme.primary
                  : Colors.transparent,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  bool _containsIndex(int start, int end, int? index) {
    return index != null && index >= start && index < end;
  }

  int? _byteIndexForDx(double dx, int start, int end) {
    if (dx < 0) {
      return null;
    }
    final slot = dx ~/ (_hexCellWidth + _hexCellGap);
    final index = start + slot;
    if (index >= end) {
      return null;
    }
    final slotStart = slot * (_hexCellWidth + _hexCellGap);
    if (dx > slotStart + _hexCellWidth) {
      return null;
    }
    return index;
  }

  void _startEdit(int index) {
    _editController.text = _hexByte(widget.bytes[index]);
    _editController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _editController.text.length,
    );
    setState(() => _editingByteIndex = index);
  }

  void _commitEdit(int index) {
    final text = _editController.text.trim();
    if (!RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 2 位 HEX 字节')));
      return;
    }
    widget.onByteChanged?.call(index, int.parse(text, radix: 16));
    setState(() => _editingByteIndex = null);
  }

  String _hexByte(int byte) {
    return (byte & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  TextStyle _mono(BuildContext context) {
    return Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFamily: 'Consolas', height: 1.35) ??
        const TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.35);
  }
}
