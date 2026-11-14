// CH341DLLA64.dll FFI 封装层
//
// 基于官方 CH341DLL.H (V2.2) 头文件，封装 CH341 USB 桥接芯片的 64 位 DLL 接口。
// 函数签名严格匹配 WCH 官方 API 定义。
//
// 关键 API：
//   CH341OpenDevice   → HANDLE  (打开设备)
//   CH341CloseDevice  → VOID    (关闭设备)
//   CH341SetStream    → BOOL    (设置 I2C/SPI 速率)
//   CH341StreamI2C    → BOOL    (多字节 I2C 传输)
//   CH341ReadI2C      → BOOL    (单字节 I2C 读取)
//   CH341WriteI2C     → BOOL    (单字节 I2C 写入)
//   CH341GetStatus    → BOOL    (读取设备状态)
//   CH341GetDeviceName→ PVOID   (获取设备名称字符串)
//   CH341GetVerIC     → ULONG   (获取芯片版本)

import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ─── 原生函数类型定义 (WINAPI = __stdcall, x64 下无区别) ──────

// HANDLE WINAPI CH341OpenDevice(ULONG iIndex);
// HANDLE 在 x64 为 8 字节指针，用 IntPtr 表示
typedef Ch341OpenDeviceNative = IntPtr Function(Uint32);
typedef Ch341OpenDeviceDart = int Function(int);

// VOID WINAPI CH341CloseDevice(ULONG iIndex);
typedef Ch341CloseDeviceNative = Void Function(Uint32);
typedef Ch341CloseDeviceDart = void Function(int);

// BOOL WINAPI CH341SetStream(ULONG iIndex, ULONG iMode);
typedef Ch341SetStreamNative = Int32 Function(Uint32, Uint32);
typedef Ch341SetStreamDart = int Function(int, int);

// BOOL WINAPI CH341StreamI2C(ULONG iIndex, ULONG iWriteLength,
//   PVOID iWriteBuffer, ULONG iReadLength, PVOID oReadBuffer);
typedef Ch341StreamI2CNative = Int32 Function(
    Uint32, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint8>);
typedef Ch341StreamI2CDart = int Function(
    int, int, Pointer<Uint8>, int, Pointer<Uint8>);

// BOOL WINAPI CH341ReadI2C(ULONG iIndex, UCHAR iDevice, UCHAR iAddr, PUCHAR oByte);
typedef Ch341ReadI2CNative = Int32 Function(
    Uint32, Uint8, Uint8, Pointer<Uint8>);
typedef Ch341ReadI2CDart = int Function(int, int, int, Pointer<Uint8>);

// BOOL WINAPI CH341WriteI2C(ULONG iIndex, UCHAR iDevice, UCHAR iAddr, UCHAR iByte);
typedef Ch341WriteI2CNative = Int32 Function(
    Uint32, Uint8, Uint8, Uint8);
typedef Ch341WriteI2CDart = int Function(int, int, int, int);

// BOOL WINAPI CH341GetStatus(ULONG iIndex, PULONG iStatus);
typedef Ch341GetStatusNative = Int32 Function(Uint32, Pointer<Uint32>);
typedef Ch341GetStatusDart = int Function(int, Pointer<Uint32>);

// PVOID WINAPI CH341GetDeviceName(ULONG iIndex);
// 返回指向设备名称字符串的指针
typedef Ch341GetDeviceNameNative = Pointer<Utf8> Function(Uint32);
typedef Ch341GetDeviceNameDart = Pointer<Utf8> Function(int);

// ULONG WINAPI CH341GetVerIC(ULONG iIndex);
typedef Ch341GetVerICNative = Uint32 Function(Uint32);
typedef Ch341GetVerICDart = int Function(int);

/// CH341DLLA64.dll 单例封装
class Ch341Dll {
  static Ch341Dll? _instance;
  factory Ch341Dll() => _instance ??= Ch341Dll._();
  Ch341Dll._();

  DynamicLibrary? _dylib;
  bool _loaded = false;

  // 原生函数指针
  late Ch341OpenDeviceDart _openDevice;
  late Ch341CloseDeviceDart _closeDevice;
  late Ch341SetStreamDart _setStream;
  late Ch341StreamI2CDart _streamI2C;
  late Ch341ReadI2CDart _readI2C;
  late Ch341WriteI2CDart _writeI2C;
  late Ch341GetStatusDart _getStatus;
  late Ch341GetDeviceNameDart _getDeviceName;
  late Ch341GetVerICDart _getVerIC;

  bool get isLoaded => _loaded;

