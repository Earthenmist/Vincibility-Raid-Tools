local _,addon=...
-- Raid overview shown during a ready check: one row per group member with
-- consumables, raid buffs and VRT-shared durability/item level/weapon oil.
-- Only public, non-secret aura values are read; restricted data is skipped.
local RC=addon.ReadyCheck
local O={shared={},durability={},latency={},lines={}};RC.Overview=O
local PREFIX='VRTRC1'
O.prefix=PREFIX

-- Game data. Current-expansion consumable IDs, plus English name fallbacks
-- for older consumables; raid buffs and Soulstone are long-standing spells.
-- Flask buffs: current flasks, their PvP forms and the previous expansion's.
local flaskIDs={[1236763]=true,[1239355]=true,[1235057]=true,[1239755]=true,[1236767]=true,[1235111]=true,[1235110]=true,[1235108]=true,
 [1235113]=true,[1235114]=true,[1235115]=true,[1235116]=true,[432473]=true,[432021]=true,[431974]=true,[431973]=true,[431972]=true,[431971]=true}
-- Augment rune buffs, including the 12.1 Tidesworn rune (1295329).
local runeIDs={[1295329]=true,[1234969]=true,[1242347]=true,[1264426]=true,[453250]=true,[393438]=true,[347901]=true}
local foodIcon,eatingIcons=136000,{[134062]=true,[132805]=true,[133950]=true}
local soulstoneID=20707
local raidBuffs={
 {key='int',name='Intellect',class='MAGE',ids={[1459]=true}},
 {key='ap',name='Attack Power',class='WARRIOR',ids={[6673]=true}},
 {key='stamina',name='Stamina',class='PRIEST',ids={[21562]=true}},
 {key='vers',name='Versatility',class='DRUID',ids={[1126]=true}},
 {key='mastery',name='Mastery',class='SHAMAN',ids={[462854]=true}},
 {key='move',name='Movement',class='EVOKER',ids={[381741]=true,[381757]=true,[381756]=true,[381732]=true,[381752]=true,[381748]=true,[381750]=true,[381749]=true,[381746]=true,[381751]=true,[381753]=true,[381754]=true,[381758]=true}},
}
O.raidBuffs=raidBuffs

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Readable(value)
 if not Public(value) then return false end
 if canaccessvalue then local ok,result=pcall(canaccessvalue,value);if ok and not result then return false end end
 return true
end
function O.Restricted()
 return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() and true or false
end
-- Classify one aura; returns kind and a display icon.
function O.Classify(aura)
 if type(aura)~='table' or not Readable(aura.spellId) then return end
 local id,icon=aura.spellId,Readable(aura.icon) and aura.icon or nil
 local name=Readable(aura.name) and type(aura.name)=='string' and aura.name or ''
 if id==soulstoneID then return 'soulstone',icon end
 for _,buff in ipairs(raidBuffs) do if buff.ids[id] then return 'buff:'..buff.key,icon end end
 if flaskIDs[id] or name:find('^Flask') or name:find('^Phial') then return 'flask',icon end
 if runeIDs[id] or name:find('Augment') then return 'rune',icon end
 if name:find('Vantus Rune') then return 'vantus',icon end
 if icon==foodIcon then return 'food',icon end
 if eatingIcons[icon] then return 'eating',icon end
end
function O.ScanUnit(unit,now)
 local record={buffs={}}
 if O.Restricted() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then record.restricted=true;return record end
 now=now or GetTime()
 for index=1,80 do
  local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,unit,index,'HELPFUL')
  if not ok or not aura then break end
  local kind,icon=O.Classify(aura)
  if kind then
   local expires=Readable(aura.expirationTime) and type(aura.expirationTime)=='number' and aura.expirationTime>0 and aura.expirationTime-now or nil
   local buff=kind:match('^buff:(.+)$')
   if buff then record.buffs[buff]=true
   elseif kind=='eating' then if not record.food then record.eating=true end
   elseif not record[kind] then record[kind]={icon=icon,remaining=expires,name=Readable(aura.name) and aura.name or nil} end
  end
 end
 return record
end

