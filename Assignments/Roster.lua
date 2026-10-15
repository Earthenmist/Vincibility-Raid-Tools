local _,addon=...
local function Now() return addon.Now and addon.Now() or (time and time() or 0) end
-- Imported raid-team roster for assignment planning: name, realm, class, spec
-- and role per member, from a VRTR1 import string (tools/gow_roster.py) or a
-- share from another VRT user. Stored only in the account's SavedVariables;
-- no roster data ships with the addon.
local A=addon.Assignments
local PREFIX='VRTROS1'
local CHUNK,MAX_MEMBERS,MAX_TEXT=230,80,8000
local classes={WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,DEATHKNIGHT=true,SHAMAN=true,MAGE=true,WARLOCK=true,MONK=true,DRUID=true,DEMONHUNTER=true,EVOKER=true}
local roles={TANK=true,HEALER=true,DAMAGER=true}
local Share={prefix=PREFIX,incoming={},outgoing={},pending=nil,serial=0};A.RosterShare=Share

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Trim(text) return (tostring(text or ''):gsub('^%s+',''):gsub('%s+$','')) end
local function Clean(text,limit)
 text=Trim(text)
 if text=='' or #text>limit or text:find('[|;,%c]') then return nil end
 return text
end
-- WoW edit boxes escape a pasted "|" as "||"; undo that before parsing.
function A.Unescape(text) return (tostring(text or ''):gsub('||','|')) end
function A.ParseRoster(text)
 text=Trim(A.Unescape(text))
 if #text>MAX_TEXT then return nil,'Roster text is too long.' end
 local team,body=text:match('^VRTR1|([^|]*)|(.*)$')
 if not team then return nil,'Not a VRT roster string (it should start with VRTR1|).' end
 local roster={team=Clean(team,40) or 'Raid team',members={}}
 local seen={}
 for item in (body..';'):gmatch('([^;]*);') do
  if Trim(item)~='' then
   local name,realm,class,spec,role=item:match('^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$')
   name,realm,spec=Clean(name,24),Clean(realm,40),Clean(spec,30)
   if not (name and realm and classes[class] and roles[role]) then return nil,'Roster entry is invalid: '..item:sub(1,40) end
   local key=(name..'-'..realm):lower()
   if not seen[key] then
    seen[key]=true
    roster.members[#roster.members+1]={name=name,realm=realm,class=class,spec=spec,role=role}
    if #roster.members>MAX_MEMBERS then return nil,'A roster holds at most '..MAX_MEMBERS..' members.' end
   end
  end
 end
 if #roster.members==0 then return nil,'The roster has no members.' end
 return roster
end
function A.EncodeRoster(roster)
 local members={}
 for _,m in ipairs(roster.members) do members[#members+1]=table.concat({m.name,m.realm,m.class,m.spec or '',m.role},',') end
 return 'VRTR1|'..(roster.team or 'Raid team')..'|'..table.concat(members,';')
end
function A.Roster()
 local store=A.Store()
 local roster=store and store.roster
 if type(roster)=='table' and type(roster.members)=='table' and #roster.members>0 then return roster end
end
-- updated: the sender's version time when synced; nil for a local import.
function A.SetRoster(roster,source,updated)
 if InCombatLockdown() then return false,'Import the roster after combat.' end
 local store,err=A.Store();if not store then return false,err end
 local now=Now()
 local version=type(updated)=='number' and updated or math.max(now,(store.roster and store.roster.updated or 0)+1,(store.rosterCleared or 0)+1)
 store.roster={team=roster.team,members=roster.members,imported=time and time() or 0,source=source,updated=version}
 store.rosterCleared=nil
 if type(updated)~='number' and addon.SyncChanged then addon.SyncChanged('roster') end
 if addon.RefreshAssignmentsPage then addon.RefreshAssignmentsPage() end
 return true,string.format('Team roster: %s, %d member%s.',roster.team,#roster.members,#roster.members==1 and '' or 's')
end
function A.ImportRoster(text)
 local roster,err=A.ParseRoster(text);if not roster then return false,err end
 return A.SetRoster(roster,'import')
end
function A.ClearRoster(when)
 local store=A.Store()
 if store then
  store.rosterCleared=type(when)=='number' and when or math.max(Now(),(store.roster and store.roster.updated or 0)+1)
  store.roster=nil
  if type(when)~='number' and addon.SyncChanged then addon.SyncChanged('roster') end
 end
 if addon.RefreshAssignmentsPage then addon.RefreshAssignmentsPage() end
 return true,'Team roster cleared.'
end

-- Sharing: chunks "id|index|total|text" on VRTROS1, paced from OnUpdate.
local function Say(text) print('|cffb8c2cfVincibility:|r '..text) end
function Share.Send(channel)
 local roster=A.Roster()
 if not roster then return false,'Import a team roster first.' end
 if InCombatLockdown() then return false,'Share after combat.' end
 if channel=='GROUP' then
  if not IsInGroup() then return false,'Join a group to share with it.' end
  channel=IsInRaid() and 'RAID' or 'PARTY'
 elseif channel=='GUILD' then
  if not IsInGuild() then return false,'You are not in a guild.' end
 else return false,'Choose group or guild.' end
 if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false,'Addon messages are locked right now.' end
 local text=A.EncodeRoster(roster)
 Share.serial=Share.serial+1
 local id=string.format('%x%x',math.random(4096,65535),Share.serial%4096)
 local total=math.ceil(#text/CHUNK)
 for index=1,total do Share.outgoing[#Share.outgoing+1]={message=id..'|'..index..'|'..total..'|'..text:sub((index-1)*CHUNK+1,index*CHUNK),channel=channel} end
 return true,string.format('Sharing %s (%d members) with your %s.',roster.team,#roster.members,channel=='GUILD' and 'guild' or 'group')
end
function Share.Tick(elapsed)
 Share.elapsed=(Share.elapsed or 0)+elapsed
 if Share.elapsed<.25 or #Share.outgoing==0 then return end
 Share.elapsed=0
 local item=table.remove(Share.outgoing,1)
 if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage,PREFIX,item.message,item.channel) end
end
local function IsSelf(sender)
 local codec=addon.ReminderSharing
 local own=GetUnitName and GetUnitName('player',true)
 if codec and codec.Normalize and own then return codec.Normalize(sender)==codec.Normalize(own) end
 return Ambiguate and Ambiguate(sender,'none')==UnitName('player')
end
local function Trusted(sender,channel)
 if channel=='GUILD' then return false end
 local codec=addon.ReminderSharing
 return codec and codec.Authority and codec.Authority(sender) or false
end
function Share.Receive(roster,sender,channel)
 if Trusted(sender,channel) and not InCombatLockdown() then
  if addon.Backup then addon.Backup.BeforeIncoming(sender) end
  local ok,message=A.SetRoster(roster,sender)
  if ok then Say('team roster from '..sender..' applied ('..#roster.members..' members).') end
  return ok
 end
 Share.pending={roster=roster,sender=sender,channel=channel}
 Say('team roster from '..sender..' ('..#roster.members..' members). Open Assignments > Team roster to accept or decline.')
 if addon.RefreshAssignmentsPage then addon.RefreshAssignmentsPage() end
 return false
end
function Share.Accept()
 local pending=Share.pending;if not pending then return false,'Nothing to accept.' end
 if addon.Backup then addon.Backup.BeforeIncoming(pending.sender) end
 local ok,message=A.SetRoster(pending.roster,pending.sender)
 if ok then Share.pending=nil end
 return ok,message
end
function Share.Decline() Share.pending=nil;return true,'Shared roster declined.' end
function Share.OnMessage(prefix,message,channel,sender)
 if not (Public(prefix) and Public(message) and Public(sender) and Public(channel)) or prefix~=PREFIX then return end
 if type(message)~='string' or type(sender)~='string' or IsSelf(sender) then return end
 local id,index,total,chunk=message:match('^(%x+)|(%d+)|(%d+)|(.*)$')
 index,total=tonumber(index),tonumber(total)
 if not id or not index or not total or total<1 or total>40 or index<1 or index>total then return end
 local key=sender..':'..id
 local transfer=Share.incoming[key]
 if not transfer then transfer={parts={},count=0,total=total,when=GetTime()};Share.incoming[key]=transfer end
 if transfer.total~=total then Share.incoming[key]=nil;return end
 if not transfer.parts[index] then transfer.parts[index]=chunk;transfer.count=transfer.count+1 end
 if transfer.count<total then return end
 Share.incoming[key]=nil
 local roster=A.ParseRoster(table.concat(transfer.parts))
 if roster then Share.Receive(roster,sender,channel) end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','CHAT_MSG_ADDON'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event,...)
 if event=='PLAYER_LOGIN' then
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX) end
 else Share.OnMessage(...) end
end)
frame:SetScript('OnUpdate',function(_,elapsed)
 Share.Tick(elapsed)
 for key,transfer in pairs(Share.incoming) do if GetTime()-transfer.when>60 then Share.incoming[key]=nil end end
end)
