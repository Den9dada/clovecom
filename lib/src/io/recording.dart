import 'dart:convert';

class RawPacket {
  RawPacket({
    required this.connectionId,
    required this.receivedAt,
    required List<int> bytes,
    this.peer,
    this.datagram = false,
  }) : bytes = List.unmodifiable(bytes);
  final String connectionId;
  final DateTime receivedAt;
  final List<int> bytes;
  final String? peer;
  final bool datagram;
  Map<String, dynamic> toJson() => {
    'connectionId': connectionId,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'peer': peer,
    'datagram': datagram,
    'bytes': base64Encode(bytes),
  };
  factory RawPacket.fromJson(Map<String, dynamic> json) => RawPacket(
    connectionId: json['connectionId'] as String,
    receivedAt: DateTime.parse(json['receivedAt'] as String),
    peer: json['peer'] as String?,
    datagram: json['datagram'] as bool,
    bytes: base64Decode(json['bytes'] as String),
  );
}
