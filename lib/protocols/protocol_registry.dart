import 'transfer_protocol.dart';
import 'raw_packet_protocol.dart';
import 'ymodem_protocol.dart';

/// 协议注册表
///
/// 管理所有可用的传输协议。
/// 添加新协议时，只需在此处注册即可。
class ProtocolRegistry {
  static final List<TransferProtocol> _protocols = [
    RawPacketProtocol(),
    YmodemProtocol(),
  ];

  /// 获取所有可用协议
  static List<TransferProtocol> get protocols => List.unmodifiable(_protocols);

  /// 根据名称获取协议
  static TransferProtocol getByName(String name) {
    return _protocols.firstWhere(
      (p) => p.name == name,
      orElse: () => _protocols.first,
    );
  }

  /// 获取默认协议（分包发送）
  static TransferProtocol get defaultProtocol => _protocols.first;
}
