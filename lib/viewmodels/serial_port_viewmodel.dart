// 串口通信视图模型文件
//
// 该文件实现了串口通信的业务逻辑，采用MVVM架构中的ViewModel层。
// 负责处理串口的打开、关闭、数据发送和接收等操作，并管理相关状态。

import 'dart:async';
import '../services/serial/serial_transfer_session.dart';
import '../services/serial/serial_byte_transport.dart';
import '../services/serial/serial_port_catalog.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:path_provider/path_provider.dart';
import '../models/serial_port_model.dart';

import '../protocols/protocol_registry.dart';
import '../protocol_editor.dart';
import '../services/firmware_protocol_binding.dart';
import '../src/application/lua_runtime.dart';
import '../src/application/firmware_upgrade.dart';
import '../src/io/connections.dart';
import '../src/io/recording.dart';

/// 串口通信视图模型类
class SerialPortViewModel extends ChangeNotifier {
  static const int _maxMessages = 5000;
  static const int _messagePruneCount = 1000;
  static const Duration _batchNotifyInterval = Duration(milliseconds: 50);

  /// 串口配置对象
  SerialPortConfig _config = SerialPortConfig(portName: '');

  /// 串口状态对象
  SerialPortState _state = SerialPortState();

  /// 消息列表
  final List<SerialPortMessage> _messages = [];

  /// 串口对象实例
  SerialByteTransport? _serialPort;

  /// 读取流订阅
  StreamSubscription<Uint8List>? _readStreamSub;

  /// 可用串口列表
  List<PortDetailInfo> _availablePorts = [];

  /// 通信统计数据
  CommunicationStats _stats = CommunicationStats();

  /// 发送模式
  SendMode _sendMode = SendMode.text;

  /// 显示配置
  DisplayConfig _displayConfig = DisplayConfig();

  /// 文件发送配置
  FileSendConfig _fileSendConfig = FileSendConfig();

  /// 文件发送定时器
  Timer? _fileSendTimer;

  /// 循环发送定时器
  Timer? _loopSendTimer;

  /// 文件数据缓存

  /// 循环发送的数据
  String _loopSendData = '';

  /// 循环发送是否使用HEX
  bool _loopSendIsHex = false;

  /// 日志文件
  File? _logFile;

  /// 错误信息
  String? _errorMessage;

  /// 错误通知流（用于 SnackBar 弹窗）
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  /// 固件升级配置
  FirmwareUpgradeConfig _firmwareConfig = FirmwareUpgradeConfig();

  /// 文件接收配置
  FileReceiveConfig _fileReceiveConfig = FileReceiveConfig();

  final _transfers = SerialTransferController();

  /// 已完整载入的固件快照与脚本运行状态
  Uint8List? _firmwareBytes;

  FirmwareProtocolBinding? firmwareProtocols;
  LuaRun? _luaRun;
  bool _firmwareStopping = false;

  Future<void> loadFirmwareProtocol(String id) async {
    final binding = firmwareProtocols;
    if (binding == null) return;
    try {
      final loaded = await binding.load(
        id,
        locked: () => isTransferBusy || _disposed,
        currentConfig: () => _config,
        connected: () => _state.isConnected,
        applyConfig: (value) {
          _config = value;
        },
      );
      if (_disposed || !loaded) return;
      _addFirmwareLog('已载入协议：${binding.loaded?.name}');
    } catch (error) {
      if (!_disposed) _setError('载入协议失败：$error');
    }
    notifyListeners();
  }

  final SerialByteTransport Function(SerialPortConfig) _openTransport;
  late final SerialPortDirectory portDirectory;
  bool _disposed = false;
  String? _connectedPortName;

  /// 批量通知：积累的接收数据量
  Timer? _batchNotifyTimer;
  bool _batchNotifyScheduled = false;

  // Getters
  SerialPortConfig get config => _config;
  SerialPortState get state => _state;
  List<SerialPortMessage> get messages => List.unmodifiable(_messages);
  List<PortDetailInfo> get availablePorts => List.unmodifiable(_availablePorts);
  CommunicationStats get stats => _stats;
  SendMode get sendMode => _sendMode;
  DisplayConfig get displayConfig => _displayConfig;
  FileSendConfig get fileSendConfig => _fileSendConfig;
  FirmwareUpgradeConfig get firmwareConfig => _firmwareConfig;
  FileReceiveConfig get fileReceiveConfig => _fileReceiveConfig;
  String? get errorMessage => _errorMessage;
  bool get isTransferBusy => _transfers.isBusy || _luaRun != null;

