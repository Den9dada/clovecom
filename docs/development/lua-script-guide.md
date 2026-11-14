# Lua 交互协议使用说明

适用 Lua 5.4.9、UTF-8 单文件协议，宿主接口版本 1.0。此处说明编写和使用流程、配置规则及场景示例；函数声明、参数和返回值见[API说明](lua-host-api.md)。

## 创建、保存与载入

1. 在协议编辑中切到“交互协议编辑”，新建普通交互、固件升级、固件打包或固件解析脚本，也可以导入 .lua 文件。
2. 修改并保存脚本。“校验”检查 Lua 语法和头部 JSON 配置，不执行 run，不连接设备，不能验证设备应答和协议流程逻辑。手动校验显示结果提示，错误明细可点击定位。
3. 数据源未连接且流程已释放时，在对应使用页选择协议并明确点击“载入”。只有这个动作会按脚本配置预填一次数据源参数。
4. 在界面检查并调整数据源参数，保存后连接。实际连接以界面最新保存参数为准，不回写脚本。连接、连接中和重连期间禁止修改物理接口参数。
5. 普通交互在数据源页开始；固件升级在设备升级页选择固件并开始，在线升级只使用明确载入的 Lua 脚本。

固件打包、解析为离线用途，不执行上述数据源载入和连接步骤。导入对应脚本后，直接在固件打包或解析页选择脚本、输入文件并执行。设备类型、编号、单／双固件形态及其他格式参数均在脚本代码中配置，页面不生成参数表单；脚本失败不会回退到内置协议。示例文件和配置步骤见 [Lua 固件打包与解析](../../protocols/firmware/README.md)。

保存只更新协议库内容，不替换已载入或排队任务使用的脚本快照。需要更新执行版本时，断开并等待释放，再明确重新载入。重启应用后需重新载入协议，已保存的数据源参数仍保留。导出包含编辑器当前草稿，允许保存、导出含错误的脚本，但含错误的脚本不能载入运行。

## 编写完整脚本

头部必须是前导 clovertls-config JSON 注释。脚本返回含 run 函数的表，入口由宿主调用；不要自行触发流程开始或结束。成功必须明确返回 status="success"，仅打印成功日志或上报 100% 进度不会使流程成功。

```lua
--[[clovertls-config
{
  "display_name": "设备查询",
  "runtime": "lua54",
  "host_api": "1.0",
  "purpose": "control",
  "transports": ["serial", "tcp"],
  "data_source": {
    "kind": "serial",
    "persistent": {
      "baud_rate": 115200, "data_bits": 8, "stop_bits": 1,
      "parity": "none", "flow_control": "none"
    }
  },
  "limits": {"run_timeout_ms": 30000}
}
]]
return {run=function(ctx)
  local reader = ctx.link:reader({mode="stream"})
  ctx.link:send(bytes.from_hex("01 02"))
  local reply = reader:read_exact(4, {deadline=ctx.time:after(1000)})
  ctx:log_bytes("info", "应答", reply)
  return {status="success", reply=reply:to_hex()}
end}
```

示例中的命令和应答长度需要按真实设备协议修改。流程参数（地址、超时、重试、步骤等）直接修改 Lua 代码，不支持 parameters 配置表单或 ctx.params。脚本在独立工作进程中运行，没有 io/os/package/debug/require，不直接读取任意文件；固件由宿主提供。

## 头部配置与数据源参数

purpose 必须为 control（普通交互）或 upgrade（固件升级）；runtime 为 lua54，host_api 为 1.0。transports 声明适用的 serial/tcp/udp 类型。头部只做静态读取，不执行脚本来获取配置。

data_source.persistent 为载入时预填的物理接口参数，支持 serial_port、baud_rate、data_bits、stop_bits、parity、flow_control、host、port、remote_host、remote_port。parity 支持 none/odd/even/mark/space；flow_control 支持 none/rts_cts/dtr_dsr/xon_xoff。UDP 的 host/port 为本地绑定地址，remote_host/remote_port 为固定远端，远端配置需成对提供。

