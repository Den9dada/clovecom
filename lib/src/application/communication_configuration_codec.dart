import 'communication_transport.dart';
import '../io/connections.dart';
import '../io/interface_params.dart';

Map<String, dynamic> encodeConnectionDefinition(ConnectionDefinition d) => {
  'id': d.id,
  'name': d.name,
  'kind': d.isSerial ? 'serial' : d.protocol!.name,
  if (d.isSerial) 'serial': d.serial!.toJson(),
  if (!d.isSerial) ...{
    'tcpClient': d.tcpClient.toJson(),
    'tcpServer': d.tcpServer.toJson(),
    'udp': d.udp.toJson(),
  },
};

ConnectionDefinition decodeConnectionDefinition(Map<String, dynamic> json) {
  final id = json['id'] as String;
  final name = json['name'] as String;
  if (json['kind'] == 'serial') {
    final serial = Map<String, dynamic>.from(json['serial'] as Map);
    if (serial['id'] != id ||
        serial['name'] != name ||
        serial['kind'] != 'serial') {
      throw const FormatException('串口配置身份不一致');
    }
    return ConnectionDefinition.serial(ConnectionConfig.fromJson(serial));
  }
  final protocol = InterfaceProtocol.values.byName(json['kind'] as String);
  Map<String, dynamic> prefs(String key) =>
      Map<String, dynamic>.from(json[key] as Map? ?? {});
  final active = prefs(protocol.name);
  // 关键目标缺失时拒绝该项；不能把设备静默切换成默认串口或回环地址。
  if (active['nicKey'] is! String ||
      active['localPort'] is! int ||
      !isValidLocalPort(active['localPort'] as int)) {
    throw const FormatException('缺少有效的本地接口配置');
  }
  if (protocol == InterfaceProtocol.tcpClient &&
      (active['remoteHost'] is! String || active['remotePort'] is! int)) {
    throw const FormatException('缺少 TCP 客户端目标');
  }
  if (protocol == InterfaceProtocol.udp &&
      (active['mode'] is! String ||
          active['unicastHost'] is! String ||
          active['unicastPort'] is! int ||
          active['broadcastHost'] is! String ||
          active['broadcastPort'] is! int)) {
    throw const FormatException('缺少 UDP 目标配置');
  }
  final d = ConnectionDefinition.network(
    id: id,
    name: name,
    protocol: protocol,
    tcpClient: TcpClientPrefs.fromJson(prefs('tcpClient')),
    tcpServer: TcpServerPrefs.fromJson(prefs('tcpServer')),
    udp: UdpPrefs.fromJson(prefs('udp')),
  );
  if (protocol == InterfaceProtocol.tcpClient && !d.tcpClient.hasValidTarget ||
      protocol == InterfaceProtocol.udp && !d.udp.hasValidTarget) {
    throw const FormatException('通信目标无效');
  }
  return d;
}
