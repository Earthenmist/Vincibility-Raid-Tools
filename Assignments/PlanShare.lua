local _,addon=...
-- Share a boss assignment plan with the group so everyone gets their own
-- in-fight reminders. Sent by button or, for the leader/assistant who starts
-- a ready check, automatically for the current boss. Packs use the bounded
-- reminder serializer, Deflate when it helps, and paced chunks on VRTPLN1.
-- Group shares from raid leaders/assistants apply automatically (after combat);
-- anything else waits for Accept/Decline. A received plan replaces that boss's plan.
local A=addon.Assignments
local PREFIX,CHUNK,LIMIT='VRTPLN1',220,90000
local P={prefix=PREFIX,incoming={},outgoing={},pending=nil,serial=0,lastApplied={}};A.PlanShare=P

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Say(text) print('|cffb8c2cfVincibility:|r '..text) end
local function Codec() return addon.ReminderSharing end
local function Compress(payload)
 local api=C_EncodingUtil
 if not api or not api.CompressString or not api.EncodeBase64 then return nil end
 local method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
 local variant=Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
 local ok,compressed=pcall(api.CompressString,payload,method)
 if not ok or type(compressed)~='string' then return nil end
 local encoded;ok,encoded=pcall(api.EncodeBase64,compressed,variant)
 if not ok or type(encoded)~='string' or #encoded>=#payload or not encoded:match('^[%w_%-=]+$') then return nil end
 return encoded
end
local function Decompress(payload)
 local api=C_EncodingUtil
 if not api or not api.DecodeBase64 or not api.DecompressString then return nil end
 local method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
 local variant=Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
 local ok,compressed=pcall(api.DecodeBase64,payload,variant)
 if not ok or type(compressed)~='string' or #compressed>LIMIT then return nil end
 local decoded;ok,decoded=pcall(api.DecompressString,compressed,method)
 if not ok or type(decoded)~='string' or #decoded>LIMIT then return nil end
 return decoded
