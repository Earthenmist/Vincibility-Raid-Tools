local _,addon=...
-- Aura displays drawn by Blizzard's 12.1 aura containers: VRT chooses the
-- unit and filters, Blizzard shows the matching auras (icons, timers, stacks)
-- without exposing them to the addon.
--  * Raid debuff overview: a row per group member (name and up to 4 debuffs).
--  * Co-tank debuffs: the other tank (optionally the second one), large icons
--    shown in a tanking spec or always.
-- Filters: the configured spell lists (all bosses combined), or "HARMFUL|RAID"
-- (boss and dispellable debuffs, as on raid frames) when a list is empty.
-- The preview draws VRT's own sample icons, so the displays can always be seen
-- and placed even if the game's containers are unavailable. Containers are
-- created and reconfigured out of combat only.
local D={rows={},tanks={}};addon.AuraDisplays=D
local MAX_ROWS,NAME_WIDTH=30,96
local colours={background={0.078,0.086,0.106,0.9},border={0.180,0.196,0.235,1},text={0.910,0.918,0.941,1},muted={0.541,0.561,0.612,1},highlight={0.78,0.11,0.25,1}}
-- Sample auras for the preview: icon, seconds, stacks, border colour (dispel type).
local samples={{136207,26,2,{.2,.6,1}},{136122,1,3,{.64,.2,.93}},{136224,52,4,{.8,.5,.1}},{135848,7,5,{.4,.8,.2}},{136118,34,6,{.8,.1,.1}},{132090,12,1,{.6,.6,.6}},{136123,45,2,{.2,.6,1}},{135975,9,1,{.64,.2,.93}}}

local function Busy() local R=addon.Reminders;return InCombatLockdown() or (R and R.encounter) or false end
local function Settings(key) return addon.Auras.Store().display[key] end
function D.CotankSettings()
 local settings=Settings('cotank')
 if type(settings.size)~='number' then settings.size=48 end
 if type(settings.max)~='number' then settings.max=5 end
 if settings.grow~='LEFT' then settings.grow='RIGHT' end
 if settings.when~='always' then settings.when='tank' end
 settings.second=settings.second==true
 return settings
end
function D.OverviewSettings()
 local settings=Settings('overview')
 if type(settings.size)~='number' then settings.size=22 end
 if type(settings.max)~='number' then settings.max=4 end
 if type(settings.columns)~='number' then settings.columns=1 end
 return settings
end
-- Displays show in raids; in 5-player parties (dungeons, Mythic+) only when you opt in.
function D.GroupAllowed()
 if IsInRaid() then return true end
 return IsInGroup() and addon.Auras.Store().display.parties==true or false
end
function D.ContainersAvailable()
 if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded('Blizzard_AuraContainer') and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn,'Blizzard_AuraContainer') end
 return AnchorUtil~=nil and AnchorUtil.FlowLayoutAxis~=nil and AnchorUtil.FlowDirection~=nil
end
local function Paint(frame,colour)
 frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 frame:SetBackdropColor(unpack(colours[colour or 'background']));frame:SetBackdropBorderColor(unpack(colours.border))
end
local function Label(parent,size,colour,width)
 local text=parent:CreateFontString(nil,'OVERLAY');text:SetFont(STANDARD_TEXT_FONT,size,'OUTLINE');text:SetTextColor(unpack(colours[colour or 'text']))
 text:SetJustifyH('LEFT');if width then text:SetWidth(width);text:SetWordWrap(false) end
 return text
