// 接口通信字节传输层抽象
//
// 对齐 ADR-0004：借鉴 clovertls 的 ByteTransport 抽象范式（chunks Stream +
// send + close），管理层由 clovecom 自研。串口、TCP客户端、TCP服务端、UDP
// 均实现本接口；未来文件传输/固件升级若接入网络接口，应接在本层而非管理层。

import 'dart:typed_data';

/// 传输生命周期事件（供 UI 状态与日志使用，与字节数据流分离）。
enum TransportEventType {
  /// 本地信道已就绪（TCP已连接 / UDP已绑定 / 服务端已监听）
  opened,

  /// 服务端接受了一个客户端连接（单客户端语义，见 ADR 决策 Q19）
  peerConnected,

  /// 对端断开（服务端回到等待状态；客户端进入重连或关闭）
  peerDisconnected,

  /// 不可用事件后进入重连等待（仅 TCP 客户端且开启自动重连）
  reconnecting,

  /// 信道已关闭
  closed,

  /// 传输错误；detail 为可读原因
  error,
}

class TransportEvent {
  const TransportEvent(this.type, [this.detail]);

  final TransportEventType type;
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'TransportEvent(${type.name})' : 'TransportEvent(${type.name}, $detail)';
}

/// 单次通信接口会话的字节通道；关闭后禁止复用。
abstract interface class ByteTransport {
  /// 接收字节流（broadcast，允许多订阅者：收发管线与预览）
  Stream<Uint8List> get chunks;

  /// 生命周期事件流
  Stream<TransportEvent> get events;

  /// 发送原始字节；失败抛异常
  Future<void> send(Uint8List bytes);

  /// 关闭信道并结束所有流；幂等
  Future<void> close();
}
