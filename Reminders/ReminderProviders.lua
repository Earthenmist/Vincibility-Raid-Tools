local _,addon=...
local R=addon.Reminders
local UNKNOWN={}
-- Public-value adapters for the remaining trigger families. Restricted
-- registrations must never be attempted: pcall does not suppress WoW's
-- ADDON_ACTION_FORBIDDEN notification. This addon targets Retail 12.x only.
-- Secret values from otherwise supported APIs are unknown, never false.
local function Public(...)
 for i=1,select('#',...) do if not R.Public(select(i,...)) then return false end end
 return true
end
local function Number(n) return Public(n) and type(n)=='number' and n==n end
local function Call(fn,...)
 if type(fn)~='function' then return UNKNOWN end
 local ok,a,b,c,d,e,f,g,h,i=pcall(fn,...)
 if not ok or not Public(a,b,c,d,e,f,g,h,i) then return UNKNOWN end
 return a,b,c,d,e,f,g,h,i
end
local frame=CreateFrame('Frame')
local api={
 [4]=function() return type(UnitHealth)=='function' and type(UnitHealthMax)=='function' end,
 [5]=function() return type(UnitPower)=='function' and type(UnitPowerMax)=='function' end,
 [9]=function() return type(UnitExists)=='function' end,
 [10]=function() return C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex)=='function' end,
 [11]=function() return type(UnitGetTotalAbsorbs)=='function' end,
 [12]=function() return type(UnitName)=='function' end,
 [13]=function() return C_Spell and type(C_Spell.GetSpellCooldown)=='function' end,
 [15]=function() return C_UIWidgetManager and type(C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo)=='function' end,
 [17]=function() return type(UnitInRange)=='function' end,
 [18]=function() return type(UnitCastingInfo)=='function' end,
 [20]=function() return type(CheckInteractDistance)=='function' and type(UnitCanAttack)=='function' end,
}
local registered={[1]=false}
-- Explicit supported events, not registration probes. Combat log and monster
-- say/yell are restricted on the supported Retail client and stay excluded.
for id,event in pairs({[8]='CHAT_MSG_RAID',[14]='UNIT_SPELLCAST_SUCCEEDED',[15]='UPDATE_UI_WIDGET'}) do
 frame:RegisterEvent(event)
 registered[id]=true
 if id==8 then
  for _,chat in ipairs({'CHAT_MSG_RAID_WARNING','CHAT_MSG_PARTY','CHAT_MSG_SAY','CHAT_MSG_YELL'}) do frame:RegisterEvent(chat) end
 end
end
function R.RefreshProviderAvailability()
 for id,check in pairs(api) do
  local def=R.catalogue[id];def.available=check() and (registered[id]~=false) or false
  if def.available then def.reason=nil else def.reason='This trigger API is unavailable in the current client. Its definition is retained.' end
 end
 for _,id in ipairs({1,8,14}) do
  local def=R.catalogue[id];def.available=registered[id] or false
  if def.available then def.reason=nil else def.reason='This event is unavailable in the current client. Its definition is retained.' end
 end
 R.catalogue[1].reason='Combat-log triggers are restricted on Retail. Use a boss-mod message, timer or pull trigger. The definition is retained.'
end
R.RefreshProviderAvailability()
local function Aura(unit,spellID)
 if not spellID then return nil end
 for _,filter in ipairs({'HELPFUL','HARMFUL'}) do
  for index=1,80 do
   local data=Call(C_UnitAuras.GetAuraDataByIndex,unit,index,filter)
   if data==UNKNOWN then return nil end
   if not data then break end
   if not Public(data.spellId,data.applications) then return nil end
   if data.spellId==spellID then return data.applications or 1 end
  end
 end
 return 0
