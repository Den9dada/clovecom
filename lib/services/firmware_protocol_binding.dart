import 'package:flutter/foundation.dart';
import '../models/serial_port_model.dart';
import '../protocol_editor.dart';

/// 已载入内容与协议库分离；保存新版本不会改变升级输入。
class FirmwareProtocolBinding extends ChangeNotifier {
  FirmwareProtocolBinding(this.library) {
    library.addListener(notifyListeners);
  }
  final ProtocolLibrary library;
  InteractionProtocol? _loaded;
  bool loading = false;
  int _request = 0;
  InteractionProtocol? get loaded => _loaded;
  bool get hasNewVersion =>
      _loaded != null &&
      library.savedInteraction(_loaded!.id)?.digest != _loaded!.digest;
  List<InteractionProtocol> get available =>
      library.savedInteractions.where((p) {
        try {
          return p.metadata.purpose == InteractionPurpose.upgrade &&
              p.metadata.transports.contains('serial');
        } catch (_) {
          return false;
        }
      }).toList();

  Future<bool> load(
    String id, {
    required bool Function() locked,
    required SerialPortConfig Function() currentConfig,
    required bool Function() connected,
    required void Function(SerialPortConfig) applyConfig,
  }) async {
    if (library.operation != null) throw StateError('请等待协议库保存完成');
    if (locked()) throw StateError('请先停止传输任务');
    final protocol =
        library.savedInteraction(id) ?? (throw StateError('请先在协议编辑页保存脚本'));
    final metadata = protocol.metadata;
    if (metadata.purpose != InteractionPurpose.upgrade ||
        !metadata.transports.contains('serial') ||
        (metadata.dataSource['kind'] != null &&
            metadata.dataSource['kind'] != 'serial')) {
      throw StateError('该脚本不能用于串口固件升级');
    }
    final request = ++_request;
    loading = true;
    notifyListeners();
    try {
      final diagnostics = await library.runtime.validate(protocol);
      if (request != _request) return false;
      if (library.operation != null || library.savedInteraction(id) == null) {
        throw StateError('协议库状态已变化，请重新载入');
      }
      if (diagnostics.isNotEmpty) throw StateError(diagnostics.join('\n'));
      if (locked()) throw StateError('连接或传输状态已变化，请重新载入');
      final persistent = metadata.dataSource['persistent'] as Map? ?? const {};
      if (persistent.keys.any(
        (k) => ['host', 'port', 'remote_host', 'remote_port'].contains(k),
      )) {
        throw StateError('串口升级不支持网络接口初值');
      }
      if (persistent.isNotEmpty && connected()) {
        throw StateError('协议声明了接口参数，请先断开串口再载入');
      }
      final current = currentConfig();
      final config = current.copyWith(
        portName: persistent['serial_port'] as String?,
        baudRate: persistent['baud_rate'] as int?,
        dataBits: persistent['data_bits'] as int?,
        stopBits: persistent['stop_bits'] as int?,
        parity: persistent['parity'] == null
            ? null
            : const {
                'none': 'None',
                'odd': 'Odd',
                'even': 'Even',
                'mark': 'Mark',
                'space': 'Space',
              }[persistent['parity']],
        flowControl: persistent['flow_control'] == null
            ? null
            : const {
                'none': 'None',
                'rts_cts': 'RTS/CTS',
                'dtr_dsr': 'DTR/DSR',
                'xon_xoff': 'XON/XOFF',
              }[persistent['flow_control']],
      );
      // 只在明确载入时填充一次，之后使用用户在界面上的最新配置。
      applyConfig(config);
      library.retain(protocol.id);
      if (_loaded != null) library.release(_loaded!.id);
      _loaded = protocol;
      return true;
    } finally {
      if (request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void unload() {
    _request++;
    loading = false;
    if (_loaded != null) library.release(_loaded!.id);
    _loaded = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _request++;
    library.removeListener(notifyListeners);
    if (_loaded != null) library.release(_loaded!.id);
    super.dispose();
  }
}
