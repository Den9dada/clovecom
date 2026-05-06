class SshConnectionParams {
  SshConnectionParams({
    required this.host,
    this.port = 22,
    this.sessionName = '',
    this.username = 'root',
    this.password = '',
    this.terminalType = 'xterm-256color',
  });

  final String host;
  final int port;
  final String sessionName;
  final String username;
  final String password;
  final String terminalType;

  String get displayName =>
      sessionName.isNotEmpty ? sessionName : '$username@$host:$port';

  static const terminalTypes = [
    'xterm-256color',
    'xterm',
    'vt100',
    'vt220',
    'vt340',
    'vt420',
    'vt520',
  ];
}
