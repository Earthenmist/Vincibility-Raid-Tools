local _,addon=...
local R=addon.Reminders
local S={prefix='VRTREM1',incoming={},pending={},outgoing={},sent={},completed={},serial=0,status='Ready',ready=false}
addon.ReminderSharing=S
local LIMIT=90000
local CHUNK=180
local function RefreshProgress()
 if addon.RefreshReminderTransferProgress then addon.RefreshReminderTransferProgress() end
end
function S.Progress()
 local request=S.latest
 if not request then return nil end
 local sent,total=request.sentCount or 0,request.total
 local percent=math.floor(sent*100/total+0.5)
 local label
 if request.failed then label='Reminder send failed after '..sent..'/'..total..' messages; no delivery confirmed.'
 elseif request.pending>0 then
  local state=(InCombatLockdown() or R.encounter) and 'paused during combat/encounter' or
   request.throttled and 'throttled, retrying' or 'sending'
  label='Sending reminders: '..sent..'/'..total..' messages ('..percent..'%) - '..state..'.'
 else
  local confirmations=0
  for _ in pairs(request.ack) do confirmations=confirmations+1 end
  if request.channel=='WHISPER' and request.result then
   label='Reminders sent: '..total..'/'..total..' messages. Recipient '..request.result..'.'
  elseif confirmations>0 then
   label='Reminders sent: '..total..'/'..total..' messages. '..confirmations..' recipient(s) acknowledged.'
  elseif GetTime()-request.when>180 then
   label='Reminders sent: '..total..'/'..total..' messages. No acceptance confirmed.'
  else label='Reminders sent: '..total..'/'..total..' messages. Awaiting recipient acknowledgement.' end
 end
 return sent/total,label
end
local function Compress(payload)
 local api=C_EncodingUtil
 if not api or not api.CompressString or not api.EncodeBase64 then return nil end
 local method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
 local variant=Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
 local ok,compressed=pcall(api.CompressString,payload,method)
 if not ok or type(compressed)~='string' then return nil end
 local encoded
 ok,encoded=pcall(api.EncodeBase64,compressed,variant)
 if not ok or type(encoded)~='string' or #encoded>=#payload or #encoded>LIMIT or
  not encoded:match('^[%w_%-=]+$') then return nil end
 return encoded
end
local function DecodePayload(kind,payload)
 if kind=='D' then return S.Decode(payload) end
 local api=C_EncodingUtil
 if not api or not api.DecodeBase64 or not api.DecompressString then return nil end
 local method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
 local variant=Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
 local ok,compressed=pcall(api.DecodeBase64,payload,variant)
 if not ok or type(compressed)~='string' or #compressed>LIMIT then return nil end
 local decoded
 ok,decoded=pcall(api.DecompressString,compressed,method)
 if not ok or type(decoded)~='string' or #decoded>LIMIT then return nil end
 return S.Decode(decoded)
