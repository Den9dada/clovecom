import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../../models/terminal/terminal_session.dart';

const _terminalTheme = TerminalTheme(
  cursor: Color(0xFFFFDD57),
  selection: Color(0x408080FF),
  foreground: Color(0xFFD4D4D4),
  background: Color(0xFF1A1A2E),
  black: Color(0xFF1A1A2E),
  red: Color(0xFFFF6B6B),
  green: Color(0xFF69DB7C),
  yellow: Color(0xFFFFD43B),
  blue: Color(0xFF4DABF7),
  magenta: Color(0xFFDA77F2),
  cyan: Color(0xFF22B8CF),
  white: Color(0xFFDEE2E6),
  brightBlack: Color(0xFF495057),
  brightRed: Color(0xFFFF8787),
  brightGreen: Color(0xFF8CE99A),
  brightYellow: Color(0xFFFFE066),
  brightBlue: Color(0xFF74C0FC),
  brightMagenta: Color(0xFFE599F7),
  brightCyan: Color(0xFF3BC9DB),
  brightWhite: Color(0xFFF8F9FA),
  searchHitBackground: Color(0x40FFDD57),
  searchHitBackgroundCurrent: Color(0x80FFDD57),
  searchHitForeground: Color(0xFF000000),
);

const _terminalStyle = TerminalStyle(
  fontSize: 14,
  fontFamily: 'Cascadia Code',
  fontFamilyFallback: [
    'Consolas',
    'Courier New',
    'Noto Sans Mono CJK SC',
    'Noto Color Emoji',
    'monospace',
  ],
);

class TerminalPane extends StatelessWidget {
  const TerminalPane({super.key, required this.session});

  final TerminalSession session;

  static KeyEventResult _onKeyEvent(
    Terminal terminal,
    FocusNode focusNode,
    KeyEvent event,
  ) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final character = event.character;
      if (character != null && character.isNotEmpty) {
        terminal.textInput(character);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: _terminalTheme.background,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: TerminalView(
          session.terminal,
          theme: _terminalTheme,
          textStyle: _terminalStyle,
          padding: const EdgeInsets.all(8),
          onKeyEvent: (focusNode, event) =>
              _onKeyEvent(session.terminal, focusNode, event),
        ),
      ),
    );
  }
}
