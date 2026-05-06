import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../models/terminal/session_type.dart';
import '../../models/terminal/terminal_session.dart';
import '../../models/terminal/ssh_connection_params.dart';
import '../../models/terminal/serial_connection_params.dart';
import '../../services/terminal/ssh_terminal_service.dart';
import '../../services/terminal/serial_terminal_service.dart';

class TerminalViewModel extends ChangeNotifier {
  final List<TerminalSession> _sessions = [];
  int _selectedSessionIndex = -1;

  final SshTerminalService _sshService = SshTerminalService();
  final SerialTerminalService _serialService = SerialTerminalService();

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  int get selectedSessionIndex => _selectedSessionIndex;
  TerminalSession? get selectedSession =>
      _selectedSessionIndex >= 0 && _selectedSessionIndex < _sessions.length
          ? _sessions[_selectedSessionIndex]
          : null;

  List<TerminalSession> get sshSessions =>
      _sessions.where((s) => s.type == SessionType.ssh).toList();
  List<TerminalSession> get serialSessions =>
      _sessions.where((s) => s.type == SessionType.serial).toList();

  void selectSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _selectedSessionIndex = index;
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
      connectionParams: params,
    );

    _sessions.add(session);
    _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();

    await _connectSsh(session);
    notifyListeners();
  }

  void createSerialSession(SerialConnectionParams params) {
    final terminal = Terminal();
    final session = TerminalSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: params.displayName,
      type: SessionType.serial,
      terminal: terminal,
      status: SessionStatus.connecting,
      connectionParams: params,
    );

    _sessions.add(session);
    _selectedSessionIndex = _sessions.length - 1;
    notifyListeners();

    _connectSerial(session);
    notifyListeners();
  }

  Future<void> reconnectSession(int index) async {
    if (index < 0 || index >= _sessions.length) return;
    final session = _sessions[index];
    if (session.isConnected) return;

    session.status = SessionStatus.connecting;
    notifyListeners();

    if (session.type == SessionType.ssh) {
      await _connectSsh(session);
    } else if (session.type == SessionType.serial) {
      _connectSerial(session);
    }
    notifyListeners();
  }

  Future<void> _connectSsh(TerminalSession session) async {
    final params = session.connectionParams as SshConnectionParams;
    _sshService.disconnect();
    try {
      await _sshService.connect(params, session.terminal);
      session.status = SessionStatus.connected;
    } catch (e) {
      session.status = SessionStatus.disconnected;
      session.terminal.write(
        '\r\n\x1b[31mConnection failed: $e\x1b[0m\r\n'
        '\x1b[33mPress r to reconnect\x1b[0m\r\n',
      );
    }
  }

  void _connectSerial(TerminalSession session) {
    final params = session.connectionParams as SerialConnectionParams;
    _serialService.disconnect();
    try {
      _serialService.connect(params, session.terminal);
      session.status = SessionStatus.connected;
    } catch (e) {
      session.status = SessionStatus.disconnected;
      session.terminal.write(
        '\r\n\x1b[31mSerial connection failed: $e\x1b[0m\r\n'
        '\x1b[33mPress r to reconnect\x1b[0m\r\n',
      );
    }
  }

  void closeSession(int index) {
    if (index < 0 || index >= _sessions.length) return;

    final session = _sessions[index];

    if (session.type == SessionType.ssh) {
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
    if (selectedSession?.type == SessionType.ssh) {
      _sshService.resize(columns, rows);
    }
  }

  @override
  void dispose() {
    _sshService.dispose();
    _serialService.dispose();
    super.dispose();
  }
}