-- VRT-to-VRT status: durability %, item level and weapon-oil seconds.
function O.OwnStatus()
 local lowest=100
 if GetInventoryItemDurability then
  for slot=1,18 do
   local current,maximum=GetInventoryItemDurability(slot)
   if current and maximum and maximum>0 then lowest=math.min(lowest,math.floor(current/maximum*100+.5)) end
  end
 end
 local itemLevel=0
 if GetAverageItemLevel then local _,equipped=GetAverageItemLevel();itemLevel=tonumber(equipped) or 0 end
 local mainOil,offOil=-1,-1
 if GetWeaponEnchantInfo then
  local hasMain,mainExpires,_,_,hasOff,offExpires=GetWeaponEnchantInfo()
  if hasMain and mainExpires then mainOil=math.floor(mainExpires/1000) end
  if hasOff and offExpires then offOil=math.floor(offExpires/1000) end
 end
 return {durability=lowest,itemLevel=math.floor(itemLevel*10+.5)/10,oil=mainOil,oilOff=offOil,when=GetTime()}
end
function O.Encode(status)
 return string.format('S:%d:%.1f:%d:%d',status.durability,status.itemLevel,status.oil,status.oilOff)
end
function O.Decode(message)
 if type(message)~='string' or #message>60 then return end
 local durability,itemLevel,oil,oilOff=message:match('^S:(%d+):(%d+%.?%d*):(%-?%d+):(%-?%d+)$')
 durability,itemLevel,oil,oilOff=tonumber(durability),tonumber(itemLevel),tonumber(oil),tonumber(oilOff)
 if not durability or durability>100 or itemLevel>2000 or oil>36000 or oilOff>36000 then return end
 return {durability=durability,itemLevel=itemLevel,oil=oil,oilOff=oilOff,when=GetTime()}
end
local function Key(name)
 if type(name)~='string' or not Public(name) then return end
 return Ambiguate and Ambiguate(name,'none') or name
end
function O.SharedFor(unit)
 if UnitIsUnit and UnitIsUnit(unit,'player') then return O.OwnStatus() end
 local key=Key(GetUnitName and GetUnitName(unit,true))
 local data=key and O.shared[key]
 if data and GetTime()-data.when<600 then return data end
end
-- LibDurability (embedded, Ace3-style BSD): average durability from any player
-- whose addons include it. VRT's own lowest-item value takes priority.
local LD=LibStub and LibStub('LibDurability',true)
O.libDurability=LD
function O.OnLibDurability(percent,broken,name)
 local key=Key(name);percent,broken=tonumber(percent),tonumber(broken)
 if key and percent and broken and percent>=0 and percent<=100 then O.durability[key]={durability=math.floor(percent+.5),broken=broken,when=GetTime()};O.dirty=true end
end
if LD then LD:Register('VincRaidTools',O.OnLibDurability) end
function O.RequestDurability()
 if LD and IsInGroup and IsInGroup() then pcall(LD.RequestDurability,LD) end
end
-- {value, kind ('lowest'|'average'), broken} or nil.
function O.DurabilityFor(unit,shared)
 if shared then return {value=shared.durability,kind='lowest'} end
 local key=Key(GetUnitName and GetUnitName(unit,true))
 local data=key and O.durability[key]
 if data and GetTime()-data.when<600 then return {value=data.durability,kind='average',broken=data.broken} end
end
-- LibLatency is bundled with VRT (as are DBM and BigWigs), so every VRT, DBM
-- or BigWigs user answers it; LibStub keeps the newest loaded copy.
local LL=LibStub and LibStub('LibLatency',true)
O.libLatency=LL
function O.OnLibLatency(home,world,name)
 local key=Key(name);home,world=tonumber(home),tonumber(world)
 if key and home and world and home>=0 and world>=0 and home<100000 and world<100000 then O.latency[key]={home=home,world=world,when=GetTime()};O.dirty=true end
end
if LL then LL:Register('VincRaidTools',O.OnLibLatency) end
function O.RequestLatency()
 if LL then pcall(LL.RequestLatency,LL) end
end
function O.LatencyFor(unit)
 local key=Key(GetUnitName and GetUnitName(unit,true))
 local data=key and O.latency[key]
 if data and GetTime()-data.when<600 then return data end
