// 接口通信参数模型
//
// 术语对齐 CONTEXT.md：通信接口（串口/网卡）→ 接口协议（TCP客户端/
// TCP服务端/UDP）→ UDP 通信模式（单播/广播）。串口线路参数（波特率等）
// 仍由 SerialPortConfig 承载，此处只记录"选中了哪个接口 + 各协议各自的参数"。
//
// 本地端口统一语义（决策 Q23）：0 = 留空、由系统自动分配；1-65535 = 手动指定。
// UDP 单播/广播的目的地址与目的端口各自独立保存，切换模式即切换字段。

import '../../models/serial_port_model.dart' show SerialPortConfig;
import 'nic_scanner.dart';

/// 通信接口类别
enum InterfaceKind { serial, nic }

/// 接口协议（仅网卡接口有协议维度）
enum InterfaceProtocol { tcpClient, tcpServer, udp }

/// UDP 通信模式
enum UdpMode { unicast, broadcast }

/// 本地端口有效性：0（自动分配）或 1-65535 均合法
bool isValidLocalPort(int port) => port >= 0 && port <= 65535;

/// TCP客户端参数
class TcpClientPrefs {
  const TcpClientPrefs({
    this.nicKey = NicEndpoint.kAutoNicKey,
    this.remoteHost = '127.0.0.1',
    this.remotePort = 9000,
    this.localPort = 0,
    this.autoReconnect = false,
  });

  /// 出口网卡（'' = 自动/系统路由；UI 以"本地IP"只读展示）
  final String nicKey;
  final String remoteHost;
  final int remotePort;

  /// 本地端口；0 = 留空由系统分配（与 TCP服务端一致，决策 Q23）
  final int localPort;

  /// 自动重连（决策 Q13：TCP客户端专属开关）
  final bool autoReconnect;

  bool get hasValidTarget =>
      remoteHost.trim().isNotEmpty && remotePort > 0 && remotePort <= 65535;

  TcpClientPrefs copyWith({
    String? nicKey,
    String? remoteHost,
    int? remotePort,
    int? localPort,
    bool? autoReconnect,
  }) =>
      TcpClientPrefs(
        nicKey: nicKey ?? this.nicKey,
        remoteHost: remoteHost ?? this.remoteHost,
        remotePort: remotePort ?? this.remotePort,
        localPort: localPort ?? this.localPort,
        autoReconnect: autoReconnect ?? this.autoReconnect,
      );

  Map<String, dynamic> toJson() => {
        'nicKey': nicKey,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
        'localPort': localPort,
        'autoReconnect': autoReconnect,
      };

  factory TcpClientPrefs.fromJson(Map<String, dynamic> json) => TcpClientPrefs(
        nicKey: json['nicKey'] as String? ?? NicEndpoint.kAutoNicKey,
        remoteHost: json['remoteHost'] as String? ?? '127.0.0.1',
        remotePort: json['remotePort'] as int? ?? 9000,
        localPort: json['localPort'] as int? ?? 0,
        autoReconnect: json['autoReconnect'] as bool? ?? false,
      );
}

/// TCP服务端参数（单客户端语义，决策 Q19）
class TcpServerPrefs {
  const TcpServerPrefs({
    this.nicKey = NicEndpoint.kAutoNicKey,
    this.localPort = 0,
  });

  /// 监听网卡（'' = 全部网卡 0.0.0.0；UI 以"本地IP"只读展示）
  final String nicKey;

  /// 本地端口；0 = 留空由系统自动分配（决策 Q23）
  final int localPort;

  bool get hasValidPort => isValidLocalPort(localPort);

  TcpServerPrefs copyWith({String? nicKey, int? localPort}) => TcpServerPrefs(
        nicKey: nicKey ?? this.nicKey,
        localPort: localPort ?? this.localPort,
      );

  Map<String, dynamic> toJson() => {'nicKey': nicKey, 'localPort': localPort};

  factory TcpServerPrefs.fromJson(Map<String, dynamic> json) => TcpServerPrefs(
        nicKey: json['nicKey'] as String? ?? NicEndpoint.kAutoNicKey,
        // 旧版键 listenPort 迁移为 localPort
        localPort:
            json['localPort'] as int? ?? json['listenPort'] as int? ?? 0,
      );
}

/// UDP参数（含通信模式，决策 Q9/Q23）。
/// 单播与广播各自保存目的地址与端口，模式切换只是切换显示。
class UdpPrefs {
  const UdpPrefs({
    this.nicKey = NicEndpoint.kAutoNicKey,
    this.localPort = 0,
    this.mode = UdpMode.unicast,
    this.unicastHost = '',
    this.unicastPort = 0,
    this.broadcastHost = '',
    this.broadcastPort = 0,
  });

  /// 绑定网卡（'' = 全部网卡 0.0.0.0；UI 以"本地IP"只读展示）
  final String nicKey;

  /// 本地端口；0 = 留空由系统分配（与 TCP服务端一致，决策 Q23）
  final int localPort;
  final UdpMode mode;

  /// 单播目的（对端 IP/端口）
  final String unicastHost;
  final int unicastPort;

  /// 广播目的（定向/受限广播地址与端口，决策 Q20）
  final String broadcastHost;
  final int broadcastPort;

  /// 当前模式生效的目的地址（传输层与校验统一走该视图）
  String get targetHost =>
      mode == UdpMode.broadcast ? broadcastHost : unicastHost;

  int get targetPort =>
      mode == UdpMode.broadcast ? broadcastPort : unicastPort;

  bool get hasValidTarget =>
      targetHost.trim().isNotEmpty && targetPort > 0 && targetPort <= 65535;

