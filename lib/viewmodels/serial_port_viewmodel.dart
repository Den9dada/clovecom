// 串口通信视图模型文件
// 
// 该文件实现了串口通信的业务逻辑，采用MVVM架构中的ViewModel层。
// 负责处理串口的打开、关闭、数据发送和接收等操作，并管理相关状态。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import '../models/serial_port_model.dart';
import '../protocols/transfer_protocol.dart';
import '../protocols/protocol_registry.dart';

/// 串口通信视图模型类
class SerialPortViewModel extends ChangeNotifier {
  /// 串口配置对象
  SerialPortConfig _config = SerialPortConfig(portName: '');
  
  /// 串口状态对象
  SerialPortState _state = SerialPortState();
  
  /// 消息列表
  final List<SerialPortMessage> _messages = [];
  
  /// 串口对象实例
  SerialPort? _serialPort;

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
  List<int> _fileData = [];
  
  /// 循环发送的数据
  String _loopSendData = '';
  
  /// 循环发送是否使用HEX
  bool _loopSendIsHex = false;
  
  /// 日志文件
  File? _logFile;
  
  /// 错误信息
  String? _errorMessage;

  /// 错误通知流（用于 SnackBar 弹窗）
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  /// 固件升级配置
  FirmwareUpgradeConfig _firmwareConfig = FirmwareUpgradeConfig();

  /// 固件升级定时器（默认发送逻辑）
  Timer? _firmwareTimer;

  /// 固件升级子进程
  Process? _firmwareProcess;

  /// 传输取消标志（用于文件发送和固件升级）
  bool _isTransferCancelled = false;

  /// 数据接收定时器（替代库的 readBytesOnListen，修复 OVERLAPPED I/O 丢数据问题）
  Timer? _readTimer;

  /// OVERLAPPED 结构体（用于异步读取）
  Pointer<OVERLAPPED>? _readOver;

  /// 实际读取字节数
  Pointer<DWORD>? _readBytesRead;

  /// 串口状态结构体（用于 ClearCommError）
  Pointer<COMSTAT>? _readComStat;

  /// 错误码
  Pointer<DWORD>? _readErrors;

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
  String? get errorMessage => _errorMessage;

  /// 错误通知流
  Stream<String> get errorStream => _errorController.stream;

  /// 设置错误信息并通知
  void _setError(String message) {
    _errorMessage = message;
    _errorController.add(message);
    notifyListeners();
  }

  /// 构造函数
  SerialPortViewModel() {
    refreshPorts();
  }

