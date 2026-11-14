import 'transfer_protocol.dart';
import 'ymodem_protocol.dart';

/// 协议注册表
class ProtocolRegistry {
  static final List<TransferProtocol> _protocols = [YmodemProtocol()];

  static List<TransferProtocol> get protocols => List.unmodifiable(_protocols);
  static List<TransferProtocol> get receiveProtocols =>
      List.unmodifiable(_protocols);

  static TransferProtocol getByName(String name) {
    return YmodemProtocol();
  }

  static TransferProtocol getByReceiveName(String name) {
    return YmodemProtocol();
  }

  static TransferProtocol get defaultProtocol => _protocols.first;
}