end
function O.SendStatus()
 if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or not IsInGroup or not IsInGroup() then return end
 if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
 local channel=IsInRaid() and 'RAID' or 'PARTY'
 pcall(C_ChatInfo.SendAddonMessage,PREFIX,O.Encode(O.OwnStatus()),channel)
end
function O.OnMessage(prefix,message,channel,sender)
 if not Public(prefix) or prefix~=PREFIX or not Public(message) or not Public(sender) then return end
 local status=O.Decode(message);local key=Key(sender)
 if status and key then O.shared[key]=status;O.dirty=true end
end

-- Display.
local colours={background={0.078,0.086,0.106,0.95},raised={0.145,0.157,0.192,1},border={0.180,0.196,0.235,1},
 accent={0.72,0.76,0.81,1},highlight={0.78,0.11,0.25,1},text={0.910,0.918,0.941,1},muted={0.541,0.561,0.612,1},
 good={0.35,0.85,0.45,1},warn={0.95,0.78,0.25,1},bad={0.95,0.3,0.3,1}}
O.colours=colours
local columnDefs={
 {key='food',title='Food',tip='Well Fed buff. A red cross means none; "eat" means eating now.'},
 {key='flask',title='Flask',tip='Minutes left on the flask. Amber with "!" when under your flask expiry warning; a red cross means none.'},
 {key='rune',title='Rune',tip='Augment rune.'},
 {key='vantus',title='Vantus',tip='Vantus rune for this boss.'},
 {key='oil',title='Oil',tip='Minutes left on the weapon oil (the player needs VRT).'},
 {key='buffs',title='Buffs',tip='Raid buffs your group can provide: OK when all are up, -N when some are missing (hover a cell to see which).'},
 {key='soulstone',title='SS',tip='Soulstone: shows who has one.'},
 {key='durability',title='Dur',tip='Gear durability: red under 30% or with broken items, amber under 60%.'},
 {key='itemLevel',title='iLvl',tip='Equipped item level (the player needs VRT).'},
 {key='latency',title='Ping',tip='World latency in ms: amber from 150, red from 300.'},
}
O.columnDefs=columnDefs
local ROW,NAME,CELL,MAXROWS=18,140,44,20
local statusIcons={ready='Interface\\RaidFrame\\ReadyCheck-Ready',notready='Interface\\RaidFrame\\ReadyCheck-NotReady',waiting='Interface\\RaidFrame\\ReadyCheck-Waiting'}
local missingIcon='Interface\\RaidFrame\\ReadyCheck-NotReady'
local function Paint(frame,colour)
 frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 frame:SetBackdropColor(unpack(colours[colour or 'background']));frame:SetBackdropBorderColor(unpack(colours.border))
end
local function Label(parent,size,colour)
 local t=parent:CreateFontString(nil,'OVERLAY');t:SetFont(STANDARD_TEXT_FONT,size,'');t:SetTextColor(unpack(colours[colour or 'text']));t:SetJustifyH('LEFT')
 return t
