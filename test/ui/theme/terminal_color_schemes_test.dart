import 'dart:io';

import 'package:clovecom/ui/theme/app_theme_controller.dart';
import 'package:clovecom/ui/theme/terminal_color_schemes.dart';
import 'package:clovecom/ui/theme/terminal_text_highlighter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('内置配色方案唯一且可解析，默认方案为 One Half Light', () {
    final ids = terminalColorSchemes.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, isNot(contains('default')));
    expect(defaultTerminalColorSchemeId, 'one-half-light');
    expect(defaultTerminalColorScheme.name, 'One Half Light');
    expect(ids, contains(defaultTerminalColorSchemeId));
    expect(terminalColorSchemes.where((s) => s.isDark), isNotEmpty);
    expect(terminalColorSchemes.where((s) => !s.isDark), isNotEmpty);

    for (final scheme in terminalColorSchemes) {
      expect(scheme.name, isNotEmpty);
      expect(scheme.ansi.length, 16);
      expect(scheme.palette, isNotEmpty);
      expect(resolveTerminalColorScheme(scheme.id), same(scheme));
    }

    expect(
      resolveTerminalColorScheme('non-existent-scheme'),
      same(defaultTerminalColorScheme),
    );
  });

  test('AppThemeController 默认使用 One Half Light 并支持切换通知', () async {
    final dir = await Directory.systemTemp.createTemp('app_theme_test_');
    addTearDown(() => dir.delete(recursive: true));
    final controller = AppThemeController(file: File('${dir.path}/theme.json'));
    expect(controller.scheme.id, 'one-half-light');

    var notified = 0;
    controller.addListener(() => notified++);
    controller.select(resolveTerminalColorScheme('dracula'));
    expect(controller.scheme.id, 'dracula');
    expect(notified, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.dispose();
  });

  test('buildTerminalTextSpans 支持 ANSI SGR 与终端语义着色', () {
    final dracula = resolveTerminalColorScheme('dracula');
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: dracula.foreground,
    );

    expect(
      buildTerminalTextSpans('plain text', scheme: dracula, baseStyle: baseStyle),
      isNull,
    );

    final semanticSpans = buildTerminalTextSpans(
      '[I/USB] Clock: 72000000 Hz',
      scheme: dracula,
      baseStyle: baseStyle,
    );
    expect(semanticSpans, isNotNull);
    expect(semanticSpans!.map((s) => s.text).join(), '[I/USB] Clock: 72000000 Hz');
    expect(semanticSpans[0].style?.color, dracula.info);
    expect(semanticSpans[2].style?.color, dracula.number);

    final ansiSpans = buildTerminalTextSpans(
      '\x1B[32mOK\x1B[0m \x1B[31mERR\x1B[0m',
      scheme: dracula,
      baseStyle: baseStyle,
    );
    expect(ansiSpans, isNotNull);
    expect(ansiSpans!.map((s) => s.text).join(), 'OK ERR');
    expect(ansiSpans[0].style?.color, dracula.ansi[2]);
    expect(ansiSpans[2].style?.color, dracula.ansi[1]);
  });
}
