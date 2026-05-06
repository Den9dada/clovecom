import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../../models/terminal/ssh_connection_params.dart';

class SshTerminalService {
  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription? _stdoutSub;

  bool get isConnected => _client != null;

  Future<void> connect(
    SshConnectionParams params,
    Terminal terminal,
  ) async {
    final socket = await SSHSocket.connect(params.host, params.port);
    _client = SSHClient(
      socket,
      username: params.username,
      onPasswordRequest: () => params.password,
    );

    _session = await _client!.shell();

    _stdoutSub = _session!.stdout.cast<List<int>>().listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });

    terminal.onOutput = (data) {
      if (_session != null) {
        _session!.write(utf8.encode(data));
      }
    };
  }

  void resize(int columns, int rows) {
    _session?.resizeTerminal(columns, rows);
  }

  void disconnect() {
    _stdoutSub?.cancel();
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _session = null;
  }

  void dispose() => disconnect();
}
