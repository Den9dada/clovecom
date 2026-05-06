import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../../models/terminal/session_type.dart';
import '../../../models/terminal/terminal_session.dart';

class TerminalPane extends StatelessWidget {
  const TerminalPane({super.key, required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      session.terminal,
      onKeyEvent: session.type == SessionType.serial
          ? (focusNode, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                final character = event.character;
                if (character != null && character.isNotEmpty) {
                  session.terminal.textInput(character);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            }
          : null,
    );
  }
}
