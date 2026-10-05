local _,addon=...
-- Missing food/flask chat report when a ready check finishes. Only the player
-- who started the check posts to group chat; "only print it to me" shows the
-- report locally for anyone. Reads public aura data only.
local RC=addon.ReadyCheck
local O=RC.Overview
local Report={};RC.Report=Report
local LIMIT=250

local function Public(value) return not issecretvalue or not issecretvalue(value) end
-- Group names into chat lines no longer than LIMIT characters.
function Report.Lines(label,names)
 local lines,current={},nil
 label=label:sub(1,1):upper()..label:sub(2)
 for _,name in ipairs(names) do
  if not current then current=label..': '..name
  elseif #current+2+#name>LIMIT then lines[#lines+1]=current;current=label..' (cont.): '..name
  else current=current..', '..name end
 end
 if current then lines[#lines+1]=current end
 return lines
end
function Report.Collect()
 local settings=RC.Settings()
 local warnSeconds=(settings.flaskWarn or 0)*60
 local food,flask,expiring={},{},{}
 for _,unit in ipairs(O.Units()) do
  if UnitIsConnected(unit) and UnitIsVisible(unit) then
   local name=UnitName(unit)
   local record=O.ScanUnit(unit)
   if record.restricted then return nil end
   if name and Public(name) then
    if not record.food and not record.eating then food[#food+1]=name end
    if not record.flask then flask[#flask+1]=name
    elseif warnSeconds>0 and record.flask.remaining and record.flask.remaining<warnSeconds then expiring[#expiring+1]=name end
   end
  end
 end
 table.sort(food);table.sort(flask);table.sort(expiring)
 local lines={}
 for _,line in ipairs(Report.Lines('no food',food)) do lines[#lines+1]=line end
 for _,line in ipairs(Report.Lines('no flask',flask)) do lines[#lines+1]=line end
 for _,line in ipairs(Report.Lines('flask under '..(settings.flaskWarn or 0)..' min',expiring)) do lines[#lines+1]=line end
 return lines
end
local function Say(text) print('|cffb8c2cfVincibility:|r '..text) end
local function Send(text,channel)
 if C_ChatInfo and C_ChatInfo.SendChatMessage then return pcall(C_ChatInfo.SendChatMessage,text,channel) end
 if SendChatMessage then return pcall(SendChatMessage,text,channel) end
 return false
end
function Report.Run()
 local settings=RC.Settings()
 if not settings.chatReport or not RC.ShouldRun() then return end
 local selfOnly=settings.chatSelfOnly
 if not selfOnly and not Report.startedByMe then return end
 local lines=Report.Collect()
 if not lines then Say('buff data is hidden by the game right now; no food/flask report.');return end
 if #lines==0 then
  if selfOnly then Say('Everyone has food and a flask.') else lines={'Everyone has food and a flask.'} end
 end
 if selfOnly then for _,line in ipairs(lines) do Say(line) end;return end
 if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
  Say('chat is locked right now; report printed here instead.')
  for _,line in ipairs(lines) do Say(line) end
  return
 end
 local channel=IsInRaid() and 'RAID' or 'PARTY'
 for _,line in ipairs(lines) do Send(line,channel) end
end
-- Options-page preview: always local, never sent to group chat.
function Report.Preview()
 local lines=Report.Collect()
 if not lines then Say('buff data is hidden by the game right now; no food/flask report.');return end
 if #lines==0 then Say('(preview) Everyone has food and a flask.');return end
 for _,line in ipairs(lines) do Say('(preview) '..line) end
end
function Report.OnReadyCheck(initiator)
 if addon.ModuleEnabled and not addon.ModuleEnabled('readycheck') then return end
 Report.startedByMe=false
 if initiator and Public(initiator) then
  local ok,same=pcall(UnitIsUnit,initiator,'player')
  if ok and same then Report.startedByMe=true
  elseif Ambiguate and UnitName and UnitName('player')==Ambiguate(initiator,'none') then Report.startedByMe=true end
 end
end
local events=CreateFrame('Frame')
for _,event in ipairs({'READY_CHECK','READY_CHECK_FINISHED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event,...)
 if event=='READY_CHECK' then Report.OnReadyCheck(...)
 elseif not InCombatLockdown() then Report.Run() end
end)
