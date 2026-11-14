# Lua 交互协议 API 1.0

适用 Lua 5.4.9。本文只列接口声明、简介、传入参数、返回值和接口约束；操作步骤、场景示例见[使用说明](lua-script-guide.md)。

Bytes 为不可变二进制值；integer 为 Lua 整数，boolean 为布尔值，table 为 Lua 表。Bytes/固件偏移从 0 开始，Lua 列表从 1 开始。opts? 表示可省略的选项表，通用字段 deadline? 为 ctx.time:after 返回的期限句柄；所有时间单位为毫秒。无返回值记为“无”，不应依赖其内部表示。未指定操作期限时仍受本次流程总期限限制。

## 脚本入口与上下文属性

脚本用途支持 `control`（普通交互）、`upgrade`（在线升级）、`pack`（离线固件打包）和 `unpack`（离线固件解析）。后两类无需绑定数据源；格式参数在脚本中配置。输入与分段输出约定及可导入示例见 [Lua 固件打包与解析](../../protocols/firmware/README.md)。

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `run(ctx)` | 脚本返回表中的执行入口，由宿主调用 | ctx：本次运行上下文 | 可序列化结果表；status 必须为 "success" 才判定成功；结果上限 64 KiB |
| `ctx.api_version` | 宿主接口版本，只读 | 无 | string，当前 "1.0" |
| `ctx.target` | 目标设备或输入文件信息，只读 | 无 | 在线升级含可用的 kind、device_id；离线固件处理含 size_a、size_b |
| `ctx.inputs` | 宿主输入，只读 | 无 | table；升级、离线打包及解析时含 firmware 句柄，普通交互不含该字段 |
| `ctx.limits` | 本次资源限制，只读 | 无 | table，字段见“资源限制字段” |
| `ctx.capabilities` | 本次能力快照，只读 | 无 | 按能力名称索引的布尔表 |

## 延时、取消与能力

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `ctx:sleep(ms, opts?)` | 可取消延时 | ms：integer，0～86400000；opts.deadline? | 无；超时或执行失效时抛错 |
| `ctx:yield()` | 让出执行，相当于 0 毫秒延时 | 无 | 无 |
| `ctx:check_cancelled()` | 检查执行是否仍有效 | 无 | 无；停止或会话失效时抛错 |
| `ctx:is_cancelled()` | 查询执行有效性检查是否失败 | 无 | boolean；检查失败为 true |
| `ctx:has_capability(name)` | 查询能力 | name：string | boolean |
| `ctx:require_capability(name)` | 要求能力存在 | name：string | 无；缺失时抛 CapabilityDenied |
| `ctx.time:now()` | 读取运行内单调时间 | 无 | 只读表 {milliseconds=integer}，不是 deadline 句柄 |
| `ctx.time:after(ms)` | 创建操作期限 | ms：integer，0～86400000 | Deadline 句柄，仅当前运行有效 |
| `ctx.time:remaining_ms(deadline)` | 查询剩余时间 | deadline：有效期限句柄 | integer，大于等于 0 |
| `ctx.time:min(a, b)` | 选择较早期限 | a、b：有效期限句柄 | Deadline 句柄 |

## 进度、日志与失败

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `ctx:progress(value)` | 上报进度与阶段 | value：table；completed?/total? 须同时提供且为整数，0 <= completed <= total <= 9007199254740991；stage?/message?：文本；total=0 不更新百分比 | 无 |
| `ctx:log(level, message, fields?)` | 输出日志 | level、message：文本，建议 debug/info/warning/error；fields?：可序列化表；单项最多展示 4096 字符 | 无 |
| `ctx:log_bytes(level, label, data, opts?)` | 输出有界 Hex 日志 | data：Bytes；level/label：文本；opts.max_bytes? 默认 256，实际不超过日志上限的一半 | {logged_bytes=integer, truncated=boolean} |
| `print(...)` | 输出 info 级文本日志 | 任意可转文本的值，以制表符连接 | 无 |
| `ctx:fail(code, message, details?)` | 锁存不可逆失败并撤销运行权限 | code、message：文本；details?：可序列化表 | 不正常返回；失败不能被 pcall 撤销 |

