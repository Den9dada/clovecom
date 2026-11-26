import 'dart:async';
import 'dart:typed_data';

import 'package:clovecom/src/application/communication_transport.dart';

/// 两台独立响应设备只实现线上的Ymodem对端；应用使用真实协议。
class YmodemDevice implements CommunicationTransport {
  final input = StreamController<TransportInput>.broadcast(sync: true);
  final changes = StreamController<CommunicationTransportState>.broadcast(
    sync: true,
  );
  final writes = <List<int>>[];
  bool holdHeader = false;
  int eots = 0, replyCount = 0;
  void reply(List<int> data) {
    replyCount++;
    input.add(TransportInput(data));
  }

  @override
  CommunicationTransportState get state =>
      const CommunicationTransportState(writable: true);
  @override
  Stream<TransportInput> get incoming => input.stream;
  @override
  Stream<CommunicationTransportState> get states => changes.stream;
  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) async {
    writes.add(List.of(bytes));
    if (bytes[0] == 4) {
      reply([++eots == 1 ? 0x15 : 6]);
    } else if (bytes[0] == 2) {
      reply([6, 0x43]);
    } else if (bytes[0] == 1 && bytes[3] == 0) {
      reply([6]);
    } else if (!holdHeader) {
      reply([6, 0x43]);
    }
    return SerialWriteResult.success(bytes.length);
  }

  @override
  Future<void> close() async {
    await input.close();
    await changes.close();
  }
}