end
-- One icon look for both real (Blizzard-filled) and sample buttons: timer in
-- the middle, stacks bottom-right, a coloured edge.
local function Dress(button,size)
 button:SetSize(size,size)
 if not button.vrtIcon then
  button.vrtEdge=button:CreateTexture(nil,'BACKGROUND');button.vrtEdge:SetAllPoints(button);button.vrtEdge:SetColorTexture(0,0,0,1)
  button.vrtIcon=button:CreateTexture(nil,'ARTWORK');button.vrtIcon:SetPoint('TOPLEFT',2,-2);button.vrtIcon:SetPoint('BOTTOMRIGHT',-2,2)
  button.vrtIcon:SetTexCoord(.08,.92,.08,.92)
  button.vrtTime=button:CreateFontString(nil,'OVERLAY');button.vrtTime:SetPoint('CENTER',0,0)
  button.vrtCount=button:CreateFontString(nil,'OVERLAY');button.vrtCount:SetPoint('BOTTOMRIGHT',-2,2)
 end
 button.vrtTime:SetFont(STANDARD_TEXT_FONT,math.max(7,math.floor(size*.42)),'OUTLINE')
 button.vrtCount:SetFont(STANDARD_TEXT_FONT,math.max(6,math.floor(size*.32)),'OUTLINE')
end
local function InitButton(button,size)
 Dress(button,size)
 if button.SetIcon then button:SetIcon(button.vrtIcon) end
 if button.SetDurationText then button:SetDurationText(button.vrtTime,{}) end
 if button.SetApplicationCount then button:SetApplicationCount(button.vrtCount,{}) end
 if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
end
local function Filters(list)
 local set=addon.Auras.SpellSet(list)
 if set then return 'HARMFUL',{includeSpellIDs=set} end
 return 'HARMFUL|RAID',{}
end
-- A Blizzard aura container, or nil (with the reason) if the game refuses.
local function NewContainer(parent,list,size,count,grow)
 if not D.ContainersAvailable() then D.problem='The game\'s aura containers are not available.';return nil end
 local ok,container=pcall(function()
  local c=CreateFrame('AuraContainer',nil,parent,'CustomAuraContainerTemplate')
  c:SetSize(count*(size+2),size)
  c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
  c:SetFlowLayoutAnchorPoint(grow=='LEFT' and 'TOPRIGHT' or 'TOPLEFT')
  c:SetFlowLayoutGrowthDirection(grow=='LEFT' and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,AnchorUtil.FlowDirection.Down)
  local filter,candidates=Filters(list)
  c:AddAuraGroup('VRT',filter,{maxFrameCount=count,candidateFilters=candidates,
   initializeFrame=function(button) InitButton(button,size) end,
   layout={elementWidth=size,elementHeight=size,elementSpacing=2,lineSpacing=2}})
  c.vrtFilter=filter
  return c
 end)
 if not ok then D.problem='Aura containers failed: '..tostring(container);return nil end
 return container
