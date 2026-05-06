import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../models/terminal/terminal_session.dart';

class TerminalPane extends StatelessWidget {
  const TerminalPane({super.key, required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    return TerminalView(session.terminal);
  }
}
