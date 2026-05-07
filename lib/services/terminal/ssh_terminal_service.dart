import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../../models/terminal/ssh_connection_params.dart';

class SshTerminalService {
  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription? _stdoutSub;
  String Function(String)? _dataTransform;

  bool get isConnected => _client != null;

  Future<void> connect(
    SshConnectionParams params,
    Terminal terminal, {
    String Function(String)? dataTransform,
  }) async {
    _dataTransform = dataTransform;
    final socket = await SSHSocket.connect(params.host, params.port);
    _client = SSHClient(
      socket,
      username: params.username,
      onPasswordRequest: () => params.password,
    );

    _session = await _client!.shell(
      pty: SSHPtyConfig(type: params.terminalType, width: 80, height: 24),
    );

    _stdoutSub = _session!.stdout.cast<List<int>>().listen((data) {
      var text = utf8.decode(data, allowMalformed: true);
      if (_dataTransform != null) {
        text = _dataTransform!(text);
      }
      terminal.write(text);
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