end
function O.Units()
 local units={}
 if IsInRaid and IsInRaid() then
  for index=1,(GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units+1]='raid'..index end
 else
  units[1]='player'
  for index=1,4 do if UnitExists and UnitExists('party'..index) then units[#units+1]='party'..index end end
 end
 local names={}
 for _,unit in ipairs(units) do names[unit]=(UnitName and UnitName(unit)) or unit end
 table.sort(units,function(a,b) return tostring(names[a])<tostring(names[b]) end)
 return units
end
local function AvailableBuffs(units)
 local classes={}
 for _,unit in ipairs(units) do local _,class=UnitClass(unit);if class then classes[class]=true end end
 local available={}
 for _,buff in ipairs(raidBuffs) do if classes[buff.class] then available[#available+1]=buff end end
 return available
end
local function Minutes(seconds) return seconds and math.floor(seconds/60+.5)..' min' or 'no expiry' end
-- Cell content: icon, text, colour key, tooltip.
function O.Cell(key,record,shared,available,settings,durability,latency)
 local warnSeconds=(settings.flaskWarn or 0)*60
 if record.restricted and key~='durability' and key~='itemLevel' and key~='oil' then return nil,'?','muted','Buff data is hidden by the game right now.' end
 if key=='food' then
  if record.food then return record.food.icon,nil,nil,'Well Fed · '..Minutes(record.food.remaining) end
  if record.eating then return nil,'eat','warn','Eating now.' end
  return missingIcon,nil,nil,'No food buff.'
 elseif key=='flask' or key=='rune' or key=='vantus' then
  local data=record[key]
  if not data then return missingIcon,nil,nil,'Missing '..key..'.' end
  local expiring=key=='flask' and warnSeconds>0 and data.remaining and data.remaining<warnSeconds
  local tip=(data.name or key)..' · '..Minutes(data.remaining)..(expiring and ' (expiring soon)' or '')
  -- Flask time matters most, so show the minutes left rather than the icon.
  if key=='flask' and data.remaining then
   return nil,math.floor(data.remaining/60+.5)..'m'..(expiring and '!' or ''),expiring and 'warn' or 'good',tip
  end
  return data.icon,expiring and '!' or nil,expiring and 'warn' or nil,tip
 elseif key=='soulstone' then
  if record.soulstone then return record.soulstone.icon,nil,nil,'Has a Soulstone.' end
  return nil,'','muted',nil
 elseif key=='buffs' then
  local missing={}
  for _,buff in ipairs(available) do if not record.buffs[buff.key] then missing[#missing+1]=buff.name end end
  if #available==0 then return nil,'-','muted','No raid-buff classes in the group.' end
  if #missing==0 then return nil,'OK','good','All available raid buffs.' end
  return nil,'-'..#missing,'bad','Missing: '..table.concat(missing,', ')
 end
 if key=='latency' then
  if not latency then return nil,'?','muted','No latency data (they need VRT, DBM, BigWigs or another addon with LibLatency).' end
  return nil,tostring(latency.world),latency.world<150 and 'good' or latency.world<300 and 'warn' or 'bad',
   string.format('World %d ms · Home %d ms (LibLatency).',latency.world,latency.home)
 end
 if key=='durability' then
  if not durability then return nil,'?','muted','No durability data from this player (needs VRT or an addon with LibDurability).' end
  local value=durability.value
  local tip=durability.kind=='lowest' and 'Lowest item durability (VRT).' or 'Average durability (LibDurability).'
  if durability.broken and durability.broken>0 then tip=tip..' '..durability.broken..' broken item'..(durability.broken>1 and 's' or '')..'.' end
  return nil,value..'%',(value<30 or (durability.broken or 0)>0) and 'bad' or value<60 and 'warn' or 'good',tip
 end
 if not shared then return nil,'?','muted','No VRT data from this player.' end
 if key=='itemLevel' then
  return nil,string.format('%.0f',shared.itemLevel),'text','Equipped item level '..shared.itemLevel..'.'
 elseif key=='oil' then
  if shared.oil<0 then return missingIcon,nil,nil,'No weapon oil.' end
  return nil,math.floor(shared.oil/60+.5)..'m',shared.oil<warnSeconds and 'warn' or 'good','Weapon oil · '..Minutes(shared.oil)
 end
end
-- Sample players for the preview, so the layout and warning colours can be
-- judged outside a group: {icon, text, colour, tooltip} per column.
local function ItemIcon(id) return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) end
local function Samples()
 local food,flask,rune,stone=136000,ItemIcon(241326),ItemIcon(259085),136210
 local missing={missingIcon,nil,nil,'Missing.'}
 return {
  {name='Tank (sample)',class='WARRIOR',status='ready',cells={food={food},flask={nil,'45m','good'},rune={rune},vantus={rune},oil={nil,'50m','good'},
   buffs={nil,'OK','good'},soulstone={nil,''},durability={nil,'88%','good'},itemLevel={nil,'330','text'},latency={nil,'40','good'}}},
  {name='Healer (sample)',class='PRIEST',status='notready',cells={food=missing,flask={nil,'6m!','warn','Flask · 6 min (expiring soon)'},rune=missing,vantus=missing,
   oil=missing,buffs={nil,'-1','bad','Missing: Power Word: Fortitude'},soulstone={stone,nil,nil,'Has a Soulstone.'},durability={nil,'25%','bad'},itemLevel={nil,'322','text'},latency={nil,'180','warn'}}},
  {name='Damage (sample)',class='MAGE',status='waiting',cells={food={nil,'eat','warn','Eating now.'},flask={nil,'38m','good'},rune={rune},vantus={rune},oil={nil,'12m','good'},
   buffs={nil,'OK','good'},soulstone={nil,''},durability={nil,'55%','warn'},itemLevel={nil,'328','text'},latency={nil,'320','bad'}}},
 }
end
O.Samples=Samples
local function Columns(settings)
 local list={}
 for _,column in ipairs(columnDefs) do if settings.columns[column.key] then list[#list+1]=column end end
 return list
end
-- Shared themed close button for the ready-check windows: raised charcoal box,
-- silver border and X, switching to the theme's red highlight on hover.
function O.CloseButton(parent,onClick)
 local button=CreateFrame('Button',nil,parent,'BackdropTemplate')
 Paint(button,'raised');button:SetSize(20,20);button:SetPoint('TOPRIGHT',-6,-5)
 button:SetBackdropBorderColor(unpack(colours.border))
 button.label=Label(button,11,'accent');button.label:SetPoint('CENTER');button.label:SetText('X')
 button:SetScript('OnEnter',function(self) self:SetBackdropBorderColor(unpack(colours.highlight));self.label:SetTextColor(unpack(colours.highlight)) end)
 button:SetScript('OnLeave',function(self) self:SetBackdropBorderColor(unpack(colours.border));self.label:SetTextColor(unpack(colours.accent)) end)
 button:SetScript('OnClick',onClick)
 return button
end
local function ShowTip(self)
 if self.tip and GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText(self.tip,1,1,1,1,true);GameTooltip:Show() end
end
local function HideTip() if GameTooltip then GameTooltip:Hide() end end
function O.Build()
 if O.frame then return O.frame end
 local frame=CreateFrame('Frame','VincibilityReadyCheckOverview',UIParent,'BackdropTemplate');O.frame=frame
 Paint(frame);frame:SetFrameStrata('HIGH');frame:SetClampedToScreen(true);frame:SetMovable(true);frame:EnableMouse(true)
 frame:RegisterForDrag('LeftButton');frame:EnableMouseWheel(true);frame:Hide()
 frame:SetScript('OnDragStart',function(self) self:StartMoving() end)
 frame:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local x,y=self:GetCenter();local px,py=UIParent:GetCenter()
  if x and px then RC.Settings().overviewPosition={x=math.floor(x-px+.5),y=math.floor(y-py+.5)} end
 end)
 frame.title=Label(frame,13,'text');frame.title:SetPoint('TOPLEFT',10,-8)
 frame.close=O.CloseButton(frame,function() O.Hide() end)
 frame.notice=Label(frame,10,'warn');frame.notice:SetPoint('BOTTOMLEFT',10,6)
 frame.headers={}
 for index,column in ipairs(columnDefs) do
  local header=Label(frame,10,'accent');header:SetJustifyH('CENTER');header:SetWidth(CELL);header:SetText(column.title);frame.headers[index]=header
  local hit=CreateFrame('Frame',nil,frame);hit:SetSize(CELL,14);hit:SetPoint('CENTER',header,'CENTER');hit:EnableMouse(true)
  hit.tip=column.title..': '..column.tip;hit:SetScript('OnEnter',ShowTip);hit:SetScript('OnLeave',HideTip)
  header.hit=hit
 end
 frame.nameHeader=Label(frame,10,'accent');frame.nameHeader:SetPoint('TOPLEFT',30,-30);frame.nameHeader:SetText('Player')
 frame:SetScript('OnMouseWheel',function(_,delta) O.offset=math.max(0,(O.offset or 0)-delta);O.Refresh() end)
 frame:SetScript('OnUpdate',function(_,elapsed)
  O.elapsed=(O.elapsed or 0)+elapsed
  if O.elapsed<.5 then return end
  O.elapsed=0
  if O.dirty or O.expires then O.dirty=false;O.Refresh() end
 end)
 return frame
end
local function Line(index)
 local frame=O.frame
 if O.lines[index] then return O.lines[index] end
 local line=CreateFrame('Frame',nil,frame,'BackdropTemplate');O.lines[index]=line
 line:SetSize(10,ROW);line:SetPoint('TOPLEFT',6,-44-(index-1)*ROW)
 line:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});line:SetBackdropColor(1,1,1,index%2==0 and .03 or 0)
 line.status=line:CreateTexture(nil,'ARTWORK');line.status:SetSize(14,14);line.status:SetPoint('LEFT',4,0)
 line.name=Label(line,11,'text');line.name:SetPoint('LEFT',24,0);line.name:SetWidth(NAME-8);line.name:SetWordWrap(false)
 line.cells={}
 for column=1,#columnDefs do
  local cell=CreateFrame('Frame',nil,line);cell:SetSize(CELL,ROW);cell:EnableMouse(true)
  cell.icon=cell:CreateTexture(nil,'ARTWORK');cell.icon:SetSize(14,14);cell.icon:SetPoint('CENTER')
  cell.text=Label(cell,10,'text');cell.text:SetPoint('CENTER');cell.text:SetJustifyH('CENTER')
  cell:SetScript('OnEnter',ShowTip);cell:SetScript('OnLeave',HideTip)
  line.cells[column]=cell
 end
 return line