end
local function Say(text) S.status=text;print('|cffb8c2cfVincibility:|r '..text) end
-- Bounded, data-only codec: length-prefixed strings, finite numbers, booleans,
-- and tables. It never compiles Lua, and has no third-party library dependency.
function S.Encode(value)
 local nodes,seen=0,{}
 local function Encode(v,depth)
  nodes=nodes+1;assert(depth<=8 and nodes<=20000,'Reminder pack is too complex.')
  if type(v)=='string' then
   local hex=v:gsub('.',function(c) return string.format('%02x',c:byte()) end)
   return 's'..#hex..':'..hex
  elseif type(v)=='number' then
   assert(v==v and math.abs(v)<1e12,'Invalid number.');local n=string.format('%.17g',v);return 'n'..#n..':'..n
  elseif type(v)=='boolean' then return v and 'y' or 'z'
  elseif type(v)=='table' then
   assert(not seen[v] and not getmetatable(v),'Invalid table.');seen[v]=true
   local keys={};for k in pairs(v) do assert(type(k)=='string' or type(k)=='number','Invalid key.');keys[#keys+1]=k end
   table.sort(keys,function(a,b) if type(a)==type(b) then return a<b end;return type(a)<type(b) end)
   local result={'t'..#keys..':'}
   for _,k in ipairs(keys) do result[#result+1]=Encode(k,depth+1);result[#result+1]=Encode(v[k],depth+1) end
   seen[v]=nil;return table.concat(result)
  end
  error('Unsupported data type.')
 end
 local ok,result=pcall(Encode,value,0)
 if not ok then return nil,result end
 if #result>LIMIT then return nil,'Pack exceeds 90 KB; send a smaller selection.' end
 return result
end
function S.Decode(text)
 if type(text)~='string' or #text>LIMIT then return nil,'Invalid pack size.' end
 local pos,nodes=1,0
 local function Read(depth)
  nodes=nodes+1;assert(depth<=8 and nodes<=20000,'Pack is too complex.')
  local tag=text:sub(pos,pos);pos=pos+1
  if tag=='y' then return true elseif tag=='z' then return false end
  assert(tag=='s' or tag=='n' or tag=='t','Invalid data tag.')
  local stop=text:find(':',pos,true);assert(stop and stop-pos<=6,'Invalid length.')
  local raw=text:sub(pos,stop-1);assert(raw:match('^%d+$'),'Invalid length.')
  local length=tonumber(raw);assert(length<=LIMIT,'Invalid length.');pos=stop+1
  if tag=='t' then
   assert(length<=2000,'Too many table entries.');local result={}
   for _=1,length do
    local key=Read(depth+1);assert(type(key)=='string' or type(key)=='number','Invalid key.')
    assert(result[key]==nil,'Duplicate key.');result[key]=Read(depth+1)
   end
   return result
  end
  assert(pos+length-1<=#text,'Truncated pack.')
  local value=text:sub(pos,pos+length-1);pos=pos+length
  if tag=='n' then
   value=tonumber(value);assert(value and value==value and math.abs(value)<1e12,'Invalid number.');return value
  end
  assert(#value%2==0 and not value:find('[^%x]'),'Invalid string encoding.')
  return (value:gsub('..',function(c) return string.char(tonumber(c,16)) end))
 end
 local ok,result=pcall(Read,0)
 if not ok or pos~=#text+1 then return nil,'Invalid reminder pack.' end
 return result
end
function S.Pack(records)
 return S.Encode({schema=1,reminders=records})
end
function S.ValidatePack(pack)
 if type(pack)~='table' or pack.schema~=1 or type(pack.reminders)~='table' then return false,'Unsupported reminder pack.' end
 for key in pairs(pack) do if key~='schema' and key~='reminders' then return false,'Unexpected pack fields.' end end
 local seen,count={},0
 for key,data in pairs(pack.reminders) do
  count=count+1
  if type(key)~='number' or key%1~=0 or key<1 or key>#pack.reminders then return false,'Invalid pack array.' end
  local ok,err=R.Validate(data);if not ok then return false,err end
  if seen[data.uid] then return false,'Duplicate reminder identity.' end;seen[data.uid]=true
 end
 if count<1 or count>200 then return false,'A pack must contain 1–200 reminders.' end
 if count~=#pack.reminders then return false,'Reminder arrays cannot contain gaps.' end
 return true
end
local function Normalize(name)
 if not R.Public(name) or type(name)~='string' or #name>160 then return nil end
 local player,realm=name:match('^([^%-]+)%-(.+)$')
 if not player then player=name;realm=GetNormalizedRealmName and GetNormalizedRealmName() end
 if not R.Public(realm) or type(realm)~='string' then return nil end
 return (player..'-'..realm:gsub('%s','')):lower()
end
S.Normalize=Normalize
-- Your raid leader and assistants (only while in a raid).
function S.RaidAuthority(sender)
 if not IsInRaid() then return false end
 local wanted=Normalize(sender);if not wanted then return false end
 for i=1,GetNumGroupMembers() do
  local unit='raid'..i
  local name,realm=UnitFullName(unit)
  if R.Public(name) and R.Public(realm) and type(name)=='string' then
   realm=(realm and realm~='') and realm or GetNormalizedRealmName()
   if R.Public(realm) and type(realm)=='string' and Normalize(name..'-'..realm)==wanted then return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit) end
  end
 end
 return false
end
-- One trust rule for every incoming send (page Send buttons and Sync):
-- raid leader/assistants, or guild members at or above the rank chosen in
-- Settings > Sync. Trusted sends apply automatically; others wait for Accept.
function S.Authority(sender)
 if S.RaidAuthority(sender) then return true end
 local Y=addon.Sync
 return Y and Y.Trusted and Y.Trusted(sender) or false
end
local function Queue(message,channel,target)
 if #S.outgoing>=520 then return false end
 S.outgoing[#S.outgoing+1]={message=message,channel=channel,target=target,id=message:match('^[DC]|([%x%-]+)|')};return true
end
local function Acknowledge(request,status)
 if request.id then Queue('A|'..request.id..'|'..status,'WHISPER',request.sender) end
end
function S.Apply(request)
 local valid,err=S.ValidatePack(request.pack);if not valid then return false,err end
 if InCombatLockdown() or R.encounter then return false,'Received reminders wait until the encounter and combat end.' end
 if addon.Backup then addon.Backup.BeforeIncoming(request.sender) end
 local db;db,err=R.Store();if not db then return false,err end
 local size=0;for _ in pairs(db.global) do size=size+1 end
 for _,data in ipairs(request.pack.reminders) do if not db.global[data.uid] then size=size+1 end end
 if size>200 then return false,'Global library limit reached; no reminders changed.' end
 -- Atomic upsert of matching IDs only; no remote delete or position/settings data.
 local nextLibrary=R.Copy(db.global)
 for _,data in ipairs(request.pack.reminders) do nextLibrary[data.uid]=R.Copy(data) end
 db.global=nextLibrary;R.Changed();Acknowledge(request,'accepted')
 if not request.quiet then Say('Accepted '..#request.pack.reminders..' reminder(s) from '..request.sender..'.') end;return true
end
function S.Receive(pack,sender,id)
 local valid,err=S.ValidatePack(pack);if not valid then return false,err end
 if #S.pending>=8 then return false,'Incoming reminder queue is full.' end
 local request={pack=R.Copy(pack),sender=sender,id=id,received=GetTime()}
 if S.Authority(sender) and not InCombatLockdown() and not R.encounter then return S.Apply(request) end
 S.pending[#S.pending+1]=request
 Say('Reminders received from '..sender..'. '..(S.Authority(sender) and 'Waiting for combat/encounter to end.' or 'Open /vincui reminders to accept or decline.'))
 return true
end
function S.Accept(index)
 local request=S.pending[index];if not request then return false,'No pending pack.' end
 local ok,err=S.Apply(request);if ok then table.remove(S.pending,index) end;return ok,err
end
function S.Decline(index)
 local request=S.pending[index];if not request then return end
 table.remove(S.pending,index);Acknowledge(request,'declined');Say('Declined reminders from '..request.sender..'.')
end
function S.Send(records,target)
 if InCombatLockdown() or R.encounter then return false,'Send reminders outside combat and encounters.' end
 if not S.ready then return false,'Addon-message transport unavailable.' end
 local valid,err=S.ValidatePack({schema=1,reminders=records});if not valid then return false,err end
 local payload;payload,err=S.Pack(records);if not payload then return false,err end
 local compressed=Compress(payload)
 local kind=compressed and 'C' or 'D'
 if compressed then payload=compressed end
 local channel='WHISPER'
 if target=='RAID' then
  if not IsInRaid() then return false,'You are not in a raid.' end;channel='RAID';target=nil
 elseif type(target)~='string' or target=='' or target:find('[|%c%s]') or #target>100 then return false,'Enter Player-Realm, or RAID.' end
 local total=math.ceil(#payload/CHUNK)
 if #S.outgoing+total>512 then return false,'A send is already queued; wait for it to finish.' end
 S.serial=S.serial+1
 local id=string.format('%x-%x',time(),S.serial)
 local request={target=target,channel=channel,when=GetTime(),ack={},pending=total,total=total,sentCount=0}
 S.sent[id]=request;S.latest=request
 for part=1,total do Queue(kind..'|'..id..'|'..part..'|'..total..'|'..payload:sub((part-1)*CHUNK+1,part*CHUNK),channel,target) end
 Say('Queued '..#records..' reminder(s) in '..total..' message(s). Waiting for recipients to acknowledge acceptance.');RefreshProgress();return true
end
function S.OnMessage(prefix,message,channel,sender)
 if not R.Public(prefix) or not R.Public(message) or not R.Public(channel) or not R.Public(sender) then return end
 if prefix~=S.prefix or type(message)~='string' or #message>250 or type(sender)~='string' then return end
 if channel~='WHISPER' and channel~='RAID' then return end
 local own=GetUnitName and GetUnitName('player',true)
 local senderName,ownName=Normalize(sender),Normalize(own)
 if senderName and ownName and senderName==ownName then return end
 local ackID,state=message:match('^A|([%x%-]+)|(%a+)$')
 if ackID then
  local request=S.sent[ackID]
  if request and (state=='accepted' or state=='declined') and not request.ack[sender] and
   (request.channel=='RAID' or Normalize(request.target)==Normalize(sender)) then
   request.ack[sender]=true;request.result=state;Say(sender..' '..state..' your reminders.');RefreshProgress()
  end
  return
 end
 local kind,id,part,total,payload=message:match('^([DC])|([%x%-]+)|(%d+)|(%d+)|([%w_%-=:]+)$')
 if not id or #id>30 or #part>3 or #total>3 then return end
 if kind=='C' and not payload:match('^[%w_%-=]+$') then return end
 if kind=='D' and not payload:match('^[%w:]+$') then return end
 part,total=tonumber(part),tonumber(total)
 if part<1 or total<1 or total>500 or part>total or #payload>CHUNK then return end
 local key=sender..'|'..id
 if S.completed[key] then return end
 local completedCount=0;for _ in pairs(S.completed) do completedCount=completedCount+1 end
 if completedCount>=128 then return end
 local transaction=S.incoming[key]
 if not transaction then
  local count=0;for _ in pairs(S.incoming) do count=count+1 end;if count>=8 then return end
  transaction={parts={},kind=kind,total=total,count=0,bytes=0,when=GetTime()};S.incoming[key]=transaction
 end
 if transaction.total~=total or transaction.kind~=kind then S.incoming[key]=nil;return end
 if transaction.parts[part] then
  if transaction.parts[part]~=payload then S.incoming[key]=nil end
  return
 end
 transaction.parts[part]=payload;transaction.count=transaction.count+1;transaction.bytes=transaction.bytes+#payload;transaction.when=GetTime()
 if transaction.bytes>LIMIT then S.incoming[key]=nil;return end
 if transaction.count==total then
  S.incoming[key]=nil;S.completed[key]=GetTime()
  local pack=DecodePayload(kind,table.concat(transaction.parts))
  if pack then local ok,err=S.Receive(pack,sender,id);if not ok then Say('Reminder pack rejected: '..err) end end
 end
end
function S.Register()
 if S.ready or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then return end
 local ok,result=pcall(C_ChatInfo.RegisterAddonMessagePrefix,S.prefix)
 local enum=Enum and Enum.RegisterAddonMessagePrefixResult
 S.ready=ok and (result==true or (enum and result==enum.Success)) or false
 if not S.ready then S.status='Addon-message prefix registration failed.' end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','CHAT_MSG_ADDON','PLAYER_REGEN_ENABLED','ENCOUNTER_END'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event,...)
 if event=='PLAYER_LOGIN' then S.Register()
 elseif event=='CHAT_MSG_ADDON' then S.OnMessage(...)
 end
end)
local elapsed=0
frame:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt;if elapsed<0.1 then return end;elapsed=0
 local now=GetTime()
 for key,v in pairs(S.incoming) do if now-v.when>120 then S.incoming[key]=nil end end
 for key,when in pairs(S.completed) do if now-when>180 then S.completed[key]=nil end end
 for key,v in pairs(S.sent) do if v.pending==0 and now-v.when>180 then S.sent[key]=nil end end
 if S.latest and S.latest.pending==0 and not S.latest.timeoutShown and now-S.latest.when>180 then
  S.latest.timeoutShown=true;RefreshProgress()
 end
 if not InCombatLockdown() and not R.encounter then
  for i=#S.pending,1,-1 do if S.Authority(S.pending[i].sender) then
   local ok=S.Apply(S.pending[i]);if ok then table.remove(S.pending,i) end
  end end
 end
 if #S.outgoing==0 or InCombatLockdown() or R.encounter then return end
 local item=S.outgoing[1]
 local ok,result=pcall(C_ChatInfo.SendAddonMessage,S.prefix,item.message,item.channel,item.target)
 local enum=Enum and Enum.SendAddonMessageResult
 if ok and (result==true or (enum and result==enum.Success)) then
  table.remove(S.outgoing,1)
  local request=item.id and S.sent[item.id]
  if request then request.pending=math.max(0,request.pending-1);request.sentCount=request.sentCount+1;request.throttled=false;request.when=now;RefreshProgress() end
 elseif ok and enum and result==enum.AddonMessageThrottle then
  local request=item.id and S.sent[item.id]
  if request then request.throttled=true;RefreshProgress() end
  return
 else
  if S.latest then S.latest.failed=true end
  S.outgoing={};S.sent={};Say('Reminder send failed; no delivery confirmed. Check recipient and client messaging availability.');RefreshProgress()
 end
end)
