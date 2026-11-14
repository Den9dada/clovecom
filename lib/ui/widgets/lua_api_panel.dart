import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/traework_theme.dart';
import 'ds_widgets.dart';

/// 与开发文档共用接口正文，避免应用内说明与实际接口清单分别维护。
class LuaApiPanel extends StatefulWidget {
  const LuaApiPanel({super.key, required this.onClose, required this.onResize});
  final VoidCallback onClose;
  final ValueChanged<double> onResize;

  @override
  State<LuaApiPanel> createState() => _LuaApiPanelState();
}

class _LuaApiPanelState extends State<LuaApiPanel> {
  final _scroll = ScrollController();
  late final _documents = Future.wait([
    rootBundle.loadString('docs/development/lua-host-api.md'),
    rootBundle.loadString('docs/development/lua-script-guide.md'),
  ]);
  int _tab = 0;
  String _chapter = '';
  double _transparency = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('lua-api-panel'),
    color: TraeWorkColors.brandPurple100.withValues(alpha: 1 - _transparency),
    elevation: 6,
    shadowColor: const Color(0x40000000),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: TraeWorkColors.borderBrand.withValues(alpha: 0.25),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  size: 16,
                  color: TraeWorkColors.bgBrand,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '接口说明',
                    style: traeworkText(weight: FontWeight.w600),
                  ),
                ),
                DsButton(
                  key: const ValueKey('lua-api-tab'),
                  label: 'API说明',
                  active: _tab == 0,
                  size: DsButtonSize.sm,
                  onPressed: () => _selectTab(0),
                ),
                const SizedBox(width: 6),
                DsButton(
                  key: const ValueKey('lua-usage-tab'),
                  label: '使用说明',
                  active: _tab == 1,
                  size: DsButtonSize.sm,
                  onPressed: () => _selectTab(1),
                ),
                const SizedBox(width: 12),
                DsButton.icon(
                  key: const ValueKey('lua-api-close'),
                  icon: Icons.close,
                  tooltip: '关闭面板',
                  size: DsButtonSize.sm,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<String>>(
            future: _documents,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('接口说明载入失败，请重新打开面板'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final chapters = _chapters(snapshot.data![_tab]);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, bounds) => Row(
                        children: [
                          Expanded(
                            child: DsSelect<String>(
                              key: const ValueKey('lua-api-chapters'),
                              expand: true,
                              value: _chapter,
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: Text(_tab == 0 ? '全部API说明' : '全部使用说明'),
                                ),
                                for (final chapter in chapters)
                                  DropdownMenuItem(
                                    value: chapter.title,
                                    child: Text(chapter.title),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _chapter = value);
                                if (_scroll.hasClients) _scroll.jumpTo(0);
                              },
                            ),
                          ),
                          if (bounds.maxWidth >= 400) ...[
                            const SizedBox(width: 12),
                            Text('透明度', style: traeworkText(size: 11)),
                            SizedBox(
                              width: 100,
                              child: Slider(
                                value: _transparency,
                                min: 0,
                                max: 1,
                                divisions: 100,
                                label: '${(_transparency * 100).round()}%',
                                onChanged: (value) =>
                                    setState(() => _transparency = value),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectionArea(
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        scrollbarOrientation: ScrollbarOrientation.right,
                        child: ListView(
                          key: const ValueKey('lua-api-content'),
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 0, 28, 16),
                          children: [
                            for (final chapter in chapters)
                              if (_chapter.isEmpty ||
                                  chapter.title == _chapter) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 12,
                                  ),
                                  child: Text(
                                    chapter.title,
                                    style: traeworkText(
                                      size: 15,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ..._body(chapter.lines),
                                const Divider(height: 24),
                              ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            key: const ValueKey('lua-api-resize'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) =>
                widget.onResize(details.delta.dy),
            child: SizedBox(
              height: 12,
              child: Center(
                child: Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: TraeWorkColors.borderControl,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  List<({String title, List<String> lines})> _chapters(String document) {
    final result = <({String title, List<String> lines})>[
      (title: _tab == 0 ? 'API约定' : '使用概览', lines: <String>[]),
    ];
    for (final line in document.split('\n')) {
      if (line.startsWith('## ')) {
        result.add((title: line.substring(3).trim(), lines: <String>[]));
      } else if (!line.startsWith('# ')) {
        result.last.lines.add(line.trimRight());
      }
    }
    return result;
  }

  void _selectTab(int tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _chapter = '';
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // 正文仅使用说明文档已有的标题、段落、列表、表格和代码块格式。
  Iterable<Widget> _body(List<String> lines) sync* {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (line.startsWith('```')) {
        final code = <String>[];
        while (++i < lines.length && !lines[i].startsWith('```')) {
          code.add(lines[i]);
        }
        yield Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: TraeWorkColors.bgBaseDefault,
            border: Border.all(color: TraeWorkColors.borderNeutralL1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code.join('\n'),
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        );
      } else if (line.startsWith('|')) {
        final rows = <List<String>>[];
        do {
          rows.add(lines[i].split('|').skip(1).toList()..removeLast());
          i++;
        } while (i < lines.length && lines[i].startsWith('|'));
        i--;
        for (final row in rows.skip(2)) {
          yield Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: TraeWorkColors.bgBaseDefault,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _paragraph(row.first.trim(), strong: true),
                for (var column = 1; column < row.length; column++)
                  _paragraph(
                    '${rows.first[column].trim()}：${row[column].trim()}',
                  ),
              ],
            ),
          );
        }
      } else {
        yield Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _paragraph(
            line.startsWith('- ') ? '• ${line.substring(2)}' : line,
          ),
        );
      }
    }
  }

  Widget _paragraph(String text, {bool strong = false}) {
    final content = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (match) => match[1]!,
    );
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in RegExp(
      r'`([^`]+)`|\*\*([^*]+)\*\*',
    ).allMatches(content)) {
      if (match.start > end) {
        spans.add(TextSpan(text: content.substring(end, match.start)));
      }
      spans.add(
        TextSpan(
          text: match[1] ?? match[2],
          style: match[1] != null
              ? const TextStyle(
                  fontFamily: 'Consolas',
                  color: TraeWorkColors.textBrand,
                )
              : const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
      end = match.end;
    }
    if (end < content.length) spans.add(TextSpan(text: content.substring(end)));
    return Text.rich(
      TextSpan(children: spans),
      style: traeworkText(
        size: 12,
        weight: strong ? FontWeight.w600 : FontWeight.w400,
      ).copyWith(height: 1.7),
    );
  }
}
