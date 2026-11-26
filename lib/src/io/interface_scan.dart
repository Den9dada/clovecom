// 接口扫描聚合：一次扫描产出串口组 + 网卡组（决策 Q3/Q7/Q16）
//
// 失效处理：网卡/IP 变化不抛错，由 UI 对照最新快照标灰"已失效"。

import '../../models/serial_port_model.dart';
import '../../services/serial/serial_port_catalog.dart';
import 'nic_scanner.dart';

class InterfaceScanResult {
  const InterfaceScanResult({
    required this.serialPorts,
    required this.nics,
    this.serialWarning,
    this.nicWarning,
  });

  final List<PortDetailInfo> serialPorts;

  /// 不含"自动"伪条目；由 UI 在网卡组顶部固定展示
  final List<NicEndpoint> nics;

  final String? serialWarning;
  final String? nicWarning;

  bool containsSerial(String portName) =>
      serialPorts.any((p) => p.portName == portName);

  bool containsNic(String ip) => nics.any((n) => n.ip == ip);
}

/// 聚合扫描串口与本机网卡；两路各自容错、互不拖累。
Future<InterfaceScanResult> scanInterfaceEndpoints(SerialPortCatalog catalog) async {
  List<PortDetailInfo> serialPorts = const [];
  String? serialWarning;
  try {
    final scan = await catalog.scan();
    serialPorts = scan.devices;
    serialWarning = scan.warning;
  } catch (error) {
    serialWarning = '串口枚举失败：$error';
  }
  List<NicEndpoint> nics = const [];
  String? nicWarning;
  try {
    nics = await scanNicEndpoints();
  } catch (error) {
    nicWarning = '网卡枚举失败：$error';
  }
  return InterfaceScanResult(
    serialPorts: serialPorts,
    nics: nics,
    serialWarning: serialWarning,
    nicWarning: nicWarning,
  );
}