  /// 刷新可用串口列表
  void refreshPorts() {
    try {
      final portInfoList = SerialPort.getPortsWithFullMessages();
      _availablePorts = portInfoList.map((info) => PortDetailInfo(
        portName: info.portName,
        friendlyName: info.friendlyName,
        hardwareID: info.hardwareID,
        manufactureName: info.manufactureName,
      )).toList();
      notifyListeners();
    } catch (e) {
      try {
        final ports = SerialPort.getAvailablePorts();
        _availablePorts = ports.map((port) => PortDetailInfo(
          portName: port,
          friendlyName: '',
          hardwareID: '',
          manufactureName: '',
        )).toList();
        notifyListeners();
      } catch (e) {
        debugPrint('刷新串口列表失败: $e');
      }
    }
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
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  /// 将HEX字符串还原为文本
  /// 例如: "48 65 6C 6C 6F" -> "Hello"
  /// 如果解析失败，返回null
  String? convertHexToText(String hex) {
    if (hex.trim().isEmpty) return '';
    try {
      final cleanHex = hex.trim().replaceAll(RegExp(r'[^0-9a-fA-F\s]'), '');
      final parts = cleanHex.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
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
    if (_config.portName.isEmpty) {
      _state = _state.copyWith(error: '请选择串口');
      notifyListeners();
      return false;
    }

    try {
      // SerialPort工厂使用静态缓存（putIfAbsent），
      // 直接构造新实例会返回缓存中的旧对象，新参数被忽略。
      // 因此先通过工厂获取缓存实例，再用 openWithSettings 应用新配置并打开。
      _serialPort = SerialPort(_config.portName, openNow: false);

      final newBaudRate = _config.baudRate;
      final newDataBits = _config.dataBits;
      final newStopBits = _config.stopBits == 1 ? 0 : 2;
      final newParity = _getParityValue(_config.parity);

      // openWithSettings 会设置 DCB 并调用 open() → _setCommState()
      _serialPort!.openWithSettings(
        BaudRate: newBaudRate,
        ByteSize: newDataBits,
        StopBits: newStopBits,
        Parity: newParity,
      );

      // openWithSettings 内部只设置了 DCB 的 BaudRate/Parity/StopBits/ByteSize，
      // 未重置 bitfield（流控制标志位）。缓存实例上残留的 bitfield 可能导致
      // SetCommState 使用了不正确的流控制配置。
      // 通过属性 setter 逐项重新设置，确保每次都会调用 _setCommState()，
      // 以当前 DCB 为准完整地应用配置。
      _serialPort!.BaudRate = newBaudRate;
      _serialPort!.ByteSize = newDataBits;
      _serialPort!.StopBits = newStopBits;
      _serialPort!.Parity = newParity;

      _state = _state.copyWith(isConnected: true, error: null);
      notifyListeners();

      _startListening();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: '连接失败: $e');
      notifyListeners();
      return false;
    }
  }

  /// 获取校验位对应的数值
  int _getParityValue(String parity) {
    switch (parity) {
      case 'Odd':
        return 1;
      case 'Even':
        return 2;
      case 'Mark':
        return 3;
      case 'Space':
        return 4;
      default:
        return 0;
    }
  }

  /// 根据追加回车/换行配置，返回需要追加的字节
  List<int> _getAppendBytes() {
    final bytes = <int>[];
    if (_displayConfig.appendCR) bytes.add(0x0D);
    if (_displayConfig.appendLF) bytes.add(0x0A);
    return bytes;
  }

  /// 开始监听串口接收数据
  /// 使用自定义 Timer 轮询 + 正确的 OVERLAPPED I/O 处理，
  /// 替代库的 readBytesOnListen（后者 _read 不等待 OVERLAPPED 完成，导致数据丢失）。
  void _startListening() {
    _readTimer?.cancel();
    _disposeReadResources();

    _readOver = calloc<OVERLAPPED>();
    _readOver!.ref.hEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    _readOver!.ref.Internal = 0;
    _readOver!.ref.InternalHigh = 0;
    _readBytesRead = calloc<DWORD>();
    _readComStat = calloc<COMSTAT>();
    _readErrors = calloc<DWORD>();

    _readTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (!_state.isConnected || _serialPort?.handler == null) {
        _readTimer?.cancel();
        return;
      }

      final handler = _serialPort!.handler!;

      // 查询接收缓冲区中的可用字节数
      ClearCommError(handler, _readErrors!, _readComStat!);
      final bytesAvailable = _readComStat!.ref.cbInQue;
      if (bytesAvailable == 0) return;

      final bytesToRead = bytesAvailable < 1024 ? bytesAvailable : 1024;
      final lpBuffer = calloc<Uint8>(bytesToRead);

      try {
        _readBytesRead!.value = 0;
        ResetEvent(_readOver!.ref.hEvent);

        final result = ReadFile(
          handler,
          lpBuffer,
          bytesToRead,
          _readBytesRead!,
          _readOver!,
        );

        int bytesRead = 0;
        if (result != FALSE) {
          // 同步完成：ReadFile 立即读取了数据
          bytesRead = _readBytesRead!.value;
        } else if (GetLastError() == ERROR_IO_PENDING) {
          // 异步操作：等待 OVERLAPPED 事件完成（最多 100ms）
          if (WaitForSingleObject(_readOver!.ref.hEvent, 100) == 0) {
            GetOverlappedResult(handler, _readOver!, _readBytesRead!, FALSE);
            bytesRead = _readBytesRead!.value;
          }
        }

        if (bytesRead > 0) {
          final data = Uint8List.fromList(lpBuffer.asTypedList(bytesRead));
          _processReceivedData(data);
        }
      } finally {
        free(lpBuffer);
      }
    });
  }

  /// 处理接收到的数据并更新 UI
  void _processReceivedData(Uint8List data) {
    if (!_state.isConnected) return;
    if (_displayConfig.hideReceive) return;

    String received = utf8.decode(data, allowMalformed: true);
    String hexStr = data.map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

    final message = SerialPortMessage(
      data: received,
      hexData: hexStr,
      timestamp: DateTime.now(),
      isSent: false,
      dataLength: data.length,
    );

    _messages.add(message);

    if (_displayConfig.logMode) {
      _writeToLogFile(message);
    }

    _stats = _stats.copyWith(
      receivedBytes: _stats.receivedBytes + data.length,
      receivedMessages: _stats.receivedMessages + 1,
    );

    notifyListeners();
  }

  /// 释放读取相关的 OVERLAPPED 资源
  void _disposeReadResources() {
    if (_readOver != null) {
      CloseHandle(_readOver!.ref.hEvent);
      free(_readOver!);
      _readOver = null;
    }
    if (_readBytesRead != null) {
      free(_readBytesRead!);
      _readBytesRead = null;
    }
    if (_readComStat != null) {
      free(_readComStat!);
      _readComStat = null;
    }
    if (_readErrors != null) {
      free(_readErrors!);
      _readErrors = null;
    }
  }

  /// 断开串口连接
  Future<void> disconnect() async {
    _stopFileSend();
    _stopLoopSend();

    // 停止数据接收定时器并释放 OVERLAPPED 资源
    _readTimer?.cancel();
    _readTimer = null;
    _disposeReadResources();

    // 先将读取回调置空，防止关闭期间旧的读取回调仍在处理数据
    if (_serialPort != null) {
      _serialPort!.readOnListenFunction = (value) {};
    }

    // 取消读取流订阅
    _readStreamSub?.cancel();
    _readStreamSub = null;

    try {
      _serialPort?.close();
    } catch (_) {
      // 忽略关闭时的异常（句柄可能已失效）
    }
    _serialPort = null;

    _state = _state.copyWith(isConnected: false);
    notifyListeners();
  }

  /// 发送数据
  Future<bool> sendData(String data, {bool? isHex}) async {
    if (!_state.isConnected || _serialPort == null) {
      _setError('未连接串口');
      return false;
    }

    try {
      final useHex = isHex ?? _displayConfig.sendHex;
      String sendDataStr;
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
          sendDataStr = String.fromCharCodes(allBytes);
          displayData = utf8.decode(allBytes, allowMalformed: true);
          hexStr = allBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        } else {
          sendDataStr = String.fromCharCodes(bytes);
          displayData = utf8.decode(bytes, allowMalformed: true);
          hexStr = cleanHex.toUpperCase();
        }
      } else {
        // 文本模式：直接发送字符串
        final appendBytes = _getAppendBytes();
        if (appendBytes.isNotEmpty) {
          final allBytes = Uint8List.fromList([...utf8.encode(data), ...appendBytes]);
          sendDataStr = String.fromCharCodes(allBytes);
          displayData = utf8.decode(allBytes, allowMalformed: true);
          hexStr = allBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        } else {
          sendDataStr = data;
          displayData = data;
          final bytes = Uint8List.fromList(utf8.encode(data));
          hexStr = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        }
      }
      
      // 使用writeBytesFromString发送数据
      final result = _serialPort!.writeBytesFromString(
        sendDataStr,
        includeZeroTerminator: false,
      );
      
      if (!result) {
        _setError('发送失败: 写入串口失败');
        return false;
      }
      
      final message = SerialPortMessage(
        data: displayData,
        hexData: hexStr,
        timestamp: DateTime.now(),
        isSent: true,
        dataLength: sendDataStr.length,
      );
      
      _messages.add(message);
      
      // 如果启用了日志模式，保存到文件
      if (_displayConfig.logMode) {
        _writeToLogFile(message);
      }
      
      _stats = _stats.copyWith(
        sentBytes: _stats.sentBytes + sendDataStr.length,
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
    if (_loopSendData.isEmpty) return;
    
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _fileSendConfig = _fileSendConfig.copyWith(
          filePath: file.path,
          fileName: file.name,
          fileSize: file.size,
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
  void updateFileSendConfig({int? packetSize, int? sendInterval, String? protocolName}) {
    _fileSendConfig = _fileSendConfig.copyWith(
      packetSize: packetSize,
      sendInterval: sendInterval,
      protocolName: protocolName,
    );
    notifyListeners();
  }

  /// 开始发送文件
  Future<void> startFileSend() async {
    if (!_state.isConnected || _serialPort == null) {
      _setError('未连接串口');
      return;
    }

    if (_fileSendConfig.filePath.isEmpty) {
      _setError('请先选择文件');
      return;
    }

    try {
      final file = File(_fileSendConfig.filePath);
      _fileData = await file.readAsBytes();

      // 重置取消标志
      _isTransferCancelled = false;

      _fileSendConfig = _fileSendConfig.copyWith(
        isSending: true,
        sentBytes: 0,
      );
      notifyListeners();

      final protocol = ProtocolRegistry.getByName(_fileSendConfig.protocolName);
      _addFirmwareLog('文件发送开始，协议: ${protocol.name}');

      await protocol.send(
        _serialPort!,
        Uint8List.fromList(_fileData),
        packetSize: _fileSendConfig.packetSize,
        intervalMs: _fileSendConfig.sendInterval,
        callbacks: TransferCallbacks(
          onProgress: (progress) {
            _fileSendConfig = _fileSendConfig.copyWith(
              sentBytes: (progress * _fileData.length).toInt(),
            );
            notifyListeners();
          },
          onLog: (msg) {
            _addFirmwareLog(msg);
          },
          onError: (msg) {
            _addFirmwareLog('错误: $msg');
            _setError(msg);
          },
          onComplete: (totalBytes) {
            _fileSendConfig = _fileSendConfig.copyWith(
              isSending: false,
              sentBytes: totalBytes,
            );
            _stats = _stats.copyWith(sentBytes: _stats.sentBytes + totalBytes);
            _addFirmwareLog('文件发送完成');
            notifyListeners();
          },
          onWaitByte: (timeoutMs) async {
            // 等待串口收到数据，返回原始字节值
            final startIdx = _messages.length;
            final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
            while (DateTime.now().isBefore(deadline)) {
              for (int i = startIdx; i < _messages.length; i++) {
                final msg = _messages[i];
                if (!msg.isSent && msg.hexData.isNotEmpty) {
                  // 从 hexData 解析第一个字节（格式如 "43" 或 "43 41 42"）
                  final hexParts = msg.hexData.split(' ');
                  if (hexParts.isNotEmpty && hexParts[0].isNotEmpty) {
                    return int.tryParse(hexParts[0], radix: 16);
                  }
                }
              }
              await Future.delayed(const Duration(milliseconds: 10));
            }
            return null;
          },
          isCancelled: () => _isTransferCancelled,
        ),
      );
    } catch (e) {
      _setError('文件发送失败: $e');
      _stopFileSend();
    }
  }

  /// 停止文件发送
  void _stopFileSend() {
    _isTransferCancelled = true;
    _fileSendTimer?.cancel();
    _fileSendTimer = null;
    _fileSendConfig = _fileSendConfig.copyWith(isSending: false);
    notifyListeners();
  }

  /// 停止文件发送（公共方法）
  void stopFileSend() {
    _stopFileSend();
    _addFirmwareLog('文件发送已停止');
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
      final fileName = 'serial_log_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.txt';
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
  // ═══════════════════════════════════════════════════════════════════════════

  /// 选择固件文件
  Future<void> selectFirmwareFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _firmwareConfig = _firmwareConfig.copyWith(
          firmwarePath: file.path,
          firmwareName: file.name,
          firmwareSize: file.size,
          progress: 0.0,
        );
        _addFirmwareLog('已选择固件: ${file.name} (${formatBytes(file.size)})');
        notifyListeners();
      }
    } catch (e) {
      _setError('选择固件文件失败: $e');
    }
  }

  /// 选择升级脚本
  Future<void> selectFirmwareScript() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dart'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _firmwareConfig = _firmwareConfig.copyWith(
          scriptPath: file.path,
          scriptName: file.name,
        );
        _addFirmwareLog('已选择脚本: ${file.name}');
        notifyListeners();
      }
    } catch (e) {
      _setError('选择升级脚本失败: $e');
    }
  }

  /// 添加日志到主数据日志区（所有模块共用）
  void _addFirmwareLog(String message) {
    _messages.add(SerialPortMessage(
      data: '[协议] $message',
      hexData: '',
      timestamp: DateTime.now(),
      isSent: false,
      dataLength: 0,
    ));
    notifyListeners();
  }

  /// 开始固件升级
  Future<void> startFirmwareUpgrade() async {
    if (!_state.isConnected || _serialPort == null) {
      _setError('未连接串口');
      return;
    }
    if (_firmwareConfig.firmwarePath.isEmpty) {
      _setError('请先选择固件文件');
      return;
    }

    try {
      // 重置取消标志
      _isTransferCancelled = false;

      _firmwareConfig = _firmwareConfig.copyWith(
        isUpgrading: true,
        progress: 0.0,
        logs: [],
      );
      _addFirmwareLog('开始固件升级...');

      final scriptPath = _firmwareConfig.scriptPath;
      if (scriptPath.isNotEmpty && scriptPath.endsWith('.dart')) {
        _addFirmwareLog('使用自定义脚本: ${_firmwareConfig.scriptName}');
        await _runCustomDartScript();
      } else {
        _addFirmwareLog('使用默认发送逻辑（分包发送）');
        await _runDefaultFirmwareSend();
      }
    } catch (e) {
      _setError('启动升级失败: $e');
      _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
      notifyListeners();
    }
  }

  /// 默认固件发送（应用内直接执行，无需外部依赖）
  Future<void> _runDefaultFirmwareSend() async {
    final firmwareFile = File(_firmwareConfig.firmwarePath);
    final firmwareBytes = await firmwareFile.readAsBytes();
    _addFirmwareLog('固件大小: ${formatBytes(firmwareBytes.length)}');
    _addFirmwareLog('每包: ${_fileSendConfig.packetSize}B, 间隔: ${_fileSendConfig.sendInterval}ms');
    notifyListeners();

    int offset = 0;
    int packetIndex = 0;
    _firmwareTimer?.cancel();
    _firmwareTimer = Timer.periodic(
      Duration(milliseconds: _fileSendConfig.sendInterval),
      (timer) {
        // 检查取消标志
        if (_isTransferCancelled) {
          timer.cancel();
          _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
          _addFirmwareLog('固件发送已取消');
          notifyListeners();
          return;
        }

        if (!_firmwareConfig.isUpgrading || _serialPort == null) {
          timer.cancel();
          return;
        }
        if (offset >= firmwareBytes.length) {
          timer.cancel();
          _firmwareConfig = _firmwareConfig.copyWith(
            isUpgrading: false,
            progress: 1.0,
          );
          _addFirmwareLog('固件发送完成！共 ${firmwareBytes.length} 字节，$packetIndex 包');
          notifyListeners();
          return;
        }

        int end = offset + _fileSendConfig.packetSize;
        if (end > firmwareBytes.length) end = firmwareBytes.length;

        final packet = Uint8List.fromList(firmwareBytes.sublist(offset, end));
        try {
          _serialPort!.writeBytesFromUint8List(packet);
          offset = end;
          packetIndex++;

          _firmwareConfig = _firmwareConfig.copyWith(
            progress: offset / firmwareBytes.length,
          );
          _stats = _stats.copyWith(sentBytes: _stats.sentBytes + packet.length);
          notifyListeners();
        } catch (e) {
          timer.cancel();
          _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
          _setError('固件发送失败: $e');
        }
      },
    );
  }

  /// 通过 Dart 子进程运行自定义脚本
  Future<void> _runCustomDartScript() async {
    final firmwareFile = File(_firmwareConfig.firmwarePath);
    final firmwareBytes = await firmwareFile.readAsBytes();
    _addFirmwareLog('固件大小: ${formatBytes(firmwareBytes.length)}');
    notifyListeners();

    try {
      _firmwareProcess = await Process.start(
        'dart',
        [_firmwareConfig.scriptPath],
        mode: ProcessStartMode.normal,
      );

      _firmwareProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) => _handleScriptMessage(line),
        onDone: () {
          if (_firmwareConfig.isUpgrading) {
            _addFirmwareLog('脚本进程已退出');
            _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
            notifyListeners();
          }
        },
      );

      _firmwareProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _addFirmwareLog('[脚本错误] $line');
        notifyListeners();
      });

      final firmwareMsg = jsonEncode({
        'type': 'firmware',
        'data': base64Encode(firmwareBytes),
      });
      _firmwareProcess!.stdin.writeln(firmwareMsg);

      _startFirmwareSerialRelay();
    } catch (e) {
      _addFirmwareLog('启动脚本失败: $e');
      _addFirmwareLog('请确认已安装 Dart SDK 且 dart 命令在 PATH 中');
      _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
      notifyListeners();
    }
  }

  /// 转发串口数据到脚本进程
  int _firmwareRelayIndex = 0;

  void _startFirmwareSerialRelay() {
    _firmwareRelayIndex = _messages.length;
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_firmwareConfig.isUpgrading || _firmwareProcess == null) {
        timer.cancel();
        return;
      }
      while (_firmwareRelayIndex < _messages.length) {
        final msg = _messages[_firmwareRelayIndex];
        _firmwareRelayIndex++;
        if (!msg.isSent) {
          final dataBytes = utf8.encode(msg.data);
          final relayMsg = jsonEncode({
            'type': 'serial',
            'data': base64Encode(dataBytes),
          });
          try {
            _firmwareProcess!.stdin.writeln(relayMsg);
          } catch (_) {
            timer.cancel();
            break;
          }
        }
      }
    });
  }

  /// 处理脚本发来的消息
  void _handleScriptMessage(String line) {
    if (line.trim().isEmpty) return;
    try {
      final msg = jsonDecode(line) as Map<String, dynamic>;
      final type = msg['type'] as String;

      switch (type) {
        case 'send':
          final data = base64Decode(msg['data'] as String);
          if (_serialPort != null && _state.isConnected) {
            _serialPort!.writeBytesFromUint8List(Uint8List.fromList(data));
            _stats = _stats.copyWith(
              sentBytes: _stats.sentBytes + data.length,
              sentMessages: _stats.sentMessages + 1,
            );
          }
          break;
        case 'progress':
          final value = (msg['value'] as num).toDouble();
          _firmwareConfig = _firmwareConfig.copyWith(progress: value.clamp(0.0, 1.0));
          notifyListeners();
          break;
        case 'log':
          _addFirmwareLog(msg['message'] as String);
          notifyListeners();
          break;
        case 'error':
          _addFirmwareLog('[错误] ${msg['message']}');
          _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
          notifyListeners();
          break;
        case 'done':
          final success = msg['success'] as bool? ?? false;
          final message = msg['message'] as String? ?? '';
          _addFirmwareLog(success ? '[完成] $message' : '[失败] $message');
          _firmwareConfig = _firmwareConfig.copyWith(
            isUpgrading: false,
            progress: success ? 1.0 : _firmwareConfig.progress,
          );
          notifyListeners();
          break;
      }
    } catch (e) {
      _addFirmwareLog('[解析] $line');
      notifyListeners();
    }
  }

  /// 停止固件升级
  void stopFirmwareUpgrade() {
    // 设置取消标志
    _isTransferCancelled = true;

    _firmwareTimer?.cancel();
    _firmwareTimer = null;

    if (_firmwareProcess != null) {
      try {
        _firmwareProcess!.stdin.writeln(jsonEncode({'type': 'close'}));
      } catch (_) {}
      try {
        _firmwareProcess!.kill(ProcessSignal.sigterm);
      } catch (_) {}
      _firmwareProcess = null;
    }

    if (_firmwareConfig.isUpgrading) {
      _firmwareConfig = _firmwareConfig.copyWith(isUpgrading: false);
      _addFirmwareLog('升级已手动停止');
      notifyListeners();
    }
  }

  /// 清空固件升级日志
  void clearFirmwareLogs() {
    _firmwareConfig = _firmwareConfig.copyWith(logs: []);
    notifyListeners();
  }

  /// 清除升级脚本（恢复默认）
  void clearFirmwareScript() {
    _firmwareConfig = _firmwareConfig.copyWith(
      scriptPath: '',
      scriptName: '',
    );
    _addFirmwareLog('已恢复默认发送脚本');
    notifyListeners();
  }

  @override
  void dispose() {
    stopFirmwareUpgrade();
    _errorController.close();
    disconnect();
    super.dispose();
  }
}