data_source.runtime_initial 形如 {"serial":{"rts":true,"dtr":false}}，在每次开始时按实际能力设置，结束/停止后恢复原基线，不保存到项目。CTS/DSR/RI/CD 为输入信号，只能读取；RTS/DTR 受流控管理或无法读取原基线时禁止写入。

required_capabilities 声明开始前必须具备的能力，例如 link.raw、link.channel、data_source.config.read、data_source.runtime.read、data_source.runtime.serial.lines、input.firmware。可选功能先用 has_capability 查询。升级配置可声明 upgrade.owns_device_liveness（由脚本判定存活）及 upgrade.supports_direct（允许直传）。

## 选择原始读取或通道成帧

同一运行只能创建一个接收所有者：reader 或 channel，不得同时创建或关闭后换用另一个。被动协议解析和原始数据日志可以继续运行。

串口/TCP 可用 stream reader，自己决定要读取的字节数；read_some 返回当前可读的部分，read_exact 等待指定长度，read_until 等待分隔符。read_exact 超时时保留已缓存的半包。丢弃缓冲必须显式说明原因，不应靠定期清空缓冲来掩盖协议错误。

UDP 必须按 packet 读取，或使用 datagram 通道。一个 UDP 数据报不能被拼入另一个数据报。发送目标固定为配置远端或启动时确定的设备；其它设备上报不会改变运行中的目标，不能用 send_to 临时改变目的地址。

常见结构化协议优先用 channel：固定长度选 fixed；前导长度选 length_prefix；帧内长度字段选 length_field；结束分隔符选 delimiter；特殊协议选 custom。custom 解析器区分 need_more、discard 和 frame，并返回精确的 consumed 字节数；对半包返回 need_more，不要误丢弃。

## 请求应答、超时和重试

```lua
local ch = ctx.link:channel({
  framer={kind="length_prefix", width=2, endian="be"}
})
local response = ch:exchange(bytes.from_hex("01 02"), {
  deadline=ctx.time:after(5000),
  attempt_timeout_ms=1000,
  retry={max_attempts=3, safety="idempotent", backoff_ms=100},
  match=function(frame) return frame.data:u8(0)==0x81 end
})
ctx:log_bytes("info", "匹配应答", response.data)
```

片段放在 run(ctx) 内使用。exchange 必须提供总期限和匹配器。匹配器应校验功能码、事务序号、地址等，不能仅因收到任意数据就判定成功。每个通道同时只能有一个请求应答事务。

max_attempts 包含首次发送，默认 1。多次尝试必须声明请求幂等（idempotent）或协议具有去重保证（deduplicated）。发送完成只表示传输层写入，不代表设备确认；OutcomeUnknown 表示设备可能已经执行，不能无条件重发有副作用的命令。接收水位会隔离已存在的数据，但无法代替协议事务编号来区分延迟应答。

时间单位为毫秒。用 ctx.time:after 创建期限句柄，不能自行构造时间表，也不要用 now() 的观察值充当期限。每个等待同时受操作期限与流程总期限限制。try_next 只把 Timeout 转成 nil，其它错误会继续抛出。

## 二进制数据与校验

所有 Bytes 偏移从 0 开始，长度按字节计。Bytes 不可变，不等同 Lua 文本；列表及 unpack 返回的 values 使用 Lua 的 1 起始索引。

```lua
local header = bytes.pack(">I2I4", 16, 1024)
local payload = bytes.from_hex("01 02 03 04")
local body = bytes.concat({header, payload})
local crc = checksum.compute("crc16_modbus", body)
local packet = bytes.concat({body, bytes.pack("<I2", crc)})
```

打包格式必须显式指定大小端；数据顺序和 CRC 字段字节序需按协议原文确定。校验覆盖范围由传入的 Bytes 或切片决定。通道可配置 checksum 自动添加和验证负载尾部校验；覆盖头部或特殊字段时应自行构建与检查，点表脚本使用 custom 解析。

64 位值使用 Lua 整数位模式，超过有符号整数范围时按位或分段处理，不转成浮点以免损失精度。

## 数据源查询和运行时控制