end
local function RangeCount(enemy)
 local count=0
 local total=enemy and 40 or (IsInRaid() and GetNumGroupMembers() or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0))
 for i=1,total do
  local unit=enemy and 'nameplate'..i or IsInRaid() and 'raid'..i or 'party'..i
  local exists=Call(UnitExists,unit)
  if exists==UNKNOWN then return nil end
  if exists then
   local inside,checked
   if enemy then
    local attack=Call(UnitCanAttack,'player',unit)
    if attack==nil or attack==UNKNOWN then return nil end
    if attack then inside=Call(CheckInteractDistance,unit,3);checked=inside~=nil else inside=false;checked=true end
   else inside,checked=Call(UnitInRange,unit) end
   if inside==UNKNOWN or not checked then return nil end
   if inside then count=count+1 end
  end
 end
 return count
end
local elapsed=0
frame:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt;if elapsed<0.3 then return end;elapsed=0
 local cache={}
 for _,entry in pairs(R.active) do
  for i,t in ipairs(entry.data.triggers) do
   if api[t.event] and t.event~=15 then
    local unit=t.unit and t.unit~='' and t.unit or 'player'
    local key=t.event..':'..unit..':'..tostring(t.spellID)
    local cached=cache[key]
    if not cached then
     local value,params=nil,{unit=unit,spellID=t.spellID}
     if t.event==4 or t.event==5 then
      local fn=t.event==4 and UnitHealth or UnitPower;local max=t.event==4 and UnitHealthMax or UnitPowerMax
      local current,total=Call(fn,unit),Call(max,unit)
      if Number(current) and Number(total) and total>0 then value=100*current/total end
     elseif t.event==9 then value=Call(UnitExists,t.unit and t.unit~='' and t.unit or 'boss1')
     elseif t.event==10 then value=Aura(unit,t.spellID)
     elseif t.event==11 then value=Call(UnitGetTotalAbsorbs,unit)
     elseif t.event==12 then value=Call(UnitName,unit..'target')
     elseif t.event==13 then
      local data=t.spellID and Call(C_Spell.GetSpellCooldown,t.spellID)
      if data and data~=UNKNOWN and Public(data.startTime,data.duration,data.isEnabled) and Number(data.startTime) and Number(data.duration) then
       value=math.max(0,data.startTime+data.duration-GetTime())
      end
     elseif t.event==17 then value=RangeCount(false)
     elseif t.event==18 then
      local name,_,_,_,_,_,_,_,spellID=Call(UnitCastingInfo,unit)
      if name~=UNKNOWN then value=name~=nil and name or false;params.spellID=spellID end
     elseif t.event==20 then value=RangeCount(true) end
     if value==UNKNOWN then value=nil end
     cached={value=value,params=params};cache[key]=cached
    end
    local value=cached.value;local condition
    if value~=nil then
     if t.event==4 or t.event==5 or t.event==13 then condition=Number(value) and value<=(t.value or (t.event==13 and 0 or 50))
     elseif t.event==10 or t.event==11 or t.event==17 or t.event==20 then condition=Number(value) and value>=(t.value or 1)
     elseif t.event==12 then condition=type(value)=='string' and (not t.target or t.target=='' or value==t.target)
     elseif t.event==18 then condition=value~=false and (not t.spellID or cached.params.spellID==t.spellID)
     else condition=value and true or false end
    end
    R.Observe(entry,i,condition,cached.params)
   end
  end
 end
end)
frame:SetScript('OnEvent',function(_,event,...)
 for i=1,select('#',...) do if not R.Public(select(i,...)) then return end end
 if event:find('^CHAT_MSG_') then
  local text,sender=...;if type(text)=='string' then R.Dispatch(8,{text=text,source=sender}) end
 elseif event=='UNIT_SPELLCAST_SUCCEEDED' then
  local unit,_,spellID=...;R.Dispatch(14,{unit=unit,spellID=spellID})
 elseif event=='UPDATE_UI_WIDGET' then
  local widget=...
  if type(widget)~='table' or not Public(widget.widgetID) then return end
  local data=Call(C_UIWidgetManager and C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo,widget.widgetID)
  local value=data and data~=UNKNOWN and data.barValue or nil
  for _,entry in pairs(R.active) do for i,t in ipairs(entry.data.triggers) do
   if t.event==15 and t.widgetID==widget.widgetID then
    local condition;if Number(value) then condition=value>=(t.value or 1) end
    R.Observe(entry,i,condition,{widgetID=widget.widgetID})
   end
  end end
 end
end)
