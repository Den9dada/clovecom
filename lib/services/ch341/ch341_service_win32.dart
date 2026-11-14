// CH341 Win32 Service 实现
//
// 基于 CH341DLLA64.dll 实现 I2C 通信服务。
// 设备枚举采用探针法（尝试打开 0-N 设备），单寄存器操作使用
// CH341ReadI2C/WriteI2C（高层 API），多字节操作使用 CH341StreamI2C。

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../../models/ch341_device_info.dart';
import '../../models/ch341_operation_result.dart';
import 'ch341_dll.dart';
import 'ch341_service_base.dart';

/// Win32 CH341 服务实现
class Ch341ServiceWin32 extends Ch341ServiceBase {
  final Ch341Dll _dll = Ch341Dll();

  /// 已打开的设备索引集合
  final Set<int> _openDevices = {};

  /// 设备名称缓存（索引 → 名称）
  final Map<int, String> _deviceNames = {};

  @override
  bool get isLoaded => _dll.isLoaded;

  @override
  bool loadDriver() => _dll.load();

  @override
  void unloadDriver() => _dll.unload();

  @override
  List<Ch341DeviceInfo> enumerateDevices() {
    final devices = <Ch341DeviceInfo>[];
    // 探针法：依次尝试打开设备 0-15（最多 16 个 CH341 设备）
    for (int i = 0; i < 16; i++) {
      // 已打开的设备不重复 open/close，避免断开活跃连接
      if (_openDevices.contains(i)) {
        final verIC = _dll.getVerIC(i);
        if (verIC != 0) {
          devices.add(Ch341DeviceInfo(
            deviceIndex: i,
            description: _chipTypeString(verIC),
            vid: 0x1A86, pid: 0x5512,
          ));
        }
        continue;
      }

      final handle = _dll.openDevice(i);
      if (handle == 0) continue;

      final verIC = _dll.getVerIC(i);
      if (verIC == 0) {
        _dll.closeDevice(i);
        continue;
      }

      devices.add(Ch341DeviceInfo(
        deviceIndex: i,
        description: _chipTypeString(verIC),
        vid: 0x1A86, pid: 0x5512,
      ));
      _dll.closeDevice(i);
    }
    return devices;
  }

  @override
  bool openDevice(int deviceIndex, {int speed = 2}) {
    if (_openDevices.contains(deviceIndex)) return true;

    final handle = _dll.openDevice(deviceIndex);
    if (handle == 0) return false;

    // 配置 I2C 速率: mode 位1-0 = speed
    // speed: 0=20KHz, 1=100KHz, 2=400KHz, 3=750KHz
    if (!_dll.setStream(deviceIndex, speed)) {
      _dll.closeDevice(deviceIndex);
      return false;
    }

    _openDevices.add(deviceIndex);
    // 缓存设备名称
    final name = _dll.getDeviceName(deviceIndex);
    if (name != null && name.isNotEmpty) {
      _deviceNames[deviceIndex] = name;
    }
    return true;
  }

  @override
  void closeDevice(int deviceIndex) {
    if (_openDevices.contains(deviceIndex)) {
      _dll.closeDevice(deviceIndex);
      _openDevices.remove(deviceIndex);
    }
  }

  @override
  bool isDeviceOpen(int deviceIndex) => _openDevices.contains(deviceIndex);

  @override
  Ch341OperationResult i2cWriteRegister(
      int deviceIndex, int deviceAddr, int regAddr, List<int> data) {
    final sw = Stopwatch()..start();
    final dataHex =
        data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final desc = 'WR 0x${regAddr.toRadixString(16)} ← $dataHex';

    try {
      if (data.length == 1) {
        // 单字节写入，使用高层 API
        final ok = _dll.writeI2C(deviceIndex, deviceAddr, regAddr, data[0]);
        sw.stop();
        if (ok) {
          return Ch341OperationResult.ok(
            data: data,
            duration: sw.elapsed,
            description: desc,
          );
        }
      } else {
        // 多字节写入，使用流 API
        final wBuf = _dll.buildWriteBuffer(deviceAddr, [regAddr, ...data]);
        final result = _dll.streamI2C(deviceIndex, wBuf, 0);
        sw.stop();
        if (result != null) {
          return Ch341OperationResult.ok(
            data: data,
            duration: sw.elapsed,
            description: desc,
          );
        }
      }
      sw.stop();
      return Ch341OperationResult.fail(
        errorMessage: 'I2C 写入失败',
        duration: sw.elapsed,
        description: desc,
      );
    } catch (e) {
      sw.stop();
      return Ch341OperationResult.fail(
        errorMessage: e.toString(),
        duration: sw.elapsed,
        description: desc,
      );
    }
  }

  @override
  Ch341OperationResult i2cReadRegister(
      int deviceIndex, int deviceAddr, int regAddr, int length) {
    final sw = Stopwatch()..start();
    final desc = 'RD 0x${regAddr.toRadixString(16)}';

    try {
      if (length == 1) {
        // 单字节读取，使用高层 API
        final byte = _dll.readI2C(deviceIndex, deviceAddr, regAddr);
        sw.stop();
        if (byte != null) {
          return Ch341OperationResult.ok(
            data: [byte],
            duration: sw.elapsed,
            description: desc,
          );
        }
      } else {
        // 多字节读取，使用流 API
        final wBuf = _dll.buildWriteBuffer(deviceAddr, [regAddr]);
        final result = _dll.streamI2C(deviceIndex, wBuf, length);
        sw.stop();
        if (result != null) {
          return Ch341OperationResult.ok(
            data: result.toList(),
            duration: sw.elapsed,
            description: desc,
          );
        }
      }
      sw.stop();
      return Ch341OperationResult.fail(
        errorMessage: 'I2C 读取失败（设备无应答）',
        duration: sw.elapsed,
        description: desc,
      );
    } catch (e) {
      sw.stop();
      return Ch341OperationResult.fail(
        errorMessage: e.toString(),
        duration: sw.elapsed,
        description: desc,
      );
    }
  }

  @override
  bool probeI2cAddress(int deviceIndex, int deviceAddr) {
    // 发送地址字节 (写位=0)
    final wBuf = [(deviceAddr << 1) & 0xFF];
    _dll.streamI2C(deviceIndex, wBuf, 0);

    // 通过状态寄存器检测 NACK：bit 0 置位表示设备未应答
    final pStatus = calloc<Uint32>(1);
    try {
      final ok = _dll.getStatus(deviceIndex, pStatus);
      if (ok != 0) {
        // bit 0 = I2C_NACK, bit 1 = I2C_BUSY
        // 正常应答时 bit 0 为 0 且 bit 1 为 0
        return (pStatus[0] & 0x01) == 0;
      }
    } finally {
      calloc.free(pStatus);
    }
    return false;
  }

  @override
  int? getDeviceStatus(int deviceIndex) {
    final pStatus = calloc<Uint32>(1);
    try {
      final ok = _dll.getStatus(deviceIndex, pStatus);
      if (!ok) return null;
      return pStatus[0];
    } finally {
      calloc.free(pStatus);
    }
  }

  @override
  void dispose() {
    for (final idx in _openDevices.toList()) {
      closeDevice(idx);
    }
    _openDevices.clear();
    _deviceNames.clear();
  }

  // ─── 辅助 ────────────────────────────────────────────────

  String _chipTypeString(int verIC) {
    switch (verIC) {
      case 0x10:
        return 'CH341';
      case 0x20:
        return 'CH341A';
      case 0x30:
        return 'CH341A3';
      default:
        return verIC != 0 ? 'CH341(0x${verIC.toRadixString(16)})' : '未知';
    }
  }
}
