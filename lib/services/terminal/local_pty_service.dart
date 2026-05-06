import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class LocalPtyService {
  Pty? _pty;

  Pty? get pty => _pty;

  static String get defaultShell {
    if (Platform.isWindows) return 'cmd.exe';
    if (Platform.isMacOS || Platform.isLinux) return 'bash';
    return 'sh';
  }

  void start({
    String? shell,
    int columns = 80,
    int rows = 24,
    Terminal? terminal,
  }) {
    _pty = Pty.start(
      shell ?? defaultShell,
      columns: columns,
      rows: rows,
    );

    if (terminal != null) {
      _pty!.output.cast<List<int>>().listen((data) {
        terminal.write(String.fromCharCodes(data));
      });
    }
  }

  void resize(int columns, int rows) {
    _pty?.resize(columns, rows);
  }

  void dispose() {
    try {
      _pty?.kill();
    } catch (_) {}
    _pty = null;
  }
}
