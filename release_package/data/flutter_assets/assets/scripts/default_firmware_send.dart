// ============================================================================
// 默认固件发送脚本
// ============================================================================
//
// 本脚本由 CloveCom 串口助手的"固件升级"功能在未选择自定义脚本时自动调用。
// 发送逻辑与"文件发送"一致：按固定包大小分包发送，可配置包大小和发送间隔。
//
// 用法: dart run default_firmware_send.dart <firmware_path> [packet_size] [interval_ms]
//
// 通信协议（stdin/stdout JSON）：
//   发送: {"type":"send","data":"<base64>"}
//   进度: {"type":"progress","value":0.75}
//   日志: {"type":"log","message":"..."}
//   错误: {"type":"error","message":"..."}
//   完成: {"type":"done","success":true,"message":"..."}
//
// ============================================================================

import 'dart:convert';
import 'dart:io';

void sendMsg(Map<String, dynamic> msg) {
  stdout.writeln(jsonEncode(msg));
}

void log(String message) => sendMsg({'type': 'log', 'message': message});
void error(String message) => sendMsg({'type': 'error', 'message': message});
void done(String message) =>
    sendMsg({'type': 'done', 'success': true, 'message': message});
void progress(double value) => sendMsg({'type': 'progress', 'value': value});

void main(List<String> args) async {
  if (args.isEmpty) {
    error('缺少固件文件路径参数');
    return;
  }

  final firmwarePath = args[0];
  final packetSize = args.length > 1 ? int.tryParse(args[1]) ?? 1024 : 1024;
  final intervalMs = args.length > 2 ? int.tryParse(args[2]) ?? 100 : 100;

  log('默认固件发送脚本已启动');
  log('固件路径: $firmwarePath');
  log('每包大小: ${packetSize}B, 间隔: ${intervalMs}ms');

  // 读取固件文件
  final file = File(firmwarePath);
  if (!await file.exists()) {
    error('固件文件不存在: $firmwarePath');
    return;
  }

  final firmwareBytes = await file.readAsBytes();
  log('固件大小: ${firmwareBytes.length} 字节');

  if (firmwareBytes.isEmpty) {
    error('固件文件为空');
    return;
  }

  // 分包发送
  int offset = 0;
  int packetIndex = 0;

  while (offset < firmwareBytes.length) {
    final end =
        (offset + packetSize > firmwareBytes.length)
            ? firmwareBytes.length
            : offset + packetSize;

    final packet = firmwareBytes.sublist(offset, end);
    sendMsg({'type': 'send', 'data': base64Encode(packet)});

    packetIndex++;
    offset = end;
    progress(offset / firmwareBytes.length);

    // 等待发送间隔
    if (offset < firmwareBytes.length) {
      await Future.delayed(Duration(milliseconds: intervalMs));
    }
  }

  done('固件发送完成！共 ${firmwareBytes.length} 字节，$packetIndex 包');
}
