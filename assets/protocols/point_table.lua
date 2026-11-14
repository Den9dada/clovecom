--[[clovertls-config
{
  "display_name": "点表协议-Lua固件升级",
  "runtime": "lua54",
  "host_api": "1.0",
  "purpose": "upgrade",
  "transports": ["serial", "tcp", "udp"],
  "required_capabilities": ["input.firmware"],
  "upgrade": {"owns_device_liveness": true, "supports_direct": true}
}
]]
-- 与内置点表保留相同帧和完成判据；流程调节直接修改下面的常量。
local ACK_TIMEOUT_MS = 10000
local IDLE_TIMEOUT_MS = 10000
local MAX_RETRANSMITS = 3

local function frame(config, func, payload)
  local body = bytes.concat({bytes.pack('>I1', func), payload})
  return bytes.concat({bytes.from_hex('424C'), bytes.pack('>I1', #config), config,
    bytes.pack('>I2', #body + 2), body, bytes.pack('<I2', checksum.compute('crc16_modbus', body))})
end

local function parse(buffer)
  if #buffer < 5 then return {kind='need_more'} end
  if buffer:u16_be(0) ~= 0x424C then return {kind='discard', consumed=1} end
  local c = buffer:u8(2)
  if #buffer < c + 5 then return {kind='need_more'} end
  local d = buffer:u16_be(c + 3)
  if c < 3 or d < 3 then return {kind='discard', consumed=1} end
  local n = c + 5 + d
  if #buffer < n then return {kind='need_more'} end
  return {kind='frame', consumed=n, payload=buffer:slice(0,n)}
end

local function run(ctx)
  local firmware = ctx.inputs.firmware
  local size = firmware:info().size
  if size < 7 then ctx:fail('InvalidFirmware','固件至少需要 6 字节识别头和 1 字节内容') end
  local header = firmware:read(0,6)
  if header:u16_be(0) ~= 0x424C then ctx:fail('InvalidFirmware','固件识别头必须为 42 4C') end
  local device_type, number = header:u16_be(2), header:u16_be(4)
  local payload_size = size - 6
  local datagram = ctx.link:info().datagram
  local ch = ctx.link:channel({framer=datagram and {kind='datagram'} or {kind='custom',parse=parse}})
  local start = frame(bytes.pack('>I2I1',device_type,0),4,bytes.pack('>I2I2I2',0xFFFF,1,number))
  ch:send(start)
  ctx:progress({completed=2,total=100,stage='start',message='等待设备读请求'})
  local handshaked, delivered, retransmits, covered = false, false, 0, 0
  local deadline = ctx.time:after(ACK_TIMEOUT_MS)
  while true do
    local ok, packet = pcall(ch.next,ch,{deadline=deadline})
    if not ok then
      if type(packet) ~= 'table' or packet.code ~= 'Timeout' then error(packet) end
      if handshaked then
        if delivered then return {status='success',bytes_covered=covered} end
        ctx:fail('PollIdle','只应答过大小查询，未传输固件数据')
      end
      if retransmits >= MAX_RETRANSMITS then ctx:fail('AckTimeout','启动命令重传耗尽') end
      retransmits = retransmits + 1
      ctx:log('warn','重发启动命令',{attempt=retransmits})
      ch:send(start)
      deadline = ctx.time:after(ACK_TIMEOUT_MS)
    else
      local b = packet.data
      local valid = #b >= 8 and b:u16_be(0) == 0x424C
      local c = valid and b:u8(2) or 0
      valid = valid and c >= 3 and #b >= c + 8 and b:u16_be(c+3) + c + 5 == #b
      local body = valid and b:slice(c+5,#b-c-7) or bytes.from_hex('')
      valid = valid and checksum.verify('crc16_modbus', body, b:u16_le(#b-2))
      if valid and #body >= 5 and body:u8(0) == 1 then
        handshaked = true
        local address, count = body:u16_be(1), body:u16_be(3)
        local ext = c >= 5 and b:u16_be(6) or 0
        local data, responded
        if address < 2 then data = bytes.pack('>I4',payload_size); responded = 2
        else
          local offset = ((ext << 16) + address - 2) * 2
          local length = math.max(0, math.min(count*2,payload_size-offset))
          data = length > 0 and firmware:read(6+offset,length) or bytes.from_hex('')
          responded = #data // 2
          if #data > 0 then delivered=true; covered=math.max(covered,offset+#data) end
        end
        local config = bytes.concat({bytes.pack('>I2',device_type),b:slice(5,c-2)})
        ch:send(frame(config,0x81,bytes.concat({bytes.pack('>I2I2',address,responded),data})))
        ctx:progress({completed=math.max(2,math.floor(covered*100/payload_size+0.5)),total=100,stage='transfer'})
        deadline = ctx.time:after(IDLE_TIMEOUT_MS)
      end
    end
  end
end
return {run=run}
