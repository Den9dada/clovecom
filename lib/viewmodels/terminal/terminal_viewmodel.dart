import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../models/terminal/session_type.dart';
import '../../models/terminal/terminal_session.dart';
import '../../models/terminal/ssh_connection_params.dart';
import '../../models/terminal/serial_connection_params.dart';
import '../../services/terminal/local_pty_service.dart';
import '../../services/terminal/ssh_terminal_service.dart';
import '../../services/terminal/serial_terminal_service.dart';

class TerminalViewModel extends ChangeNotifier {
  final List<TerminalSession> _sessions = [];
  int _selectedSessionIndex = -1;

  final LocalPtyService _localPty = LocalPtyService();
  final SshTerminalService _sshService = SshTerminalService();
  final SerialTerminalService _serialService = SerialTerminalService();

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  int get selectedSessionIndex => _selectedSessionIndex;
  TerminalSession? get selectedSession =>
      _selectedSessionIndex >= 0 && _selectedSessionIndex < _sessions.length
          ? _sessions[_selectedSessionIndex]
          : null;

  bool get hasLocal =>
      _sessions.any((s) => s.type == SessionType.local);
  List<TerminalSession> get sshSessions =>
      _sessions.where((s) => s.type == SessionType.ssh).toList();
  List<TerminalSession> get serialSessions =>
      _sessions.where((s) => s.type == SessionType.serial).toList();

  void selectSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _selectedSessionIndex = index;
    notifyListeners();
  }

  void createLocalTerminal() {
    if (hasLocal) {
      final idx =
          _sessions.indexWhere((s) => s.type == SessionType.local);
      if (idx >= 0) {
        _selectedSessionIndex = idx;
        notifyListeners();
      }
      return;
    }

    final terminal = Terminal();
    final session = TerminalSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '本地Shell',
      type: SessionType.local,
      terminal: terminal,
      status: SessionStatus.connected,
    );

    _localPty.start(terminal: terminal);

    terminal.onOutput = (data) {
      _localPty.pty?.write(Uint8List.fromList(data.codeUnits));
    };

    _sessions.add(session);
    _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();
  }

  Future<void> createSshSession(SshConnectionParams params) async {
    final terminal = Terminal();
    final session = TerminalSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: params.displayName,
      type: SessionType.ssh,
      terminal: terminal,
      status: SessionStatus.connecting,
    );

    _sessions.add(session);
    _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();

    try {
      await _sshService.connect(params, terminal);
      session.status = SessionStatus.connected;
    } catch (e) {
      session.status = SessionStatus.disconnected;
      terminal.write('\r\n\x1b[31mConnection failed: $e\x1b[0m\r\n');
    }
    notifyListeners();
  }

  void createSerialSession(SerialConnectionParams params) {
    final terminal = Terminal();
    final session = TerminalSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: params.displayName,
      type: SessionType.serial,
      terminal: terminal,
      status: SessionStatus.connected,
    );

    _serialService.connect(params, terminal);

    _sessions.add(session);
    _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();
  }

  void closeSession(int index) {
    if (index < 0 || index >= _sessions.length) return;

    final session = _sessions[index];

    if (session.type == SessionType.local) {
      _localPty.dispose();
    } else if (session.type == SessionType.ssh) {
      _sshService.disconnect();
    } else if (session.type == SessionType.serial) {
      _serialService.disconnect();
    }

    _sessions.removeAt(index);

    if (_sessions.isEmpty) {
      _selectedSessionIndex = -1;
    } else if (_selectedSessionIndex >= _sessions.length) {
      _selectedSessionIndex = _sessions.length - 1;
    } else if (index <= _selectedSessionIndex) {
      _selectedSessionIndex--;
    }
    notifyListeners();
  }

  void resizeActiveTerminal(int columns, int rows) {
    if (selectedSession?.type == SessionType.local) {
      _localPty.resize(columns, rows);
    }
    if (selectedSession?.type == SessionType.ssh) {
      _sshService.resize(columns, rows);
    }
  }

  @override
  void dispose() {
    _localPty.dispose();
    _sshService.dispose();
    _serialService.dispose();
    super.dispose();
  }
}
