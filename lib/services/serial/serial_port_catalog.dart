import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import '../../models/serial_port_model.dart';

class SerialPortScan {
  SerialPortScan(List<PortDetailInfo> devices, {this.warning})
    : devices = List.unmodifiable(devices);
  final List<PortDetailInfo> devices;
  final String? warning;
}

/// 原生通知常驻应用；页面取消订阅不会撤销底层消息处理器。
class SerialPortCatalog {
  static const _channel = MethodChannel('clovecom/serial_ports');
  static final _changes = StreamController<void>.broadcast();
  static bool _watching = false;

  Stream<void> watchChanges() {
    if (!Platform.isWindows) return const Stream.empty();
    if (!_watching) {
      _watching = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'portsChanged') _changes.add(null);
      });
    }
    return _changes.stream;
  }

  Future<SerialPortScan> scan() async {
    if (!Platform.isWindows) return SerialPortScan([]);
    Object? nativeError;
    try {
      final values = await _channel.invokeListMethod<dynamic>('listPorts');
      if (values == null) throw StateError('原生枚举未返回结果');
      return _sorted(
        values
            .map(
              (dynamic item) => PortDetailInfo(
                portName: item['port'] as String,
                friendlyName: item['description'] as String? ?? '',
                hardwareID: '',
                manufactureName: '',
              ),
            )
            .toList(),
      );
    } catch (error) {
      nativeError = error;
    }
    try {
      final ports = SerialPort.getPortsWithFullMessages();
      return _sorted(
        ports
            .map(
              (port) => PortDetailInfo(
                portName: port.portName,
                friendlyName: port.friendlyName,
                hardwareID: port.hardwareID,
                manufactureName: port.manufactureName,
              ),
            )
            .toList(),
        warning: '原生枚举不可用，已使用备用枚举：$nativeError',
      );
    } catch (error) {
      // 两路均失败时不能把空快照当作真实拔出。
      throw StateError('串口枚举失败：$nativeError；$error');
    }
  }

  SerialPortScan _sorted(List<PortDetailInfo> ports, {String? warning}) {
    final unique = {for (final port in ports) port.portName: port};
    final result = unique.values.toList()
      ..sort((a, b) {
        final pattern = RegExp(r'^COM(\d+)$', caseSensitive: false);
        final left = pattern.firstMatch(a.portName);
        final right = pattern.firstMatch(b.portName);
        if (left != null && right != null) {
          return int.parse(left[1]!).compareTo(int.parse(right[1]!));
        }
        return a.portName.compareTo(b.portName);
      });
    return SerialPortScan(result, warning: warning);
  }
}

/// 串行扫描、合并请求，并独立累积拔出检查意图。
class SerialPortDirectory extends ChangeNotifier {
  SerialPortDirectory({
    required Future<SerialPortScan> Function() scan,
    required Stream<void> changes,
  }) : _scan = scan {
    _subscription = changes.listen((_) {
      _debounce?.cancel();
      _rescan?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 300),
        () => refresh(evictStaleSelection: true),
      );
      _rescan = Timer(
        const Duration(milliseconds: 1000),
        () => refresh(evictStaleSelection: true),
      );
    });
  }
  final Future<SerialPortScan> Function() _scan;
  late final StreamSubscription<void> _subscription;
  Timer? _debounce;
  Timer? _rescan;
  bool _disposed = false;
  bool _scanning = false;
  bool _pending = false;
  bool _pendingEviction = false;
  SerialPortScan snapshot = SerialPortScan([]);
  Set<String> removedPorts = {};
  String? warning;

  Future<void> refresh({bool evictStaleSelection = false}) async {
    if (_disposed) return;
    _pending = true;
    _pendingEviction |= evictStaleSelection;
    if (_scanning) return;
    _scanning = true;
    try {
      while (_pending && !_disposed) {
        _pending = false;
        final evict = _pendingEviction;
        _pendingEviction = false;
        try {
          final next = await _scan();
          if (_disposed) return;
          final currentNames = next.devices.map((p) => p.portName).toSet();
          removedPorts = evict
              ? snapshot.devices
                    .map((p) => p.portName)
                    .toSet()
                    .difference(currentNames)
              : {};
          // 扫描期间排队的热插拔检查也必须对比扫描前的快照。
          if (_pendingEviction) {
            removedPorts = snapshot.devices
                .map((p) => p.portName)
                .toSet()
                .difference(currentNames);
          }
          snapshot = next;
          warning = next.warning;
        } catch (error) {
          if (_disposed) return;
          warning = '$error';
          removedPorts = {};
        }
        notifyListeners();
      }
    } finally {
      _scanning = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _rescan?.cancel();
    _subscription.cancel();
    super.dispose();
  }
}
