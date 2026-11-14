# 串口双栈以新 src 词汇为准，strangler 收拢所有权

Status: accepted

串口配置长期存在旧 SerialPortConfig 与新 src/io ConnectionConfig 两套词汇，靠两份手写映射缝合，且串口页与固件升级页各持一份连接所有权。决定以新 src 栈词汇为准，旧配置降为视图层适配；连接所有者先以 strangler 方式包住现有 VM，翻译收拢到唯一一处缝，不一次性重写。理由：迁移方向本就朝 lib/src＋lib/ui，strangler 风险最低，且让"串口传输会话"一端口一任务不变量立即跨页成立。

## Considered Options

- 旧栈为准、新栈适配旧栈：逆迁移方向，旧 VM 1486 行成为长期中心。
- 长期双栈、只收拢翻译缝：所有权重复的病灶仍在，跨页独占无法成立。

## Consequences

- 旧 VM 逐步降为收发面适配器；新增 parity/flowControl 取值只改一处映射。
- 未来架构评审不应重新建议"以旧栈为准"或"保留双所有权"。