end
function P.Pack(bossID)
 local plan=A.Plan(bossID)
 if not plan or #plan.entries==0 then return nil,'This boss has no assignments to share.' end
 local entries={}
 for _,entry in ipairs(plan.entries) do
  local copy={}
  for key,value in pairs(entry) do if key~='id' then copy[key]=value end end
  entries[#entries+1]=copy
 end
 -- updated: the plan's version time, kept by receivers so sync converges.
 return {schema=1,boss=bossID,name=plan.name,entries=entries,updated=plan.updated}
end
function P.Validate(pack)
 if type(pack)~='table' or pack.schema~=1 or type(pack.boss)~='number' or type(pack.entries)~='table' then return false,'Invalid plan.' end
 if pack.name~=nil and (type(pack.name)~='string' or #pack.name>80) then return false,'Invalid boss name.' end
 if pack.updated~=nil and (type(pack.updated)~='number' or pack.updated<0 or pack.updated>1e10) then return false,'Invalid plan version.' end
 for _,entry in ipairs(pack.entries) do local ok,err=A.Validate(entry);if not ok then return false,err end end
 return true
end
function P.Send(bossID)
 if InCombatLockdown() then return false,'Share after combat.' end
 if not IsInGroup() then return false,'Join a group to share the plan.' end
 if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false,'Addon messages are locked right now.' end
 local codec=Codec();if not codec or not codec.Encode then return false,'Sharing is unavailable.' end
 local pack,err=P.Pack(bossID);if not pack then return false,err end
 local payload;payload,err=codec.Encode(pack);if not payload then return false,err end
 local compressed=Compress(payload)
 local kind=compressed and 'C' or 'D';payload=compressed or payload
 P.serial=P.serial+1
 local id=string.format('%x%x',math.random(4096,65535),P.serial%4096)
 local total=math.ceil(#payload/CHUNK)
 if total>400 then return false,'The plan is too large to share.' end
 local channel=IsInRaid() and 'RAID' or 'PARTY'
 for index=1,total do P.outgoing[#P.outgoing+1]={message=id..'|'..index..'|'..total..'|'..kind..'|'..payload:sub((index-1)*CHUNK+1,index*CHUNK),channel=channel} end
 return true,string.format('Sharing the %s plan (%d assignment%s) with your group.',pack.name or 'boss',#pack.entries,#pack.entries==1 and '' or 's')
end
function P.Tick(elapsed)
 P.elapsed=(P.elapsed or 0)+elapsed
 if P.elapsed<.2 or #P.outgoing==0 then return end
 P.elapsed=0
 local item=table.remove(P.outgoing,1)
 if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage,PREFIX,item.message,item.channel) end
end
local function IsSelf(sender)
 local codec=Codec()
 local own=GetUnitName and GetUnitName('player',true)
 if codec and codec.Normalize and own then return codec.Normalize(sender)==codec.Normalize(own) end
 return Ambiguate and Ambiguate(sender,'none')==UnitName('player')
end
local function Trusted(sender)
 local codec=Codec()
 return codec and codec.Authority and codec.Authority(sender) or false
end
local function Busy() return InCombatLockdown() or (addon.Reminders and addon.Reminders.encounter) end
function P.Apply(request)
 if addon.Backup then addon.Backup.BeforeIncoming(request.sender) end
 local ok,message=A.ReplacePlan(request.pack.boss,request.pack.name,request.pack.entries,request.pack.updated)
 if ok then
  P.lastApplied[request.sender..':'..request.pack.boss]=request.payload
  Say(request.sender..' shared the '..(request.pack.name or 'boss')..' plan ('..#request.pack.entries..' assignments).')
  if addon.RefreshAssignmentsPage then addon.RefreshAssignmentsPage() end
 end
 return ok,message
end
function P.Receive(pack,sender,payload)
 local ok=P.Validate(pack);if not ok then return false end
 if P.lastApplied[sender..':'..pack.boss]==payload then return true end -- unchanged resend
 local request={pack=pack,sender=sender,payload=payload,trusted=Trusted(sender)}
 if request.trusted and not Busy() then return P.Apply(request) end
 P.pending=request
 if not request.trusted then Say(sender..' shared the '..(pack.name or 'boss')..' plan. Open Assignments to accept or decline.') end
 if addon.RefreshAssignmentsPage then addon.RefreshAssignmentsPage() end
 return false
end
function P.Accept()
 local request=P.pending;if not request then return false,'Nothing to accept.' end
 if Busy() then return false,'Accept after combat.' end
 local ok,message=P.Apply(request)
 if ok then P.pending=nil end
 return ok,message
end
function P.Decline() P.pending=nil;return true,'Shared plan declined.' end
-- A trusted share received in combat applies once combat ends.
function P.ApplyDeferred()
 local request=P.pending
 if request and request.trusted and not Busy() then P.pending=nil;P.Apply(request) end
end
function P.OnMessage(prefix,message,channel,sender)
 if not (Public(prefix) and Public(message) and Public(sender) and Public(channel)) or prefix~=PREFIX then return end
 if type(message)~='string' or type(sender)~='string' or IsSelf(sender) then return end
 local id,index,total,kind,chunk=message:match('^(%x+)|(%d+)|(%d+)|([CD])|(.*)$')
 index,total=tonumber(index),tonumber(total)
 if not id or not index or not total or total<1 or total>400 or index<1 or index>total then return end
 local key=sender..':'..id
 local transfer=P.incoming[key]
 if not transfer then transfer={parts={},count=0,total=total,kind=kind,when=GetTime()};P.incoming[key]=transfer end
 if transfer.total~=total or transfer.kind~=kind then P.incoming[key]=nil;return end
 if not transfer.parts[index] then transfer.parts[index]=chunk;transfer.count=transfer.count+1 end
 if transfer.count<total then return end
 P.incoming[key]=nil
 local payload=table.concat(transfer.parts)
 local decoded=kind=='C' and Decompress(payload) or payload
 local codec=Codec()
 local pack=decoded and codec and codec.Decode and codec.Decode(decoded)
 if pack then P.Receive(pack,sender,payload) end
end
-- Leader/assistant who starts a ready check sends the current boss's plan.
function P.CurrentBoss()
 local room=addon.GetNativeBossID and addon.GetNativeBossID()
 if room and A.Plan(room) then return room end
 local store=A.Store()
 return store and store.lastBoss
end
function P.OnReadyCheck(initiator)
 if addon.ModuleEnabled and not addon.ModuleEnabled('assignments') then return end
 local store=A.Store()
 if not store or store.autoSharePlan==false or not IsInGroup() then return end
 if not (UnitIsGroupLeader('player') or UnitIsGroupAssistant('player')) then return end
 local mine=false
 if initiator and Public(initiator) then
  local ok,same=pcall(UnitIsUnit,initiator,'player');mine=ok and same
  if not mine and Ambiguate and UnitName then mine=UnitName('player')==Ambiguate(initiator,'none') end
 end
 if not mine then return end
 local boss=P.CurrentBoss()
 local plan=boss and A.Plan(boss)
 if plan and #plan.entries>0 then
  local ok,message=P.Send(boss)
  if ok then Say('ready check: '..message) end
 end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','CHAT_MSG_ADDON','READY_CHECK','PLAYER_REGEN_ENABLED','ENCOUNTER_END'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event,...)
 if event=='PLAYER_LOGIN' then
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX) end
 elseif event=='CHAT_MSG_ADDON' then P.OnMessage(...)
 elseif event=='READY_CHECK' then P.OnReadyCheck(...)
 else P.ApplyDeferred() end
end)
frame:SetScript('OnUpdate',function(_,elapsed)
 P.Tick(elapsed)
 for key,transfer in pairs(P.incoming) do if GetTime()-transfer.when>90 then P.incoming[key]=nil end end
end)
