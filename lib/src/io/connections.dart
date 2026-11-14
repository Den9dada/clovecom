enum TransportKind { udp, tcp, serial }

enum LinkState { connecting, connected, retrying, disconnected }

class ConnectionConfig {
  ConnectionConfig({
    required this.id,
    String? name,
    this.enabled = true,
    required this.protocolId,
    required this.kind,
    this.host = '127.0.0.1',
    this.port = 9000,
    this.serialPort = '',
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
    this.anchorId,
    this.autoReconnect = true,
    this.interactionProtocolId,
    this.flowControl = 'none',
    this.remoteHost,
    this.remotePort,
  }) : name = name ?? id {
    if (id.trim().isEmpty) {
      throw const FormatException('连接标识不能为空');
    }
    if (this.name.trim().isEmpty) throw const FormatException('数据源名称不能为空');
    if (!['none', 'rts_cts', 'dtr_dsr', 'xon_xoff'].contains(flowControl)) {
      throw const FormatException('流控模式无效');
    }
    if ((remoteHost == null) != (remotePort == null) ||
        (remoteHost != null &&
            (remoteHost!.trim().isEmpty ||
                remotePort! <= 0 ||
                remotePort! > 65535))) {
      throw const FormatException('UDP 固定对端必须包含有效地址和端口');
    }
    if (kind == TransportKind.serial) {
      if (serialPort.isEmpty ||
          baudRate <= 0 ||
          ![5, 6, 7, 8].contains(dataBits) ||
          ![1, 2].contains(stopBits) ||
          parity < 0 ||
          parity > 4) {
        throw const FormatException('串口配置无效');
      }
    } else if (host.trim().isEmpty ||
        port < 0 ||
        port > 65535 ||
        (kind == TransportKind.tcp && port == 0)) {
      throw const FormatException('网络地址或端口无效');
    }
  }
  final String id;
  final String name;
  final bool enabled;

  /// 空字符串表示仅收发原始字节，不接入定位协议解析。
  final String protocolId;
  final TransportKind kind;
  final String host;
  final int port;
  final String serialPort;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final int parity;
  final String? anchorId;
  final bool autoReconnect;
  final String? interactionProtocolId;
  final String flowControl;
  final String? remoteHost;
  final int? remotePort;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'protocolId': protocolId,
    'kind': kind.name,
    'host': host,
    'port': port,
    'serialPort': serialPort,
    'baudRate': baudRate,
    'dataBits': dataBits,
    'stopBits': stopBits,
    'parity': parity,
    'anchorId': anchorId,
    'autoReconnect': autoReconnect,
    'interactionProtocolId': interactionProtocolId,
    'flowControl': flowControl,
    'remoteHost': remoteHost,
    'remotePort': remotePort,
  };
  factory ConnectionConfig.fromJson(Map<String, dynamic> json) =>
      ConnectionConfig(
        interactionProtocolId: json['interactionProtocolId'] as String?,
        flowControl: json['flowControl'] as String? ?? 'none',
        remoteHost: json['remoteHost'] as String?,
        remotePort: json['remotePort'] as int?,
        id: json['id'] as String,
        name: json['name'] as String?,
        enabled: json['enabled'] as bool? ?? true,
        protocolId: json['protocolId'] as String,
        kind: TransportKind.values.byName(json['kind'] as String),
        host: json['host'] as String,
        port: json['port'] as int,
        serialPort: json['serialPort'] as String,
        baudRate: json['baudRate'] as int,
        dataBits: json['dataBits'] as int,
        stopBits: json['stopBits'] as int,
        parity: json['parity'] as int,
        anchorId: json['anchorId'] as String?,
        autoReconnect: json['autoReconnect'] as bool,
      );
}
