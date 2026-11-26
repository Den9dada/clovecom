/// 旧页面状态栏使用的展示词汇；实际网络生命周期由 CommunicationRuntime 管理。
/// 保留本枚举以兼容页面，旧 NetworkLinkController 已退出连接所有权。
enum LinkPhase {
  open,
  peerConnected,
  peerDisconnected,
  reconnecting,
  failed,
  closed,
}