## 字节构造与编解码

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `bytes.from_string(binary)` | 从 Lua 二进制字符串构造 | binary：string | 新 Bytes |
| `bytes.from_utf8(text)` | 从 UTF-8 文本构造 | text：有效 UTF-8 string | 新 Bytes；编码无效时报错 |
| `bytes.from_hex(text)` | 从 Hex 文本构造 | text：string；允许空白，去空白后长度为偶数且仅含十六进制字符 | 新 Bytes |
| `bytes.from_base64(text)` | 从 Base64 构造 | text：Base64 string | 新 Bytes；格式无效时报错 |
| `bytes.concat(parts)` | 连接字节列表 | parts：按 1 起始索引的 Bytes 列表，总长不超过 1 MiB | 新 Bytes |
| `bytes.pack(format, ...)` | 按格式打包 | format：显式以 < 或 > 开头；禁止平台相关格式 =/j/J/T/n；后续参数为待打包值 | 新 Bytes |
| `bytes.unpack(format, data, offset?)` | 按格式解包 | format：规则同 pack；data：Bytes；offset：integer，默认 0 | {values=值列表, next_offset=下次读取的 0 起始偏移} |
| `data:len()` / `#data` | 获取长度 | data：Bytes | integer，字节数 |
| `data:slice(offset, length)` | 获取指定字节范围 | offset/length：integer，须位于 data 范围内 | 新 Bytes |
| `data:equals(other)` | 比较字节内容 | other：Bytes；非 Bytes 返回 false | boolean |
| `data:to_string()` | 导出原始二进制字符串 | 无 | Lua string |
| `data:to_utf8()` | 导出 UTF-8 文本 | 无 | string；编码无效时报错 |
| `data:to_hex()` | 导出 Hex 文本 | 无 | 大写、无空格的 string |
| `data:to_base64()` | 导出 Base64 文本 | 无 | string |

## 数值读取与校验

以下 data 为 Bytes，offset 为 0 起始字节偏移，读取范围不得越界。le 表示小端，be 表示大端。每个声明均是实际可调用的方法。

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `data:u8(offset)` / `data:i8(offset)` | 读取 8 位无符号/有符号整数 | offset：integer | integer |
| `data:u16_le(offset)` / `data:u16_be(offset)` | 读取 16 位无符号整数 | offset：integer | integer |
| `data:i16_le(offset)` / `data:i16_be(offset)` | 读取 16 位有符号整数 | offset：integer | integer |
| `data:u32_le(offset)` / `data:u32_be(offset)` | 读取 32 位无符号整数 | offset：integer | integer |
| `data:i32_le(offset)` / `data:i32_be(offset)` | 读取 32 位有符号整数 | offset：integer | integer |
| `data:u64_le(offset)` / `data:u64_be(offset)` | 读取 64 位无符号整数位模式 | offset：integer | Lua integer 位模式，超过有符号上限不转成浮点 |
| `data:i64_le(offset)` / `data:i64_be(offset)` | 读取 64 位有符号整数 | offset：integer | integer |
| `data:f32_le(offset)` / `data:f32_be(offset)` | 读取 32 位浮点数 | offset：integer | number |
| `data:f64_le(offset)` / `data:f64_be(offset)` | 读取 64 位浮点数 | offset：integer | number |
| `checksum.compute(profile, data)` | 计算校验值 | profile：crc16_modbus/sum8/xor8；data：覆盖范围的 Bytes | integer |
| `checksum.verify(profile, data, expected)` | 验证校验值 | profile/data：同 compute；expected：integer | boolean |

## 原始链路与读取器

