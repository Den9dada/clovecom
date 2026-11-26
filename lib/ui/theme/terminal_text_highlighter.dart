import 'package:material_ui/material_ui.dart';

import 'terminal_color_schemes.dart';

/// 为会话终端纯文本行解析 ANSI SGR 转义序列或终端语义着色的 `TextSpan` 列表。
///
/// 若整行无需额外分段着色，返回 `null`，由调用方直接使用单样式 `Text` 绘制。
List<TextSpan>? buildTerminalTextSpans(
  String data, {
  required TerminalColorScheme scheme,
  required TextStyle baseStyle,
}) {
  if (data.isEmpty) return null;
  if (data.contains('\x1B[')) {
    return _parseAnsiSgr(data, scheme: scheme, baseStyle: baseStyle);
  }
  if (data.length > 2048) return null;
  return _highlightSemanticTokens(data, scheme: scheme, baseStyle: baseStyle);
}

final _ansiSgrPattern = RegExp(r'\x1B\[([0-9;]*)m');

List<TextSpan>? _parseAnsiSgr(
  String data, {
  required TerminalColorScheme scheme,
  required TextStyle baseStyle,
}) {
  final spans = <TextSpan>[];
  var cursor = 0;
  var currentStyle = baseStyle;
  var hasCustomStyle = false;

  for (final match in _ansiSgrPattern.allMatches(data)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(
          text: data.substring(cursor, match.start),
          style: hasCustomStyle ? currentStyle : null,
        ),
      );
    }
    final rawCodes = match.group(1) ?? '';
    final codes = rawCodes.isEmpty
        ? const [0]
        : rawCodes
              .split(';')
              .map((part) => int.tryParse(part) ?? 0)
              .toList(growable: false);
    var i = 0;
    while (i < codes.length) {
      final code = codes[i];
      if (code == 0) {
        currentStyle = baseStyle;
        hasCustomStyle = false;
      } else if (code == 1) {
        currentStyle = currentStyle.copyWith(fontWeight: FontWeight.w600);
        hasCustomStyle = true;
      } else if (code == 2) {
        final color = currentStyle.color ?? baseStyle.color;
        currentStyle = currentStyle.copyWith(
          color: color?.withValues(alpha: 0.65),
        );
        hasCustomStyle = true;
      } else if (code == 22) {
        currentStyle = currentStyle.copyWith(
          fontWeight: baseStyle.fontWeight,
          color: currentStyle.color?.withValues(alpha: 1.0),
        );
        hasCustomStyle = currentStyle != baseStyle;
      } else if (code >= 30 && code <= 37) {
        currentStyle = currentStyle.copyWith(color: scheme.ansi[code - 30]);
        hasCustomStyle = true;
      } else if (code == 39) {
        currentStyle = currentStyle.copyWith(color: baseStyle.color);
        hasCustomStyle = currentStyle != baseStyle;
      } else if (code >= 90 && code <= 97) {
        currentStyle = currentStyle.copyWith(color: scheme.ansi[code - 90 + 8]);
        hasCustomStyle = true;
      } else if (code == 38 && i + 1 < codes.length) {
        if (codes[i + 1] == 5 && i + 2 < codes.length) {
          currentStyle = currentStyle.copyWith(
            color: _xterm256Color(codes[i + 2], scheme.ansi),
          );
          hasCustomStyle = true;
          i += 2;
        } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
          currentStyle = currentStyle.copyWith(
            color: Color.fromARGB(
              255,
              codes[i + 2].clamp(0, 255),
              codes[i + 3].clamp(0, 255),
              codes[i + 4].clamp(0, 255),
            ),
          );
          hasCustomStyle = true;
          i += 4;
        }
      }
      i++;
    }
    cursor = match.end;
  }

  if (cursor < data.length) {
    spans.add(
      TextSpan(
        text: data.substring(cursor),
        style: hasCustomStyle ? currentStyle : null,
      ),
    );
  }
  return spans.isEmpty ? null : spans;
}

Color _xterm256Color(int index, List<Color> ansi16) {
  final clamped = index.clamp(0, 255);
  if (clamped < 16) return ansi16[clamped];
  if (clamped < 232) {
    final c = clamped - 16;
    const levels = [0, 95, 135, 175, 215, 255];
    final r = levels[c ~/ 36];
    final g = levels[(c % 36) ~/ 6];
    final b = levels[c % 6];
    return Color.fromARGB(255, r, g, b);
  }
  final gray = 8 + (clamped - 232) * 10;
  return Color.fromARGB(255, gray, gray, gray);
}

final _bannerPattern = RegExp(r'^\s*[-=]{3,}.*[-=]{3,}\s*$');
final _semanticPattern = RegExp(
  r'(?<error>\[(?:E|ERR|ERROR)(?:\/[^\]]+)?\]|\b(?:ERROR|FAIL(?:ED)?)\b)'
  r'|(?<warn>\[(?:W|WARN|WARNING)(?:\/[^\]]+)?\]|\bWARN(?:ING)?\b)'
  r'|(?<info>\[(?:I|INFO)(?:\/[^\]]+)?\]|\bINFO\b)'
  r'|(?<debug>\[(?:D|DBG|DEBUG|V|TRACE)(?:\/[^\]]+)?\]|\b(?:DEBUG|TRACE)\b)'
  r'|(?<number>\b0[xX][0-9a-fA-F]+\b|(?<![a-zA-Z0-9_.:/-])\d+(?:\.\d+)?(?![a-zA-Z0-9_.:/-]))',
);

List<TextSpan>? _highlightSemanticTokens(
  String data, {
  required TerminalColorScheme scheme,
  required TextStyle baseStyle,
}) {
  if (_bannerPattern.hasMatch(data) && scheme.banner != null) {
    return [
      TextSpan(
        text: data,
        style: baseStyle.copyWith(
          color: scheme.banner,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in _semanticPattern.allMatches(data)) {
    Color? tokenColor;
    var weight = baseStyle.fontWeight;
    if (match.namedGroup('error') != null) {
      tokenColor = scheme.notice;
      weight = FontWeight.w600;
    } else if (match.namedGroup('warn') != null) {
      tokenColor = scheme.warning;
      weight = FontWeight.w600;
    } else if (match.namedGroup('info') != null) {
      tokenColor = scheme.info;
      weight = FontWeight.w600;
    } else if (match.namedGroup('debug') != null) {
      tokenColor = scheme.debug;
    } else if (match.namedGroup('number') != null) {
      tokenColor = scheme.number;
    }
    if (tokenColor == null) continue;
    if (match.start > cursor) {
      spans.add(TextSpan(text: data.substring(cursor, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(0),
        style: baseStyle.copyWith(color: tokenColor, fontWeight: weight),
      ),
    );
    cursor = match.end;
  }

  if (spans.isEmpty) return null;
  if (cursor < data.length) {
    spans.add(TextSpan(text: data.substring(cursor)));
  }
  return spans;
}
