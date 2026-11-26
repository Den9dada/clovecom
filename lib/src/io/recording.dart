import 'dart:convert';
import 'dart:typed_data';

class TransportInput {
  TransportInput(List<int> bytes, {this.peer, this.datagram = false})
    : bytes = _freezePacketBytes(bytes);

  /// 接收独占缓冲区的所有权。调用者移交后不得再修改底层字节。
  TransportInput.takeOwned(Uint8List bytes, {this.peer, this.datagram = false})
    : bytes = bytes.asUnmodifiableView();

  final List<int> bytes;
  final String? peer;
  final bool datagram;
}

List<int> _freezePacketBytes(List<int> bytes) => bytes is Uint8List
    ? Uint8List.fromList(bytes).asUnmodifiableView()
    : List.unmodifiable(bytes);

class RawPacket {
  RawPacket({
    required this.connectionId,
    required this.receivedAt,
    required List<int> bytes,
    this.epoch = 0,
    this.sequence = 0,
    this.peer,
    this.datagram = false,
  }) : bytes = _freezePacketBytes(bytes);

  /// 传输入口已经独占并冻结缓冲区，分发时直接复用。
  RawPacket.fromInput(
    TransportInput input, {
    required this.connectionId,
    required this.receivedAt,
    required this.epoch,
    required this.sequence,
    String? peer,
  }) : bytes = input.bytes,
       peer = input.peer ?? peer,
       datagram = input.datagram;
  final String connectionId;
  final DateTime receivedAt;
  final List<int> bytes;
  final int epoch;
  final int sequence;
  final String? peer;
  final bool datagram;
  Map<String, dynamic> toJson() => {
    'connectionId': connectionId,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'epoch': epoch,
    'sequence': sequence,
    'peer': peer,
    'datagram': datagram,
    'bytes': base64Encode(bytes),
  };
  factory RawPacket.fromJson(Map<String, dynamic> json) => RawPacket(
    connectionId: json['connectionId'] as String,
    receivedAt: DateTime.parse(json['receivedAt'] as String),
    epoch: json['epoch'] as int? ?? 0,
    sequence: json['sequence'] as int? ?? 0,
    peer: json['peer'] as String?,
    datagram: json['datagram'] as bool,
    bytes: base64Decode(json['bytes'] as String),
  );
}