每次运行只允许一个 reader 或 channel 接收所有者，重复创建抛 OwnershipConflict；close 不重置所有权。

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `ctx.link:info()` | 查询链路快照 | 无 | 只读 table，含 transport、session_id、datagram、peer 等链路信息 |
| `ctx.link:reader(opts?)` | 创建原始读取器 | opts.mode：stream/packet；串口/TCP 默认 stream，UDP 默认且仅支持 packet | Reader |
| `ctx.link:send(data, opts?)` | 在原始读取模式发送 | data：Bytes，最多 65536 字节；opts.deadline?；必须已创建 reader | 发送收据 {write_id, accepted_bytes, completion_layer="transport_write", completed_at} |
| `ctx.link:send_to(data, peer, opts?)` | 指定对端发送的预留接口 | 当前版本不接受非空 peer，指定时抛 CapabilityDenied | 无可用的指定对端发送结果 |
| `ctx.link:drain(opts?)` | 等待宿主在途写完成 | opts.deadline? | {completion_layer="host_queue"}，不代表设备 ACK |
| `reader:read_some(max_bytes, opts?)` | 读取当前可用的部分字节 | 仅 stream；max_bytes：1～max_rx_bytes；opts.deadline? | 非空 Bytes，长度最多 max_bytes |
| `reader:read_exact(n, opts?)` | 等待并读取精确长度 | 仅 stream；n：0～max_rx_bytes；opts.deadline? | 长度为 n 的 Bytes；超时保留半包 |
| `reader:read_until(delimiter, opts?)` | 读取到指定分隔符 | 仅 stream；delimiter：非空 Bytes；opts.deadline?、max_bytes?（默认 max_frame_bytes）、include_delimiter?（默认 true） | Bytes；分隔符始终从缓冲消耗 |
| `reader:next(opts?)` | 读取一个接收块/数据报 | 仅 packet；opts.deadline? | Packet，字段见“返回结构” |
| `reader:discard_buffer(opts)` | 丢弃本地和宿主接收缓冲 | opts.reason：必填丢弃原因文本 | {bytes=丢弃字节总数, packets=宿主队列块数} |
| `reader:close()` | 关闭读取器并清本地缓存 | 无 | 无；不关闭物理连接 |

## 通道成帧与请求应答

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `ctx.link:channel(config)` | 创建成帧通道 | config.framer：Framer；max_frame_bytes? 默认 65536；max_buffer_bytes? 默认 1048576；assembly_timeout_ms? 默认 10000；checksum?={profile,wire_endian}；invalid_frame?="discard" 可最多连续丢弃 128 个坏帧，默认报错 | Channel |
| `channel:send(data, opts?)` | 编码并发送通道负载 | data：Bytes；opts.deadline? | 发送收据，结构同 link:send |
| `channel:next(opts?)` | 读取下一完整帧 | opts.deadline? | Frame；超时抛 Timeout |
| `channel:try_next(opts?)` | 尝试读取完整帧 | opts.deadline? | Frame；仅 Timeout 返回 nil，其它错误继续抛出 |
| `channel:exchange(data, opts)` | 单事务发送并等待匹配应答 | data：Bytes；opts.deadline 与 match(frame) 必填；attempt_timeout_ms? 默认 10000；retry? 见下表 | 匹配的 Frame；已发送而未确认时可能抛 OutcomeUnknown |
| `channel:close()` | 关闭通道并清缓存 | 无 | 无；不关闭物理连接 |

| Framer kind / 参数 | 定义 |
| --- | --- |
| `fixed` | size：固定帧字节数 |
| `length_prefix` | width：1/2/4；endian：le/be；长度为前缀后 wire body 字节数，不含前缀 |
| `length_field` | offset、width、endian、adjustment：总长=长度字段值+adjustment；payload_offset? 为提取负载偏移 |
| `delimiter` | delimiter：非空 Bytes；include_delimiter?：默认 true |
| `datagram` | UDP 一个数据报一帧 |
| `custom` | parse(buffer: Bytes)：返回 {kind="need_more"}、{kind="discard",consumed=n} 或 {kind="frame",consumed=n,payload=Bytes} |

| exchange 选项 | 定义 |
| --- | --- |
| `match(frame)` | 必须返回 boolean；函数抛错为 MatcherError |
| `retry.max_attempts` | 包含首次的尝试总次数，默认 1，范围 1～16 |
| `retry.safety` | 多次尝试时必填 idempotent 或 deduplicated |
| `retry.backoff_ms` | 指数退避基数，默认 0 |
| `retry.max_backoff_ms` | 退避上限，默认 10000 |
| `retry.jitter` | 可选 boolean，为 true 时加入随机退避 |

