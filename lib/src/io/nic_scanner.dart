// 网卡扫描（接口扫描的网卡分组）
//
// 决策依据：仅枚举本机 IPv4 单播地址（决策 Q3/Q22），不探测局域网设备；
// "自动（全部网卡）"以空字符串哨兵表示（决策 Q15）。
// 广播默认目的地址尽力推算子网定向广播，失败回退受限广播 255.255.255.255
// （决策 Q20）。

import 'dart:io';

/// 一个可选的网卡通信接口端点（本机视角）。
class NicEndpoint {
  const NicEndpoint({required this.name, required this.address});

  /// 操作系统连接名称，如 "以太网"、"WLAN"
  final String name;

  /// 本机 IPv4 单播地址
  final InternetAddress address;

  String get ip => address.address;

  /// 选择器唯一键；"自动"键见 [kAutoNicKey]
  String get key => ip;

  String get label => '$name ($ip)';

  static const String kAutoNicKey = '';
  static const String kAutoNicLabel = '自动（全部网卡）';
  static const String kLimitedBroadcast = '255.255.255.255';

  /// 受限/兜底伪条目：自动
  static NicEndpoint get auto =>
      NicEndpoint(name: kAutoNicLabel, address: InternetAddress('0.0.0.0'));
}

/// 枚举本机网卡 IPv4 地址（不含回环与链路本地地址）。
Future<List<NicEndpoint>> scanNicEndpoints() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  final endpoints = <NicEndpoint>[];
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (address.isLoopback) continue;
      if (address.address.startsWith('169.254.')) continue; // APIPA 无实际出口
      endpoints.add(NicEndpoint(name: interface.name, address: address));
    }
  }
  endpoints.sort((a, b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.ip.compareTo(b.ip);
  });
  return endpoints;
}

/// 尽力推算 [nicIp] 所在子网的定向广播地址；不可得时回退受限广播。
///
/// Windows 走 `netsh interface ipv4 show subnets`；其他平台直接回退。
Future<String> probeDirectedBroadcastAddress(String nicIp) async {
  if (!Platform.isWindows || nicIp.isEmpty || nicIp == '0.0.0.0') {
    return NicEndpoint.kLimitedBroadcast;
  }
  try {
    final result = await Process.run(
      'netsh',
      ['interface', 'ipv4', 'show', 'subnets'],
    ).timeout(const Duration(seconds: 3));
    if (result.exitCode != 0) return NicEndpoint.kLimitedBroadcast;
    final output = result.stdout as String;
    for (final line in output.split('\n')) {
      final columns = line.trim().split(RegExp(r'\s+'));
      if (columns.length < 4) continue;
      final cidr = columns.first; // 形如 192.168.1.0/24
      final slash = cidr.indexOf('/');
      if (slash <= 0) continue;
      final maskBits = int.tryParse(cidr.substring(slash + 1));
      if (maskBits == null || maskBits < 0 || maskBits > 32) continue;
      final base = InternetAddress(cidr.substring(0, slash)).address;
      final broadcast = _broadcastOf(base, maskBits);
      if (broadcast == null) continue;
      final octets = base.split('.');
      final target = nicIp.split('.');
      // 同子网判定：网络前缀一致
      final prefixBytes = maskBits ~/ 8;
      var sameNetwork = true;
      for (var i = 0; i < prefixBytes; i++) {
        if (octets[i] != target[i]) {
          sameNetwork = false;
          break;
        }
      }
      if (sameNetwork && maskBits % 8 == 0) return broadcast;
      if (sameNetwork && maskBits % 8 != 0) {
        // 非整字节的最后一位也一致才可用
        final hostBits = 8 - (maskBits % 8);
        if ((int.parse(octets[prefixBytes]) >> hostBits) ==
            (int.parse(target[prefixBytes]) >> hostBits)) {
          return broadcast;
        }
      }
    }
  } catch (_) {
    // 探测失败静默回退
  }
  return NicEndpoint.kLimitedBroadcast;
}

String? _broadcastOf(String networkIp, int maskBits) {
  final octets = networkIp.split('.').map(int.tryParse).toList();
  if (octets.any((o) => o == null)) return null;
  final mask = maskBits == 0 ? 0 : (0xFFFFFFFF << (32 - maskBits)) & 0xFFFFFFFF;
  final host = (0xFFFFFFFF & ~mask) & 0xFFFFFFFF;
  final value = octets.fold<int>(0, (acc, o) => (acc << 8) | o!) & mask | host;
  return [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
      .join('.');
}
