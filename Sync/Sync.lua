local _,addon=...
-- Sync by reconciliation (IBLT): only records that differ
-- are transferred. Each kind (text notes, visual notes, reminders, boss plans,
-- team roster) is a set of records {u=uid, v=version, d=data} or tombstones
-- {u=uid, v=deleted time, x=true}. A client announces a small summary (count
-- and two fingerprint sums); anyone whose summary differs pulls what they lack
-- from that client over whispers: open, IBLT cells (or a paged inventory),
-- then only the missing records. The newest version of a record wins; ties
-- are broken by content so every client converges. Records are only taken
-- from trusted senders (raid leader/assistants, guild members at or above the
-- chosen rank) or after Accept. Automatic: summaries after login and after
-- local edits; the Sync buttons announce on demand.
local Y={prefix='VRTSYN2',outgoing={},incoming={},pending={},jobs={},serving={},dirty={},cache={},
 sequence=0,status='Ready',interval=.25,received=0}
addon.Sync=Y
local I=addon.SyncIBLT
local CHUNK,MAX_PARTS,MAX_ASSEMBLY,ASSEMBLY_EXPIRY=200,600,16,120
local WAIT,SERVE_EXPIRY,MAX_SERVING,BATCH,PAGE=30,45,6,16,32
Y.kinds={
 {key='notes',label='Text notes',noun='text note'},
 {key='visual',label='Visual notes',noun='visual note'},
 {key='reminders',label='Reminders',noun='reminder'},
 {key='plans',label='Assignments',noun='boss plan'},
 {key='roster',label='Team roster',noun='roster'},
 {key='auras',label='Aura tracking',noun='aura setup'},
}
local kindByKey={};for _,kind in ipairs(Y.kinds) do kindByKey[kind.key]=kind end

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Codec() return addon.ReminderSharing end
local function Now() return addon.Now and addon.Now() or (time and time() or 0) end
local function InGuild() return IsInGuild and IsInGuild() or false end
local function Say(text,quiet) Y.status=text;if not quiet then print('|cffb8c2cfVincibility:|r '..text) end;if addon.RefreshSyncTab then addon.RefreshSyncTab() end end
local function Busy()
 local R=addon.Reminders
 return InCombatLockdown() or (R and R.encounter) or false
end
local function Copy(value)
 if type(value)~='table' then return value end
 local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end
local function Plural(count,noun) return count..' '..noun..(count==1 and '' or 's') end
local function Short(name) return type(name)=='string' and (name:gsub('%-.*$',''):lower()) or nil end
local function Same(a,b) local codec=Codec();return codec and codec.Normalize(a)~=nil and codec.Normalize(a)==codec.Normalize(b) end
local function IsSelf(sender) return Same(sender,GetUnitName and GetUnitName('player',true)) end
function Y.Settings()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.sync)~='table' then db.sync={} end
 if type(db.sync.guildRank)~='number' then db.sync.guildRank=1 end -- rank index: 0 guild master, 1 first officer rank
 if db.sync.auto==nil then db.sync.auto=true end
 return db.sync
end

