// I2C 寄存器映射模型
//
// 定义芯片寄存器映射的完整数据结构，包括寄存器定义、位域定义和芯片配置。

/// 位域定义
class I2cRegisterBitField {
  /// 高位索引
  final int msb;

  /// 低位索引
  final int lsb;

  /// 位域名称（如 VIN_REG）
  final String fieldName;

  /// 访问权限 "R" / "RW"
  final String access;

  /// 默认值
  final int defaultValue;

  /// 功能描述
  final String description;

  /// 增益（从描述 <gain> 解析，用于物理值换算）
  final double? gain;

  /// 偏移（从描述 <offset> 解析，用于物理值换算）
  final int? offsetValue;

  /// 枚举值描述（如 {"00": "2.8V", "01": "3V"}）
  final Map<int, String>? enumValues;

  const I2cRegisterBitField({
    required this.msb,
    required this.lsb,
    required this.fieldName,
    required this.access,
    this.defaultValue = 0,
    this.description = '',
    this.gain,
    this.offsetValue,
    this.enumValues,
  });

  bool get isReadOnly => access == 'R';
  bool get isReadWrite => access == 'RW';

  /// 位宽
  int get width => msb - lsb + 1;

  /// 位掩码
  int get mask => ((1 << width) - 1) << lsb;

  /// 从寄存器值中提取位域值
  int extract(int registerValue) =>
      (registerValue >> lsb) & ((1 << width) - 1);

  /// 将位域值编码到寄存器位中
  int encode(int fieldValue) => (fieldValue << lsb) & mask;

  /// 物理值换算（如 gain=2, offset=1 → physical = fieldValue * 2 + 1）
  double? toPhysical(int fieldValue) {
    if (gain == null && offsetValue == null) return null;
    final g = gain ?? 1.0;
    final o = offsetValue ?? 0;
    return fieldValue * g + o;
  }

  /// 从物理值反算位域值
  int? fromPhysical(double physicalValue) {
    if (gain == null && offsetValue == null) return null;
    final g = gain ?? 1.0;
    final o = offsetValue ?? 0;
    return ((physicalValue - o) / g).round();
  }
}

/// 寄存器定义
class I2cRegister {
  /// 寄存器名称（如 CHG INPUT）
  final String name;

  /// 偏移地址（如 0x10）
  final int offset;

  /// 位域列表
  final List<I2cRegisterBitField> bitFields;

  /// 从芯片读取的当前值（null 表示未读取）
  int? currentValue;

  /// 用户编辑中的值（null 表示未修改）
  int? _editingValue;

  /// 寄存器位宽（8 或 16）
  final int bitWidth;

  I2cRegister({
    required this.name,
    required this.offset,
    this.bitWidth = 8,
    this.bitFields = const [],
    this.currentValue,
  });

  /// 是否已读取
  bool get hasBeenRead => currentValue != null;

  /// 是否有未写入的修改
  bool get isModified => _editingValue != null && _editingValue != currentValue;

  /// 获取编辑值（优先返回 editingValue，否则返回 currentValue）
  int? get editingValue => _editingValue ?? currentValue;

  /// 设置编辑值
  void setEditingValue(int? value) => _editingValue = value;

  /// 放弃编辑
  void discardEditing() => _editingValue = null;

  /// 十六进制偏移字符串
  String get offsetHex => '0x${offset.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}

/// 芯片配置（从 Excel 元数据解析）
class I2cChipConfig {
  /// 模块名称（默认 "Module Registers"）
  final String moduleName;

  /// 版本（如 "V0.0.1"）
  final String version;

  /// 接口类型（如 "SCLink-I2C"）
  final String interfaceType;

  /// I2C 速率 (kHz)
  final int speed;

  /// 7-bit 设备地址
  final int deviceAddress;

  /// 基地址
  final int baseAddress;

  /// 字节序是否为小端
  final bool littleEndian;

  /// 是否多模块
  final bool multiModule;

  /// 寄存器设置偏移
  final int? registerSetOffset;

  /// 寄存器清零偏移
  final int? registerClearOffset;

  const I2cChipConfig({
    this.moduleName = 'Module Registers',
    this.version = '',
    this.interfaceType = 'I2C',
    this.speed = 400,
    this.deviceAddress = 0x00,
    this.baseAddress = 0x00,
    this.littleEndian = true,
    this.multiModule = false,
    this.registerSetOffset,
    this.registerClearOffset,
  });

  /// 设备地址十六进制字符串
  String get deviceAddressHex =>
      '0x${deviceAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}

/// 完整寄存器映射
class I2cRegisterMap {
  /// Excel 文件路径
  final String filePath;

  /// 芯片配置
  final I2cChipConfig chipConfig;

  /// 寄存器列表
  final List<I2cRegister> registers;

  /// 解析警告/错误
  final List<String> parseErrors;

  /// 文件来源 Sheet 名称列表
  final List<String> sheetNames;

  const I2cRegisterMap({
    required this.filePath,
    required this.chipConfig,
    this.registers = const [],
    this.parseErrors = const [],
    this.sheetNames = const [],
  });

  int get registerCount => registers.length;
}
