local _,addon=...
-- Break timers shared with DBM and BigWigs. Both boss mods use DBM's "D5"
-- break message ("Name-Realm<TAB>1<TAB>BT<TAB>seconds"; 0 cancels), so:
--  * a VRT user with no boss mod shows a break bar when the leader or an
--    assistant starts a break from DBM, BigWigs or VRT;
--  * VRT's own break (the raid panel uses it only when neither boss mod is
--    loaded) is sent in that format, so DBM and BigWigs users see it too.
-- With DBM or BigWigs loaded VRT shows nothing: the boss mod shows the break.
local B={};addon.Break=B
local PREFIX='D5'
B.prefix=PREFIX
local UID='VRT-break'

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Short(name) return type(name)=='string' and (name:gsub('%-.*$','')) or nil end
local function Busy() return InCombatLockdown() or (IsEncounterInProgress and IsEncounterInProgress()) end
function B.BossMod()
 return (DBM and type(DBM.CreateBreakTimer)=='function') or (BigWigsLoader and type(BigWigsLoader.RegisterMessage)=='function') or false
end
local function Channel()
 if IsInGroup(2) then return 'INSTANCE_CHAT' end
 return IsInRaid() and 'RAID' or 'PARTY'
end
-- Leader or assistant of the current group, by name (sender may include a realm).
function B.Authority(sender)
 if not Public(sender) or type(sender)~='string' then return false end
 local wanted=Short(sender);if not wanted then return false end
 local units={}
 if IsInRaid() then for index=1,GetNumGroupMembers() do units[#units+1]='raid'..index end
 else units[1]='player';for index=1,4 do units[#units+1]='party'..index end end
 for _,unit in ipairs(units) do
  local name=UnitName(unit)
  if Public(name) and name==wanted then return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit) or false end
 end
 return false
end
function B.Show(seconds,sender)
 local display=addon.ReminderDisplay
 if seconds<=0 then
  if display and display.Remove then display.Remove(UID) end
  print('|cffb8c2cfVincibility:|r break cancelled'..(sender and (' by '..Short(sender)) or '')..'.')
  return
 end
 if display and display.Show then
  display.Show({uid=UID,message='Break',duration=seconds,display='Bars',countdown=true,icon=134062},{})
 end
 print(string.format('|cffb8c2cfVincibility:|r %d minute break%s.',math.floor(seconds/60+.5),sender and (' from '..Short(sender)) or ''))
end
-- Start a break of the given minutes (1-60), or 0 to cancel, for the group.
function B.Start(minutes)
 minutes=tonumber(minutes)
 if not minutes or minutes<0 or minutes>60 or (minutes>0 and minutes<1) then return false,'Breaks are 1 to 60 minutes.' end
 if Busy() then return false,'Breaks are not available in combat.' end
 local seconds=math.floor(minutes*60)
 if not B.BossMod() then B.Show(seconds) end
 if IsInGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage and not (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then
  local realm=(GetRealmName() or ''):gsub('[%s%-]+','') -- DBM's normalised realm
  C_ChatInfo.SendAddonMessage(PREFIX,string.format('%s-%s\t1\tBT\t%d',UnitName('player'),realm,seconds),Channel())
 end
 return true
end
function B.OnMessage(prefix,message,_,sender)
 if prefix~=PREFIX or B.BossMod() then return end
 if not Public(message) or not Public(sender) or type(message)~='string' then return end
 local _,_,kind,value=strsplit('\t',message)
 if kind~='BT' then return end
 if Short(sender)==UnitName('player') then return end -- our own send
 local seconds=tonumber(value)
 if not seconds or seconds<0 or seconds>3600 or seconds%1~=0 or Busy() or not B.Authority(sender) then return end
 B.Show(seconds,sender)
end
local frame=CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN');frame:RegisterEvent('CHAT_MSG_ADDON')
frame:SetScript('OnEvent',function(_,event,...)
 if event=='PLAYER_LOGIN' then
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
 else B.OnMessage(...) end
end)
