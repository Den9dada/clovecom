import 'package:xterm/xterm.dart';
import 'session_type.dart';

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.name,
    required this.type,
    required this.terminal,
    this.status = SessionStatus.disconnected,
    this.connectionParams,
  });

  final String id;
  final String name;
  final SessionType type;
  SessionStatus status;
  final Terminal terminal;
  dynamic connectionParams;

  bool get isConnected => status == SessionStatus.connected;

  String get statusLabel => switch (status) {
    SessionStatus.connected => 'Connected',
    SessionStatus.connecting => 'Connecting',
    SessionStatus.disconnected => 'Disconnected',
  };
}
