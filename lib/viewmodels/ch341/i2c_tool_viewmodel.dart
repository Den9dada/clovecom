// I2C 工具 ViewModel
//
// 管理 CH341 I2C 寄存器映射工具的全部业务状态：
// - 设备管理（驱动加载、定时设备扫描、连接/断开）
// - Excel 加载（寄存器映射解析 + 拖入支持）
// - 寄存器读写（单寄存器 + 批量操作）
// - 位域编辑联动（位域值 ↔ HEX 值双向同步）
// - 日志管理（含详细错误描述）
// - Excel 反向导出

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../../models/ch341_device_info.dart';
import '../../models/ch341_operation_result.dart';
import '../../models/i2c_register_map.dart';
import '../../services/ch341/ch341_service_base.dart';
import '../../services/ch341/ch341_service_win32.dart';
import '../../services/ch341/i2c_register_parser.dart';
import '../../services/ch341/i2c_register_writer.dart';

class I2cToolViewModel extends ChangeNotifier {
  final Ch341ServiceBase _service;
  final I2cRegisterParser _parser = I2cRegisterParser();
  final I2cRegisterWriter _writer = I2cRegisterWriter();

  I2cToolViewModel({Ch341ServiceBase? service})
      : _service = service ?? Ch341ServiceWin32();

  static const int _maxLogEntries = 500;
  static const int _logPruneCount = 100;

  // ─── 驱动状态 ─────────────────────────────────────────

  bool _driverLoaded = false;
  String? _driverError;
  bool get driverLoaded => _driverLoaded;
  String? get driverError => _driverError;

  // ─── 设备状态 ─────────────────────────────────────────

  List<Ch341DeviceInfo> _availableDevices = [];
  int? _selectedDeviceIndex;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _autoScanTimer;
  bool _autoScanEnabled = false;

  List<Ch341DeviceInfo> get availableDevices => _availableDevices;
  int? get selectedDeviceIndex => _selectedDeviceIndex;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  // ─── I2C 速率 ─────────────────────────────────────────

  int _i2cSpeed = 2; // 0=20K, 1=100K, 2=400K, 3=750K
  int get i2cSpeed => _i2cSpeed;

  static const List<Map<String, dynamic>> i2cSpeedOptions = [
    {'label': '20 kHz', 'value': 0, 'speedHz': 20000},
    {'label': '100 kHz', 'value': 1, 'speedHz': 100000},
    {'label': '400 kHz', 'value': 2, 'speedHz': 400000},
    {'label': '750 kHz', 'value': 3, 'speedHz': 750000},
  ];

  /// 根据 Excel 中的 Speed(kHz) 匹配最佳速率挡位（无匹配则向下取）
  int _matchI2cSpeed(int speedKHz) {
    for (int i = i2cSpeedOptions.length - 1; i >= 0; i--) {
      if (speedKHz >= (i2cSpeedOptions[i]['speedHz'] as int) ~/ 1000) {
        return i2cSpeedOptions[i]['value'] as int;
      }
    }
    return 0; // 最低挡位 20kHz
  }

  // ─── 寄存器映射 ───────────────────────────────────────

  I2cRegisterMap? _registerMap;
  bool get hasMapLoaded => _registerMap != null;
  I2cRegisterMap? get registerMap => _registerMap;
  int? _selectedRegisterIndex;

  int? get selectedRegisterIndex => _selectedRegisterIndex;

  // ─── 拖入状态 ─────────────────────────────────────────

  bool _showDragHint = false;
  bool get showDragHint => _showDragHint;

  // ─── 操作状态 ─────────────────────────────────────────

  bool _isBusy = false;
  String? _statusMessage;
  double _progress = 0.0;
  String _progressLabel = '';

  bool get isBusy => _isBusy;
  String? get statusMessage => _statusMessage;
  double get progress => _progress;
  String get progressLabel => _progressLabel;

  // ─── 日志 ─────────────────────────────────────────────

  final List<Ch341OperationResult> _operationLog = [];
  List<Ch341OperationResult> get operationLog =>
      List.unmodifiable(_operationLog);

