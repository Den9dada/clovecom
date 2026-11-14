// CH341 抽象 Service 接口
//
// 定义 CH341 I2C 操作的统一接口，便于后续跨平台扩展。

import '../../models/ch341_device_info.dart';
import '../../models/ch341_operation_result.dart';

/// CH341 抽象服务接口
abstract class Ch341ServiceBase {
  /// 驱动是否已加载
  bool get isLoaded;

  /// 加载驱动/打开 DLL
  bool loadDriver();

  /// 卸载驱动
  void unloadDriver();

  /// 枚举可用 CH341 设备
  List<Ch341DeviceInfo> enumerateDevices();

  /// 打开设备（建立 I2C 通信就绪状态）
  /// [deviceIndex] 设备索引（0 起）
  /// [speed] I2C 速率 0=20K, 1=100K, 2=400K, 3=750K
  bool openDevice(int deviceIndex, {int speed = 2});

  /// 关闭设备
  void closeDevice(int deviceIndex);

  /// 检查设备是否已打开
  bool isDeviceOpen(int deviceIndex);

  /// ─── I2C 操作 ──────────────────────────────────────

  /// 写入单字节寄存器
  /// [deviceAddr] 7-bit I2C 设备地址
  /// [regAddr] 寄存器地址
  /// [data] 要写入的数据
  Ch341OperationResult i2cWriteRegister(
      int deviceIndex, int deviceAddr, int regAddr, List<int> data);

  /// 读取寄存器
  /// [deviceAddr] 7-bit I2C 设备地址
  /// [regAddr] 寄存器地址
  /// [length] 读取字节数
  Ch341OperationResult i2cReadRegister(
      int deviceIndex, int deviceAddr, int regAddr, int length);

  /// 探测 I2C 地址是否存在（仅发地址字节，检测 ACK）
  /// [deviceAddr] 7-bit I2C 设备地址
  /// @return true 表示设备应答（ACK）
  bool probeI2cAddress(int deviceIndex, int deviceAddr);

  /// 获取设备状态
  /// @return null 表示通信失败
  int? getDeviceStatus(int deviceIndex);

  /// 释放资源
  void dispose();
}
