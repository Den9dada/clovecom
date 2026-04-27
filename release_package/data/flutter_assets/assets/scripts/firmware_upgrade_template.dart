// ============================================================================
// 固件升级脚本模板
// ============================================================================
//
// 本脚本由 CloveCom 串口助手的"固件升级"功能调用。
// 用户根据实际固件协议修改 upgrade() 函数实现升级逻辑。
//
// ── 通信协议 ──────────────────────────────────────────────────────────────────
//
// 本脚本通过 stdin/stdout 与主程序通信，使用换行分隔的 JSON 消息。
//
// 【接收（主程序 → 脚本）】
//   {"type":"firmware","data":"<base64编码的固件数据块>"}
//   {"type":"serial","data":"<base64编码的串口收到的数据>"}
//   {"type":"close"}
//
// 【发送（脚本 → 主程序）】
//   {"type":"send","data":"<base64编码的要发送的字节>"}     — 通过串口发送数据
//   {"type":"progress","value":0.75}                       — 更新进度条 (0.0~1.0)
//   {"type":"log","message":"正在擦除扇区..."}              — 输出日志
//   {"type":"error","message":"校验失败"}                   — 报告错误
//   {"type":"done","success":true,"message":"升级完成"}     — 通知结束
//
// ── 可用 API ──────────────────────────────────────────────────────────────────
//
//   sendBytes(List<int> bytes)   — 通过串口发送字节数据
//   sendString(String text)      — 通过串口发送字符串
//   setProgress(double value)    — 设置进度条 (0.0 ~ 1.0)
//   log(String message)          — 输出日志信息
//   error(String message)        — 报告错误并终止
//   done(String message)         — 通知升级成功完成
//   awaitSerialData()            — 等待并返回串口收到的数据 (Future<List<int>>)
//   firmwareData                 — 固件二进制数据 (List<int>)
//
// ── 修改指南 ──────────────────────────────────────────────────────────────────
//
// 1. 修改 upgrade() 函数中的升级流程
// 2. 根据你的设备协议，调整命令格式、应答校验、分包大小等
// 3. 脚本可直接运行: dart run firmware_upgrade_template.dart
//
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ── 全局状态 ──────────────────────────────────────────────────────────────────

List<int> firmwareData = [];
final StreamController<List<int>> _serialDataController =
    StreamController<List<int>>.broadcast();

// ── API 函数 ──────────────────────────────────────────────────────────────────

/// 通过串口发送字节数据
void sendBytes(List<int> bytes) {
  final msg = jsonEncode({'type': 'send', 'data': base64Encode(bytes)});
  stdout.writeln(msg);
}

/// 通过串口发送字符串
void sendString(String text) {
  sendBytes(utf8.encode(text));
}

/// 设置进度条 (0.0 ~ 1.0)
void setProgress(double value) {
  final msg = jsonEncode({'type': 'progress', 'value': value});
  stdout.writeln(msg);
}

/// 输出日志信息
void log(String message) {
  final msg = jsonEncode({'type': 'log', 'message': message});
  stdout.writeln(msg);
}

/// 报告错误并终止
void error(String message) {
  final msg = jsonEncode({'type': 'error', 'message': message});
  stdout.writeln(msg);
}

/// 通知升级成功完成
void done(String message) {
  final msg = jsonEncode({'type': 'done', 'success': true, 'message': message});
  stdout.writeln(msg);
}

/// 等待串口数据，超时返回 null
Future<List<int>?> awaitSerialData({int timeoutMs = 3000}) async {
  try {
    return await _serialDataController.stream.first
        .timeout(Duration(milliseconds: timeoutMs));
  } on TimeoutException {
    return null;
  }
}

// ── 协议示例 ──────────────────────────────────────────────────────────────────
// 以下为一个简单的 YMODEM-like 升级协议示例。
// 请根据实际设备协议修改 upgrade() 函数。
// ─────────────────────────────────────────────────────────────────────────────

/// 升级入口 — 在此实现你的升级逻辑
Future<void> upgrade() async {
  log('固件大小: ${firmwareData.length} 字节');

  // ═══════════════════════════════════════════════════════════════════════════
  // 示例: 简单分包发送协议
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // 以下代码演示了一个简单的固件升级流程：
  //   1. 发送升级命令头（包含固件长度）
  //   2. 等待设备应答
  //   3. 分包发送固件数据
  //   4. 每包等待应答确认
  //   5. 发送结束标记
  //
  // 请根据你的设备协议替换以下逻辑。

  const int packetSize = 128; // 每包大小（根据设备要求调整）

  // 步骤1: 发送升级命令头
  log('发送升级命令...');
  final header = [
    0x55, 0xAA, // 起始标记
    0x01,       // 命令类型: 升级
    (firmwareData.length >> 24) & 0xFF,
    (firmwareData.length >> 16) & 0xFF,
    (firmwareData.length >> 8) & 0xFF,
    firmwareData.length & 0xFF,
  ];
  sendBytes(header);

  // 步骤2: 等待设备应答
  final ack = await awaitSerialData(timeoutMs: 2000);
  if (ack == null || ack.isEmpty) {
    error('设备未应答，升级中止');
    return;
  }
  log('设备应答: ${ack.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');

  // 步骤3: 分包发送固件数据
  int offset = 0;
  while (offset < firmwareData.length) {
    final end = (offset + packetSize > firmwareData.length)
        ? firmwareData.length
        : offset + packetSize;
    final packet = firmwareData.sublist(offset, end);

    // 发送数据包（添加包头标记）
    sendBytes([0x55, 0xAA, 0x02, ...packet]);

    // 等待应答
    final packetAck = await awaitSerialData(timeoutMs: 1000);
    if (packetAck == null || packetAck.isEmpty) {
      error('包 ${offset ~/ packetSize + 1} 应答超时，升级中止');
      return;
    }

    offset = end;
    setProgress(offset / firmwareData.length);
  }

  // 步骤4: 发送结束标记
  log('发送结束标记...');
  sendBytes([0x55, 0xAA, 0x03]);

  final endAck = await awaitSerialData(timeoutMs: 2000);
  if (endAck == null || endAck.isEmpty) {
    error('设备未确认结束，升级可能未完成');
    return;
  }

  done('固件升级完成！共发送 ${firmwareData.length} 字节');
}

// ── 主入口（请勿修改） ────────────────────────────────────────────────────────

void main() async {
  // 通知脚本已启动
  log('固件升级脚本已启动');

  // 监听 stdin
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        final type = msg['type'] as String;

        switch (type) {
          case 'firmware':
            firmwareData = base64Decode(msg['data'] as String);
            log('已接收固件数据: ${firmwareData.length} 字节');
            // 收到固件数据后开始升级
            upgrade().catchError((e) {
              error('升级异常: $e');
            });
            break;

          case 'serial':
            final data = base64Decode(msg['data'] as String);
            _serialDataController.add(data);
            break;

          case 'close':
            log('收到关闭信号');
            _serialDataController.close();
            exit(0);
        }
      } catch (e) {
        stderr.writeln('解析消息失败: $e, 原始数据: $line');
      }
    },
    onDone: () {
      _serialDataController.close();
    },
  );
}
