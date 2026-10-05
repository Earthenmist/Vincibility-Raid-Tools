local _,addon=...
-- Signup check: compare named assignments with the sign-ups on a guild
-- calendar event (Guilds of WoW writes its sign-ups there, so this works with
-- GoW or a hand-made event). On demand only. The calendar is read, never
-- changed, and left alone while Blizzard's calendar window or another addon
-- (such as Guilds of WoW) is using it.
local A=addon.Assignments
local S={};A.Signups=S
local DAYS=7

local function Status(name,fallback) return Enum and Enum.CalendarStatus and Enum.CalendarStatus[name] or fallback end
-- Category per calendar status: ok, tentative, standby or missing.
function S.Category(status)
 if status==nil then return 'missing' end
 if status==Status('Signedup',6) or status==Status('Available',1) or status==Status('Confirmed',3) then return 'ok' end
 if status==Status('Tentative',8) then return 'tentative' end
 if status==Status('Standby',5) then return 'standby' end
 return 'missing' -- Invited (no reply), Not signed up, Declined, Out
end
S.categoryLabels={missing='Not signed up',tentative='Tentative',standby='Standby'}

local function Normalize(name)
 if type(name)~='string' or name=='' then return nil end
 local short,realm=name:match('^([^%-]+)%-(.+)$')
 short=(short or name):lower()
 return short,realm and realm:gsub('[%s%-]',''):lower() or nil
end
-- Lookup by short name and by Name-Realm (the calendar omits same-realm realms).
local function Index(invites)
 local byShort,byFull={},{}
 for _,invite in ipairs(invites) do
  local short,realm=Normalize(invite.name)
  if short then
   if realm then byFull[short..'-'..realm]=invite.status end
   if byShort[short]==nil or S.Category(invite.status)=='ok' then byShort[short]=invite.status end
  end
 end
 return byShort,byFull
end
local function StatusFor(name,byShort,byFull)
 local short,realm=Normalize(name);if not short then return nil end
 if realm and byFull[short..'-'..realm]~=nil then return byFull[short..'-'..realm] end
 return byShort[short]
end