  /// 加载 CH341DLLA64.dll
  bool load() {
    if (_loaded) return true;
    try {
      _dylib = DynamicLibrary.open('CH341DLLA64.dll');
      _openDevice =
          _dylib!.lookupFunction<Ch341OpenDeviceNative, Ch341OpenDeviceDart>(
              'CH341OpenDevice');
      _closeDevice =
          _dylib!.lookupFunction<Ch341CloseDeviceNative, Ch341CloseDeviceDart>(
              'CH341CloseDevice');
      _setStream =
          _dylib!.lookupFunction<Ch341SetStreamNative, Ch341SetStreamDart>(
              'CH341SetStream');
      _streamI2C =
          _dylib!.lookupFunction<Ch341StreamI2CNative, Ch341StreamI2CDart>(
              'CH341StreamI2C');
      _readI2C =
          _dylib!.lookupFunction<Ch341ReadI2CNative, Ch341ReadI2CDart>(
              'CH341ReadI2C');
      _writeI2C =
          _dylib!.lookupFunction<Ch341WriteI2CNative, Ch341WriteI2CDart>(
              'CH341WriteI2C');
      _getStatus =
          _dylib!.lookupFunction<Ch341GetStatusNative, Ch341GetStatusDart>(
              'CH341GetStatus');
      _getDeviceName = _dylib!
          .lookupFunction<Ch341GetDeviceNameNative, Ch341GetDeviceNameDart>(
              'CH341GetDeviceName');
      _getVerIC =
          _dylib!.lookupFunction<Ch341GetVerICNative, Ch341GetVerICDart>(
              'CH341GetVerIC');
      _loaded = true;
      return true;
    } on ArgumentError {
      _loaded = false;
      return false;
    }
  }

  void unload() {
    _dylib = null;
    _loaded = false;
  }

  // ─── 设备管理 ────────────────────────────────────────────

  /// 打开 CH341 设备，返回非零句柄表示成功
  int openDevice(int index) {
    _ensureLoaded();
    return _openDevice(index);
  }

  /// 关闭 CH341 设备
  void closeDevice(int index) {
    _ensureLoaded();
    _closeDevice(index);
  }

  /// 获取设备名称字符串
  String? getDeviceName(int index) {
    _ensureLoaded();
    final ptr = _getDeviceName(index);
    if (ptr == nullptr) return null;
    return ptr.toDartString();
  }

  /// 获取芯片版本: 0=无效, 0x10=CH341, 0x20=CH341A, 0x30=CH341A3
  int getVerIC(int index) {
    _ensureLoaded();
    return _getVerIC(index);
  }

  /// 获取设备状态（32 位）
  /// @return true 表示读取成功
  bool getStatus(int index, Pointer<Uint32> outStatus) {
    _ensureLoaded();
    return _getStatus(index, outStatus) != 0;
  }

  // ─── 流配置 ──────────────────────────────────────────────

  /// 设置串行接口模式
  /// [mode] 位1-0: I2C 速率 (0=20K, 1=100K, 2=400K, 3=750K)
  bool setStream(int index, int mode) {
    _ensureLoaded();
    return _setStream(index, mode) != 0;
  }

  // ─── 单字节 I2C 操作（高层 API，推荐用于寄存器读写）───────

  /// 从 I2C 设备读取单个字节
  /// [deviceAddr] 7-bit 设备地址
  /// [regAddr] 寄存器地址（单字节）
  /// @return 读取的字节值，null 表示失败
  int? readI2C(int index, int deviceAddr, int regAddr) {
    _ensureLoaded();
    final pByte = calloc<Uint8>(1);
    try {
      final ret = _readI2C(index, deviceAddr, regAddr, pByte);
      if (ret == 0) return null;
      return pByte[0];
    } finally {
      calloc.free(pByte);
    }
  }

  /// 向 I2C 设备写入单个字节
  /// [deviceAddr] 7-bit 设备地址
  /// [regAddr] 寄存器地址（单字节）
  /// [byte] 写入的数据
  bool writeI2C(int index, int deviceAddr, int regAddr, int byte) {
    _ensureLoaded();
    return _writeI2C(index, deviceAddr, regAddr, byte) != 0;
  }

  // ─── 多字节 I2C 传输（低层 API）─────────────────────────

  /// I2C 流式传输（写 + 读）
  ///
  /// 写入 [wBuf] 的字节后，若 [readLen] > 0 则产生 Repeated Start
  /// 并读取 [readLen] 字节到返回的缓冲区中。
  ///
  /// [wBuf] 首字节通常为设备地址(左移1位|写位 = deviceAddr<<1)
  /// @return 读取的数据，null 表示失败
  Uint8List? streamI2C(int index, List<int> wBuf, int readLen) {
    _ensureLoaded();
    final wLen = wBuf.length;
    final wPtr = calloc<Uint8>(wLen);
    final rPtr = readLen > 0 ? calloc<Uint8>(readLen) : nullptr;
    try {
      for (int i = 0; i < wLen; i++) {
        wPtr[i] = wBuf[i];
      }
      final ret = _streamI2C(index, wLen, wPtr, readLen, rPtr);
      if (ret == 0) return null;
      if (readLen == 0) return Uint8List(0);
      final result = Uint8List(readLen);
      for (int i = 0; i < readLen; i++) {
        result[i] = rPtr[i];
      }
      return result;
    } finally {
      calloc.free(wPtr);
      if (readLen > 0) calloc.free(rPtr);
    }
  }

  /// 构建 I2C 写缓冲区（设备地址 + 寄存器地址 + 数据）
  List<int> buildWriteBuffer(int deviceAddr, List<int> data) {
    return [(deviceAddr << 1) & 0xFF, ...data];
  }

  // ─── 内部 ────────────────────────────────────────────────

  void _ensureLoaded() {
    if (!_loaded) {
      throw StateError('CH341DLLA64.dll 未加载，请先调用 load()');
    }
  }
}