------------------------------------------------------------------ Records
local function TombRecords(kind,list,live)
 for uid,deleted in pairs(addon.Tombstones and addon.Tombstones(kind) or {}) do
  if not live[uid] and type(deleted)=='number' then list[#list+1]={u=uid,v=deleted,x=true} end
 end
end
-- All records of a kind (live and tombstones).
function Y.Records(key)
 local list,live={},{}
 if key=='notes' then
  local store=addon.NativeNotes and addon.NativeNotes.Store()
  for _,item in ipairs(store and store.items or {}) do
   if addon.ValidUID(item.uid) then live[item.uid]=true;list[#list+1]={u=item.uid,v=item.updatedAt or 0,d={name=item.name,text=item.text,bossID=item.bossID}} end
  end
  TombRecords('notes',list,live)
 elseif key=='visual' then
  local store=addon.NativeVisualNotes and addon.NativeVisualNotes.Store()
  for _,item in ipairs(store and store.items or {}) do
   if addon.ValidUID(item.uid) then
    local data=Copy(item);data.id,data.uid,data.updated,data.origin=nil,nil,nil,nil
    live[item.uid]=true;list[#list+1]={u=item.uid,v=item.updated or 0,d=data}
   end
  end
  TombRecords('visual',list,live)
 elseif key=='reminders' then
  local R=addon.Reminders;local db=R and R.Store()
  for uid,data in pairs(db and db.global or {}) do
   if type(uid)=='string' then local copy=Copy(data);copy.updated=nil;live[uid]=true;list[#list+1]={u=uid,v=data.updated or 0,d=copy} end
  end
  TombRecords('reminders',list,live)
 elseif key=='plans' then
  local A=addon.Assignments;local store=A and A.Store()
  for bossID,plan in pairs(store and store.plans or {}) do
   local entries={}
   for _,entry in ipairs(plan.entries or {}) do local copy=Copy(entry);copy.id=nil;entries[#entries+1]=copy end
   list[#list+1]={u='plan-'..bossID,v=plan.updated or 0,d={boss=bossID,name=plan.name,entries=entries}}
  end
 elseif key=='auras' then
  local U=addon.Auras
  for bossID,config in pairs(U and U.Store().bosses or {}) do
   local data={};for field,value in pairs(config) do if field~='updated' then data[field]=Copy(value) end end
   list[#list+1]={u='auras-'..bossID,v=config.updated or 0,d=data}
  end
 elseif key=='roster' then
  local A=addon.Assignments;local store=A and A.Store()
  if store and store.roster and A.Roster() then list[#list+1]={u='roster',v=store.roster.updated or 0,d={text=A.EncodeRoster(store.roster)}}
  elseif store and type(store.rosterCleared)=='number' then list[#list+1]={u='roster',v=store.rosterCleared,x=true} end
 end
 table.sort(list,function(a,b) return a.u<b.u end)
 return list
end
-- Snapshot: records with fingerprint keys and sums (cached until a change).
function Y.Snapshot(key)
 local cached=Y.cache[key]
 if cached and GetTime()-cached.at<30 then return cached end
 local snapshot={records=Y.Records(key),keys={},byID={},byUid={},a=0,b=0,at=GetTime()}
 for index,record in ipairs(snapshot.records) do
  local k=I.Key(record);snapshot.keys[index]=k
  snapshot.byID[I.ID(k)]=record;snapshot.byUid[record.u]=record
  snapshot.a=(snapshot.a+k[1])%I.P;snapshot.b=(snapshot.b+k[2])%I.P
 end
 snapshot.count=#snapshot.records
 Y.cache[key]=snapshot
 return snapshot
end
function Y.Count(key)
 local count=0;for _,record in ipairs(Y.Snapshot(key).records) do if not record.x then count=count+1 end end;return count
end
function Y.Changed(key)
 Y.cache[key]=nil
 if kindByKey[key] then Y.dirty[key]=GetTime()+10 end -- announce shortly (coalesces bursts of edits)
end

-- Newer version wins; equal versions are decided by content so all converge.
local function Wins(incoming,current)
 if not current then return true end
 if incoming.v~=current.v then return incoming.v>current.v end
 return I.Canonical(incoming)>I.Canonical(current)
end
local function Valid(record)
 return type(record)=='table' and type(record.u)=='string' and #record.u<=120 and type(record.v)=='number' and record.v>=0 and record.v<1e10
  and ((record.x==true and record.d==nil) or (record.x==nil and type(record.d)=='table'))
end
-- Apply one record of a kind. Returns true (changed), false (older/same) or nil,message.
function Y.ApplyRecord(key,record,sender)
 if not Valid(record) then return nil,'invalid record' end
 local current=Y.Snapshot(key).byUid[record.u]
 if not Wins(record,current) then return false end
 -- Keep a backup before taking someone else's change (not for restores).
 if sender~='restore' and addon.Backup then addon.Backup.BeforeIncoming(sender) end
 local uid,version=record.u,record.v
 if key=='notes' then
  if not addon.ValidUID(uid) then return nil,'invalid uid' end
  local N=addon.NativeNotes;local store=N.Store();if not store then return nil,'note storage' end
  local at;for index,item in ipairs(store.items) do if item.uid==uid then at=index end end
  if record.x then
   if at then table.remove(store.items,at) end
   addon.MarkDeleted('notes',uid,version)
  else
   local d=record.d
   if type(d.name)~='string' or d.name=='' or #d.name>240 or type(d.text)~='string' or #d.text>200000 then return nil,'invalid note' end
   if d.bossID~=nil and (type(d.bossID)~='number' or d.bossID<1 or d.bossID%1~=0) then return nil,'invalid boss' end
   local bytes=0;for index,item in ipairs(store.items) do if index~=at then bytes=bytes+#item.text end end
   if bytes+#d.text>4000000 then return nil,'library over 4 MB' end
   if not at and #store.items>=500 then return nil,'library full' end
   local entry=at and Copy(store.items[at]) or {}
   if not at then store.serial=store.serial+1;entry.id='VRT-note-'..store.serial;entry.createdAt=version end
   entry.uid,entry.name,entry.text,entry.bossID,entry.updatedAt=uid,d.name,d.text,d.bossID,version
   if at then store.items[at]=entry else store.items[#store.items+1]=entry end
   addon.Tombstones('notes')[uid]=nil
  end
 elseif key=='visual' then
  if not addon.ValidUID(uid) then return nil,'invalid uid' end
  local V=addon.NativeVisualNotes;local store=V.Store();if not store then return nil,'visual storage' end
  local at;for index,item in ipairs(store.items) do if item.uid==uid then at=index end end
  if record.x then
   if at then table.remove(store.items,at) end
   addon.MarkDeleted('visual',uid,version)
  else
   if not at and #store.items>=100 then return nil,'library full' end
   local note=Copy(record.d);note.uid,note.updated=uid,version
   if at then note.id=store.items[at].id else store.serial=store.serial+1;note.id='VRT-visual-'..store.serial end
   local ok=V.Validate(note);if not ok then return nil,'invalid visual note' end
   store.items[at or (#store.items+1)]=note
   addon.Tombstones('visual')[uid]=nil
  end
 elseif key=='reminders' then
  local R=addon.Reminders;local db=R.Store();if not db then return nil,'reminder storage' end
  if record.x then
   db.global[uid]=nil;addon.MarkDeleted('reminders',uid,version)
  else
   local data=Copy(record.d);data.uid,data.updated=uid,version
   local ok=R.Validate(data);if not ok then return nil,'invalid reminder' end
   local count=0;for _ in pairs(db.global) do count=count+1 end
   if not db.global[uid] and count>=200 then return nil,'library full' end
   db.global[uid]=data;addon.Tombstones('reminders')[uid]=nil
  end
 elseif key=='plans' then
  local A=addon.Assignments;local d=record.d
  if record.x or type(d.boss)~='number' or 'plan-'..d.boss~=uid or type(d.entries)~='table' then return nil,'invalid plan' end
  local ok,message=A.ReplacePlan(d.boss,d.name,d.entries,version);if not ok then return nil,message end
 elseif key=='auras' then
  local bossID=tonumber(uid:match('^auras%-(%d+)$'))
  if record.x or not bossID or not addon.Auras then return nil,'invalid aura setup' end
  local ok,message=addon.Auras.Replace(bossID,record.d,version);if not ok then return nil,message end
 elseif key=='roster' then
  local A=addon.Assignments
  if uid~='roster' then return nil,'invalid roster' end
  if record.x then A.ClearRoster(version)
  else
   local roster=type(record.d.text)=='string' and A.ParseRoster(record.d.text);if not roster then return nil,'invalid roster' end
   local ok,message=A.SetRoster(roster,sender,version);if not ok then return nil,message end
  end
 else return nil,'unknown kind' end
 Y.cache[key]=nil
 return true
end
local function AfterApply(key)
 if key=='notes' and addon.RefreshNativeTextNote then addon.RefreshNativeTextNote() end
 if key=='visual' and addon.UpdateVisualNote then addon.UpdateVisualNote() end
 if key=='reminders' and addon.Reminders and addon.Reminders.Changed then addon.Reminders.Changed() end
 if (key=='plans' or key=='roster') and addon.RefreshAssignmentsPage then addon.RefreshAssignmentsPage() end
end
Y.AfterApply=AfterApply

------------------------------------------------------------------ Transport
local function Encode(message)
 local text,err=Codec().Encode(message);if not text then return nil,err end
 local api=C_EncodingUtil
 if api and api.CompressString and api.EncodeBase64 then
  local method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
  local variant=Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
  local ok,compressed=pcall(api.CompressString,text,method)
  if ok and type(compressed)=='string' then
   local encoded;ok,encoded=pcall(api.EncodeBase64,compressed,variant)
   if ok and type(encoded)=='string' and #encoded<#text and encoded:match('^[%w_%-=]+$') then return encoded,'C' end
  end
 end
 return text,'D'
end
local function Decode(payload,mode)
 if mode=='D' then return Codec().Decode(payload) end
 local api=C_EncodingUtil
 if not api or not api.DecodeBase64 or not api.DecompressString then return nil end
 local method=Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
 local variant=Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
 local ok,compressed=pcall(api.DecodeBase64,payload,variant);if not ok or type(compressed)~='string' then return nil end
 local text;ok,text=pcall(api.DecompressString,compressed,method);if not ok or type(text)~='string' then return nil end
 return Codec().Decode(text)
end
-- Queue one message table for a channel ('WHISPER' needs target).
function Y.Post(message,channel,target)
 if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or not Codec() then return false,'Addon messages are unavailable.' end
 local payload,mode=Encode(message);if not payload then return false,'too large' end
 local total=math.ceil(#payload/CHUNK)
 if total>MAX_PARTS then return false,'too large' end
 if #Y.outgoing+total>4000 then return false,'Sync queue is full; try again shortly.' end
 Y.sequence=Y.sequence+1
 local id=string.format('%x%x',Now()%65536,Y.sequence%65536)
 for part=1,total do
  Y.outgoing[#Y.outgoing+1]={message=table.concat({id,part,total,mode,payload:sub((part-1)*CHUNK+1,part*CHUNK)},'|'),channel=channel,target=target}
 end
 return true
end
function Y.Tick()
 local item=Y.outgoing[1];if not item or Busy() then return end
 if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
 local ok,result=pcall(C_ChatInfo.SendAddonMessage,Y.prefix,item.message,item.channel,item.target)
 local enum=Enum and Enum.SendAddonMessageResult
 if ok and enum and result==enum.AddonMessageThrottle then return end
 table.remove(Y.outgoing,1) -- sent, or refused (a missing whisper target): reconciliation retries later
end

------------------------------------------------------------------ Trust
function Y.GuildRankIndex(sender)
 if not InGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
 for index=1,GetNumGuildMembers() do
  local name,_,rankIndex=GetGuildRosterInfo(index)
  if Public(name) and type(name)=='string' and (Same(name,sender) or (not name:find('-',1,true) and Short(name)==Short(sender))) then return rankIndex end
 end
end
function Y.Trusted(sender)
 local codec=Codec()
 if codec and codec.RaidAuthority and codec.RaidAuthority(sender) then return true end
 local rank=Y.GuildRankIndex(sender)
 return rank~=nil and rank<=Y.Settings().guildRank
end
-- Only guild members and group members can open sessions with us.
function Y.Known(sender)
 if Y.GuildRankIndex(sender)~=nil then return true end
 local name=Ambiguate and Ambiguate(sender,'none') or sender
 return (UnitInRaid and UnitInRaid(name)~=nil) or (UnitInParty and UnitInParty(name)) or false
end

------------------------------------------------------------------ Announce
local function Summary(key,manual,reply)
 local snapshot=Y.Snapshot(key)
 return {o='sum',k=key,c=snapshot.count,a=snapshot.a,b=snapshot.b,m=manual or nil,r=reply or nil}
end
-- Announce a summary. target: 'RAID' (raid or party), 'GUILD' or a player name.
function Y.Announce(key,target,manual)
 local kind=kindByKey[key];if not kind then return false,'Unknown sync type.' end
 if Busy() then return false,'Sync outside combat and encounters.' end
 local channel,whom,where
 if target=='RAID' then
  if not IsInGroup() then return false,'Join a group first.' end
  channel=IsInRaid() and 'RAID' or 'PARTY';where='your group'
 elseif target=='GUILD' then
  if not InGuild() then return false,'You are not in a guild.' end
  channel='GUILD';where='your guild'
 else
  if type(target)~='string' or target=='' or target:find('[|%c%s]') or #target>60 then return false,'Type a player name (Name or Name-Realm).' end
  channel='WHISPER';whom=target;where=target
 end
 local ok,err=Y.Post(Summary(key,manual),channel,whom);if not ok then return false,err end
 if manual then Say(string.format('Offered %s to %s; they fetch only what changed.',kind.label:lower(),where)) end
 return true,Y.status
end
Y.Send=function(key,target) return Y.Announce(key,target,true) end

------------------------------------------------------------------ Requester
local function Queue(peer,key,forced)
 for _,job in ipairs(Y.jobs) do if Same(job.peer,peer) and job.key==key then job.forced=job.forced or forced;job.due=nil;return end end
 if Y.active and Same(Y.active.peer,peer) and Y.active.key==key then return end
 Y.jobs[#Y.jobs+1]={peer=peer,key=key,forced=forced}
end
local function Ask(job,message)
 Y.sequence=Y.sequence+1
 message.k,message.s=job.key,job.session or ('q'..Y.sequence)
 job.session=message.s;job.wait=GetTime()
 Y.Post(message,'WHISPER',job.peer)
end
local function Finish(job,text,retry)
 if Y.active~=job then return end
 Y.active=nil
 if retry then
  job.tries=(job.tries or 0)+1
  if job.tries<6 then Y.jobs[#Y.jobs+1]={peer=job.peer,key=job.key,forced=job.forced,tries=job.tries,due=GetTime()+math.min(120,20*job.tries)} end
 end
 if job.applied and job.applied>0 then AfterApply(job.key) end
 local kind=kindByKey[job.key]
 if text then Say(text,true)
 elseif (job.applied or 0)>0 or (job.failed or 0)>0 then
  Say(string.format('Synced %s from %s.%s',Plural(job.applied or 0,kind.noun..' change'),(job.peer:gsub('%-.*$','')),(job.failed or 0)>0 and (' '..job.failed..' could not be applied (limits or invalid data).') or ''))
 end
end
local function NextGet(job)
 if #job.wanted==0 then
  if job.nextOffset then Ask(job,{o='inv',f=job.nextOffset}) else Finish(job) end
  return
 end
 local keys={}
 for _=1,math.min(job.limit or BATCH,#job.wanted) do keys[#keys+1]=table.remove(job.wanted) end
 job.expected=keys
 Ask(job,{o='get',keys=keys})
end
local function Start(job)
 Y.active=job;job.applied,job.failed=0,0
 local snapshot=Y.Snapshot(job.key)
 job.localState=snapshot
 Ask(job,{o='open',c=snapshot.count,a=snapshot.a,b=snapshot.b})
end
local function Response(sender,message)
 local job=Y.active
 if not job or not Same(sender,job.peer) or message.s~=job.session or message.k~=job.key then return end
 job.wait=GetTime()
 local op=message.o
 if op=='bad' then Finish(job,'Sync with '..(job.peer:gsub('%-.*$',''))..' was interrupted; retrying shortly.',true);return end
 if op=='re' then
  if message.q or message.c==0 then Finish(job);return end
  local gap=math.abs(job.localState.count-(tonumber(message.c) or 0))
  if job.localState.count==0 or gap>128 then job.wanted={};Ask(job,{o='inv',f=1});return end
  job.size=gap>32 and 256 or (gap>8 and 64 or 16)
  Ask(job,{o='ib',n=job.size})
 elseif op=='cells' then
  if not I.Valid(message.cells,job.size) then return end
  local cells=I.New(job.size)
  for _,k in ipairs(job.localState.keys) do I.Add(cells,k,1) end
  local _,missing=I.Peel(I.Subtract(cells,message.cells))
  if missing then job.wanted=missing;NextGet(job)
  elseif job.size<256 then job.size=job.size*4;Ask(job,{o='ib',n=job.size})
  else job.wanted={};Ask(job,{o='inv',f=1}) end
 elseif op=='keys' then
  if type(message.keys)~='table' or #message.keys>PAGE then return end
  job.wanted={}
  for _,k in ipairs(message.keys) do
   if type(k)~='table' or type(k[1])~='number' or type(k[2])~='number' then return end
   if not job.localState.byID[I.ID(k)] then job.wanted[#job.wanted+1]=k end
  end
  job.nextOffset=not message.fin and tonumber(message.nx) or nil
  NextGet(job)
 elseif op=='big' then
  if job.expected and #job.expected>1 then
   job.limit=math.max(1,math.floor(#job.expected/2))
   for _,k in ipairs(job.expected) do job.wanted[#job.wanted+1]=k end
  else job.failed=job.failed+1 end
  NextGet(job)
 elseif op=='recs' then
  if type(message.recs)~='table' or not job.expected or #message.recs~=#job.expected then return end
  for index,record in ipairs(message.recs) do if not Valid(record) or I.ID(I.Key(record))~=I.ID(job.expected[index]) then return end end
  if Busy() then Finish(job,'Sync paused for combat; retrying afterwards.',true);return end
  for _,record in ipairs(message.recs) do
   local changed=Y.ApplyRecord(job.key,record,job.peer)
   if changed then job.applied=job.applied+1;Y.received=Y.received+1 elseif changed==nil then job.failed=job.failed+1 end
  end
  NextGet(job)
 end
end

------------------------------------------------------------------ Server
local function Serve(sender,message)
 if not Y.Known(sender) then return end
 local key=message.k;if not kindByKey[key] then return end
 local servingKey=Short(sender) -- one session per peer; a new open replaces it
 local function Reply(reply) reply.k,reply.s=key,message.s;Y.Post(reply,'WHISPER',sender) end
 if message.o=='open' then
  local count=0;for _ in pairs(Y.serving) do count=count+1 end
  if count>=MAX_SERVING and not Y.serving[servingKey] then Reply({o='bad'});return end
  local snapshot=Y.Snapshot(key)
  Y.serving[servingKey]={snapshot=snapshot,at=GetTime(),session=message.s,key=key}
  Reply({o='re',q=(message.c==snapshot.count and message.a==snapshot.a and message.b==snapshot.b) or nil,c=snapshot.count})
  return
 end
 local served=Y.serving[servingKey]
 if not served or served.session~=message.s or served.key~=key then Reply({o='bad'});return end
 served.at=GetTime()
 local snapshot=served.snapshot
 if message.o=='ib' then
  local size=message.n;if size~=16 and size~=64 and size~=256 then return end
  local cells=I.New(size);for _,k in ipairs(snapshot.keys) do I.Add(cells,k,1) end
  Reply({o='cells',cells=cells})
 elseif message.o=='inv' then
  local offset=tonumber(message.f);if not offset or offset<1 or offset%1~=0 or offset>snapshot.count+1 then return end
  local keys={};for index=offset,math.min(offset+PAGE-1,snapshot.count) do keys[#keys+1]=snapshot.keys[index] end
  Reply({o='keys',keys=keys,nx=offset+#keys,fin=offset+#keys>snapshot.count or nil})
 elseif message.o=='get' then
  if type(message.keys)~='table' or #message.keys>BATCH then return end
  local records={}
  for _,k in ipairs(message.keys) do
   if type(k)~='table' or type(k[1])~='number' or type(k[2])~='number' then return end
   local record=snapshot.byID[I.ID(k)];if not record then Reply({o='bad'});return end
   records[#records+1]=record
  end
  if not Y.Post({o='recs',k=key,s=message.s,recs=records},'WHISPER',sender) then Reply({o='big'}) end
 end
end

------------------------------------------------------------------ Summaries received
local replied={}
local function OnSummary(sender,channel,message)
 local key=message.k
 local snapshot=Y.Snapshot(key)
 if message.c==snapshot.count and message.a==snapshot.a and message.b==snapshot.b then return end
 if Y.Trusted(sender) then Queue(sender,key,false)
 elseif message.m then
  local exists=false
  for _,offer in ipairs(Y.pending) do if Same(offer.sender,sender) and offer.key==key then exists=true end end
  if not exists then
   if #Y.pending>=8 then table.remove(Y.pending,1) end
   Y.pending[#Y.pending+1]={sender=sender,key=key,count=tonumber(message.c) or 0}
   Say(string.format('%s offered %s. Accept or decline in Settings > Sync.',(sender:gsub('%-.*$','')),kindByKey[key].label:lower()))
  end
 end
 -- Answer a broadcast with our own summary, so the sender can fetch from us.
 if not message.r and channel~='WHISPER' and Y.Known(sender) then
  local tag=Short(sender)..'|'..key
  if not replied[tag] or GetTime()-replied[tag]>60 then replied[tag]=GetTime();Y.Post(Summary(key,nil,true),'WHISPER',sender) end
 end
end
function Y.Accept(index)
 local offer=Y.pending[index];if not offer then return false,'Nothing to accept.' end
 if Busy() then return false,'Accept after combat.' end
 table.remove(Y.pending,index);Queue(offer.sender,offer.key,true)
 Say('Fetching '..kindByKey[offer.key].label:lower()..' changes from '..(offer.sender:gsub('%-.*$',''))..'.')
 return true,Y.status
end
function Y.Decline(index)
 local offer=Y.pending[index];if not offer then return false,'Nothing to decline.' end
 table.remove(Y.pending,index);Say('Declined sync from '..(offer.sender:gsub('%-.*$',''))..'.');return true,Y.status
end
------------------------------------------------------------------ Versions
-- Ask the group or guild which VRT version each player has and whether
-- their data matches ours (each kind's summary fingerprint).
Y.versions={}
function Y.Version()
 local metadata=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
 local ok,value=pcall(metadata or function() end,'VincRaidTools','Version')
 return ok and type(value)=='string' and value or 'unknown'
end
local function Fingerprints()
 local out={}
 for _,kind in ipairs(Y.kinds) do local s=Y.Snapshot(kind.key);out[kind.key]=s.count..':'..s.a..':'..s.b end
 return out
end
-- Version order: -1 older, 0 same, 1 newer. X.Y.Z compares numerically; for
-- the same X.Y.Z a Release is newer than any Beta, Beta.N orders by N, and
-- development builds ("-dev" or no suffix) count as the same build.
function Y.CompareVersions(a,b)
 local function Parse(text)
  text=tostring(text)
  local core,list=text:match('^[%d%.]+') or '',{}
  for n in core:gmatch('%d+') do list[#list+1]=tonumber(n) end
  local beta=text:match('%-[Bb]eta%.?(%d+)')
  local stage=text:find('%-[Rr]elease') and math.huge or (beta and tonumber(beta)) or 0
  return list,stage
 end
 local x,xs=Parse(a)
 local y,ys=Parse(b)
 for index=1,math.max(#x,#y,3) do
  local p,q=x[index] or 0,y[index] or 0
  if p~=q then return p<q and -1 or 1 end
 end
 if xs~=ys then return xs<ys and -1 or 1 end
 return 0
end
-- target: 'RAID' (raid or party) or 'GUILD'.
function Y.CheckVersions(target)
 if Busy() then return false,'Check versions outside combat and encounters.' end
 local channel
 if target=='RAID' then if not IsInGroup() then return false,'Join a group first.' end;channel=IsInRaid() and 'RAID' or 'PARTY'
 elseif target=='GUILD' then if not InGuild() then return false,'You are not in a guild.' end;channel='GUILD'
 else return false,'Choose raid or guild.' end
 Y.versions={};Y.versionScope=target;Y.versionAsked=GetTime()
 local ok,err=Y.Post({o='vq'},channel);if not ok then return false,err end
 return true,'Asking '..(target=='GUILD' and 'the guild' or 'your group')..' for VRT versions...'
end
local answered={}
local function OnVersion(sender,channel,message)
 if message.o=='vq' then
  -- Answer each asker at most once every 10 seconds.
  local tag=Short(sender)
  if answered[tag] and GetTime()-answered[tag]<10 then return end
  answered[tag]=GetTime()
  Y.Post({o='va',ver=Y.Version(),d=Fingerprints()},'WHISPER',sender)
 elseif message.o=='va' and channel=='WHISPER' and type(message.ver)=='string' and #message.ver<=40 and type(message.d)=='table' then
  local digests={}
  for _,kind in ipairs(Y.kinds) do local value=message.d[kind.key];if type(value)=='string' and #value<=60 then digests[kind.key]=value end end
  Y.versions[Short(sender)]={name=(sender:gsub('%-.*$','')),full=sender,ver=message.ver,digests=digests,at=GetTime()}
  if addon.RefreshVersionsTab then addon.RefreshVersionsTab() end
 end
end
-- Rows for the Versions tab: everyone who answered, plus group members who did not.
function Y.VersionRows()
 local mine=Fingerprints();local myVersion=Y.Version()
 local rows={}
 for _,entry in pairs(Y.versions) do
  local row={name=entry.name,ver=entry.ver,installed=true,older=Y.CompareVersions(entry.ver,myVersion)<0,newer=Y.CompareVersions(entry.ver,myVersion)>0,same={}}
  for _,kind in ipairs(Y.kinds) do row.same[kind.key]=entry.digests[kind.key]==mine[kind.key] end
  rows[#rows+1]=row
 end
 if Y.versionScope=='RAID' and IsInGroup() and Y.versionAsked and GetTime()-Y.versionAsked>5 then
  local units={}
  if IsInRaid() then for index=1,GetNumGroupMembers() do units[#units+1]='raid'..index end
  else for index=1,4 do units[#units+1]='party'..index end end
  for _,unit in ipairs(units) do
   local name=UnitName(unit)
   if Public(name) and type(name)=='string' and not (UnitIsUnit and UnitIsUnit(unit,'player')) and not Y.versions[name:lower()] then
    rows[#rows+1]={name=name,installed=false,same={}}
   end
  end
 end
 table.sort(rows,function(a,b)
  if a.installed~=b.installed then return a.installed end
  return a.name:lower()<b.name:lower()
 end)
 return rows
end

function Y.Handle(sender,channel,message)
 if type(message)=='table' and (message.o=='vq' or message.o=='va') then OnVersion(sender,channel,message);return end
 if type(message)~='table' or not kindByKey[message.k] then return end
 if message.o=='sum' then
  if type(message.c)=='number' and type(message.a)=='number' and type(message.b)=='number' then OnSummary(sender,channel,message) end
 elseif channel=='WHISPER' then
  if message.o=='open' or message.o=='ib' or message.o=='inv' or message.o=='get' then Serve(sender,message)
  else Response(sender,message) end
 end
end

------------------------------------------------------------------ Receive
function Y.OnMessage(prefix,message,channel,sender)
 if prefix~=Y.prefix or not Public(message) or not Public(sender) or not Public(channel) then return end
 if type(message)~='string' or #message>255 or type(sender)~='string' then return end
 if channel~='RAID' and channel~='PARTY' and channel~='GUILD' and channel~='WHISPER' and channel~='INSTANCE_CHAT' then return end
 if IsSelf(sender) then return end
 local id,part,total,mode,chunk=message:match('^(%x+)|(%d+)|(%d+)|([DC])|(.*)$')
 if not id or #id>10 then return end
 part,total=tonumber(part),tonumber(total)
 if total<1 or total>MAX_PARTS or part<1 or part>total then return end
 local key=sender..'|'..id
 local assembly=Y.incoming[key]
 if not assembly then
  local open=0;for _ in pairs(Y.incoming) do open=open+1 end
  if open>=MAX_ASSEMBLY then return end
  assembly={total=total,mode=mode,got=0,chunks={}}
  Y.incoming[key]=assembly
 end
 if assembly.total~=total or assembly.mode~=mode or assembly.chunks[part] then return end
 assembly.chunks[part]=chunk;assembly.got=assembly.got+1;assembly.last=GetTime()
 if assembly.got<total then return end
 Y.incoming[key]=nil
 local decoded=Decode(table.concat(assembly.chunks),mode)
 if type(decoded)=='table' then Y.Handle(sender,channel,decoded) end
end

------------------------------------------------------------------ Scheduler
function Y.Progress()
 local job=Y.active;if not job then return nil end
 return nil,string.format('Syncing %s from %s: %d received.',kindByKey[job.key].label:lower(),(job.peer:gsub('%-.*$','')),job.applied or 0)
end
function Y.Step()
 local now=GetTime()
 for key,assembly in pairs(Y.incoming) do if now-(assembly.last or now)>ASSEMBLY_EXPIRY then Y.incoming[key]=nil end end
 for key,served in pairs(Y.serving) do if now-served.at>SERVE_EXPIRY then Y.serving[key]=nil end end
 if Busy() then return end
 -- Local edits: announce a fresh summary once they settle.
 if Y.Settings().auto then
  for key,due in pairs(Y.dirty) do
   if now>=due then
    Y.dirty[key]=nil
    if InGuild() then Y.Post(Summary(key),'GUILD') end
    if IsInGroup() then Y.Post(Summary(key),IsInRaid() and 'RAID' or 'PARTY') end
   end
  end
 else Y.dirty={} end
 local job=Y.active
 if job then
  if now-(job.wait or now)>WAIT then Finish(job,'Sync with '..(job.peer:gsub('%-.*$',''))..' timed out; retrying shortly.',true) end
  return
 end
 for index,nextJob in ipairs(Y.jobs) do
  if not nextJob.due or now>=nextJob.due then
   table.remove(Y.jobs,index)
   if nextJob.forced or Y.Trusted(nextJob.peer) then Start(nextJob) end
   return
  end
 end
end
function Y.AnnounceAll(channel)
 for _,kind in ipairs(Y.kinds) do Y.Post(Summary(kind.key),channel) end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','CHAT_MSG_ADDON'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event,...)
 if event=='CHAT_MSG_ADDON' then Y.OnMessage(...)
 elseif event=='PLAYER_LOGIN' then
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(Y.prefix) end
  -- Guild ranks (for trust) are only known once the guild roster has been requested.
  if InGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
  -- After login settles, compare with trusted guild members.
  if C_Timer and C_Timer.After then
   C_Timer.After(30,function() if Y.Settings().auto and InGuild() and not Busy() then Y.AnnounceAll('GUILD') end end)
  end
 end
end)
local elapsed,stepElapsed=0,0
frame:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt;stepElapsed=stepElapsed+dt
 if elapsed>=Y.interval then elapsed=0;Y.Tick() end
 if stepElapsed>=1 then stepElapsed=0;Y.Step() end
end)
