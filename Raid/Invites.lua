local _,addon=...
-- Raid invites from the calendar (Guilds of WoW writes its sign-ups there).
-- Phase 1 invites everyone signed up (Signed up, Available, Confirmed) who
-- is online; tentative and standby players are invited only once every
-- signed-up player is in the group (or when the leader chooses to invite
-- them now). Missing signed-up players are re-invited every 90 seconds, up to
-- three times. The party becomes a raid as soon as someone joins.
local V={phase=nil,status='Ready'};addon.Invites=V
local PACE,RETRY,TRIES,MAX_RUN=.5,90,3,1800

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Short(name) return type(name)=='string' and (name:gsub('%-.*$',''):lower()) or nil end
local function Say(text,quiet) V.status=text;if not quiet then print('|cffb8c2cfVincibility:|r '..text) end;if addon.RefreshInvites then addon.RefreshInvites() end end
local function Signups() return addon.Assignments and addon.Assignments.Signups end

-- Who is in our group now (short names).
local function GroupNames()
 local names={}
 local own=UnitName and UnitName('player');if Public(own) and own then names[own:lower()]=true end
 if IsInGroup() then
  local units={}
  if IsInRaid() then for index=1,GetNumGroupMembers() do units[#units+1]='raid'..index end
  else for index=1,4 do units[#units+1]='party'..index end end
  for _,unit in ipairs(units) do
   local name=UnitName(unit)
   if Public(name) and type(name)=='string' then names[name:lower()]=true end
  end
 end
 return names
end
-- Online state from the guild roster: true, false, or nil when not in the guild list.
local function Online(name)
 if not (IsInGuild and IsInGuild()) or not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
 local short=Short(name)
 for index=1,GetNumGuildMembers() do
  local member,_,_,_,_,_,_,_,online=GetGuildRosterInfo(index)
  if Public(member) and type(member)=='string' and Short(member)==short then return online and true or false end
 end
end
function V.CanInvite()
 if InCombatLockdown() then return false,'Invite after combat.' end
 if IsInGroup() and not (UnitIsGroupLeader('player') or (IsInRaid() and UnitIsGroupAssistant('player'))) then return false,'Only the leader (or a raid assistant) can invite.' end
 return true
end

-- Start from a calendar event (nil = the next raid).
function V.Start(event)
 local ok,err=V.CanInvite();if not ok then return false,err end
 local S=Signups();if not S then return false,'Signups are unavailable.' end
 if V.reading then return false,'Already reading the calendar.' end
 if not event then
  local list;list,err=S.Upcoming();if not list then return false,err end
  event=list[1];if not event then return false,'No guild event in the next 7 days. Has Guilds of WoW added the raid to the calendar?' end
 end
 V.reading=true
 local started,message=S.Read(event,function(invites,readError)
  V.reading=false
  if not invites then Say(readError or 'Could not read the event.');return end
  V.Begin(event,invites)
 end)
 if not started then V.reading=false;return false,message end
 return true,'Reading sign-ups for '..event.title..'...'
end
-- Build the lists and start phase 1 (also used by tests with a stand-in invite list).
function V.Begin(event,invites)
 local S=Signups()
 local own=Short(UnitName('player'))
 local accepted,later={},{}
 for _,invite in ipairs(invites) do
  local short=Short(invite.name)
  if short and short~=own then
   local category=S.Category(invite.status)
   if category=='ok' then accepted[#accepted+1]={name=invite.name,tries=0}
   elseif category=='tentative' or category=='standby' then later[#later+1]={name=invite.name,tries=0,category=category} end
  end
 end
 V.event,V.accepted,V.later,V.queue,V.phase,V.started=event,accepted,later,{},1,GetTime()
 V.Queue(accepted)
 Say(string.format('Inviting %d signed-up player%s for %s. Tentative and standby (%d) follow once they are all in.',#accepted,#accepted==1 and '' or 's',event.title,#later))
 V.Check()
 return true
end
-- Queue invites for anyone in the list who is not in the group and is online.
function V.Queue(list,now)
 local inGroup=GroupNames()
 for _,player in ipairs(list) do
  local short=Short(player.name)
  local online=Online(player.name)
  player.offline=online==false
  if not inGroup[short] and online~=false and player.tries<TRIES and (now or not player.sent or GetTime()-player.sent>=RETRY) then
   local queued=false;for _,item in ipairs(V.queue) do if item==player then queued=true end end
   if not queued then V.queue[#V.queue+1]=player end
  end
 end
end
-- Missing signed-up players (not in the group), split into online and offline.
function V.Missing()
 local inGroup=GroupNames();local missing,offline={},{}
 for _,player in ipairs(V.accepted or {}) do
  if not inGroup[Short(player.name)] then
   if player.offline then offline[#offline+1]=player.name else missing[#missing+1]=player.name end
  end
 end
 return missing,offline
end
-- Phase 2: tentative and standby.
function V.InviteLater(manual)
 if not V.phase then return false,'Start invites first.' end
 if V.phase==2 then return false,'Tentative and standby are already invited.' end
 local ok,err=V.CanInvite();if not ok then return false,err end
 V.phase=2;V.Queue(V.later,true)
 Say(string.format('%s: inviting %d tentative and standby player%s.',manual and 'Leader choice' or 'Everyone signed up is in',#V.later,#V.later==1 and '' or 's'))
 return true,V.status
end
function V.Stop()
 if not V.phase then return false,'No invites running.' end
 V.phase,V.queue=nil,{};Say('Invites stopped.');return true,V.status
end
-- Re-check after roster changes and on a timer.
function V.Check()
 if not V.phase then return end
 if GetTime()-V.started>MAX_RUN then V.phase=nil;Say('Invites finished (30 minutes).');return end
 -- Convert to a raid once anyone has joined, so more than five fit.
 if IsInGroup() and not IsInRaid() and GetNumGroupMembers()>1 and UnitIsGroupLeader('player') and C_PartyInfo and C_PartyInfo.ConvertToRaid and not InCombatLockdown() then
  C_PartyInfo.ConvertToRaid()
 end
 local missing,offline=V.Missing()
 if V.phase==1 and #missing==0 and #offline==0 then V.InviteLater(false) end
 if V.phase==1 then V.Queue(V.accepted) end
 local text
 if V.phase==1 then
  text=string.format('Waiting for %d signed-up player%s%s%s.',#missing+#offline,#missing+#offline==1 and '' or 's',
   #missing>0 and (': '..table.concat(missing,', ')) or '',#offline>0 and (' (offline: '..table.concat(offline,', ')..')') or '')
  if #missing+#offline==0 then text='Everyone signed up is in.' end
 else
  local inGroup=GroupNames();local waiting={}
  for _,player in ipairs(V.later) do if not inGroup[Short(player.name)] then waiting[#waiting+1]=player.name end end
  text=#waiting==0 and 'Everyone is invited and in the group.' or ('Tentative/standby still to join: '..table.concat(waiting,', '))
 end
 Say(text,true)
end
-- One invite per tick.
function V.Tick()
 if not V.phase or #V.queue==0 or InCombatLockdown() then return end
 local player=table.remove(V.queue,1)
 if GroupNames()[Short(player.name)] then return end
 player.tries=player.tries+1;player.sent=GetTime()
 if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(player.name) elseif InviteUnit then InviteUnit(player.name) end
end
local frame=CreateFrame('Frame')
frame:RegisterEvent('GROUP_ROSTER_UPDATE')
frame:SetScript('OnEvent',function() V.Check() end)
local elapsed,checkElapsed=0,0
frame:SetScript('OnUpdate',function(_,dt)
 if not V.phase then return end
 elapsed=elapsed+dt;checkElapsed=checkElapsed+dt
 if elapsed>=PACE then elapsed=0;V.Tick() end
 if checkElapsed>=5 then checkElapsed=0;V.Check() end
end)
