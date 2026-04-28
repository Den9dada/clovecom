import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../services/toolbox/hex_ascii_line_formatter.dart';

class HexAsciiViewer extends StatefulWidget {
  const HexAsciiViewer({super.key, required this.bytes, this.baseAddress = 0});

  final List<int> bytes;
  final int baseAddress;

  @override
  State<HexAsciiViewer> createState() => _HexAsciiViewerState();
}

class _HexAsciiViewerState extends State<HexAsciiViewer> {
  static const int _bytesPerLine = 16;
  static const double _lineExtent = 22;
  static const int _maxCachedLines = 4096;

  final LinkedHashMap<int, HexAsciiLine> _lineCache = LinkedHashMap();
  final ScrollController _scrollController = ScrollController();
  List<int>? _lastBytes;
  int? _lastBaseAddress;

  @override
  void dispose() {
    _scrollController.dispose();
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
                      itemCount:
                          (widget.bytes.length / _bytesPerLine).ceil(),
                      itemBuilder: (context, index) {
                        final line = _lineFor(index);
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
                                child: Text(line.hex, style: _mono(context)),
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

  TextStyle _mono(BuildContext context) {
    return Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFamily: 'Consolas', height: 1.35) ??
        const TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.35);
  }
}