-- Compare every named assignment in the saved plans with the invite list.
-- invites: {{name=,status=}}. Returns {missing={},tentative={},standby={},flags={},checked=n}.
function S.Compare(invites)
 local byShort,byFull=Index(invites or {})
 local result={missing={},tentative={},standby={},flags={},checked=0,byShort=byShort,byFull=byFull}
 local store=A.Store()
 local seen={}
 for bossID,plan in pairs(store and store.plans or {}) do
  for _,entry in ipairs(plan.entries or {}) do
   for _,who in ipairs(entry.who or {}) do
    if not A.roleLabels[who] then
     result.checked=result.checked+1
     local category=S.Category(StatusFor(who,byShort,byFull))
     if category~='ok' then
      local key=bossID..'|'..entry.id..'|'..who:lower()
      if not seen[key] then
       seen[key]=true
       local list=result[category]
       list[#list+1]={name=who,boss=plan.name or ('Boss '..bossID),bossID=bossID,entry=entry}
       result.flags[(Normalize(who))]=category
      end
     end
    end
   end
  end
 end
 for _,category in ipairs({'missing','tentative','standby'}) do
  table.sort(result[category],function(a,b) if a.boss~=b.boss then return a.boss<b.boss end;return a.name:lower()<b.name:lower() end)
 end
 return result
end
-- Category for an assigned name from the last check (nil when fine or never checked).
function S.Flag(name) local short=Normalize(name);return short and S.last and S.last.flags[short] end
-- Category for anyone (assigned or not) from the last check: ok, tentative,
-- standby or missing; nil when no check has run.
function S.StatusOf(name)
 if not S.last or not S.last.byShort then return nil end
 return S.Category(StatusFor(name,S.last.byShort,S.last.byFull))
end

-- Why the calendar cannot be read right now, or nil.
function S.Busy()
 if InCombatLockdown() then return 'Signups can be checked out of combat.' end
 if not (C_Calendar and C_Calendar.GetNumDayEvents) then return 'The calendar is not available.' end
 if CalendarFrame and CalendarFrame:IsShown() then return 'Close the calendar window first.' end
 if (C_Calendar.IsActionPending and C_Calendar.IsActionPending()) or (C_Calendar.IsEventOpen and C_Calendar.IsEventOpen()) then
  return 'The calendar is busy (Guilds of WoW may be updating it). Try again in a moment.'
 end
end
local function Now() return C_DateAndTime and C_DateAndTime.GetServerTimeLocal and C_DateAndTime.GetServerTimeLocal() or time() end
-- Point the calendar at the current month so day offsets are relative to now.
local function ResetMonth(now)
 local info=C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo()
 local month,year=tonumber(date('%m',now)),tonumber(date('%Y',now))
 if info and (info.month~=month or info.year~=year) and C_Calendar.SetAbsMonth then C_Calendar.SetAbsMonth(month,year) end
 return month
end
-- Guild and player events with invites from 4 hours ago to 7 days ahead, soonest first.
function S.Upcoming()
 local busy=S.Busy();if busy then return nil,busy end
 local now=Now();local current=ResetMonth(now)
 local list,seen={},{}
 for day=0,DAYS do
  local when=now+day*86400
  local month,monthDay=tonumber(date('%m',when)),tonumber(date('%d',when))
  local offset=month-current;if offset<0 then offset=offset+12 end
  for index=1,C_Calendar.GetNumDayEvents(offset,monthDay) do
   local event=C_Calendar.GetDayEvent(offset,monthDay,index)
   if event and (event.calendarType=='GUILD_EVENT' or event.calendarType=='PLAYER') and event.startTime and event.sequenceType~='ONGOING' and event.sequenceType~='END' then
    local t=event.startTime
    local start=time({year=t.year,month=t.month,day=t.monthDay,hour=t.hour,min=t.minute})
    local key=(event.title or '')..'@'..start
    if start>=now-4*3600 and not seen[key] then
     seen[key]=true
     list[#list+1]={title=event.title or 'Event',start=start,offset=offset,day=monthDay,index=index,key=key,
      label=(event.title or 'Event')..' ('..date('%a %d %b %H:%M',start)..')'}
    end
   end
  end
 end
 table.sort(list,function(a,b) return a.start<b.start end)
 return list
end

-- Read an event's invite list. Opening a calendar event is asynchronous: the
-- callback gets ({{name=,status=}}) or (nil, message).
local pending
local function Finish(invites,message)
 local job=pending;pending=nil
 if C_Calendar.IsEventOpen and C_Calendar.IsEventOpen() and C_Calendar.CloseEvent then C_Calendar.CloseEvent() end
 if job then job.callback(invites,message) end
end
local function TryRead()
 if not pending or not pending.opened then return end
 if C_Calendar.AreNamesReady and not C_Calendar.AreNamesReady() then return end -- wait for CALENDAR_UPDATE_INVITE_LIST
 local invites={}
 for index=1,C_Calendar.GetNumInvites() do
  local info=C_Calendar.EventGetInvite(index)
  if info and type(info.name)=='string' and info.name~='' then invites[#invites+1]={name=info.name,status=info.inviteStatus} end
 end
 Finish(invites)
end
function S.Read(event,callback)
 if pending then return false,'Already checking signups.' end
 local busy=S.Busy();if busy then return false,busy end
 -- Find the event again: indexes shift if the calendar changed.
 local list=S.Upcoming() or {}
 local target;for _,candidate in ipairs(list) do if candidate.key==event.key then target=candidate end end
 if not target then return false,'That event is no longer in the calendar.' end
 pending={callback=callback,started=GetTime()}
 if not C_Calendar.OpenEvent(target.offset,target.day,target.index) then pending=nil;return false,'The calendar did not open that event. Try again.' end
 if C_Timer and C_Timer.After then
  local job=pending
  C_Timer.After(8,function() if pending==job then Finish(nil,'The calendar did not answer. Try again.') end end)
 end
 return true
end
-- Check the given event (or the next one) against the assignments.
function S.Check(event,callback)
 if not event then
  local list,err=S.Upcoming();if not list then return false,err end
  event=list[1];if not event then return false,'No guild event in the next 7 days. Has Guilds of WoW added the raid to the calendar?' end
 end
 return S.Read(event,function(invites,message)
  if not invites then callback(nil,message);return end
  local result=S.Compare(invites);result.event=event;result.invites=#invites
  S.last=result;callback(result)
 end)
end
local frame=CreateFrame('Frame')
for _,name in ipairs({'CALENDAR_OPEN_EVENT','CALENDAR_UPDATE_INVITE_LIST','CALENDAR_CLOSE_EVENT'}) do frame:RegisterEvent(name) end
frame:SetScript('OnEvent',function(_,name)
 if not pending then return end
 if name=='CALENDAR_OPEN_EVENT' then pending.opened=true;TryRead()
 elseif name=='CALENDAR_UPDATE_INVITE_LIST' then TryRead()
 elseif name=='CALENDAR_CLOSE_EVENT' and pending.opened then Finish(nil,'The event was closed before its sign-ups loaded. Try again.') end
end)
-- Ask the server for calendar data so the event list is ready when needed.
function S.Prepare() if C_Calendar and C_Calendar.OpenCalendar and not InCombatLockdown() then C_Calendar.OpenCalendar() end end
