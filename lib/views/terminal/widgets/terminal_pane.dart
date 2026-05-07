import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../../models/terminal/terminal_session.dart';

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
  const TerminalPane({
    super.key,
    required this.session,
    required this.theme,
    this.onReconnect,
  });

  final TerminalSession session;
  final TerminalTheme theme;
  final VoidCallback? onReconnect;

  KeyEventResult _onKeyEvent(Terminal terminal, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final character = event.character;
      if (character != null && character.isNotEmpty) {
        if (!session.isConnected && character == 'r' && onReconnect != null) {
          onReconnect!();
          return KeyEventResult.handled;
        }
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
          color: theme.background,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: TerminalView(
          session.terminal,
          theme: theme,
          textStyle: _terminalStyle,
          padding: const EdgeInsets.all(8),
          onKeyEvent: (focusNode, event) =>
              _onKeyEvent(session.terminal, event),
        ),
      ),
    );
  }
}
