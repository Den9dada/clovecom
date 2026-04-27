// 串口通信数据模型文件
// 
// 该文件定义了串口通信相关的所有数据模型，包括：
// - SerialPortConfig: 串口配置参数
// - SerialPortMessage: 串口消息数据
// - SerialPortState: 串口连接状态
// - DisplayConfig: 显示配置
// - FileSendConfig: 文件发送配置
// - CommunicationStats: 通信统计数据

/// 串口配置类
class SerialPortConfig {
  /// 串口端口号
  final String portName;
  
  /// 串口友好名称
  final String portFriendlyName;
  
  /// 波特率
  final int baudRate;
  
  /// 数据位
  final int dataBits;
  
  /// 停止位
  final int stopBits;
  
  /// 校验位
  final String parity;
  
  /// 流控制
  final String flowControl;

  SerialPortConfig({
    required this.portName,
    this.portFriendlyName = '',
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 'None',
    this.flowControl = 'None',
  });

  SerialPortConfig copyWith({
    String? portName,
    String? portFriendlyName,
    int? baudRate,
    int? dataBits,
    int? stopBits,
    String? parity,
    String? flowControl,
  }) {
    return SerialPortConfig(
      portName: portName ?? this.portName,
      portFriendlyName: portFriendlyName ?? this.portFriendlyName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      stopBits: stopBits ?? this.stopBits,
      parity: parity ?? this.parity,
      flowControl: flowControl ?? this.flowControl,
    );
  }

  @override
  String toString() {
    return '$portName, $baudRate, $dataBits, $stopBits, $parity, $flowControl';
  }
}

/// 串口消息类
class SerialPortMessage {
  /// 消息数据内容（文本格式）
  final String data;
  
  /// 消息数据内容（十六进制格式）
  final String hexData;
  
  /// 消息时间戳
  final DateTime timestamp;
  
  /// 是否为发送的消息
  final bool isSent;
  
  /// 数据长度（字节数）
  final int dataLength;

  SerialPortMessage({
    required this.data,
    this.hexData = '',
    required this.timestamp,
    this.isSent = false,
    this.dataLength = 0,
  });
}

/// 串口状态类
class SerialPortState {
  /// 是否已连接串口
  final bool isConnected;
  
  /// 错误信息
  final String? error;

  SerialPortState({
    this.isConnected = false,
    this.error,
  });

  SerialPortState copyWith({
    bool? isConnected,
    String? error,
  }) {
    return SerialPortState(
      isConnected: isConnected ?? this.isConnected,
      error: error ?? this.error,
    );
  }
}

/// 发送模式枚举
enum SendMode {
  text,
  hex,
  file,
}

/// 显示配置类
class DisplayConfig {
  /// 接收区是否使用HEX显示
  final bool receiveHex;
  
  /// 接收区是否启用日志模式
  final bool logMode;
  
  /// 接收区是否自动换行
  final bool autoWrap;
  
  /// 是否隐藏接收数据
  final bool hideReceive;
  
  /// 是否将接收数据保存为文件
  final bool saveToFile;
  
  /// 是否自动滚动
  final bool autoScroll;
  
  /// 发送区是否使用HEX
  final bool sendHex;
  
  /// 是否循环发送
  final bool loopSend;
  
  /// 循环发送间隔（毫秒）
  final int loopInterval;

  /// 发送时追加回车符（CR, 0x0D）
  final bool appendCR;

  /// 发送时追加换行符（LF, 0x0A）
  final bool appendLF;

  DisplayConfig({
    this.receiveHex = false,
    this.logMode = false,
    this.autoWrap = true,
    this.hideReceive = false,
    this.saveToFile = false,
    this.autoScroll = true,
    this.sendHex = false,
    this.loopSend = false,
    this.loopInterval = 1000,
    this.appendCR = false,
    this.appendLF = false,
  });

  DisplayConfig copyWith({
    bool? receiveHex,
    bool? logMode,
    bool? autoWrap,
    bool? hideReceive,
    bool? saveToFile,
    bool? autoScroll,
    bool? sendHex,
    bool? loopSend,
    int? loopInterval,
    bool? appendCR,
    bool? appendLF,
  }) {
    return DisplayConfig(
      receiveHex: receiveHex ?? this.receiveHex,
      logMode: logMode ?? this.logMode,
      autoWrap: autoWrap ?? this.autoWrap,
      hideReceive: hideReceive ?? this.hideReceive,
      saveToFile: saveToFile ?? this.saveToFile,
      autoScroll: autoScroll ?? this.autoScroll,
      sendHex: sendHex ?? this.sendHex,
      loopSend: loopSend ?? this.loopSend,
      loopInterval: loopInterval ?? this.loopInterval,
      appendCR: appendCR ?? this.appendCR,
      appendLF: appendLF ?? this.appendLF,
    );
  }
}

