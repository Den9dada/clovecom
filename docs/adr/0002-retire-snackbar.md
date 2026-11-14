# 退役 SnackBar，统一反馈走四个呈现适配器

Status: accepted

"操作失败"曾以 5 种机制呈现（SnackBar、内联面板、状态栏、弹窗、DsToast），异步反馈不变量（防重入/清旧错/错误保留/mounted 守卫）被复制 ≥7 份，而深模块 DsDialogAction 零调用。决定退役 SnackBar，呈现适配器定为 DsDialog（确认/输入/进度/持久错误）、DsToast（瞬态）、内联面板（持久错误）、状态栏（状态语义）；业务侧只发语义事件，适配器负责映射。理由：DsDialog/DsToast 已是共享主题下的现成适配器（真实的缝），SnackBar 与 DsToast 语义重叠；统一后反馈不变量只住一处。

## Considered Options

- 保留 SnackBar 作第五个适配器：语义与 DsToast 重叠，呈现仍然分裂，病灶不除。

## Consequences

- 串口/固件/工具箱现有 SnackBar 全部改道；串口打开失败的 state.error 接入持久错误通道（修复静默失败）。
- 未来架构评审不应重新建议引入 SnackBar。