end
-- Sample icons shown only in the preview.
local function Samples(parent,size,count,grow)
 parent.vrtSamples=parent.vrtSamples or {}
 for index=1,math.max(count,#parent.vrtSamples) do
  local sample=parent.vrtSamples[index]
  if index<=count then
   if not sample then sample=CreateFrame('Frame',nil,parent);parent.vrtSamples[index]=sample end
   Dress(sample,size)
   local data=samples[(index-1)%#samples+1]
   sample.vrtIcon:SetTexture(data[1]);sample.vrtTime:SetText(tostring(data[2]));sample.vrtCount:SetText(tostring(data[3]))
   sample.vrtEdge:SetColorTexture(data[4][1],data[4][2],data[4][3],1)
   sample.vrtTime:SetTextColor(data[2]<=3 and 1 or 1,data[2]<=3 and .2 or 1,data[2]<=3 and .2 or 1)
   sample:ClearAllPoints()
   local offset=(index-1)*(size+2)
   if grow=='LEFT' then sample:SetPoint('TOPRIGHT',parent,'TOPRIGHT',-offset,0) else sample:SetPoint('TOPLEFT',parent,'TOPLEFT',offset,0) end
   sample:SetShown(D.preview)
  elseif sample then sample:Hide() end
 end
end
local function Movable(frame,key)
 frame:SetMovable(true);frame:SetClampedToScreen(true);frame:EnableMouse(false);frame:RegisterForDrag('LeftButton')
 frame:SetScript('OnDragStart',function(self) if D.preview and not InCombatLockdown() then self:StartMoving() end end)
 frame:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local x,y=self:GetCenter();local px,py=UIParent:GetCenter()
  if x and px then local settings=Settings(key);settings.x,settings.y=math.floor(x-px+.5),math.floor(y-py+.5) end
 end)
end
local function Place(frame,key,dx,dy)
 local settings=Settings(key);frame:ClearAllPoints()
 if type(settings.x)=='number' and type(settings.y)=='number' then frame:SetPoint('CENTER',UIParent,'CENTER',settings.x,settings.y)
 else frame:SetPoint('CENTER',UIParent,'CENTER',dx,dy) end
end

function D.Build()
 if D.built then return true end
 D.problem=nil
 -- Raid debuff overview.
 local overview=CreateFrame('Frame','VincibilityRaidDebuffs',UIParent,'BackdropTemplate');D.overview=overview
 Paint(overview);overview:SetSize(200,40);overview:SetFrameStrata('MEDIUM');overview:Hide()
 overview.title=Label(overview,11,'muted',220);overview.title:SetPoint('TOPLEFT',6,-5)
 Movable(overview,'overview')
 for index=1,MAX_ROWS do
  local row=CreateFrame('Frame',nil,overview)
  row.name=Label(row,10,'text',NAME_WIDTH-4);row.name:SetPoint('LEFT',2,0)
  row.icons=CreateFrame('Frame',nil,row);row.icons:SetPoint('LEFT',row,'LEFT',NAME_WIDTH,0)
  row:Hide();D.rows[index]=row
 end
 -- Co-tank debuffs: no box in the fight, just the tank's name and icons.
 local tanks=CreateFrame('Frame','VincibilityCoTankDebuffs',UIParent,'BackdropTemplate');D.tankFrame=tanks
 tanks:SetFrameStrata('MEDIUM');tanks:Hide();Movable(tanks,'cotank')
 tanks.title=Label(tanks,11,'muted',300);tanks.title:SetPoint('BOTTOMLEFT',tanks,'TOPLEFT',0,3)
 for index=1,2 do
  local block=CreateFrame('Frame',nil,tanks)
  block.name=Label(block,12,'text',260)
  block.icons=CreateFrame('Frame',nil,block)
  block:Hide();D.tanks[index]=block
 end
 Place(overview,'overview',-450,0);Place(tanks,'cotank',0,-160)
 D.built=true
 return true
end
-- Co-tank blocks follow the size, count and direction settings; containers
-- are rebuilt when those change.
local function LayoutTanks()
 local settings=D.CotankSettings()
 local size,count,grow=settings.size,settings.max,settings.grow
 local width=count*(size+2)
 for index,block in ipairs(D.tanks) do
  block:SetSize(width,size+16);block:ClearAllPoints();block:SetPoint('TOPLEFT',D.tankFrame,'TOPLEFT',0,-(index-1)*(size+22))
  block.name:ClearAllPoints()
  if grow=='LEFT' then block.name:SetPoint('TOPRIGHT',block,'TOPRIGHT',0,0);block.name:SetJustifyH('RIGHT') else block.name:SetPoint('TOPLEFT',block,'TOPLEFT',0,0);block.name:SetJustifyH('LEFT') end
  block.icons:SetSize(width,size);block.icons:ClearAllPoints();block.icons:SetPoint('TOPLEFT',block,'TOPLEFT',0,-16)
  local signature=size..':'..count..':'..grow
  if block.signature~=signature and not Busy() then
   if block.container then block.container:Hide();if block.container.SetEnabled then block.container:SetEnabled(false) end;block.container=nil end
   block.container=NewContainer(block.icons,'cotank',size,count,grow)
   if block.container then block.container:SetPoint(grow=='LEFT' and 'TOPRIGHT' or 'TOPLEFT',block.icons,grow=='LEFT' and 'TOPRIGHT' or 'TOPLEFT',0,0) end
   block.signature=signature;block.unit=nil
  end
  Samples(block.icons,size,count,grow)
 end
 D.tankFrame:SetSize(width,(settings.second and 2 or 1)*(size+22))
end
-- Overview rows follow the size and icon settings; containers are rebuilt
-- when those change (out of combat).
local function LayoutRows()
 local settings=D.OverviewSettings()
 local size,count=settings.size,settings.max
 for _,row in ipairs(D.rows) do
  row:SetSize(NAME_WIDTH+count*(size+2),size+2);row.icons:SetSize(count*(size+2),size)
  local signature=size..':'..count
  if row.signature~=signature and not Busy() then
   if row.container then row.container:Hide();if row.container.SetEnabled then row.container:SetEnabled(false) end;row.container=nil end
   row.container=NewContainer(row.icons,'overview',size,count,'RIGHT')
   if row.container then row.container:SetPoint('TOPLEFT',row.icons,'TOPLEFT',0,0) end
   row.signature=signature;row.unit=nil
  end
 end
end
local function SetUnit(container,unit,owner)
 if not container or owner.unit==unit then return end
 owner.unit=unit;container:SetUnit(unit)
end
local function UpdateFilters(container,list)
 if not container then return end
 local filter,candidates=Filters(list)
 if container.SetAuraGroupFilterString and container.vrtFilter~=filter then container:SetAuraGroupFilterString('VRT',filter);container.vrtFilter=filter end
 if container.SetAuraGroupCandidateFilters then container:SetAuraGroupCandidateFilters('VRT',candidates) end
end
local function Enable(container,on) if container and container.SetEnabled then container:SetEnabled(on) end end
local function TankSpec()
 if UnitGroupRolesAssigned and UnitGroupRolesAssigned('player')=='TANK' then return true end
 local index=GetSpecialization and GetSpecialization()
 return index and GetSpecializationRole and GetSpecializationRole(index)=='TANK' or false
end
-- Assign units and filters (out of combat) and show what is enabled.
function D.Refresh()
 if Busy() or not D.Build() then return end
 if addon.ModuleEnabled and not addon.ModuleEnabled('auras') and not D.preview then D.overview:Hide();D.tankFrame:Hide();return end
 local U=addon.Auras
 local inGroup=D.GroupAllowed()
 -- Overview rows, in one to three columns.
 local overview=D.OverviewSettings()
 LayoutRows()
 -- Sample players for the preview, already in role order.
 local previewPlayers={{'Tank','WARRIOR'},{'Healer','PRIEST'},{'Healer','PALADIN'},{'Damage','MAGE'},{'Damage','ROGUE'},{'Damage','HUNTER'}}
 local units=D.preview and {'player','player','player','player','player','player'} or (inGroup and U.GroupUnits() or {})
 local present={}
 for _,unit in ipairs(units) do if D.preview or UnitExists(unit) then present[#present+1]=unit end end
 -- Tanks, then healers, then damage; by name within a role.
 if not D.preview then
  local order={TANK=1,HEALER=2,DAMAGER=3}
  local function Role(unit) return order[UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or ''] or 4 end
  local function Name(unit) return tostring(UnitName(unit) or unit) end
  table.sort(present,function(a,b) if Role(a)~=Role(b) then return Role(a)<Role(b) end return Name(a)<Name(b) end)
 end
 local columns=math.max(1,math.min(3,overview.columns))
 local perColumn=math.max(1,math.ceil(#present/columns))
 -- Names first, in class colours, so the name column fits the longest one shown.
 local nameWidth=40
 for index,row in ipairs(D.rows) do
  local unit=present[index]
  if unit then
   local name,class
   if D.preview then name,class=previewPlayers[index][1],previewPlayers[index][2] else name=UnitName(unit) or unit;class=UnitClass and select(2,UnitClass(unit)) end
   local colour=class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
   row.name:SetWidth(NAME_WIDTH-4);row.name:SetText(name)
   if colour then row.name:SetTextColor(colour.r,colour.g,colour.b) else row.name:SetTextColor(unpack(colours.text)) end
   local width=row.name.GetStringWidth and row.name:GetStringWidth()
   nameWidth=math.max(nameWidth,math.min(NAME_WIDTH,(type(width)=='number' and width or NAME_WIDTH)+10))
  end
 end
 local rowHeight,rowWidth=overview.size+2,nameWidth+overview.max*(overview.size+2)
 for index,row in ipairs(D.rows) do
  local unit=present[index]
  if unit then
   local column,line=math.floor((index-1)/perColumn),(index-1)%perColumn
   row:ClearAllPoints();row:SetPoint('TOPLEFT',D.overview,'TOPLEFT',4+column*(rowWidth+8),-20-line*rowHeight)
   row:SetWidth(rowWidth);row.name:SetWidth(nameWidth-4)
   row.icons:ClearAllPoints();row.icons:SetPoint('LEFT',row,'LEFT',nameWidth,0)
   if not D.preview then SetUnit(row.container,unit,row);UpdateFilters(row.container,'overview') end
   Enable(row.container,not D.preview)
   if row.container then row.container:SetShown(not D.preview) end
   Samples(row.icons,overview.size,D.preview and math.min(overview.max,(index%overview.max)+1) or 0,'RIGHT')
   row:Show()
  else Enable(row.container,false);if row.icons.vrtSamples then Samples(row.icons,overview.size,0,'RIGHT') end;row:Hide() end
 end
 local usedColumns=math.min(columns,math.max(1,#present))
 D.overview:SetSize(8+usedColumns*(rowWidth+8),24+math.min(perColumn,math.max(1,#present))*rowHeight)
 D.overview.title:SetText(D.preview and 'Raid debuffs (drag me)' or 'Raid debuffs')
 D.overview:SetShown((D.preview or (Settings('overview').enabled~=false and inGroup)) and true or false)
 -- Co-tank blocks.
 local settings=D.CotankSettings()
 LayoutTanks()
 local tanks=U.CoTankUnits()
 local wanted=D.preview and (settings.second and 2 or 1) or math.min(#tanks,settings.second and 2 or 1)
 for index,block in ipairs(D.tanks) do
  if index<=wanted then
   local unit=tanks[index]
   block.name:SetText(D.preview and ('Co-tank '..index) or (UnitName(unit) or unit))
   if not D.preview then SetUnit(block.container,unit,block);UpdateFilters(block.container,'cotank') end
   Enable(block.container,not D.preview)
   if block.container then block.container:SetShown(not D.preview) end
   block:Show()
  else Enable(block.container,false);block:Hide() end
 end
 local active=inGroup and settings.enabled~=false and #tanks>0 and (settings.when=='always' or TankSpec())
 D.tankFrame:SetShown((D.preview or active) and true or false)
 if D.preview then Paint(D.tankFrame) else D.tankFrame:SetBackdrop(nil) end
 D.tankFrame.title:SetText(D.preview and 'Co-tank debuffs (drag me)' or '')
end
-- Preview: show both displays with sample icons, movable.
function D.SetPreview(on)
 if Busy() then return false,'Position the displays out of combat.' end
 D.Build()
 D.preview=on and true or false
 -- Above the main VRT window while placing them; normal layer in the fight.
 for _,frame in ipairs({D.overview,D.tankFrame}) do frame:EnableMouse(D.preview);frame:SetFrameStrata(D.preview and 'FULLSCREEN_DIALOG' or 'MEDIUM') end
 D.Refresh()
 if not D.preview then return true,'Display positions saved.' end
 return true,'Drag the displays into place, then click Done.'..(D.problem and (' Note: '..D.problem) or '')
end