/// 文件发送配置类
class FileSendConfig {
  final String filePath;
  final String fileName;
  final int fileSize;
  final int packetSize;
  final int sendInterval;
  final int sentBytes;
  final bool isSending;
  final String protocolName;

  FileSendConfig({
    this.filePath = '',
    this.fileName = '',
    this.fileSize = 0,
    this.packetSize = 1024,
    this.sendInterval = 100,
    this.sentBytes = 0,
    this.isSending = false,
    this.protocolName = '分包发送',
  });

  FileSendConfig copyWith({
    String? filePath,
    String? fileName,
    int? fileSize,
    int? packetSize,
    int? sendInterval,
    int? sentBytes,
    bool? isSending,
    String? protocolName,
  }) {
    return FileSendConfig(
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      packetSize: packetSize ?? this.packetSize,
      sendInterval: sendInterval ?? this.sendInterval,
      sentBytes: sentBytes ?? this.sentBytes,
      isSending: isSending ?? this.isSending,
      protocolName: protocolName ?? this.protocolName,
    );
  }

  double get progress {
    if (fileSize <= 0) return 0.0;
    return sentBytes / fileSize;
  }
}

/// 通信统计数据类
class CommunicationStats {
  final int receivedBytes;
  final int sentBytes;
  final int receivedMessages;
  final int sentMessages;

  CommunicationStats({
    this.receivedBytes = 0,
    this.sentBytes = 0,
    this.receivedMessages = 0,
    this.sentMessages = 0,
  });

  CommunicationStats copyWith({
    int? receivedBytes,
    int? sentBytes,
    int? receivedMessages,
    int? sentMessages,
  }) {
    return CommunicationStats(
      receivedBytes: receivedBytes ?? this.receivedBytes,
      sentBytes: sentBytes ?? this.sentBytes,
      receivedMessages: receivedMessages ?? this.receivedMessages,
      sentMessages: sentMessages ?? this.sentMessages,
    );
  }

  CommunicationStats reset() {
    return CommunicationStats();
  }
}

/// 串口详细信息类
class PortDetailInfo {
  final String portName;
  final String friendlyName;
  final String hardwareID;
  final String manufactureName;

  PortDetailInfo({
    required this.portName,
    required this.friendlyName,
    required this.hardwareID,
    required this.manufactureName,
  });

  String get displayText => '$portName - $friendlyName';
  String get shortDisplayText => portName;
}

/// 固件升级配置类
class FirmwareUpgradeConfig {
  /// 固件文件路径
  final String firmwarePath;

  /// 固件文件名
  final String firmwareName;

  /// 固件文件大小
  final int firmwareSize;

  /// 升级脚本路径
  final String scriptPath;

  /// 升级脚本名称
  final String scriptName;

  /// 升级进度 (0.0 ~ 1.0)
  final double progress;

  /// 是否正在升级
  final bool isUpgrading;

  /// 升级日志
  final List<String> logs;

  FirmwareUpgradeConfig({
    this.firmwarePath = '',
    this.firmwareName = '',
    this.firmwareSize = 0,
    this.scriptPath = '',
    this.scriptName = '',
    this.progress = 0.0,
    this.isUpgrading = false,
    this.logs = const [],
  });

  FirmwareUpgradeConfig copyWith({
    String? firmwarePath,
    String? firmwareName,
    int? firmwareSize,
    String? scriptPath,
    String? scriptName,
    double? progress,
    bool? isUpgrading,
    List<String>? logs,
  }) {
    return FirmwareUpgradeConfig(
      firmwarePath: firmwarePath ?? this.firmwarePath,
      firmwareName: firmwareName ?? this.firmwareName,
      firmwareSize: firmwareSize ?? this.firmwareSize,
      scriptPath: scriptPath ?? this.scriptPath,
      scriptName: scriptName ?? this.scriptName,
      progress: progress ?? this.progress,
      isUpgrading: isUpgrading ?? this.isUpgrading,
      logs: logs ?? this.logs,
    );
  }
}