  /// 错误通知流
  Stream<String> get errorStream => _errorController.stream;

  /// 设置错误信息并通知
  void _setError(String message) {
    _errorMessage = message;
    if (!_disposed) _errorController.add(message);
    notifyListeners();
  }

  /// 构造函数
  SerialPortViewModel({
    ProtocolLibrary? protocolLibrary,
    SerialPortDirectory? directory,
    SerialByteTransport Function(SerialPortConfig)? openTransport,
  }) : _openTransport = openTransport ?? Win32SerialTransport.new {
    if (protocolLibrary != null) {
      firmwareProtocols = FirmwareProtocolBinding(protocolLibrary)
        ..addListener(notifyListeners);
    }
    final catalog = SerialPortCatalog();
    portDirectory =
        directory ??
        SerialPortDirectory(
          scan: catalog.scan,
          changes: catalog.watchChanges(),
        );
    portDirectory.addListener(_portsUpdated);
    unawaited(refreshPorts());
  }

  Future<void> refreshPorts() =>
      portDirectory.refresh(evictStaleSelection: true);

  void _portsUpdated() {
    if (_disposed) return;
    _availablePorts = portDirectory.snapshot.devices;
    if (portDirectory.removedPorts.contains(_connectedPortName)) {
      unawaited(disconnect());
      _setError('串口设备已移除');
    }
    if (portDirectory.removedPorts.contains(_config.portName)) {
      _config = _config.copyWith(portName: '', portFriendlyName: '');
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// 更新串口配置
  void updateConfig({
    String? portName,
    String? portFriendlyName,
    int? baudRate,
    int? dataBits,
    int? stopBits,
    String? parity,
    String? flowControl,
  }) {
    if (_state.isConnected ||
        isTransferBusy ||
        firmwareProtocols?.loading == true) {
      return;
    }
    _config = _config.copyWith(
      portName: portName,
      portFriendlyName: portFriendlyName,
      baudRate: baudRate,
      dataBits: dataBits,
      stopBits: stopBits,
      parity: parity,
      flowControl: flowControl,
    );
    notifyListeners();
  }

  /// 更新显示配置
  void updateDisplayConfig({
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
    _displayConfig = _displayConfig.copyWith(
      receiveHex: receiveHex,
      logMode: logMode,
      autoWrap: autoWrap,
      hideReceive: hideReceive,
      saveToFile: saveToFile,
      autoScroll: autoScroll,
      sendHex: sendHex,
      loopSend: loopSend,
      loopInterval: loopInterval,
      appendCR: appendCR,
      appendLF: appendLF,
    );

    // 处理循环发送
    if (loopSend == true) {
      _startLoopSend();
    } else if (loopSend == false) {
      _stopLoopSend();
    }

    // 处理保存为文件
    if (saveToFile == true) {
      _initLogFile();
    }

    notifyListeners();
  }

  /// 更新发送模式
  void updateSendMode(SendMode mode) {
    _sendMode = mode;
    notifyListeners();
  }

  /// 将文本转换为HEX字符串
  /// 例如: "Hello" -> "48 65 6C 6C 6F"
  String convertTextToHex(String text) {
    if (text.isEmpty) return '';
    final bytes = utf8.encode(text);
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  /// 将HEX字符串还原为文本
  /// 例如: "48 65 6C 6C 6F" -> "Hello"
  /// 如果解析失败，返回null
  String? convertHexToText(String hex) {
    if (hex.trim().isEmpty) return '';
    try {
      final cleanHex = hex.trim().replaceAll(RegExp(r'[^0-9a-fA-F\s]'), '');
      final parts = cleanHex
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      final bytes = <int>[];
      for (final part in parts) {
        final padded = part.length == 1 ? '${part}0' : part;
        if (padded.length > 2) return null; // 非标准hex格式，放弃转换
        bytes.add(int.parse(padded, radix: 16));
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return null; // 解析失败，放弃转换
    }
  }

  /// 连接串口
  Future<bool> connect() async {
    if (_disposed) return false;
    if (_state.isConnected) return true;
    if (_config.portName.isEmpty) {
      _state = SerialPortState(error: '请选择串口');
      notifyListeners();
      return false;
    }
    SerialByteTransport? transport;
    try {
      transport = _openTransport(_config);
      _serialPort = transport;
      _connectedPortName = _config.portName;
      _state = SerialPortState(isConnected: true);
      _readStreamSub = transport.chunks.listen(
        (data) {
          if (identical(_serialPort, transport)) _processReceivedData(data);
        },
        onError: (Object error) => _transportEnded(transport!, '$error'),
        onDone: () => _transportEnded(transport!, '串口读取已结束'),
      );
      notifyListeners();
      return true;
    } catch (error) {
      transport?.close();
      _serialPort = null;
      _connectedPortName = null;
      _state = SerialPortState(error: '连接失败: $error');
      notifyListeners();
      return false;
    }
  }

  void _transportEnded(SerialByteTransport transport, String error) {
    if (_disposed || !identical(_serialPort, transport)) return;
    unawaited(disconnect());
    _state = SerialPortState(error: error);
    _setError(error);
  }

  /// 根据追加回车/换行配置，返回需要追加的字节
  List<int> _getAppendBytes() {
    final bytes = <int>[];
    if (_displayConfig.appendCR) bytes.add(0x0D);
    if (_displayConfig.appendLF) bytes.add(0x0A);
    return bytes;
  }

  /// 处理接收到的数据并更新 UI
  void _processReceivedData(Uint8List data) {
    if (!_state.isConnected) return;

    if (_transfers.accept(data)) return;

    if (_displayConfig.hideReceive) return;

    String received = utf8.decode(data, allowMalformed: true);
    String hexStr = data
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    final message = SerialPortMessage(
      data: received,
      hexData: hexStr,
      timestamp: DateTime.now(),
      isSent: false,
      dataLength: data.length,
    );

    _messages.add(message);
    _pruneMessagesIfNeeded();

    if (_displayConfig.logMode) {
      _writeToLogFile(message);
    }

    _stats = _stats.copyWith(
      receivedBytes: _stats.receivedBytes + data.length,
      receivedMessages: _stats.receivedMessages + 1,
    );

    _scheduleBatchNotify();
  }

  void _pruneMessagesIfNeeded() {
    if (_messages.length > _maxMessages) {
      _messages.removeRange(
        0,
        _messages.length - _maxMessages + _messagePruneCount,
      );
    }
  }

  void _scheduleBatchNotify() {
    if (_batchNotifyScheduled) return;
    _batchNotifyScheduled = true;
    _batchNotifyTimer?.cancel();
    _batchNotifyTimer = Timer(_batchNotifyInterval, () {
      _batchNotifyScheduled = false;
      if (_state.isConnected) {
        notifyListeners();
      }
    });
  }

  void _flushBatchNotify() {
    _batchNotifyTimer?.cancel();
    _batchNotifyTimer = null;
    _batchNotifyScheduled = false;
  }

  /// 断开串口连接
  Future<void> disconnect() async {
    stopFirmwareUpgrade();
    _stopFileSend();
    _stopFileReceive();
    _stopLoopSend();
    _flushBatchNotify();

    final subscription = _readStreamSub;
    _readStreamSub = null;
    if (subscription != null) unawaited(subscription.cancel());

    try {
      _serialPort?.close();
    } catch (_) {
      // 忽略关闭时的异常（句柄可能已失效）
    }
    _serialPort = null;
    _connectedPortName = null;

    _state = _state.copyWith(isConnected: false);
    notifyListeners();
  }

  /// 发送数据
  Future<bool> sendData(String data, {bool? isHex}) async {
    if (_transfers.isBusy) {
      _setError('串口正在执行传输任务');
      return false;
    }
    if (!_state.isConnected || _serialPort == null) {
      _setError('未连接串口');
      return false;
    }

    try {
      final useHex = isHex ?? _displayConfig.sendHex;
      String displayData;
      String hexStr;

      if (useHex) {
        // HEX模式：解析HEX数据
        // 去除首尾空格
        data = data.trim();

        // 按空格分割，处理每一组
        final parts = data.split(RegExp(r'\s+'));
        final StringBuffer cleanHexBuffer = StringBuffer();

        for (int i = 0; i < parts.length; i++) {
          String part = parts[i];
          if (part.isEmpty) continue;

          // 移除每组中的非十六进制字符
          part = part.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
          if (part.isEmpty) continue;

          // 如果只有1个字符，在前面补0
          if (part.length == 1) {
            part = '0$part';
          }

          // 如果超过2个字符，只取前2个
          if (part.length > 2) {
            part = part.substring(0, 2);
          }

          cleanHexBuffer.write(part);
        }

        final cleanHex = cleanHexBuffer.toString();

        // 检查是否有有效的十六进制字符
        if (cleanHex.isEmpty) {
          _setError('HEX格式错误：没有有效的十六进制字符');
          return false;
        }

        // 转换为字节数组
        final bytes = Uint8List(cleanHex.length ~/ 2);
        for (int i = 0; i < cleanHex.length; i += 2) {
          bytes[i ~/ 2] = int.parse(cleanHex.substring(i, i + 2), radix: 16);
        }

        // 追加回车/换行
        final appendBytes = _getAppendBytes();
        if (appendBytes.isNotEmpty) {
          final allBytes = Uint8List.fromList([...bytes, ...appendBytes]);
          displayData = utf8.decode(allBytes, allowMalformed: true);
          hexStr = allBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');
        } else {
          displayData = utf8.decode(bytes, allowMalformed: true);
          hexStr = cleanHex.toUpperCase();
        }
      } else {
        // 文本模式：直接发送字符串
        final appendBytes = _getAppendBytes();
        if (appendBytes.isNotEmpty) {
          final allBytes = Uint8List.fromList([
            ...utf8.encode(data),
            ...appendBytes,
          ]);
          displayData = utf8.decode(allBytes, allowMalformed: true);
          hexStr = allBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');
        } else {
          displayData = data;
          final bytes = Uint8List.fromList(utf8.encode(data));
          hexStr = bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');
        }
      }

      final compactHex = hexStr.replaceAll(' ', '');
      final wireBytes = Uint8List.fromList(
        List.generate(
          compactHex.length ~/ 2,
          (i) => int.parse(compactHex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
      final result = _reliableWrite(wireBytes, 5000);

      if (!result) {
        _setError('发送失败: 写入串口失败');
        return false;
      }

      final message = SerialPortMessage(
        data: displayData,
        hexData: hexStr,
        timestamp: DateTime.now(),
        isSent: true,
        dataLength: wireBytes.length,
      );

      _messages.add(message);

      // 如果启用了日志模式，保存到文件
      if (_displayConfig.logMode) {
        _writeToLogFile(message);
      }

      _stats = _stats.copyWith(
        sentBytes: _stats.sentBytes + wireBytes.length,
        sentMessages: _stats.sentMessages + 1,
      );

      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _setError('发送失败: $e');
      return false;
    }
  }

  /// 发送数据并启动循环发送（如果开启）
  Future<bool> sendDataWithLoopCheck(String data, {bool? isHex}) async {
    // 保存数据用于循环发送
    final useHex = isHex ?? _displayConfig.sendHex;
    setLoopSendData(data, isHex: useHex);

    // 发送数据
    final result = await sendData(data, isHex: isHex);

    // 如果循环发送开启，启动循环发送
    if (result && _displayConfig.loopSend) {
      _startLoopSend();
    }

    return result;
  }

  /// 开始循环发送
  void _startLoopSend() {
    _stopLoopSend();
    if (_loopSendData.isEmpty || _transfers.isBusy) return;

    _loopSendTimer = Timer.periodic(
      Duration(milliseconds: _displayConfig.loopInterval),
      (timer) {
        if (_loopSendData.isNotEmpty) {
          sendData(_loopSendData, isHex: _loopSendIsHex);
        }
      },
    );
  }

  /// 停止循环发送
  void _stopLoopSend() {
    _loopSendTimer?.cancel();
    _loopSendTimer = null;
  }

  /// 设置循环发送数据
  void setLoopSendData(String data, {bool isHex = false}) {
    _loopSendData = data;
    _loopSendIsHex = isHex;
  }

  /// 选择文件
  Future<void> selectFile() async {
    try {
      PickedFiles? result = await FilePickerCompat.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _fileSendConfig = _fileSendConfig.copyWith(
          filePath: file.path,
          fileName: file.name,
          fileSize: await file.length() ?? 0,
          sentBytes: 0,
          isSending: false,
        );
        notifyListeners();
      }
    } catch (e) {
      _setError('选择文件失败: $e');
    }
  }

  /// 更新文件发送配置
  void updateFileSendConfig({
    int? packetSize,
    int? sendInterval,
    String? protocolName,
  }) {
    _fileSendConfig = _fileSendConfig.copyWith(
      packetSize: packetSize,
      sendInterval: sendInterval,
      protocolName: protocolName,
    );
    notifyListeners();
  }

  /// 开始发送文件
  SerialTransferSession? _beginTransfer(SerialTransferKind kind) {
    if (isTransferBusy || firmwareProtocols?.loading == true) {
      _setError('请等待当前传输或协议载入完成');
      return null;
    }
    if (!_state.isConnected || _serialPort == null) {
      _setError('未连接串口');
      return null;
    }
    try {
      final port = _serialPort;
      final session = _transfers.begin(
        kind,
        write: (bytes, timeout) =>
            identical(port, _serialPort) && _reliableWrite(bytes, timeout),
      );
      _stopLoopSend();
      _purgeSerialBuffers();
      return session;
    } on StateError catch (error) {
      _setError(error.message.toString());
      return null;
    }
  }

  Future<void> startFileSend() async {
    if (_fileSendConfig.filePath.isEmpty) {
      _setError('请先选择文件');
      return;
    }
    final session = _beginTransfer(SerialTransferKind.send);
    if (session == null) return;
    final config = _fileSendConfig;
    _fileSendConfig = config.copyWith(isSending: true, sentBytes: 0);
    notifyListeners();
    try {
      final data = await File(config.filePath).readAsBytes();
      if (!session.isActive) return;

      final protocol = ProtocolRegistry.getByName(config.protocolName);
      await protocol.send(
        data,
        packetSize: config.packetSize,
        intervalMs: config.sendInterval,
        callbacks: session.callbacks(
          fileName: config.fileName,
          onProgress: (progress) {
            _fileSendConfig = _fileSendConfig.copyWith(
              sentBytes: (progress * data.length).toInt(),
            );
            notifyListeners();
          },
          onLog: _addFirmwareLog,
          onError: _setError,
          onComplete: (total) {
            _fileSendConfig = _fileSendConfig.copyWith(sentBytes: total);
            _stats = _stats.copyWith(sentBytes: _stats.sentBytes + total);
            _addFirmwareLog('文件发送完成');
          },
        ),
      );
    } catch (error) {
      if (session.isActive) _setError('文件发送失败: $error');
    } finally {
      if (session.isActive) {
        session.finish();
        _fileSendConfig = _fileSendConfig.copyWith(isSending: false);
        notifyListeners();
      }
    }
  }

  void _stopFileSend() {
    final session = _transfers.active;
    if (session?.kind == SerialTransferKind.send) session!.cancel();
    _fileSendTimer?.cancel();
    _fileSendTimer = null;
    _fileSendConfig = _fileSendConfig.copyWith(isSending: false);
    notifyListeners();
  }

  /// 清除串口硬件收发缓冲区残留数据
  void _purgeSerialBuffers() {
    try {
      _serialPort?.purge();
    } catch (_) {}
  }

  bool _reliableWrite(Uint8List data, int timeoutMs) =>
      _state.isConnected && (_serialPort?.send(data, timeoutMs) ?? false);

  /// 停止文件发送（公共方法）
  void stopFileSend() {
    _stopFileSend();
    _addFirmwareLog('文件发送已停止');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 文件接收
  // ═══════════════════════════════════════════════════════════════════════════

  /// 选择文件接收保存路径（手动指定完整文件路径）
  Future<void> selectReceivePath() async {
    try {
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final defaultName = 'received_$timestamp.bin';

      String? result = await FilePickerCompat.saveFile(
        dialogTitle: '选择文件保存路径',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['bin', 'txt', 'dat'],
      );

      if (result != null && result.isNotEmpty) {
        _fileReceiveConfig = _fileReceiveConfig.copyWith(
          savePath: result,
          fileName: result.split(Platform.pathSeparator).last,
        );
        notifyListeners();
      }
    } catch (e) {
      _setError('选择保存路径失败: $e');
    }
  }

  /// 选择默认存储目录（接收文件自动保存到此目录，使用发送端文件名）
  Future<void> selectDefaultReceiveDir() async {
    try {
      String? result = await FilePickerCompat.getDirectoryPath(
        dialogTitle: '选择默认存储目录',
      );

      if (result != null && result.isNotEmpty) {
        _fileReceiveConfig = _fileReceiveConfig.copyWith(
          defaultSaveDir: result,
        );
        notifyListeners();
      }
    } catch (e) {
      _setError('选择存储目录失败: $e');
    }
  }

  /// 更新文件接收配置
  void updateFileReceiveConfig({
    int? packetSize,
    int? receiveInterval,
    String? protocolName,
  }) {
    _fileReceiveConfig = _fileReceiveConfig.copyWith(
      packetSize: packetSize,
      receiveInterval: receiveInterval,
      protocolName: protocolName,
    );
    notifyListeners();
  }

  Future<void> startFileReceive() async {
    final config = _fileReceiveConfig;
    var savePath = config.savePath;
    if (savePath.isEmpty) {
      if (config.defaultSaveDir.isEmpty) {
        _setError('请先选择保存路径或设置默认存储目录');
        return;
      }
      savePath =
          '${config.defaultSaveDir}${Platform.pathSeparator}receiving_${DateTime.now().millisecondsSinceEpoch}.tmp';
    }
    final session = _beginTransfer(SerialTransferKind.receive);
    if (session == null) return;
    String? senderName;
    _fileReceiveConfig = config.copyWith(
      isReceiving: true,
      receivedBytes: 0,
      totalBytes: 0,
    );
    notifyListeners();
    try {
      final protocol = ProtocolRegistry.getByReceiveName(config.protocolName);
      await protocol.receive(
        savePath: savePath,
        callbacks: session.callbacks(
          onProgress: (progress) {
            _fileReceiveConfig = _fileReceiveConfig.copyWith(
              receivedBytes: (progress * _fileReceiveConfig.totalBytes).toInt(),
            );
            notifyListeners();
          },
          onLog: _addFirmwareLog,
          onError: _setError,
          onComplete: (total) {
            _fileReceiveConfig = _fileReceiveConfig.copyWith(
              receivedBytes: total,
              totalBytes: _fileReceiveConfig.totalBytes > 0
                  ? _fileReceiveConfig.totalBytes
                  : total,
            );
            _stats = _stats.copyWith(
              receivedBytes: _stats.receivedBytes + total,
            );
            _addFirmwareLog('文件接收完成');
          },
          onFileInfo: (name, size) {
            senderName = name.split(RegExp(r'[\\/]')).last;
            _fileReceiveConfig = _fileReceiveConfig.copyWith(totalBytes: size);
            notifyListeners();
          },
        ),
      );
      if (session.isActive &&
          session.completed &&
          !session.hasFailed &&
          senderName != null &&
          senderName!.isNotEmpty &&
          config.savePath.isEmpty) {
        final name = senderName!;
        final path = '${config.defaultSaveDir}${Platform.pathSeparator}$name';
        await File(savePath).rename(path);
        if (session.isActive) {
          _fileReceiveConfig = _fileReceiveConfig.copyWith(fileName: name);
          _addFirmwareLog('文件已保存: $path');
        }
      }
    } catch (error) {
      if (session.isActive) _setError('文件接收失败: $error');
    } finally {
      if (session.isActive) {
        session.finish();
        _fileReceiveConfig = _fileReceiveConfig.copyWith(isReceiving: false);
        notifyListeners();
      }
    }
  }

  void _stopFileReceive() {
    final session = _transfers.active;
    if (session?.kind == SerialTransferKind.receive) session!.cancel();
    _fileReceiveConfig = _fileReceiveConfig.copyWith(isReceiving: false);
    notifyListeners();
  }

  /// 停止文件接收（公共方法）
  void stopFileReceive() {
    _stopFileReceive();
    _addFirmwareLog('文件接收已停止');
  }

  /// 清空消息列表
  void clearMessages() {
    _messages.clear();
    _stats = CommunicationStats();
    notifyListeners();
  }

  /// 重置统计数据
  void resetStats() {
    _stats = CommunicationStats();
    notifyListeners();
  }

  /// 格式化字节数为可读字符串
  String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  /// 初始化日志文件
  Future<void> _initLogFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final fileName =
          'serial_log_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.txt';
      _logFile = File('${directory.path}/$fileName');
      debugPrint('日志文件已创建: ${_logFile!.path}');
    } catch (e) {
      debugPrint('创建日志文件失败: $e');
    }
  }

  /// 写入日志文件
  Future<void> _writeToLogFile(SerialPortMessage message) async {
    if (_logFile == null) return;

    try {
      final timeStr = message.timestamp.toString();
      final direction = message.isSent ? 'TX' : 'RX';
      final data = _displayConfig.receiveHex ? message.hexData : message.data;
      final logLine = '[$timeStr] $direction: $data\n';

      await _logFile!.writeAsString(logLine, mode: FileMode.append);
    } catch (e) {
      debugPrint('写入日志文件失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 固件升级
  // ═══════════════════════════════════════════════════════════════════════

  /// 选择固件文件
  Future<void> selectFirmwareFile() async {
    try {
      PickedFiles? result = await FilePickerCompat.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        await loadFirmwareFile(file.path ?? (throw StateError('所选文件没有本地路径')));
      }
    } catch (e) {
      _setError('选择固件文件失败: $e');
    }
  }

  /// 成功读完整个文件后才替换输入，避免文件信息与旧字节混用。
  Future<void> loadFirmwareFile(String path) async {
    if (isTransferBusy) throw StateError('请先停止传输任务');
    final bytes = await File(path).readAsBytes();
    if (_disposed || isTransferBusy) return;
    if (bytes.isEmpty) throw const FormatException('固件文件不能为空');
    _firmwareBytes = Uint8List.fromList(bytes).asUnmodifiableView();
    _firmwareConfig = _firmwareConfig.copyWith(
      firmwarePath: path,
      firmwareName: File(path).uri.pathSegments.last,
      firmwareSize: bytes.length,
      progress: 0,
    );
    _addFirmwareLog(
      '已载入固件：${_firmwareConfig.firmwareName} (${formatBytes(bytes.length)})',
    );
  }

  /// 添加日志到主数据日志区（所有模块共用）
  void _addFirmwareLog(String message) {
    _messages.add(
      SerialPortMessage(
        data: '[协议] $message',
        hexData: '',
        timestamp: DateTime.now(),
        isSent: false,
        dataLength: 0,
      ),
    );
    notifyListeners();
  }

  /// 升级任务复用当前连接，并固定本次物理连接身份。
  Future<void> startFirmwareUpgrade() async {
    if (_firmwareConfig.firmwarePath.isEmpty) {
      _setError('请先选择固件文件');
      return;
    }
    final loadedProtocol = firmwareProtocols?.loaded;
    if (loadedProtocol == null) {
      _setError('请先选择并载入升级协议');
      return;
    }
    final session = _beginTransfer(SerialTransferKind.firmware);
    if (session == null) return;
    final config = _firmwareConfig;
    _firmwareConfig = config.copyWith(isUpgrading: true, progress: 0, logs: []);
    _addFirmwareLog('开始固件升级...');
    try {
      final bytes =
          _firmwareBytes ?? await File(config.firmwarePath).readAsBytes();
      if (!session.isActive) return;
      _addFirmwareLog('固件大小: ${formatBytes(bytes.length)}');
      if (bytes.isEmpty) throw StateError('固件文件不能为空');
      await _runLuaUpgrade(session, loadedProtocol, bytes);
    } catch (error) {
      if (session.isActive) _setError('固件升级失败: $error');
    } finally {
      if (session.isActive) {
        session.finish();
        _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
        notifyListeners();
      }
    }
  }

  /// 在现有独占会话上运行脚本，等待解释器和在途操作释放后才开放下一任务。
  Future<void> _runLuaUpgrade(
    SerialTransferSession session,
    InteractionProtocol protocol,
    Uint8List bytes,
  ) async {
    final input = StreamController<RawPacket>.broadcast(sync: true);
    final source = ConnectionConfig(
      id: 'firmware-serial',
      protocolId: '',
      kind: TransportKind.serial,
      serialPort: _config.portName,
      baudRate: _config.baudRate,
      dataBits: _config.dataBits,
      stopBits: _config.stopBits,
      parity: const [
        'None',
        'Odd',
        'Even',
        'Mark',
        'Space',
      ].indexOf(_config.parity),
      flowControl: const {
        'None': 'none',
        'RTS/CTS': 'rts_cts',
        'DTR/DSR': 'dtr_dsr',
        'XON/XOFF': 'xon_xoff',
      }[_config.flowControl]!,
    );
    _firmwareStopping = false;
    final run = firmwareProtocols!.library.runtime.start(
      protocol,
      LuaRunContext(
        config: source,
        inbound: input.stream,
        firmware: bytes,
        firmwareName: _firmwareConfig.firmwareName,
        isClosed: () => !session.isActive || !_state.isConnected,
        send: (frame) async {
          if (_firmwareStopping || !session.write(frame, 5000)) {
            throw StateError('串口会话已停止或写入失败');
          }
          _stats = _stats.copyWith(
            sentBytes: _stats.sentBytes + frame.length,
            sentMessages: _stats.sentMessages + 1,
          );
          notifyListeners();
        },
      ),
    );
    _luaRun = run;
    final library = firmwareProtocols!.library;
    library.retain(protocol.id);
    final terminal = Completer<UpgradeRunEvent>();
    final subscription = run.events.listen((event) {
      if (event.terminal != null && !terminal.isCompleted) {
        terminal.complete(event);
      }
      if (!session.isActive || _disposed) return;
      if (event.percent != null) {
        _firmwareConfig = _firmwareConfig.copyWith(
          progress: event.percent! / 100,
        );
        notifyListeners();
      }
      if (event.message != null) _addFirmwareLog(event.message!);
      if (event.terminal != null && !terminal.isCompleted) {
        terminal.complete(event);
      }
    });
    session.onData = (data) {
      if (!input.isClosed) {
        input.add(
          RawPacket(
            connectionId: source.id,
            receivedAt: DateTime.now(),
            bytes: data,
          ),
        );
      }
    };
    try {
      // 文件读取期间到达的接收数据仍属于本次会话。
      final pending = await session.readData(0);
      if (pending != null) session.onData?.call(pending);
      final event = await terminal.future;
      await run.released;
      if (session.isActive && !_disposed) {
        if (event.terminal == UpgradeTerminal.done) {
          _firmwareConfig = _firmwareConfig.copyWith(progress: 1);
          _addFirmwareLog('Lua 协议升级完成');
        } else if (event.terminal == UpgradeTerminal.failed) {
          throw StateError(event.error ?? 'Lua 协议升级失败');
        }
      }
    } finally {
      try {
        await subscription.cancel();
        await run.cancel();
      } finally {
        session.onData = null;
        await input.close();
        library.release(protocol.id);
        if (identical(_luaRun, run)) _luaRun = null;
        _firmwareStopping = false;
      }
    }
  }

  void stopFirmwareUpgrade() {
    final run = _luaRun;
    if (run != null) {
      if (!_firmwareStopping) {
        _firmwareStopping = true;
        _addFirmwareLog('正在停止 Lua 升级并释放会话');
        unawaited(
          run.cancel().catchError((Object error) {
            if (!_disposed) _setError('释放 Lua 会话失败：$error');
          }),
        );
      }
      return;
    }
    final session = _transfers.active;
    if (session?.kind != SerialTransferKind.firmware) return;
    session!.cancel();
    _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
    _addFirmwareLog('升级已停止');
  }

  /// 清空固件升级日志
  void clearFirmwareLogs() {
    _firmwareConfig = _firmwareConfig.copyWith(logs: []);
    notifyListeners();
  }

  /// 卸载 Lua 协议，必须重新载入后才能升级
  void unloadFirmwareProtocol() {
    if (isTransferBusy) return;
    firmwareProtocols?.unload();

    _addFirmwareLog('已卸载升级协议，请重新选择并载入');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    firmwareProtocols?.removeListener(notifyListeners);
    firmwareProtocols?.dispose();
    portDirectory.removeListener(_portsUpdated);
    portDirectory.dispose();
    _flushBatchNotify();
    stopFirmwareUpgrade();
    disconnect();
    _errorController.close();
    super.dispose();
  }
}