  // ─── 合并通知 ─────────────────────────────────────────

  Timer? _batchNotifyTimer;
  bool _batchNotifyScheduled = false;
  static const Duration _batchInterval = Duration(milliseconds: 50);

  void _scheduleNotify() {
    if (_batchNotifyScheduled) return;
    _batchNotifyScheduled = true;
    _batchNotifyTimer?.cancel();
    _batchNotifyTimer = Timer(_batchInterval, () {
      _batchNotifyScheduled = false;
      notifyListeners();
    });
  }

  // ─── 驱动管理 ─────────────────────────────────────────

  void loadDriver() {
    _driverError = null;
    final ok = _service.loadDriver();
    _driverLoaded = ok;
    if (!ok) {
      _driverError = 'CH341DLLA64.dll 加载失败，请确认驱动已安装\n'
          '下载地址：https://www.wch.cn/downloads/CH341PAR_ZIP.html';
    } else {
      startAutoScan();
    }
    notifyListeners();
  }

  void unloadDriver() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    _autoScanEnabled = false;
    _service.unloadDriver();
    _driverLoaded = false;
    _driverError = null;
    notifyListeners();
  }

  // ─── 定时设备扫描 ─────────────────────────────────────

  /// 启动定时扫描（每 2 秒）
  void startAutoScan() {
    if (_autoScanEnabled) return;
    _autoScanEnabled = true;
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _autoScanTick();
    });
    // 立即执行一次
    _autoScanTick();
  }

  void stopAutoScan() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    _autoScanEnabled = false;
  }

  void _autoScanTick() {
    if (!_driverLoaded) {
      loadDriver();
      if (!_driverLoaded) return;
    }
    final previousCount = _availableDevices.length;
    final wasDisconnected = _availableDevices.isEmpty;
    _availableDevices = _service.enumerateDevices();

    // 如果之前无设备现在有了，通知
    if (wasDisconnected && _availableDevices.isNotEmpty) {
      _addLog(Ch341OperationResult.ok(
        data: null,
        duration: Duration.zero,
        description: '检测到 ${_availableDevices.length} 个 CH341 设备',
      ));
    }
    // 如果设备数有变化
    if (_availableDevices.length != previousCount || wasDisconnected) {
      notifyListeners();
    }

    // 如果连接丢失，自动断开
    if (_isConnected && _selectedDeviceIndex != null) {
      final stillPresent = _availableDevices
          .any((d) => d.deviceIndex == _selectedDeviceIndex);
      if (!stillPresent) {
        _addLog(Ch341OperationResult.fail(
          errorMessage: 'CH341 设备 #$_selectedDeviceIndex 已断开',
          duration: Duration.zero,
          description: '设备断开',
        ));
        _doDisconnect();
      }
    }
  }

  // ─── 设备管理 ─────────────────────────────────────────

  void refreshDevices() {
    if (!_driverLoaded) {
      loadDriver();
      if (!_driverLoaded) return;
    }
    _availableDevices = _service.enumerateDevices();
    notifyListeners();
  }

  Future<void> connect(int deviceIndex) async {
    if (_isConnecting || _isConnected) return;
    _isConnecting = true;
    notifyListeners();

    final devName = _availableDevices
        .where((d) => d.deviceIndex == deviceIndex)
        .firstOrNull
        ?.description ?? 'CH341 #$deviceIndex';

    try {
      final ok = _service.openDevice(deviceIndex, speed: _i2cSpeed);
      if (ok) {
        _selectedDeviceIndex = deviceIndex;
        _isConnected = true;
        _statusMessage = '已连接: $devName';
        _addLog(Ch341OperationResult.ok(
          data: null,
          duration: Duration.zero,
          description: '已连接 $devName (I2C ${i2cSpeedOptions[_i2cSpeed]['label']})',
        ));
      } else {
        _addLog(Ch341OperationResult.fail(
          errorMessage: '无法打开设备 #$deviceIndex ($devName)，'
              '可能原因：设备被其他程序占用、驱动未正确安装、设备未切换到 I2C 模式',
          duration: Duration.zero,
          description: '连接失败: $devName',
        ));
      }
    } catch (e) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '连接异常: $e',
        duration: Duration.zero,
        description: '连接失败: $devName',
      ));
    }
    _isConnecting = false;
    notifyListeners();
  }

  void disconnect() {
    final devName = _selectedDeviceIndex != null
        ? (_availableDevices
                .where((d) => d.deviceIndex == _selectedDeviceIndex)
                .firstOrNull
                ?.description ??
            'CH341 #$_selectedDeviceIndex')
        : '';
    _addLog(Ch341OperationResult.ok(
      data: null,
      duration: Duration.zero,
      description: '已断开 $devName',
    ));
    _doDisconnect();
    notifyListeners();
  }

  void _doDisconnect() {
    if (_selectedDeviceIndex != null) {
      _service.closeDevice(_selectedDeviceIndex!);
    }
    _isConnected = false;
    _selectedDeviceIndex = null;
    if (_registerMap != null) {
      for (final reg in _registerMap!.registers) {
        reg.currentValue = null;
        reg.discardEditing();
      }
    }
  }

  void setI2cSpeed(int speed) {
    _i2cSpeed = speed;
    notifyListeners();
  }

  // ─── Excel 加载 ───────────────────────────────────────

  Future<void> loadExcelFile([String? filePath]) async {
    if (filePath == null) return;
    _isBusy = true;
    _statusMessage = '正在解析寄存器映射...';
    notifyListeners();

    try {
      _registerMap = await _parser.parse(filePath);
      _selectedRegisterIndex = null;
      final config = _registerMap!.chipConfig;

      // 根据 Excel 中的 Speed 自动匹配 I2C 速率
      final matchedSpeed = _matchI2cSpeed(config.speed);
      _i2cSpeed = matchedSpeed;
      final speedLabel =
          i2cSpeedOptions.firstWhere((o) => o['value'] == _i2cSpeed)['label'];

      _statusMessage = '加载完成：${_registerMap!.registerCount} 个寄存器'
          ' | 地址: ${config.deviceAddressHex}'
          ' | 速率: $speedLabel';

      _addLog(Ch341OperationResult.ok(
        data: null,
        duration: Duration.zero,
        description: 'Excel 加载: ${config.moduleName} v${config.version}'
            ' (${_registerMap!.registerCount} 寄存器,'
            ' 地址=${config.deviceAddressHex}, 接口=${config.interfaceType}, 速率=$speedLabel)',
      ));

      if (_registerMap!.parseErrors.isNotEmpty) {
        for (final err in _registerMap!.parseErrors) {
          _addLog(Ch341OperationResult.fail(
            errorMessage: 'Excel 解析警告: $err',
            duration: Duration.zero,
            description: '解析警告',
          ));
        }
      }
    } catch (e) {
      _statusMessage = '解析失败';
      _addLog(Ch341OperationResult.fail(
        errorMessage: 'Excel 文件解析失败: $e\n'
            '请确认文件格式正确（参考 SC7061 寄存器映射模板）',
        duration: Duration.zero,
        description: 'Excel 加载失败',
      ));
    }
    _isBusy = false;
    notifyListeners();
  }

  // ─── 寄存器选择 ───────────────────────────────────────

  void selectRegister(int regIndex) {
    if (_registerMap == null ||
        regIndex < 0 ||
        regIndex >= _registerMap!.registers.length) return;
    _selectedRegisterIndex = regIndex;
    notifyListeners();
  }

  /// 双击寄存器列表项 → 自动读取
  Future<void> selectAndRead(int regIndex) async {
    selectRegister(regIndex);
    await readRegister(regIndex);
  }

  // ─── 寄存器读取 ───────────────────────────────────────

  Future<void> readRegister(int regIndex) async {
    if (!_ensureReady()) return;
    final reg = _registerMap!.registers[regIndex];
    final config = _registerMap!.chipConfig;

    _isBusy = true;
    notifyListeners();

    final readLen = (reg.bitWidth + 7) ~/ 8; // 8位→1B, 16位→2B
    final result = _service.i2cReadRegister(
      _selectedDeviceIndex!,
      config.deviceAddress,
      reg.offset,
      readLen,
    );

    if (result.success && result.data != null && result.data!.isNotEmpty) {
      // 小端序组装多字节值
      int value = 0;
      for (var j = 0; j < result.data!.length; j++) {
        value |= result.data![j] << (8 * j);
      }
      reg.currentValue = value;
      reg.discardEditing();
    }
    _addLog(result);
    _isBusy = false;
    notifyListeners();
  }

  // ─── 寄存器写入（读-改-写保护）───────────────────────

  Future<void> writeRegister(int regIndex) async {
    if (!_ensureReady()) return;
    final reg = _registerMap!.registers[regIndex];
    final config = _registerMap!.chipConfig;

    final writeValue = reg.editingValue ?? reg.currentValue;
    if (writeValue == null) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '寄存器 ${reg.name}(${reg.offsetHex}) 没有要写入的值，'
            '请先点击"读取"获取当前值，或编辑后再写入',
        duration: Duration.zero,
        description: 'WR ${reg.offsetHex} ${reg.name}',
      ));
      notifyListeners();
      return;
    }

    // 读-改-写保护：先读取当前值，合并只读位域
    int finalValue = writeValue;
    if (reg.currentValue != null) {
      int readOnlyMask = 0;
      for (final bf in reg.bitFields) {
        if (bf.isReadOnly) {
          readOnlyMask |= bf.mask;
        }
      }
      finalValue = (reg.currentValue! & readOnlyMask) |
          (writeValue & ~readOnlyMask);
    }

    _isBusy = true;
    notifyListeners();

    final writeLen = (reg.bitWidth + 7) ~/ 8;
    final writeBytes = <int>[];
    for (var j = 0; j < writeLen; j++) {
      writeBytes.add((finalValue >> (8 * j)) & 0xFF);
    }
    final result = _service.i2cWriteRegister(
      _selectedDeviceIndex!,
      config.deviceAddress,
      reg.offset,
      writeBytes,
    );

    if (result.success) {
      reg.currentValue = finalValue;
      reg.discardEditing();
    }
    _addLog(result);
    _isBusy = false;
    notifyListeners();
  }

  // ─── 全部读取 ─────────────────────────────────────────

  Future<void> readAllRegisters() async {
    if (!_ensureReady() || _registerMap == null) return;
    final config = _registerMap!.chipConfig;
    final registers = _registerMap!.registers;

    _isBusy = true;
    _progress = 0;
    _progressLabel = '全部读取中...';
    notifyListeners();

    int successCount = 0;
    int failCount = 0;
    for (int i = 0; i < registers.length; i++) {
      final reg = registers[i];
      final readLen = (reg.bitWidth + 7) ~/ 8;
      final result = _service.i2cReadRegister(
        _selectedDeviceIndex!,
        config.deviceAddress,
        reg.offset,
        readLen,
      );
      if (result.success && result.data != null && result.data!.isNotEmpty) {
        int value = 0;
        for (var j = 0; j < result.data!.length; j++) {
          value |= result.data![j] << (8 * j);
        }
        reg.currentValue = value;
        reg.discardEditing();
        successCount++;
      } else {
        failCount++;
      }
      _addLog(result);
      _progress = (i + 1) / registers.length;
      if ((i + 1) % 4 == 0) notifyListeners();
    }

    _isBusy = false;
    _progressLabel = '读取完成: $successCount/${registers.length} 成功'
        '${failCount > 0 ? ', $failCount 失败' : ''}';
    notifyListeners();
  }

  // ─── 全部写入 ─────────────────────────────────────────

  Future<void> writeAllRegisters() async {
    if (!_ensureReady() || _registerMap == null) return;
    final config = _registerMap!.chipConfig;
    final registers = _registerMap!.registers;

    _isBusy = true;
    _progress = 0;
    _progressLabel = '全部写入中...';
    notifyListeners();

    int count = 0;
    for (int i = 0; i < registers.length; i++) {
      final reg = registers[i];
      final value = reg.editingValue ?? reg.currentValue;
      if (value == null) continue;
      final writeLen = (reg.bitWidth + 7) ~/ 8;
      final writeBytes = <int>[];
      for (var j = 0; j < writeLen; j++) {
        writeBytes.add((value >> (8 * j)) & 0xFF);
      }
      final result = _service.i2cWriteRegister(
        _selectedDeviceIndex!,
        config.deviceAddress,
        reg.offset,
        writeBytes,
      );
      _addLog(result);
      count++;
      _progress = (i + 1) / registers.length;
      if ((i + 1) % 4 == 0) notifyListeners();
    }

    _isBusy = false;
    _progressLabel = '写入完成: $count 个寄存器';
    notifyListeners();
  }

  // ─── 位域编辑联动 ─────────────────────────────────────

  void updateBitFieldValue(int regIndex, int fieldIndex, int value) {
    final reg = _registerMap!.registers[regIndex];
    final bf = reg.bitFields[fieldIndex];
    final clampedValue = value.clamp(0, (1 << bf.width) - 1);

    final currentFull = reg.editingValue ?? reg.currentValue ?? 0;
    final newFull = (currentFull & ~bf.mask) | bf.encode(clampedValue);
    reg.setEditingValue(newFull);
    notifyListeners();
  }

  void setRegisterHexValue(int regIndex, int value) {
    final reg = _registerMap!.registers[regIndex];
    final maxVal = (1 << reg.bitWidth) - 1;
    reg.setEditingValue(value.clamp(0, maxVal));
    notifyListeners();
  }

  void resetRegisterToReadValue(int regIndex) {
    final reg = _registerMap!.registers[regIndex];
    reg.discardEditing();
    notifyListeners();
  }

  void resetRegisterToDefault(int regIndex) {
    final reg = _registerMap!.registers[regIndex];
    int defaultValue = 0;
    for (final bf in reg.bitFields) {
      defaultValue |= bf.encode(bf.defaultValue);
    }
    reg.setEditingValue(defaultValue);
    notifyListeners();
  }

  // ─── 拖入 ─────────────────────────────────────────────

  void setDragHint(bool show) {
    if (_showDragHint == show) return;
    _showDragHint = show;
    notifyListeners();
  }

  // ─── Excel 导出 ───────────────────────────────────────

  Future<void> exportExcel(String outputPath) async {
    if (_registerMap == null) return;
    _isBusy = true;
    _statusMessage = '正在导出...';
    notifyListeners();
    try {
      await _writer.writeToFile(_registerMap!, outputPath);
      _statusMessage = '导出完成';
      _addLog(Ch341OperationResult.ok(
        data: null,
        duration: Duration.zero,
        description: 'Excel 导出: $outputPath',
      ));
    } catch (e) {
      _statusMessage = '导出失败';
      _addLog(Ch341OperationResult.fail(
        errorMessage: 'Excel 导出失败: $e\n'
            '请检查目标路径是否有写入权限',
        duration: Duration.zero,
        description: '导出失败',
      ));
    }
    _isBusy = false;
    notifyListeners();
  }

  // ─── New Register: 导出新映射 ──────────────────────────

  Future<void> exportNewMap(I2cRegisterMap map, String outputPath) async {
    _isBusy = true;
    _statusMessage = '正在导出...';
    notifyListeners();
    try {
      await _writer.writeToFile(map, outputPath);
      _statusMessage = '导出完成';
      _addLog(Ch341OperationResult.ok(
        data: null, duration: Duration.zero,
        description: 'New Register 导出: $outputPath',
      ));
    } catch (e) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '导出失败: $e',
        duration: Duration.zero, description: '导出失败',
      ));
    }
    _isBusy = false;
    notifyListeners();
  }

  // ─── Transform: 原始 I2C 收发 ──────────────────────────

  Future<void> transformRead(int devAddr, int regAddr, int len) async {
    if (!_isConnected) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '未连接 CH341 设备',
        duration: Duration.zero, description: 'I2C 读取失败',
      ));
      notifyListeners();
      return;
    }
    _isBusy = true; notifyListeners();
    final result = _service.i2cReadRegister(
        _selectedDeviceIndex!, devAddr, regAddr, len);
    _addLog(Ch341OperationResult(
      success: result.success,
      errorMessage: result.success ? null
          : 'I2C 读取失败: 0x${devAddr.toRadixString(16)}+0x${regAddr.toRadixString(16)} — ${result.errorMessage ?? "无应答"}',
      data: result.data, duration: result.duration,
      timestamp: result.timestamp,
      description: 'RD 0x${devAddr.toRadixString(16)}+0x${regAddr.toRadixString(16)} (${len}B)',
    ));
    _isBusy = false; notifyListeners();
  }

  Future<void> transformWrite(int devAddr, int regAddr, List<int> data) async {
    if (!_isConnected) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '未连接 CH341 设备',
        duration: Duration.zero, description: 'I2C 写入失败',
      ));
      notifyListeners();
      return;
    }
    _isBusy = true; notifyListeners();
    final result = _service.i2cWriteRegister(
        _selectedDeviceIndex!, devAddr, regAddr, data);
    _addLog(Ch341OperationResult(
      success: result.success,
      errorMessage: result.success ? null
          : 'I2C 写入失败: 0x${devAddr.toRadixString(16)}+0x${regAddr.toRadixString(16)} — ${result.errorMessage ?? "无应答"}',
      data: result.data, duration: result.duration,
      timestamp: result.timestamp,
      description: 'WR 0x${devAddr.toRadixString(16)}+0x${regAddr.toRadixString(16)} ← ${result.hexData}',
    ));
    _isBusy = false; notifyListeners();
  }

  // ─── I2C 设备扫描 ──────────────────────────────────────

  Future<Set<int>> i2cScan({
    void Function(int progress, int? foundAddr)? onProgress,
  }) async {
    final found = <int>{};
    if (!_isConnected) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '未连接 CH341 设备',
        duration: Duration.zero, description: 'I2C 扫描失败',
      ));
      notifyListeners();
      return found;
    }
    _isBusy = true; notifyListeners();
    int scanned = 0;
    for (int addr = 0x03; addr <= 0x77; addr++) {
      try {
        if (_service.probeI2cAddress(_selectedDeviceIndex!, addr)) {
          found.add(addr);
          onProgress?.call(scanned, addr);
        }
      } catch (_) {}
      scanned++;
      if (scanned % 8 == 0) {
        onProgress?.call(scanned, null);
      }
    }
    _addLog(Ch341OperationResult.ok(
      data: found.toList(), duration: Duration.zero,
      description: 'I2C 扫描完成: ${found.length} 个设备',
    ));
    _isBusy = false; notifyListeners();
    return found;
  }

  /// 添加简洁日志
  void addLogMessage(String message, bool success) {
    _addLog(success
        ? Ch341OperationResult.ok(data: null, duration: Duration.zero, description: message)
        : Ch341OperationResult.fail(errorMessage: message, duration: Duration.zero, description: message));
    notifyListeners();
  }

  // ─── 日志 ─────────────────────────────────────────────

  void clearLog() {
    _operationLog.clear();
    notifyListeners();
  }

  void _addLog(Ch341OperationResult result) {
    _operationLog.insert(0, result);
    if (_operationLog.length > _maxLogEntries) {
      _operationLog.removeRange(
          _maxLogEntries - _logPruneCount, _operationLog.length);
    }
    _scheduleNotify();
  }

  // ─── 辅助 ─────────────────────────────────────────────

  bool _ensureReady() {
    if (!_isConnected) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '未连接 CH341 设备，请先在设备栏中选择并连接设备',
        duration: Duration.zero,
        description: '操作失败: 未连接',
      ));
      notifyListeners();
      return false;
    }
    if (_registerMap == null) {
      _addLog(Ch341OperationResult.fail(
        errorMessage: '未加载寄存器映射文件，请先加载芯片的 .xlsx 寄存器定义文件',
        duration: Duration.zero,
        description: '操作失败: 无映射',
      ));
      notifyListeners();
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    stopAutoScan();
    _batchNotifyTimer?.cancel();
    _doDisconnect();
    _service.unloadDriver();
    _service.dispose();
    super.dispose();
  }
}
