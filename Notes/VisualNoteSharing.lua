local _,addon=...
local V=addon.NativeVisualNotes
local codec=addon.ReminderSharing
local R=addon.Reminders
local S={prefix='VRTVIS1',incoming={},pending={},outgoing={},sent={},completed={},serial=0,ready=false,status='Ready'}
addon.VisualNoteSharing=S
local LIMIT=90000
local CHUNK=180

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
 if kind=='D' then return codec.Decode(payload) end
 local api=C_EncodingUtil
 if not api or not api.DecodeBase64 or not api.DecompressString then return nil end
 local method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
 local variant=Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
 local ok,compressed=pcall(api.DecodeBase64,payload,variant)
 if not ok or type(compressed)~='string' or #compressed>LIMIT then return nil end
 local decoded
 ok,decoded=pcall(api.DecompressString,compressed,method)
 if not ok or type(decoded)~='string' or #decoded>LIMIT then return nil end
 return codec.Decode(decoded)
end

local function Notify(message)
 S.status=message;print('|cffb8c2cfVincibility:|r '..message)
 if addon.RefreshNativeVisualNotesUI then addon.RefreshNativeVisualNotesUI() end
end
local function Ready() return not InCombatLockdown() and not R.encounter end
local function Count(tableValue) local n=0;for _ in pairs(tableValue) do n=n+1 end;return n end
local function Queue(message,channel,target)
 if #S.outgoing>=520 then return false end
 S.outgoing[#S.outgoing+1]={message=message,channel=channel,target=target,id=message:match('^[DC]|([%x%-]+)|')}
 return true
end
local function Ack(request,state)
 if request.id then Queue('A|'..request.id..'|'..state,'WHISPER',request.sender) end
end
function S.ValidatePack(pack)
 if type(pack)~='table' or getmetatable(pack) or pack.schema~=1 or type(pack.note)~='table' then return false,'Unsupported visual-note pack.' end
 for key in pairs(pack) do if key~='schema' and key~='note' then return false,'Unexpected visual-note pack field.' end end
 if not pack.note.id or pack.note.origin then return false,'Visual-note source is invalid.' end
 return V.Validate(pack.note)
end
function S.Apply(request)
 local valid,err=S.ValidatePack(request.pack);if not valid then return false,err end
 if not Ready() then return false,'Received visual notes wait until combat and the encounter end.' end
 if addon.Backup then addon.Backup.BeforeIncoming(request.sender) end
 local sender=codec.Normalize(request.sender);if not sender then return false,'Sender identity is invalid.' end
 local store;store,err=V.Store();if not store then return false,err end
 local remote=request.pack.note
 local at,byUid
 -- Same note: the global uid, else the sender's earlier copy.
 if remote.uid then for index,item in ipairs(store.items) do if item.uid==remote.uid then at,byUid=index,true;break end end end
 if not at then for index,item in ipairs(store.items) do
  if item.origin and item.origin.sender==sender and item.origin.id==remote.id then at=index;break end
 end end
 if not at and #store.items>=100 then return false,'Visual-note library is full.' end
 local nextNote=V.Copy(remote)
 local serial=store.serial
 if at then nextNote.id=store.items[at].id else serial=serial+1;nextNote.id='VRT-visual-'..serial;at=#store.items+1 end
 -- Provenance: kept as it is for a note matched by its global uid (it may be our own).
 if byUid then nextNote.origin=store.items[at].origin else nextNote.origin={sender=sender,id=remote.id} end
 valid,err=V.Validate(nextNote);if not valid then return false,err end
 local items=V.Copy(store.items);items[at]=nextNote
 store.items=items;store.serial=serial
 Ack(request,'accepted');if not request.quiet then Notify('Accepted visual note "'..nextNote.name..'" from '..request.sender..'.') end
 if addon.UpdateVisualNote then addon.UpdateVisualNote() end
 return true
end
function S.Receive(pack,sender,id)
 local valid,err=S.ValidatePack(pack);if not valid then return false,err end
 if not codec.Normalize(sender) then return false,'Sender identity is invalid.' end
 if #S.pending>=8 then return false,'Incoming visual-note queue is full.' end
 local request={pack=V.Copy(pack),sender=sender,id=id,received=GetTime()}
 local authority=codec.Authority(sender)
 if authority and Ready() then return S.Apply(request) end
 S.pending[#S.pending+1]=request
 Notify('Visual note from '..sender..'. '..(authority and 'Waiting for combat/encounter to end.' or
  'Open /vincui visual to accept or decline.'))
 return true
end
function S.Accept(index)
 local request=S.pending[index];if not request then return false,'No pending visual note.' end
 local ok,err=S.Apply(request);if ok then table.remove(S.pending,index) end
 return ok,err
end
function S.Decline(index)
 local request=S.pending[index];if not request then return false,'No pending visual note.' end
 table.remove(S.pending,index);Ack(request,'declined')
 Notify('Declined visual note from '..request.sender..'.');return true
end
function S.Send(note,target)
 if not Ready() then return false,'Send visual notes outside combat and encounters.' end
 if not S.ready then return false,'Visual-note transport unavailable.' end
 local valid,err=V.Validate(note);if not valid then return false,err end
 if not note.id then return false,'Save the visual note before sending it.' end
 local outgoing=V.Copy(note);outgoing.origin=nil
 local pack={schema=1,note=outgoing}
 valid,err=S.ValidatePack(pack);if not valid then return false,err end
 local payload;payload,err=codec.Encode(pack);if not payload then return false,err end
 local compressed=Compress(payload)
 local kind=compressed and 'C' or 'D'
 if compressed then payload=compressed end
 local channel='WHISPER'
 if target=='RAID' then
  if not IsInRaid() then return false,'You are not in a raid.' end
  channel='RAID';target=nil
 elseif type(target)~='string' or target=='' or target:find('[|%c%s]') or #target>100 then
  return false,'Enter Player-Realm, or choose Raid.'
 end
 local total=math.ceil(#payload/CHUNK)
 if #S.outgoing+total>512 then return false,'A send is already queued; wait for it to finish.' end
 S.serial=S.serial+1
 local id=string.format('%x-%x',time(),S.serial)
 local request={target=target,channel=channel,when=GetTime(),ack={},pending=total,total=total,sentCount=0}
 S.sent[id]=request;S.latest=request
 for part=1,total do Queue(kind..'|'..id..'|'..part..'|'..total..'|'..payload:sub((part-1)*CHUNK+1,part*CHUNK),channel,target) end
 Notify('Queued visual note "'..note.name..'" ('..total..' message'..(total==1 and '' or 's')..').');return true
end
function S.OnMessage(prefix,message,channel,sender)
 if not R.Public(prefix) or not R.Public(message) or not R.Public(channel) or not R.Public(sender) then return end
 if prefix~=S.prefix or type(message)~='string' or #message>250 or type(sender)~='string' then return end
 if channel~='WHISPER' and channel~='RAID' then return end
 local own=GetUnitName and GetUnitName('player',true)
 if codec.Normalize(sender) and codec.Normalize(sender)==codec.Normalize(own) then return end
 local ackID,state=message:match('^A|([%x%-]+)|(%a+)$')
 if ackID then
  local request=S.sent[ackID]
  if request and (state=='accepted' or state=='declined') and not request.ack[sender] and
   (request.channel=='RAID' or codec.Normalize(request.target)==codec.Normalize(sender)) then
   request.ack[sender]=true;request.result=state;Notify(sender..' '..state..' your visual note.')
  end
  return
 end
 local kind,id,part,total,payload=message:match('^([DC])|([%x%-]+)|(%d+)|(%d+)|([%w:%+%-%._=]+)$')
 if not id or #id>30 or #part>3 or #total>3 then return end
 if kind=='C' and not payload:match('^[%w_%-=]+$') then return end
 if kind=='D' and not payload:match('^[%w:%+%-%.]+$') then return end
 part,total=tonumber(part),tonumber(total)
 if part<1 or total<1 or total>500 or part>total or #payload>CHUNK then return end
 local key=sender..'|'..id
 if S.completed[key] or Count(S.completed)>=128 then return end
 local transaction=S.incoming[key]
 if not transaction then
  if Count(S.incoming)>=8 then return end
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
  if pack then local ok,err=S.Receive(pack,sender,id);if not ok then Notify('Visual-note pack rejected: '..err) end end
 end
end
function S.Register()
 if S.ready or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then return end
 local ok,result=pcall(C_ChatInfo.RegisterAddonMessagePrefix,S.prefix)
 local enum=Enum and Enum.RegisterAddonMessagePrefixResult
 S.ready=ok and (result==true or (enum and result==enum.Success)) or false
 if not S.ready then S.status='Visual-note message registration failed.' end
end
function S.Tick(dt)
 S.elapsed=(S.elapsed or 0)+dt;if S.elapsed<.1 then return end;S.elapsed=0
 local now=GetTime()
 for key,item in pairs(S.incoming) do if now-item.when>120 then S.incoming[key]=nil end end
 for key,when in pairs(S.completed) do if now-when>180 then S.completed[key]=nil end end
 for key,item in pairs(S.sent) do if item.pending==0 and now-item.when>180 then S.sent[key]=nil end end
 if Ready() then
  for index=#S.pending,1,-1 do if codec.Authority(S.pending[index].sender) then
   local ok=S.Apply(S.pending[index]);if ok then table.remove(S.pending,index) end
  end end
 end
 if #S.outgoing==0 or not Ready() then return end
 local item=S.outgoing[1]
 local ok,result=pcall(C_ChatInfo.SendAddonMessage,S.prefix,item.message,item.channel,item.target)
 local enum=Enum and Enum.SendAddonMessageResult
 if ok and (result==true or (enum and result==enum.Success)) then
  table.remove(S.outgoing,1)
  local request=item.id and S.sent[item.id]
  if request then request.pending=math.max(0,request.pending-1);request.sentCount=request.sentCount+1;request.throttled=false;request.when=now end
 elseif ok and enum and result==enum.AddonMessageThrottle then
  local request=item.id and S.sent[item.id]
  if request then request.throttled=true end
  return
 else
  if S.latest then S.latest.failed=true end
  S.outgoing={};S.sent={};Notify('Visual-note send failed; no delivery confirmed.')
 end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','CHAT_MSG_ADDON'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event,...)
 if event=='PLAYER_LOGIN' then S.Register() elseif event=='CHAT_MSG_ADDON' then S.OnMessage(...) end
end)
frame:SetScript('OnUpdate',function(_,dt) S.Tick(dt) end)
