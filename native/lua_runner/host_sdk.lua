-- 私有工作进程 SDK。协议只获得末尾构造的受限环境，不获得此文件的 IO/调试能力。
local host_new, host_raw, host_is = __host_bytes_new, __host_bytes_raw, __host_bytes_is
local host_methods, check_only = __host_bytes_methods, __host_check_only
local json = {}
local null = {}
local function encode(v, seen)
  local t = type(v)
  if v == nil or v == null then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    assert(v == v and v ~= math.huge and v ~= -math.huge, "JSON 数值必须有限")
    assert(math.abs(v) <= 9007199254740991, "JSON 整数超出精度范围")
    return tostring(v)
  end
  if t == "string" then
    return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
      return ({['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'})[c]
        or string.format('\\u%04x', c:byte())
    end) .. '"'
  end
  if host_is(v) then
    local hex = host_raw(v):gsub('.', function(c) return string.format('%02X', c:byte()) end)
    return encode({type="bytes",hex=hex}, seen)
  end
  assert(t == "table", "结果包含不可序列化的值")
  seen = seen or {}; assert(not seen[v], "结果包含循环引用"); seen[v] = true
  local count, array = 0, true
  for k in pairs(v) do count=count+1; if type(k)~="number" or k<1 or k%1~=0 then array=false end end
  array = array and count > 0 and count == #v
  local out = {}
  if array then for i=1,#v do out[#out+1]=encode(v[i],seen) end
  else for k,x in pairs(v) do assert(type(k)=="string", "结果对象键必须为字符串"); out[#out+1]=encode(k)..":"..encode(x,seen) end end
  seen[v] = nil
  return (array and "[" or "{") .. table.concat(out,",") .. (array and "]" or "}")
end
json.encode = encode
function json.decode(s)
  local p, depth = 1, 0
  local function ws() local _,b=s:find('^[ \t\r\n]*',p); p=(b or p-1)+1 end
  local value
  local function str()
    assert(s:sub(p,p)=='"'); p=p+1; local out={}
    while p<=#s do
      local c=s:sub(p,p); p=p+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        local e=s:sub(p,p); p=p+1
        local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if e=='u' then
          local h=s:sub(p,p+3); assert(h:match('^%x%x%x%x$'),"无效 Unicode 转义")
          local n=tonumber(h,16); p=p+4
          if n>=0xD800 and n<=0xDBFF then
            assert(s:sub(p,p+1)=='\\u',"缺少低代理项"); p=p+2
            local low=tonumber(s:sub(p,p+3),16); p=p+4
            assert(low and low>=0xDC00 and low<=0xDFFF,"无效低代理项")
            n=0x10000+(n-0xD800)*1024+low-0xDC00
          end
          assert(n<0xD800 or n>0xDFFF,"孤立代理项"); out[#out+1]=utf8.char(n)
        else assert(map[e],"无效 JSON 转义"); out[#out+1]=map[e] end
      else assert(c:byte()>=32,"JSON 字符串含控制字符"); out[#out+1]=c end
    end
    error("JSON 字符串未结束")
  end
  value=function()
    ws(); depth=depth+1; assert(depth<=64,"JSON 嵌套过深")
    local c=s:sub(p,p); local result
    if c=='"' then result=str()
    elseif c=='{' or c=='[' then
      p=p+1; result={}; ws(); local close=c=='{' and '}' or ']'
      if s:sub(p,p)~=close then
        repeat
          local key
          if c=='{' then ws(); key=str(); ws(); assert(s:sub(p,p)==':'); p=p+1 end
          local x=value(); if c=='{' then result[key]=x else result[#result+1]=x end
          ws(); local sep=s:sub(p,p); if sep~=',' then break end; p=p+1
        until false
      end
      assert(s:sub(p,p)==close,"JSON 缺少结束符"); p=p+1
    elseif s:sub(p,p+3)=='true' then result=true; p=p+4
    elseif s:sub(p,p+4)=='false' then result=false; p=p+5
    elseif s:sub(p,p+3)=='null' then result=null; p=p+4
    else
      local n=s:match('^-?%d+%.?%d*[eE]?[+-]?%d*',p)
      assert(n and tonumber(n),"无效 JSON 值"); result=tonumber(n); p=p+#n
    end
    depth=depth-1; return result
  end
  local result=value(); ws(); assert(p>#s,"JSON 存在尾随内容"); return result
end
local function output(v) io.write(json.encode(v),"\n"); io.flush() end
local initial_line=assert(io.read('*l'),"缺少运行输入")
local initial=json.decode(initial_line)
local function raise(code,message,details)
  error({code=code,message=message,details=details},0)
end
local function integer(n,name,min,max)
  if type(n)~="number" or n%1~=0 or n<(min or 0) or n>(max or 9007199254740991) then
    raise("InvalidArgument",(name or "数值").." 超出范围")
  end
  return n
end
local function readonly(v)
  if v==null then return nil end
  if type(v)~="table" then return v end
  local backing={}; for k,x in pairs(v) do backing[k]=readonly(x) end
  return setmetatable({}, {__index=backing,__newindex=function() raise("InvalidArgument","值只读") end,
    __pairs=function() return next,backing,nil end,__len=function() return #backing end,__metatable=false})
end
local operations, work = 0, 0
local function request(op,args)
  operations=operations+1; work=0
  output({id=operations,op=op,args=args or {}})
  local line=io.read('*l'); if not line then raise("Cancelled","宿主已关闭运行") end
  local reply=json.decode(line)
  assert(reply.id==operations,"IPC 请求编号不一致")
  if not reply.ok then error(reply.error,0) end
  if reply.value==null then return nil end
  return reply.value
end
local function instruction_hook()
  work=work+10000
  if work>20000000 then raise("ResourceLimit","脚本连续计算超过指令预算") end
end
local bytes, methods = {}, {}
function bytes.from_string(s) assert(type(s)=="string","需要二进制字符串"); return host_new(s) end
function bytes.from_utf8(s) assert(utf8.len(s),"无效 UTF-8"); return host_new(s) end
function bytes.from_hex(s)
  assert(type(s)=="string","Hex 必须为文本"); s=s:gsub('%s','')
  if #s%2~=0 or s:find('[^%x]') then raise("InvalidArgument","无效 Hex") end
  return host_new((s:gsub('%x%x',function(h) return string.char(tonumber(h,16)) end)))
end
function bytes.concat(parts)
  local out, size={},0
  for _,b in ipairs(parts) do local raw=host_raw(b); size=size+#raw; assert(size<=1048576,"Bytes 超限"); out[#out+1]=raw end
  return host_new(table.concat(out))
end
local function format_check(f)
  assert(type(f)=="string" and (f:sub(1,1)=='<' or f:sub(1,1)=='>'),"格式必须显式指定大小端")
  assert(not f:find('[=jJTn]'),"禁止平台相关打包格式")
end
function bytes.pack(f,...) format_check(f); return host_new(string.pack(f,...)) end
function bytes.unpack(f,b,offset)
  format_check(f); offset=integer(offset or 0,"偏移",0,#b)
  local values={string.unpack(f,host_raw(b),offset+1)}; local next_offset=table.remove(values)-1
  return {values=values,next_offset=next_offset}
end
function methods:len() return #self end
function methods:to_string() return host_raw(self) end
function methods:to_utf8() local s=host_raw(self); assert(utf8.len(s),"无效 UTF-8"); return s end
function methods:to_hex() return (host_raw(self):gsub('.',function(c) return string.format('%02X',c:byte()) end)) end
function methods:slice(offset,length)
  integer(offset,"偏移",0,#self); integer(length,"长度",0,#self-offset)
  return host_new(host_raw(self):sub(offset+1,offset+length))
end
function methods:equals(b) return host_is(b) and host_raw(self)==host_raw(b) end
local formats={u8='I1',i8='i1',u16_le='<I2',u16_be='>I2',u32_le='<I4',u32_be='>I4',
  i64_le='<i8',i64_be='>i8',u64_le='<I8',u64_be='>I8',
  i16_le='<i2',i16_be='>i2',i32_le='<i4',i32_be='>i4',f32_le='<f',f32_be='>f',f64_le='<d',f64_be='>d'}
for name,f in pairs(formats) do
  methods[name]=function(b,offset)
    integer(offset,"偏移",0,#b-string.packsize(f)); local v=string.unpack(f,host_raw(b),offset+1); return v
  end
end
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function methods:to_base64()
  local s,out=host_raw(self),{}
  for p=1,#s,3 do
    local a,b,c=s:byte(p,p+2); b=b or 0; c=c or 0; local n=(a<<16)|(b<<8)|c
    out[#out+1]=alphabet:sub((n>>18)+1,(n>>18)+1)..alphabet:sub(((n>>12)&63)+1,((n>>12)&63)+1)
      ..(p+1<=#s and alphabet:sub(((n>>6)&63)+1,((n>>6)&63)+1) or '=')
      ..(p+2<=#s and alphabet:sub((n&63)+1,(n&63)+1) or '=')
  end
  return table.concat(out)
end
function bytes.from_base64(s)
  assert(type(s)=='string' and #s%4==0 and not s:find('[^%w+/=]'),"无效 Base64")
  local out={}
  for p=1,#s,4 do
    local a,b,c,d=s:sub(p,p),s:sub(p+1,p+1),s:sub(p+2,p+2),s:sub(p+3,p+3)
    assert(a~='=' and b~='=' and (c~='=' or d=='=') and (d~='=' or p+3==#s),"无效 Base64 填充")
    local function index(ch) if ch=='=' then return 0 end; local n=alphabet:find(ch,1,true); assert(n,"无效 Base64"); return n-1 end
    local n=(index(a)<<18)|(index(b)<<12)|(index(c)<<6)|index(d)
    out[#out+1]=string.char((n>>16)&255)
    if c~='=' then out[#out+1]=string.char((n>>8)&255) end
    if d~='=' then out[#out+1]=string.char(n&255) end
  end
  return host_new(table.concat(out))
end
host_methods(methods)
local checksum={}
function checksum.compute(profile,b)
  local s,v=host_raw(b),profile=='crc16_modbus' and 0xFFFF or 0
  assert(profile=='crc16_modbus' or profile=='sum8' or profile=='xor8',"不支持的校验 profile")
  for p=1,#s do
    local x=s:byte(p)
    if profile=='sum8' then v=(v+x)&255
    elseif profile=='xor8' then v=v~x
    else v=v~x; for _=1,8 do v=(v&1)~=0 and ((v>>1)~0xA001) or (v>>1) end end
  end
  return v
end
function checksum.verify(profile,b,expected) return checksum.compute(profile,b)==expected end
local deadlines=setmetatable({},{__mode='k'})
local time={}
function time:now() local t={}; deadlines[t]=request('now'); return readonly({milliseconds=deadlines[t]}) end
function time:after(ms) integer(ms,"延时",0,86400000); local d={}; deadlines[d]=request('now')+ms; return d end
function time:remaining_ms(d) assert(deadlines[d],"无效 deadline"); return math.max(0,deadlines[d]-request('now')) end
function time:min(a,b) assert(deadlines[a] and deadlines[b],"无效 deadline"); return deadlines[a]<=deadlines[b] and a or b end
local function limit(opts)
  opts=opts or {}; if opts.deadline then assert(deadlines[opts.deadline],"无效 deadline"); return deadlines[opts.deadline] end
  return nil
end
local link, owner={},nil
function link:info() return readonly(initial.link) end
local function send_raw(data,opts)
  return request('send',{hex=methods.to_hex(data),deadline=limit(opts)})
end
function link:send(data,opts) assert(owner=='reader',"send 仅用于原始读取模式"); return send_raw(data,opts) end
function link:send_to(data,peer,opts)
  assert(owner=='reader',"send_to 仅用于原始读取模式")
  return request('send',{hex=methods.to_hex(data),peer=peer,deadline=limit(opts)})
end
function link:drain(opts) return readonly(request('drain',{deadline=limit(opts)})) end
local function packet(opts)
  local p=request('receive',{deadline=limit(opts)}); p.bytes=bytes.from_hex(p.hex); p.hex=nil; return p
end
function link:reader(opts)
  if owner then raise('OwnershipConflict','本次运行已选择接收所有者') end
  owner='reader'; opts=opts or {}; local mode=opts.mode or (initial.link.datagram and 'packet' or 'stream')
  assert(mode=='packet' or mode=='stream','无效读取模式'); assert(not initial.link.datagram or mode=='packet','UDP 只能按数据报读取')
  local buffer,closed='',false
  local r={}
  local function open() assert(not closed,'读取器已关闭') end
  local function fill(o)
    open(); local p=packet(o); buffer=buffer..host_raw(p.bytes)
    if #buffer>initial.limits.max_rx_bytes then raise('BufferOverflow','读取缓冲超限') end
  end
  function r:next(o) open(); assert(mode=='packet','不能混用读取族'); return readonly(packet(o)) end
  function r:read_some(n,o)
    open(); assert(mode=='stream','不能混用读取族'); integer(n,'长度',1,initial.limits.max_rx_bytes)
    if #buffer==0 then fill(o) end
    local count=math.min(n,#buffer); local data=buffer:sub(1,count); buffer=buffer:sub(count+1); return host_new(data)
  end
  function r:read_exact(n,o)
    open(); assert(mode=='stream','不能混用读取族'); integer(n,'长度',0,initial.limits.max_rx_bytes)
    while #buffer<n do fill(o) end
    local data=buffer:sub(1,n); buffer=buffer:sub(n+1); return host_new(data)
  end
  function r:read_until(delimiter,o)
    open(); assert(mode=='stream','不能混用读取族'); o=o or {}; local sep=host_raw(delimiter); assert(#sep>0,'分隔符不能为空')
    local max=integer(o.max_bytes or initial.limits.max_frame_bytes,'上限',1,initial.limits.max_rx_bytes)
    while true do
      local a,b=buffer:find(sep,1,true)
      if b then
        if b>max then raise('BufferOverflow','分隔帧超限') end
        local data=buffer:sub(1,o.include_delimiter==false and a-1 or b); buffer=buffer:sub(b+1); return host_new(data)
      end
      if #buffer>=max then raise('BufferOverflow','分隔帧超限') end
      fill(o)
    end
  end
  function r:discard_buffer(o)
    open(); assert(o and o.reason,'丢弃必须说明原因')
    local result=request('discard',{reason=o.reason}); result.bytes=result.bytes+#buffer; buffer=''; return result
  end
  function r:close() closed=true; buffer='' end
  return readonly(r)
end
function link:channel(config)
  if owner then raise('OwnershipConflict','本次运行已选择接收所有者') end
  owner='channel'; config=config or {}; local f=config.framer or {kind='datagram'}
  local max=integer(config.max_frame_bytes or initial.limits.max_frame_bytes,'帧上限',1,initial.limits.max_frame_bytes)
  local max_buffer=integer(config.max_buffer_bytes or initial.limits.max_rx_bytes,'缓存上限',max,initial.limits.max_rx_bytes)
  local check=config.checksum; local trailer=check and (check.profile=='crc16_modbus' and 2 or 1) or 0
  local buffer,first,frames,closed='',nil,{},false
  local assembly,queued_bytes,invalid_count=nil,0,0
  local busy=false
  local function pack_int(v,width,endian) return string.pack((endian=='be' and '>' or '<')..'I'..width,v) end
  local function read_int(s,offset,width,endian) return string.unpack((endian=='be' and '>' or '<')..'I'..width,s,offset+1) end
  local function append_check(s)
    if not check then return s end
    return s..pack_int(checksum.compute(check.profile,host_new(s)),trailer,check.wire_endian)
  end
  local function payload(s)
    if trailer>0 then
      if #s<trailer then raise('InvalidFrame','帧短于校验字段') end
      local body=s:sub(1,#s-trailer)
      if not checksum.verify(check.profile,host_new(body),read_int(s,#s-trailer,trailer,check.wire_endian)) then raise('ChecksumMismatch','校验不一致') end
      return body
    end
    return s
  end
  local function emit(s,p)
    local body=payload(s)
    if f.kind=='length_field' and f.payload_offset then body=body:sub(f.payload_offset+1) end
    frames[#frames+1]={data=host_new(body),rx_seq=p.rx_seq,first_rx_seq=first and first.rx_seq or p.rx_seq,
      first_received_at=first and first.first_received_at or p.first_received_at,last_received_at=p.last_received_at,peer=p.peer,session_id=p.session_id}
    if #frames>initial.limits.max_queued_frames then raise('BufferOverflow','帧队列超限') end
    queued_bytes=queued_bytes+#body
    if queued_bytes>initial.limits.max_rx_bytes then raise('BufferOverflow','帧队列总字节超限') end
  end
  local function feed(p)
    local raw=host_raw(p.bytes)
    if f.kind=='datagram' then assert(p.datagram,'需要数据报链路'); assert(#raw<=max,'帧超限'); first=p; emit(raw,p); first=nil; return end
    assert(not p.datagram,'流式成帧不能合并 UDP 数据报')
    if #buffer==0 then first=p end
    buffer=buffer..raw; if #buffer>max_buffer then raise('BufferOverflow','成帧缓存超限') end
    while #buffer>0 do
      local n,skip,body
      if f.kind=='fixed' then n=integer(f.size,'固定帧长',1,max)
      elseif f.kind=='length_prefix' then
        local width=integer(f.width,'长度宽度',1,4); assert(width==1 or width==2 or width==4,'长度宽度不支持')
        if #buffer<width then break end
        skip=width; n=read_int(buffer,0,width,f.endian)+width; assert(n>=width+trailer,'长度值过小')
      elseif f.kind=='length_field' then
        local offset=integer(f.offset,'长度偏移',0,max); local width=integer(f.width,'长度宽度',1,4)
        if #buffer<offset+width then break end
        n=read_int(buffer,offset,width,f.endian)+(f.adjustment or 0); assert(n>=offset+width+trailer,'无效总帧长')
      elseif f.kind=='delimiter' then
        local sep=host_raw(f.delimiter); assert(#sep>0,'分隔符不能为空'); local a,b=buffer:find(sep,1,true)
        if not b then if #buffer>=max then raise('BufferOverflow','分隔帧超限') end; break end
        n=b; body=buffer:sub(1,f.include_delimiter and b or a-1)
      elseif f.kind=='custom' then
        local result=f.parse(host_new(buffer))
        if result.kind=='need_more' then break end
        n=integer(result.consumed,'消耗字节',1,#buffer)
        if result.kind=='discard' then
          buffer=buffer:sub(n+1); first=#buffer>0 and p or nil; goto continue
        end
        assert(result.kind=='frame','无效解析器结果'); body=host_raw(result.payload)
      else raise('InvalidArgument','不支持的 framer') end
      if n>max then raise('BufferOverflow','帧长度超限') end
      if #buffer<n then break end
      local s=body or buffer:sub((skip or 0)+1,n)
      local ok,err=pcall(emit,s,p)
      if not ok then
        invalid_count=invalid_count+1
        if config.invalid_frame~='discard' or invalid_count>128 then error(err,0) end
      else invalid_count=0 end
      buffer=buffer:sub(n+1); first=#buffer>0 and p or nil
      assembly=nil
      ::continue::
    end
  end
  local ch={}
  function ch:send(data,o)
    assert(not closed,'通道已关闭'); local raw=host_raw(data)
    if f.kind=='length_field' then
      local width=f.width; local total=#raw+trailer; local offset=f.offset
      assert(offset+width<=#raw,'长度字段越界')
      raw=raw:sub(1,offset)..pack_int(total-(f.adjustment or 0),width,f.endian)..raw:sub(offset+width+1)
    end
    raw=append_check(raw)
    if f.kind=='length_prefix' then raw=pack_int(#raw,f.width,f.endian)..raw
    elseif f.kind=='delimiter' then raw=raw..host_raw(f.delimiter)
    elseif f.kind=='fixed' then assert(#raw==f.size,'固定帧长不符') end
    if #raw>max then raise('BufferOverflow','发送帧超限') end
    return send_raw(host_new(raw),o)
  end
  local function next_frame(o)
    assert(not closed,'通道已关闭')
    while #frames==0 do
      local opts=o
      if #buffer>0 then
        assembly=assembly or time:after(config.assembly_timeout_ms or 10000)
        opts={deadline=o and o.deadline and time:min(o.deadline,assembly) or assembly}
      end
      feed(packet(opts))
    end
    local result=table.remove(frames,1)
    queued_bytes=queued_bytes-#result.data
    return result
  end
  function ch:next(o) assert(not busy,'事务占用中'); return readonly(next_frame(o)) end
  function ch:try_next(o)
    local ok,v=pcall(ch.next,ch,o); if ok then return v end
    if type(v)=='table' and v.code=='Timeout' then return nil end; error(v,0)
  end
  function ch:exchange(data,o)
    assert(not busy and not closed,'事务占用或通道关闭'); assert(o and o.deadline and type(o.match)=='function','需要期限和匹配器')
    local retry=o.retry or {}; local attempts=integer(retry.max_attempts or 1,'尝试次数',1,16)
    if attempts>1 then assert(retry.safety=='idempotent' or retry.safety=='deduplicated','重试必须声明幂等或去重保证') end
    busy=true; local stash={}; local stash_bytes=0; local receipt
    local ok,result=pcall(function()
      local watermark=request('mark')
      for attempt=1,attempts do
        if time:remaining_ms(o.deadline)==0 then break end
        local attempt_end=time:min(o.deadline,time:after(o.attempt_timeout_ms or 10000))
        receipt=ch:send(data,{deadline=attempt_end})
        while true do
          local got,frame=pcall(next_frame,{deadline=attempt_end})
          if not got then
            if type(frame)=='table' and frame.code=='Timeout' then break end
            error(frame,0)
          end
          local matches=false
          if frame.first_rx_seq>watermark then
            local worked,v=pcall(o.match,readonly(frame)); if not worked then raise('MatcherError',tostring(v)) end
            assert(type(v)=='boolean','匹配器必须返回布尔值'); matches=v
          end
          if matches then return frame end
          stash[#stash+1]=frame
          stash_bytes=stash_bytes+#frame.data
          if stash_bytes+queued_bytes>initial.limits.max_rx_bytes then raise('BufferOverflow','未请求帧总字节超限') end
          if #stash>initial.limits.max_queued_frames then raise('BufferOverflow','未请求帧队列超限') end
        end
        if attempt<attempts then
          local pause=math.min((retry.backoff_ms or 0)*2^(attempt-1),retry.max_backoff_ms or 10000)
          if retry.jitter then pause=math.floor(pause*math.random()) end
          request('sleep',{ms=pause,deadline=limit(o)})
        end
      end
      if receipt then raise('OutcomeUnknown','已发送请求，但应答等待超时',{write_receipt=receipt,cause='Timeout'}) end
      raise('Timeout','发送前总期限已到',{write_state='none'})
    end)
    for i=#stash,1,-1 do table.insert(frames,1,stash[i]); queued_bytes=queued_bytes+#stash[i].data end
    busy=false
    if not ok then error(result,0) end
    return readonly(result)
  end
  function ch:close() closed=true; frames={}; buffer='' end
  return readonly(ch)
end
local source={}
function source:describe() return readonly(request('source_describe')) end
function source:get_config() return readonly(initial.source_config) end
function source:get_runtime(keys,o) return readonly(request('source_get',{keys=keys,deadline=limit(o)})) end
function source:set_runtime(patch,o) return readonly(request('source_set',{patch=patch,deadline=limit(o)})) end
local firmware={}
function firmware:info() assert(initial.firmware,'本流程没有固件输入'); return readonly(initial.firmware) end
function firmware:read(offset,length,o)
  integer(offset,'固件偏移',0,initial.firmware.size); integer(length,'长度',0,initial.firmware.size-offset)
  return bytes.from_hex(request('firmware_read',{offset=offset,length=length,deadline=limit(o)}))
end
function firmware:chunks(o)
  o=o or {}; local offset=o.offset or 0; local stop=offset+(o.length or initial.firmware.size-offset)
  integer(stop,'末端',offset,initial.firmware.size); local count=integer(o.chunk_bytes,'块长度',1,initial.limits.max_artifact_read_bytes)
  return function() if offset>=stop then return nil end; local at=offset; local n=math.min(count,stop-offset); local b=self:read(at,n,o); offset=offset+n; return {offset=at,data=b} end
end
local ctx={api_version='1.0',link=readonly(link),data_source=readonly(source),time=readonly(time),
  limits=readonly(initial.limits),target=readonly(initial.target or {}),inputs=readonly(initial.firmware and {firmware=firmware} or {}),capabilities=readonly(initial.capabilities)}
function ctx:has_capability(name) return initial.capabilities[name]==true end
function ctx:require_capability(name) if not self:has_capability(name) then raise('CapabilityDenied','缺少能力：'..name) end end
function ctx:sleep(ms,o) integer(ms,'延时',0,86400000); return request('sleep',{ms=ms,deadline=limit(o)}) end
function ctx:yield() return request('sleep',{ms=0}) end
function ctx:check_cancelled() request('check') end
function ctx:is_cancelled() local ok=pcall(request,'check'); return not ok end
function ctx:progress(v) request('progress',v) end
function ctx:log(level,message,fields) request('log',{level=level,message=message,fields=fields}) end
function ctx:log_bytes(level,label,data,o)
  local count=math.min(#data,(o and o.max_bytes) or 256,initial.limits.max_log_entry_bytes//2)
  request('log',{level=level,message=label,fields={hex=methods.to_hex(methods.slice(data,0,count)),truncated=count<#data}})
  return {logged_bytes=count,truncated=count<#data}
end
function ctx:fail(code,message,details) request('fail',{code=code,message=message,details=details}); raise(code,message,details) end
local safe_string={}; for k,v in pairs(string) do if k~='dump' then safe_string[k]=v end end
local env={assert=assert,error=error,ipairs=ipairs,next=next,pairs=pairs,pcall=pcall,xpcall=xpcall,
  select=select,tonumber=tonumber,tostring=tostring,type=type,rawequal=rawequal,
  math=readonly(math),string=readonly(safe_string),table=readonly(table),utf8=readonly(utf8),
  bytes=readonly(bytes),checksum=readonly(checksum),_VERSION=_VERSION}
env.print=function(...) local a={}; for i=1,select('#',...) do a[#a+1]=tostring(select(i,...)) end; ctx:log('info',table.concat(a,'\t')) end
env._G=readonly(env)
local user_source=(initial.source or ''):gsub('^\239\187\191','')
local chunk,syntax=load(user_source, '@protocol.lua','t',readonly(env))
if check_only then
  output({valid=chunk~=nil,error=syntax}); return
end
local function report_error(e)
  local err=type(e)=='table' and e or {code='ScriptError',message=tostring(e)}
  err.stack=debug.traceback('',2); return err
end
debug.sethook(instruction_hook,'',10000)
local ok,result=xpcall(function()
  if not chunk then raise('ScriptError',syntax) end
  local definition=chunk()
  assert(type(definition)=='table' and type(definition.run)=='function','脚本必须返回包含 run(ctx) 的表')
  return definition.run(readonly(ctx))
end,report_error)
debug.sethook()
if ok and (type(result)~='table' or result.status~='success') then ok=false; result={code='ProtocolViolation',message='脚本未明确返回成功结果'} end
local encoded,err=pcall(output,{event='result',ok=ok,value=ok and result or nil,error=not ok and result or nil})
if not encoded then output({event='result',ok=false,error={code='ScriptError',message=tostring(err)}}) end
