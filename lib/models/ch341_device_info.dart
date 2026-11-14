// CH341 设备信息模型

/// CH341 USB 设备信息
class Ch341DeviceInfo {
  /// 设备索引（用于 CH341OpenDevice）
  final int deviceIndex;

  /// 设备描述（如 "CH341A USB-I2C/SPI Bridge"）
  final String description;

  /// 厂商 ID
  final int vid;

  /// 产品 ID（0x5512 = I2C/SPI/GPIO, 0x5523 = UART）
  final int pid;

  /// 设备路径（SetupAPI 设备实例路径）
  final String? devicePath;

  /// 是否为 I2C/SPI/GPIO 模式（PID=0x5512）
  bool get isI2cSpiMode => pid == 0x5512;

  const Ch341DeviceInfo({
    required this.deviceIndex,
    required this.description,
    required this.vid,
    required this.pid,
    this.devicePath,
  });
}