先通过 describe 获取实际数据源类型及运行时控制能力，再用 get_config 查看连接建立时固定的参数。脚本没有持久配置写接口，物理参数只能在未连接且流程释放后由用户在界面修改。

```lua
local config = ctx.data_source:get_config()
ctx:log("info", "当前数据源", {kind=config.kind})
local state = ctx.data_source:get_runtime(nil, {deadline=ctx.time:after(1000)})
ctx:log("info", "运行时状态", state.values)
-- 确认支持、未受流控接管且可恢复基线后，才能设置控制线。
-- ctx.data_source:set_runtime({serial={rts=true}}, {deadline=ctx.time:after(1000)})
```

get_runtime 当前返回全部可用值，keys 仅作预留过滤参数。无法读取的字段在 unavailable 中列出；不能把缺失值当 false。控制线恢复失败时，数据源仍保持占用，需要断开处理。

## 固件、进度和日志

升级脚本由 ctx.inputs.firmware 获取只读固件快照。普通交互没有此输入，读取前检查 input.firmware 能力。固件不暴露路径，不支持任意文件系统访问。

```lua
ctx:require_capability("input.firmware")
local fw = ctx.inputs.firmware
local info = fw:info()
for block in fw:chunks({chunk_bytes=1024}) do
  ctx:check_cancelled()
  -- 用 block.offset / block.data 构建协议帧并等待设备确认。
  -- 确认后才能上报相应完成量；读取固件本身不等于升级成功。
end
ctx:log("info", "固件读取结束", {size=info.size})
```

chunks 的 chunk_bytes 必须指定，每次返回 offset 和 data，最后一块可以更短。按设备确认的字节数或步骤上报进度，避免逐字节刷新日志。completed 和 total 需同时提供且为整数，0 <= completed <= total；total=0 不更新百分比。只上报阶段信息时可以省略两者。

```lua
ctx:progress({completed=3, total=10, stage="write", message="已确认 3 块"})
ctx:log("info", "等待应答", {attempt=1, address=16})
ctx:log_bytes("debug", "接收", bytes.from_hex("01 02"), {max_bytes=128})
```

进度 100% 后仍须检查设备最终完成应答，再明确返回成功。日志单项超过 4096 字符时截断，普通交互显示最近 500 条；高频日志可能触发请求速率限制。

## 错误处理、停止和资源限制

宿主错误通常是 {code,message,details} 表，Lua assert/error 也可能产生字符串。pcall 后先判断类型，只有明确可恢复的错误才处理后继续，其它错误应重新抛出。

```lua
local ok, result = pcall(function()
  return ch:next({deadline=ctx.time:after(1000)})
end)
if not ok then
  if type(result)=="table" and result.code=="Timeout" then
    ctx:log("warning", "等待应答超时")
  else
    error(result, 0)
  end
end
```

片段假设已创建 ch。Timeout 为等待超时；OutcomeUnknown 表示结果不确定；Cancelled/SessionLost 应结束运行；ChecksumMismatch/InvalidFrame 应检查协议和校验范围；OwnershipConflict 表示重复创建接收所有者；BufferOverflow/ResourceLimit 应检查帧长度、缓冲和批量大小。具体参数、返回结构和错误声明见“API说明”。

ctx:fail 会锁存失败，不能靠 pcall 吞掉后返回成功。停止先撤销发送权限，再终止计算进程，等待在途发送与控制线恢复后才释放数据源。正常完成或取消不主动断开物理连接。

源码和单个 Bytes 最大 1 MiB；单帧、单次发送和固件单块读取最大 65536 字节；接收/成帧队列总字节预算 1 MiB，最多 4096 项；结果最大 64 KiB。进程内存预算 128 MiB，连续计算预算 2000 万 Lua 指令。流程总期限默认 1 小时，可用头部 limits.run_timeout_ms 设置为 1～86400000 毫秒。超限会显式失败。

内置可编辑的点表 Lua 示例与内置实现保持帧格式和完成判据一致，默认 10 秒 ACK、10 秒静默、启动最多三次重传。实际调节直接修改脚本常量。
