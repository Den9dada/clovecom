class SshConnectionParams {
  SshConnectionParams({
    required this.host,
    this.port = 22,
    this.sessionName = '',
    this.username = 'root',
    this.password = '',
  });

  final String host;
  final int port;
  final String sessionName;
  final String username;
  final String password;

  String get displayName =>
      sessionName.isNotEmpty ? sessionName : '$username@$host:$port';
}
