# 系统提示统一走 DsToast 浮层，退役内联持久错误面板

Status: accepted（取代 ADR-0002 的"内联面板（持久错误）"适配器与 DsDialog 持久错误角色）

用户真机实测串口后指令："所有的系统提示参考 clovertls 的提示弹窗的实现，而不是将提示夹杂在页内容里。" clovertls 的系统提示（错误/警告/成功，含"串口已拔出，升级已中断"）一律经 `showDsToast` 全局浮层呈现：窗口左下角、3 秒倒计时进度条、悬停暂停、单击淡出、同文同语义去重、剥离 `Bad state:`/`FormatException:` 前缀。持久错误的可见性由连接态（端口"未连接"）与接口占用浮窗等功能态补偿，而非把错误 banner 嵌进页面内容。clovecom 的 C2/ADR-0002 曾把持久错误做成内联面板，与 clovertls 分裂，且串口打开失败实际静默（端口栏不渲染 state.error）。决定：系统提示统一 DsToast 浮层（clovertls 对齐），退役内联持久错误面板。理由：DsToast 已是共享主题下与 clovertls 同源的现成适配器（真实的缝），统一后系统提示只住一处呈现 seam，错误归一化/去重不变量集中于宿主。

## Considered Options

- 保留内联持久 banner（ADR-0002 原决策）：错误常驻可见，但提示夹杂页面内容、与 clovertls 不一致，用户明确否定。
- 持久浮窗（仿 clovertls InterfaceStatusHost）：适用于接口占用等功能态清单，非事件提示；系统事件提示仍走 toast，二者不混用。

## Consequences

- 串口/固件视图移除 `_buildErrorBanner`，固件连接卡移除内联 `state.error` 红字。每条错误本已经 `errorStream→showDsToast`，移除内联不丢提示。
- `connect()` 空端口校验与打开失败统一经 `_setError→errorStream→toast`，真正修复串口打开失败静默；`state.error` 保留供连接态语义与测试，连接成功清 `_errorMessage`。
- `errorMessage` 字段保留为 VM 错误态测试面（升级测试断言），不再内联渲染。
- `ds_toast.show()` 同步 clovertls 的归一化＋去重。
- 权衡：toast 3 秒自动消失，持久错误可见性由连接态补偿（clovertls 同款）。若未来需要持久错误清单，应走功能态浮窗而非页面内联。
- 保留非事件提示的功能态内容：固件"协议有新版本"上下文 hint（绑定 hasNewVersion）、i2c 日志条目错误（日志记录）、工具箱规划状态面板（功能态）。
- 未来架构评审不应重新建议把系统提示内联到页面内容，亦不应重新引入 SnackBar（见 ADR-0002）。