## 数据源配置与运行时状态

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `ctx.data_source:describe()` | 查询数据源能力 | 无 | 只读 {source_id,kind,runtime_schema,config_access="read",persistent_writes=false} |
| `ctx.data_source:get_config()` | 查询本次连接的物理参数 | 无 | 只读 {source_id,config_revision,kind,interface} |
| `ctx.data_source:get_runtime(keys?, opts?)` | 查询运行时状态 | keys：预留参数，当前返回全部可用值；opts.deadline? | 只读 {session_id,observed_at,values,provenance,unavailable}；values.serial 含可读信号 |
| `ctx.data_source:set_runtime(patch, opts?)` | 写运行时控制 | patch：{serial={rts=boolean?,dtr=boolean?}}；opts.deadline?；仅可写、未被流控接管且可恢复基线的控制线 | 只读运行时设置收据，含 applied 等字段 |

CTS/DSR/RI/CD 只读。物理接口参数没有写接口；写入被流控接管的控制线抛 SettingManagedByDriver，不支持或无法建立恢复基线时抛 UnsupportedSetting。

## 固件输入

| 声明 | 简介 | 传入参数 | 返回值 |
| --- | --- | --- | --- |
| `ctx.inputs.firmware:info()` | 查询固件快照信息 | 无；要求存在固件输入 | 只读 {id,display_name,size} |
| `ctx.inputs.firmware:read(offset, length, opts?)` | 读取固件范围 | offset：0 起始偏移；length：0～65536，范围不得越界；opts.deadline? | Bytes |
| `ctx.inputs.firmware:chunks(opts)` | 获取分块迭代器 | opts.chunk_bytes：必填，1～65536；offset? 默认 0；length? 默认从 offset 到末尾；deadline? | 迭代函数，每次返回 {offset=integer,data=Bytes}，结束返回 nil |

## 返回结构

| 类型 / 字段 | 定义 |
| --- | --- |
| `Packet` | bytes：Bytes；datagram：boolean；peer：对端信息；rx_seq：接收序号；session_id：会话；first_received_at、last_received_at：接收时间 |
| `Frame` | data：Bytes 负载；rx_seq、first_rx_seq：接收序号；peer、session_id、first_received_at、last_received_at：来源及时间 |
| `WriteReceipt` | write_id：发送标识；accepted_bytes：字节数；completion_layer：完成层级；completed_at：运行内完成时间 |
| `RuntimeState` | session_id：会话；observed_at：观测时间；values：可用值；provenance：来源；unavailable：不可读取的字段名称列表 |
| `Error` | code、message、details?；Lua 自身错误也可能为 string |

## 资源限制字段

| ctx.limits 字段 | 当前值 |
| --- | --- |
| `max_frame_bytes` | 65536，最大帧字节数 |
| `max_rx_bytes` | 1048576，接收与成帧队列字节预算 |
| `max_queued_frames` | 4096，队列项数上限 |
| `max_write_bytes` | 65536，单次发送字节上限 |
| `max_artifact_read_bytes` | 65536，固件单次读取字节上限 |
| `max_log_entry_bytes` | 4096，日志条目预算 |

## 错误码

| code | 简介 |
| --- | --- |
| `Timeout` | 操作期限已到 |
| `OutcomeUnknown` | 数据可能已发送或执行，无法确认结果 |
| `Cancelled` / `SessionLost` | 执行权限撤销或物理会话失效 |
| `CapabilityDenied` / `DestinationUnavailable` | 能力缺失或 UDP 无固定对端 |
| `ConfigReadOnly` / `SettingReadOnly` | 尝试写物理参数或只读信号 |
| `SettingManagedByDriver` / `UnsupportedSetting` | 控制线被流控接管或当前操作不受支持 |
| `BufferOverflow` / `ResourceLimit` | 缓冲、队列、计算、时间或其它预算超限 |
| `ChecksumMismatch` / `InvalidFrame` / `MatcherError` | 校验、帧格式或匹配函数错误 |
| `OwnershipConflict` | 重复创建接收所有者 |
| `RangeError` / `InvalidArgument` | 偏移、长度或参数不合法 |
| `RuntimeUnavailable` / `ScriptError` / `HostError` | 运行时不可用、脚本异常或宿主操作失败 |