  UdpPrefs copyWith({
    String? nicKey,
    int? localPort,
    UdpMode? mode,
    String? unicastHost,
    int? unicastPort,
    String? broadcastHost,
    int? broadcastPort,
  }) =>
      UdpPrefs(
        nicKey: nicKey ?? this.nicKey,
        localPort: localPort ?? this.localPort,
        mode: mode ?? this.mode,
        unicastHost: unicastHost ?? this.unicastHost,
        unicastPort: unicastPort ?? this.unicastPort,
        broadcastHost: broadcastHost ?? this.broadcastHost,
        broadcastPort: broadcastPort ?? this.broadcastPort,
      );

  Map<String, dynamic> toJson() => {
        'nicKey': nicKey,
        'localPort': localPort,
        'mode': mode.name,
        'unicastHost': unicastHost,
        'unicastPort': unicastPort,
        'broadcastHost': broadcastHost,
        'broadcastPort': broadcastPort,
      };

  factory UdpPrefs.fromJson(Map<String, dynamic> json) {
    final mode = UdpMode.values.byName(json['mode'] as String? ?? 'unicast');
    // 旧版单字段 targetHost/targetPort 迁移到当前模式对应字段
    final legacyHost = json['targetHost'] as String?;
    final legacyPort = json['targetPort'] as int?;
    final hasLegacy = legacyHost != null || legacyPort != null;
    return UdpPrefs(
      nicKey: json['nicKey'] as String? ?? NicEndpoint.kAutoNicKey,
      localPort: json['localPort'] as int? ?? 0,
      mode: mode,
      unicastHost:
          json['unicastHost'] as String? ?? (hasLegacy && mode == UdpMode.unicast ? legacyHost ?? '' : ''),
      unicastPort:
          json['unicastPort'] as int? ?? (hasLegacy && mode == UdpMode.unicast ? legacyPort ?? 0 : 0),
      broadcastHost:
          json['broadcastHost'] as String? ?? (hasLegacy && mode == UdpMode.broadcast ? legacyHost ?? '' : ''),
      broadcastPort:
          json['broadcastPort'] as int? ?? (hasLegacy && mode == UdpMode.broadcast ? legacyPort ?? 0 : 0),
    );
  }
}

/// 接口通信整体偏好：上次选中的接口 + 各协议各自的参数（决策 Q14）。
class InterfacePrefs {
  InterfacePrefs({
    this.lastKind = InterfaceKind.serial,
    this.lastProtocol = InterfaceProtocol.tcpClient,
    SerialPortConfig? serial,
    TcpClientPrefs? tcpClient,
    TcpServerPrefs? tcpServer,
    UdpPrefs? udp,
  })  : serial = serial ?? SerialPortConfig(portName: ''),
        tcpClient = tcpClient ?? const TcpClientPrefs(),
        tcpServer = tcpServer ?? const TcpServerPrefs(),
        udp = udp ?? const UdpPrefs();

  final InterfaceKind lastKind;
  final InterfaceProtocol lastProtocol;
  final SerialPortConfig serial;
  final TcpClientPrefs tcpClient;
  final TcpServerPrefs tcpServer;
  final UdpPrefs udp;

  InterfacePrefs copyWith({
    InterfaceKind? lastKind,
    InterfaceProtocol? lastProtocol,
    SerialPortConfig? serial,
    TcpClientPrefs? tcpClient,
    TcpServerPrefs? tcpServer,
    UdpPrefs? udp,
  }) =>
      InterfacePrefs(
        lastKind: lastKind ?? this.lastKind,
        lastProtocol: lastProtocol ?? this.lastProtocol,
        serial: serial ?? this.serial,
        tcpClient: tcpClient ?? this.tcpClient,
        tcpServer: tcpServer ?? this.tcpServer,
        udp: udp ?? this.udp,
      );

  Map<String, dynamic> toJson() => {
        'lastKind': lastKind.name,
        'lastProtocol': lastProtocol.name,
        'serial': {
          'portName': serial.portName,
          'portFriendlyName': serial.portFriendlyName,
          'baudRate': serial.baudRate,
          'dataBits': serial.dataBits,
          'stopBits': serial.stopBits,
          'parity': serial.parity,
          'flowControl': serial.flowControl,
        },
        'tcpClient': tcpClient.toJson(),
        'tcpServer': tcpServer.toJson(),
        'udp': udp.toJson(),
      };

  factory InterfacePrefs.fromJson(Map<String, dynamic> json) {
    final serial = json['serial'] as Map? ?? const {};
    return InterfacePrefs(
      lastKind: InterfaceKind.values.byName(json['lastKind'] as String? ?? 'serial'),
      lastProtocol:
          InterfaceProtocol.values.byName(json['lastProtocol'] as String? ?? 'tcpClient'),
      serial: SerialPortConfig(
        portName: serial['portName'] as String? ?? '',
        portFriendlyName: serial['portFriendlyName'] as String? ?? '',
        baudRate: serial['baudRate'] as int? ?? 9600,
        dataBits: serial['dataBits'] as int? ?? 8,
        stopBits: serial['stopBits'] as int? ?? 1,
        parity: serial['parity'] as String? ?? 'None',
        flowControl: serial['flowControl'] as String? ?? 'None',
      ),
      tcpClient: TcpClientPrefs.fromJson(
          (json['tcpClient'] as Map?)?.cast<String, dynamic>() ?? const {}),
      tcpServer: TcpServerPrefs.fromJson(
          (json['tcpServer'] as Map?)?.cast<String, dynamic>() ?? const {}),
      udp: UdpPrefs.fromJson((json['udp'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }
}