end
function O.Refresh()
 local frame=O.frame;if not frame or not frame:IsShown() then return end
 local settings=RC.Settings()
 local columns=Columns(settings)
 local units=O.Units();local available=AvailableBuffs(units)
 if O.preview then for _,sample in ipairs(Samples()) do units[#units+1]=sample end end
 local width=24+NAME+#columns*CELL+12
 O.offset=math.max(0,math.min(O.offset or 0,#units-MAXROWS))
 local visible=math.min(#units,MAXROWS)
 local restricted=O.Restricted()
 frame.notice:SetText(restricted and 'Buff data is hidden by the game right now; consumables show "?".' or '')
 frame:SetSize(math.max(width,260),44+visible*ROW+(frame.notice:GetText()~='' and 22 or 10))
 for index,header in ipairs(frame.headers) do header:Hide();header.hit:Hide() end
 for position,column in ipairs(columns) do
  for index,def in ipairs(columnDefs) do if def==column then
   local header=frame.headers[index];header:ClearAllPoints();header:SetPoint('TOPLEFT',6+24+NAME+(position-1)*CELL,-30);header:Show();header.hit:Show()
  end end
 end
 local now=GetTime()
 local remaining=O.expires and math.max(0,math.floor(O.expires-now+.5))
 frame.title:SetText((O.preview and 'Ready check preview' or 'Ready check')..(remaining and remaining>0 and ('  ·  '..remaining..'s') or (O.finished and '  ·  finished' or '')))
 for index=1,math.max(#O.lines,visible) do
  local line=Line(index)
  local unit=index<=visible and units[index+O.offset]
  local sample=type(unit)=='table' and unit or nil
  if sample then
   line:SetWidth(width-12);line:Show()
   line.status:SetTexture(statusIcons[sample.status])
   local colour=RAID_CLASS_COLORS and RAID_CLASS_COLORS[sample.class]
   line.name:SetText(sample.name)
   if colour then line.name:SetTextColor(colour.r,colour.g,colour.b) else line.name:SetTextColor(unpack(colours.text)) end
   for column=1,#columnDefs do line.cells[column]:Hide() end
   for position,column in ipairs(columns) do
    local cell=line.cells[position];local value=sample.cells[column.key] or {}
    cell:ClearAllPoints();cell:SetPoint('LEFT',24+NAME+(position-1)*CELL,0);cell:Show()
    cell.icon:SetTexture(value[1]);cell.icon:SetShown(value[1]~=nil)
    cell.text:SetText(value[2] or '');cell.text:SetTextColor(unpack(colours[value[3] or 'text']))
    cell.tip=value[4] or (column.title..' (sample)');cell.key=column.key
   end
   line.unit=nil
  elseif unit then
   line:SetWidth(width-12);line:Show()
   local status=GetReadyCheckStatus and GetReadyCheckStatus(unit)
   if O.preview then status=status or 'waiting' end
   line.status:SetTexture(statusIcons[status] or nil)
   local _,class=UnitClass(unit)
   local colour=class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
   line.name:SetText(UnitName(unit) or unit)
   if colour then line.name:SetTextColor(colour.r,colour.g,colour.b) else line.name:SetTextColor(unpack(colours.text)) end
   local record=O.ScanUnit(unit,now);local shared=O.SharedFor(unit);local durability=O.DurabilityFor(unit,shared);local latency=O.LatencyFor(unit)
   for column=1,#columnDefs do line.cells[column]:Hide() end
   for position,column in ipairs(columns) do
    local cell=line.cells[position]
    cell:ClearAllPoints();cell:SetPoint('LEFT',24+NAME+(position-1)*CELL,0);cell:Show()
    local icon,text,colourKey,tip=O.Cell(column.key,record,shared,available,settings,durability,latency)
    cell.icon:SetTexture(icon);cell.icon:SetShown(icon~=nil)
    cell.text:SetText(text or '');cell.text:SetTextColor(unpack(colours[colourKey or 'text']))
    cell.tip=tip;cell.key=column.key
   end
   line.unit=unit
  else line:Hide();line.unit=nil end
 end
end
function O.Show(duration,preview)
 local frame=O.Build()
 if preview then O.RequestDurability();O.RequestLatency() end
 local position=RC.Settings().overviewPosition
 frame:ClearAllPoints()
 if type(position)=='table' and type(position.x)=='number' and type(position.y)=='number' then frame:SetPoint('CENTER',UIParent,'CENTER',position.x,position.y)
 else frame:SetPoint('TOP',UIParent,'TOP',0,-160) end
 if O.hideTimer then O.hideTimer:Cancel();O.hideTimer=nil end
 O.preview=preview;O.finished=false;O.offset=0
 O.expires=duration and GetTime()+duration or nil
 frame:Show();O.Refresh()
end
function O.Hide()
 if O.hideTimer then O.hideTimer:Cancel();O.hideTimer=nil end
 O.expires=nil;O.preview=nil
 if O.frame then O.frame:Hide() end
end
function O.Finish()
 if not O.frame or not O.frame:IsShown() or O.preview then return end
 O.expires=nil;O.finished=true;O.Refresh()
 if C_Timer and C_Timer.NewTimer then O.hideTimer=C_Timer.NewTimer(10,O.Hide) end
end

-- When to run.
local function InLFR()
 local _,_,difficulty=GetInstanceInfo()
 return difficulty==17 or difficulty==7 or (IsPartyLFG and IsPartyLFG()) or false
end
function RC.ShouldRun()
 local settings=RC.Settings()
 if not settings.enabled then return false end
 if settings.raidOnly then local inside,kind=IsInInstance();if not inside or kind~='raid' then return false end end
 if settings.skipLFR and InLFR() then return false end
 return true
end
function O.ShouldShow()
 local settings=RC.Settings()
 if not RC.ShouldRun() or not settings.overview then return false end
 if settings.overviewLeaderOnly and not (UnitIsGroupLeader('player') or UnitIsGroupAssistant('player')) then return false end
 return true
end
function O.OnReadyCheck(initiator,timeLeft)
 if addon.ModuleEnabled and not addon.ModuleEnabled('readycheck') then return end
 O.SendStatus()
 if not O.ShouldShow() then return end
 O.RequestDurability();O.RequestLatency()
 local duration=Public(timeLeft) and tonumber(timeLeft) or 35
 O.Show(duration,false)
end
local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','READY_CHECK','READY_CHECK_CONFIRM','READY_CHECK_FINISHED','CHAT_MSG_ADDON','UNIT_AURA','GROUP_ROSTER_UPDATE','PLAYER_REGEN_DISABLED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event,...)
 if event=='PLAYER_LOGIN' then
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX) end
 elseif event=='READY_CHECK' then O.OnReadyCheck(...)
 elseif event=='READY_CHECK_FINISHED' then O.Finish()
 elseif event=='CHAT_MSG_ADDON' then O.OnMessage(...)
 elseif event=='PLAYER_REGEN_DISABLED' then if O.frame and O.frame:IsShown() and not O.preview then O.Hide() end
 elseif O.frame and O.frame:IsShown() then O.dirty=true end
end)
