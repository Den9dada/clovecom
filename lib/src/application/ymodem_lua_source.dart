// 与 assets/protocols/ymodem.lua 保持一致。
const ymodemLuaSource = r'''--[[clovertls-config
{
  "display_name": "标准 YMODEM 固件升级",
  "runtime": "lua54",
  "host_api": "1.0",
  "purpose": "upgrade",
  "transports": ["serial"],
  "required_capabilities": ["input.firmware", "link.raw"],
  "upgrade": {"owns_device_liveness": true, "supports_direct": true}
}
]]
-- 标准单文件 YMODEM 批传输：文件头 -> 数据 -> EOT -> 空文件名结束块。
-- 流程参数只在脚本中配置；数据块间不增加人为发送间隔。
local DATA_BYTES = 1024 -- 可改为 128；不支持 YMODEM-g。
local START_TIMEOUT_MS = 60000
local ACK_TIMEOUT_MS = 10000
local MAX_ATTEMPTS = 10
local SOH, STX, EOT, ACK, NAK, CAN, C = 1, 2, 4, 6, 21, 24, 67

local function crc16(data)
  local crc = 0
  for i = 1, #data do
    crc = crc ~ (data:byte(i) << 8)
    for _ = 1, 8 do
      crc = ((crc << 1) ~ ((crc & 0x8000) ~= 0 and 0x1021 or 0)) & 0xffff
    end
  end
  return crc
end

local function block(sequence, data, size, pad, crc_mode)
  data = data .. string.rep(string.char(pad), size - #data)
  local trailer
  if crc_mode then
    trailer = string.pack('>I2', crc16(data))
  else
    local sum = 0
    for i = 1, #data do sum = (sum + data:byte(i)) & 255 end
    trailer = string.char(sum)
  end
  return bytes.from_string(string.char(size == 1024 and STX or SOH,
    sequence & 255, 255 - (sequence & 255)) .. data .. trailer)
end

local function run(ctx)
  assert(DATA_BYTES == 128 or DATA_BYTES == 1024, '数据块必须为 128 或 1024 字节')
  local firmware = ctx.inputs.firmware
  local info = firmware:info()
  local size = info.size
  local name = (info.display_name or ''):gsub('\\', '/'):match('([^/]+)$')
  if not name or name:find('[^!-~]') or #name + #tostring(size) + 2 > 128 then
    name = 'firmware.bin'
  end
  name = name:lower()
  local reader = ctx.link:reader()

  local function wait_control(wanted, timeout)
    local deadline, cancelled = ctx.time:after(timeout), 0
    while true do
      local ok, data = pcall(reader.read_exact, reader, 1, {deadline = deadline})
      if not ok then
        if type(data) == 'table' and data.code == 'Timeout' then return nil end
        error(data, 0)
      end
      local value = data:u8(0)
      if value == CAN then
        cancelled = cancelled + 1
        if cancelled >= 2 then error({code='RemoteCancelled', message='接收端取消传输'}, 0) end
      else
        cancelled = 0
        if wanted[value] then return value end
      end
    end
  end

  local function transmit(packet, phase)
    for attempt = 1, MAX_ATTEMPTS do
      ctx.link:send(packet, {deadline=ctx.time:after(ACK_TIMEOUT_MS)})
      if wait_control({[ACK]=true, [NAK]=true}, ACK_TIMEOUT_MS) == ACK then return end
      ctx:log('warning', phase .. '等待确认失败，准备重传', {attempt=attempt})
    end
    error({code='RetryExhausted', message=phase .. '重传次数耗尽'}, 0)
  end

  local function transfer()
    ctx:log('info', '等待接收端请求 YMODEM 传输')
    local mode = wait_control({[C]=true, [NAK]=true}, START_TIMEOUT_MS)
    if not mode then error({code='HandshakeTimeout', message='未收到接收端传输请求'}, 0) end
    local crc_mode = mode == C
    transmit(block(0, name .. '\0' .. tostring(size) .. '\0', 128, 0, crc_mode), '文件头')
    local data_mode = wait_control({[C]=true, [NAK]=true}, ACK_TIMEOUT_MS)
    if not data_mode then error({code='HandshakeTimeout', message='未收到数据阶段请求'}, 0) end
    crc_mode = data_mode == C
    local offset, sequence = 0, 1
    while offset < size do
      local count = math.min(DATA_BYTES, size - offset)
      local data = firmware:read(offset, count):to_string()
      transmit(block(sequence, data, DATA_BYTES, 0x1a, crc_mode), '数据块 ' .. sequence)
      offset, sequence = offset + count, (sequence + 1) & 255
      ctx:progress({completed=offset, total=size, stage='transfer'})
    end
    -- 接收端可直接 ACK EOT，也可先 NAK 再 ACK 第二次 EOT。
    transmit(bytes.from_string(string.char(EOT)), '结束握手')
    local final_mode = wait_control({[C]=true, [NAK]=true}, ACK_TIMEOUT_MS)
    if not final_mode then error({code='HandshakeTimeout', message='未收到批传输结束请求'}, 0) end
    transmit(block(0, '', 128, 0, final_mode == C), '空文件名结束块')
    ctx:progress({completed=size, total=size, stage='complete', message='YMODEM 传输完成'})
    return {status='success', bytes_sent=size, file_name=name}
  end

  local ok, result = pcall(transfer)
  if not ok then
    -- 协议失败时通知对端；宿主取消后发送权限已撤销，此处不会越过取消边界。
    pcall(ctx.link.send, ctx.link, bytes.from_hex('1818'), {deadline=ctx.time:after(1000)})
    if type(result) == 'table' then
      ctx:fail(result.code or 'YmodemFailed', result.message or 'YMODEM 升级失败')
    end
    ctx:fail('YmodemFailed', tostring(result))
  end
  return result
end
return {run=run}
''';
