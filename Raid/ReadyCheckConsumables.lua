local _,addon=...
-- Consumables bar shown on a ready check: your food, flask, weapon oil per
-- weapon and augment rune with time left and bag counts. Flask, oil and rune
-- buttons can use an item from your bags through secure item buttons; food is
-- status only so a click can never place a feast. Attributes change only out
-- of combat, and the bar hides in combat.
local RC=addon.ReadyCheck
local O=RC.Overview
local C={buttons={}};RC.Consumables=C

-- Current-expansion items (best first); verify the IDs each season
-- in game. Bag fallbacks use item classes and English names.
local flaskVariants={
 {buff=1235111,items={245929,245928,241326,241327}},
 {buff=1235108,items={245933,245932,241322,241323}},
 {buff=1235110,items={245931,245930,241324,241325}},
 {buff=1235057,items={245926,245927,241320,241321}},
}
-- Weapon enchants by the weapons they fit ('any' fits every weapon).
local oilVariants={
 {kind='any',items={243734,243733}},    -- Thalassian Phoenix Oil
 {kind='any',items={243736,243735}},    -- Oil of Dawn
 {kind='any',items={243738,243737}},    -- Smuggler's Enchanted Edge
 {kind='bladed',items={237371,237370}}, -- Refulgent Whetstone
 {kind='blunt',items={237369,237367}},  -- Refulgent Weightstone
 {kind='ranged',items={257750,257749}}, -- Laced Zoomshots
 {kind='ranged',items={257752,257751}}, -- Weighted Boomshots
}
local oilItems={};for _,variant in ipairs(oilVariants) do for _,id in ipairs(variant.items) do oilItems[#oilItems+1]=id end end
local runeItems={259085,243191,274797}
local CONSUMABLE,FLASK_SUBCLASS,WEAPON=0,3,2
C.flaskVariants=flaskVariants
local QUESTION='Interface\\Icons\\INV_Misc_QuestionMark'
local FOOD_ICON=136000
-- Category placeholder: the first known item's own icon, else a question mark.
local function Placeholder(list)
 for _,id in ipairs(list) do local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id);if icon then return icon end end
 return QUESTION
end
local LOW=600

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Count(itemID) return C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID) or 0 end
local function FirstOwned(list) for _,id in ipairs(list) do if Count(id)>0 then return id end end end
-- Every item in the player's bags as {itemID, classID, subclassID, name}.
function C.BagItems()
 local list,seen={},{}
 if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return list end
 for bag=0,5 do
  for slot=1,(C_Container.GetContainerNumSlots(bag) or 0) do
   local info=C_Container.GetContainerItemInfo(bag,slot)
   local id=type(info)=='table' and info.itemID
   if id and not seen[id] then
    seen[id]=true
    local _,_,_,_,_,classID,subclassID=C_Item.GetItemInfoInstant(id)
    list[#list+1]={itemID=id,classID=classID,subclassID=subclassID,name=type(info.itemName)=='string' and info.itemName or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ''}
   end
  end
 end
 return list
end
function C.ChooseFlask(currentBuff)
 for _,variant in ipairs(flaskVariants) do if variant.buff==currentBuff then local id=FirstOwned(variant.items);if id then return id end end end
 for _,variant in ipairs(flaskVariants) do local id=FirstOwned(variant.items);if id then return id end end
 for _,item in ipairs(C.BagItems()) do if item.classID==CONSUMABLE and item.subclassID==FLASK_SUBCLASS then return item.itemID end end
end
-- Weapon subclasses: bows, guns, crossbows and wands are ranged; maces and
-- staves blunt; other melee weapons bladed.
local RANGED={[2]=true,[3]=true,[18]=true,[19]=true}
local BLUNT={[4]=true,[5]=true,[10]=true}
function C.WeaponKind(slot)
 local link=slot and GetInventoryItemLink('player',slot)
 if not link or not C_Item.GetItemInfoInstant then return nil end
 local _,_,_,_,_,classID,subclassID=C_Item.GetItemInfoInstant(link)
 if classID~=WEAPON then return nil end
 return RANGED[subclassID] and 'ranged' or BLUNT[subclassID] and 'blunt' or 'bladed'
end
-- Best owned enchant for the weapon in that slot (any weapon when no slot).
function C.ChooseOil(slot)
 local kind=C.WeaponKind(slot)
 for _,variant in ipairs(oilVariants) do
  if variant.kind=='any' or not kind or variant.kind==kind then local id=FirstOwned(variant.items);if id then return id end end
 end
 for _,item in ipairs(C.BagItems()) do
  if item.classID==CONSUMABLE and (item.name:find('Oil') or item.name:find('Whetstone') or item.name:find('Weightstone')) then return item.itemID end
 end
end
function C.ChooseRune()
 local id=FirstOwned(runeItems);if id then return id end
 for _,item in ipairs(C.BagItems()) do if item.name:find('Augment Rune') then return item.itemID end end
end
local function IsWeapon(slot)
 local link=GetInventoryItemLink('player',slot)
 if not link or not C_Item.GetItemInfoInstant then return false end
 local _,_,_,_,_,classID=C_Item.GetItemInfoInstant(link)
 return classID==WEAPON
end
-- Slots to show: {key, label, remaining seconds or nil, missing, item, targetSlot}.
function C.Slots()
 local record=O.ScanUnit('player')
 local slots={}
 local food=record.food
 slots[#slots+1]={key='food',label='Food',icon=food and food.icon or FOOD_ICON,remaining=food and food.remaining,missing=not food and not record.eating,eating=record.eating}
 local flask=record.flask
 local flaskBuff
 if flask and C_UnitAuras then
  for index=1,80 do
   local aura=C_UnitAuras.GetAuraDataByIndex('player',index,'HELPFUL')
   if not aura then break end
   if Public(aura.spellId) and O.Classify(aura)=='flask' then flaskBuff=aura.spellId;break end
  end
 end
 slots[#slots+1]={key='flask',label='Flask',icon=flask and flask.icon or Placeholder(flaskVariants[1].items),remaining=flask and flask.remaining,missing=not flask,item=C.ChooseFlask(flaskBuff)}
 local hasMain,mainExpires,_,_,hasOff,offExpires=GetWeaponEnchantInfo()
 if IsWeapon(16) then slots[#slots+1]={key='oil',label='Main hand',icon=Placeholder(oilItems),remaining=hasMain and mainExpires and mainExpires/1000,missing=not hasMain,item=C.ChooseOil(16),targetSlot=16} end
 if IsWeapon(17) then slots[#slots+1]={key='oil',label='Off hand',icon=Placeholder(oilItems),remaining=hasOff and offExpires and offExpires/1000,missing=not hasOff,item=C.ChooseOil(17),targetSlot=17} end
 local rune=record.rune
 slots[#slots+1]={key='rune',label='Augment rune',icon=rune and rune.icon or Placeholder(runeItems),remaining=rune and rune.remaining,missing=not rune,item=C.ChooseRune()}
 if record.restricted then for _,slot in ipairs(slots) do slot.unknown=true end end
 return slots
end
local function Duration(seconds)
 if not seconds then return '' end
 if seconds>=3600 then return math.floor(seconds/3600)..'h' end
 return math.max(0,math.floor(seconds/60+.5))..'m'
end
-- Low when missing, or flask under the chosen threshold / others under 10 min.
function C.IsLow(slot)
 if slot.unknown or slot.eating then return false end
 if slot.missing then return true end
 local threshold=slot.key=='flask' and (RC.Settings().flaskWarn or 0)*60 or LOW
 return slot.remaining~=nil and threshold>0 and slot.remaining<threshold
end

-- Display.
local colours=O.colours
local SIZE,GAP=40,6
local function ItemIcon(itemID) return C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) end
local function Button(index)
 if C.buttons[index] then return C.buttons[index] end
 local button=CreateFrame('Button',nil,C.frame,'SecureActionButtonTemplate,BackdropTemplate');C.buttons[index]=button
 button:SetSize(SIZE,SIZE);button:SetPoint('TOPLEFT',8+(index-1)*(SIZE+GAP),-26)
 button:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=2})
 button:SetBackdropColor(unpack(colours.raised))
 button:RegisterForClicks('AnyDown');button:SetAttribute('useOnKeyDown',true)
 button.icon=button:CreateTexture(nil,'ARTWORK');button.icon:SetPoint('TOPLEFT',2,-2);button.icon:SetPoint('BOTTOMRIGHT',-2,2)
 button.time=button:CreateFontString(nil,'OVERLAY');button.time:SetFont(STANDARD_TEXT_FONT,11,'OUTLINE');button.time:SetPoint('TOP',button,'BOTTOM',0,-3)
 button.count=button:CreateFontString(nil,'OVERLAY');button.count:SetFont(STANDARD_TEXT_FONT,11,'OUTLINE');button.count:SetPoint('BOTTOMRIGHT',-2,3)
 button.state=button:CreateFontString(nil,'OVERLAY');button.state:SetFont(STANDARD_TEXT_FONT,14,'OUTLINE');button.state:SetPoint('CENTER')
 -- Missing, but there is one in your bags: the action-bar proc glow. Built on
 -- our own frame from Blizzard's alert template (sized as the action bars do),
 -- so the action bars' own alert manager is never touched.
 button.glowing=false
 local ok,alert=pcall(CreateFrame,'Frame',nil,button,'ActionButtonSpellAlertTemplate')
 if ok and alert and type(alert.ProcStartAnim)=='table' and type(alert.ProcLoop)=='table' then
  alert:SetSize(SIZE*1.4,SIZE*1.4);alert:SetPoint('CENTER',button,'CENTER',0,0);alert:Hide()
  if alert.ProcStartFlipbook then alert.ProcStartFlipbook:SetSize(150*SIZE/45,150*SIZE/45) end
  button.alert=alert
 else
  -- Fallback when the template is unavailable: a pulsing gold ring.
  button.glow=CreateFrame('Frame',nil,button);button.glow:SetAllPoints(button);button.glow:SetFrameLevel((button:GetFrameLevel() or 0)+5);button.glow:Hide()
  local ring=button.glow:CreateTexture(nil,'OVERLAY')
  ring:SetTexture('Interface\\Buttons\\UI-ActionButton-Border');ring:SetBlendMode('ADD');ring:SetVertexColor(1,.88,.3)
  ring:SetSize(SIZE*2,SIZE*2);ring:SetPoint('CENTER')
  local pulse=button.glow.CreateAnimationGroup and button.glow:CreateAnimationGroup()
  if pulse then
   pulse:SetLooping('BOUNCE')
   local fade=pulse:CreateAnimation('Alpha');fade:SetFromAlpha(.6);fade:SetToAlpha(1);fade:SetDuration(.6)
   button.pulse=pulse
  end
 end
 button:SetScript('OnEnter',function(self)
  if not GameTooltip or not self.slot then return end
  GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(self.slot.label,1,1,1)
  local slot=self.slot
  if slot.unknown then GameTooltip:AddLine('Buff data is hidden by the game right now.',1,.8,.3,true)
  elseif slot.eating then GameTooltip:AddLine('Eating now.',1,.8,.3)
  elseif slot.missing then GameTooltip:AddLine('Missing.',1,.4,.4)
  else GameTooltip:AddLine(slot.remaining and (Duration(slot.remaining)..' left') or 'Active',.7,.9,.7) end
  if slot.key=='food' then GameTooltip:AddLine('Eat from a feast or your bags.',.75,.78,.82,true)
  elseif self.useItem then GameTooltip:AddLine('Click to use '..((C_Item.GetItemNameByID and C_Item.GetItemNameByID(self.useItem)) or 'item')..(slot.targetSlot and (' on your '..slot.label:lower()) or '')..'.',.75,.78,.82,true)
  elseif slot.item==nil then GameTooltip:AddLine('None in your bags.',.75,.78,.82) end
  GameTooltip:Show()
 end)
 button:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
 button:HookScript('PostClick',function() if C_Timer and C_Timer.After then C_Timer.After(.5,C.Refresh) end end)
 return button
end
function C.Build()
 if C.frame then return C.frame end
 local frame=CreateFrame('Frame','VincibilityReadyCheckConsumables',UIParent,'BackdropTemplate');C.frame=frame
 frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 frame:SetBackdropColor(unpack(colours.background));frame:SetBackdropBorderColor(unpack(colours.border))
 frame:SetFrameStrata('HIGH');frame:SetClampedToScreen(true);frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag('LeftButton');frame:Hide()
 frame:SetScript('OnDragStart',function(self) if not InCombatLockdown() then self:StartMoving() end end)
 frame:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local x,y=self:GetCenter();local px,py=UIParent:GetCenter()
  if x and px then RC.Settings().consumablesPosition={x=math.floor(x-px+.5),y=math.floor(y-py+.5)} end
 end)
 frame.title=frame:CreateFontString(nil,'OVERLAY');frame.title:SetFont(STANDARD_TEXT_FONT,10,'');frame.title:SetTextColor(unpack(colours.accent))
 frame.title:SetPoint('TOPLEFT',8,-6);frame.title:SetText('CONSUMABLES')
 frame.close=O.CloseButton(frame,function() C.Hide() end)
 frame.close:SetSize(16,16);frame.close:ClearAllPoints();frame.close:SetPoint('TOPRIGHT',-4,-3)
 frame:SetScript('OnUpdate',function(_,elapsed)
  C.elapsed=(C.elapsed or 0)+elapsed
  if C.elapsed>=1 then C.elapsed=0;C.Refresh() end
 end)
 return frame
end
-- Secure attributes; callers guarantee we are out of combat.
local function Arm(button,slot,clickable)
 local item=clickable and slot.key~='food' and slot.item or nil
 button.useItem=item
 button:SetAttribute('type',item and 'item' or nil)
 button:SetAttribute('item',item and ('item:'..item) or nil)
 button:SetAttribute('target-slot',item and slot.targetSlot or nil)
end
function C.Refresh()
 local frame=C.frame
 if not frame or not frame:IsShown() then return end
 if InCombatLockdown() then return end
 local clickable=RC.Settings().consumablesClick
 local slots=C.Slots()
 for index,slot in ipairs(slots) do
  local button=Button(index)
  button.slot=slot;Arm(button,slot,clickable)
  local icon=slot.missing and slot.item and ItemIcon(slot.item) or slot.icon
  button.icon:SetTexture(icon);button.icon:SetDesaturated(slot.missing and not slot.unknown)
  button.time:SetText(slot.unknown and '?' or slot.eating and 'eating' or slot.missing and '' or Duration(slot.remaining))
  button.count:SetText(slot.item and Count(slot.item)>0 and tostring(Count(slot.item)) or '')
  button.state:SetText(slot.missing and not slot.unknown and '|cffff5050x|r' or '')
  -- Missing with one in the bags: glow so it catches the eye.
  local inBags=slot.missing and not slot.unknown and slot.item~=nil and Count(slot.item)>0
  local alert=type(button.alert)=='table' and button.alert or nil
  if alert then
   -- Burst once when it starts, then loop (the template chains the two).
   if inBags and not button.glowing then alert:Show();alert.ProcLoop:Stop();alert.ProcStartAnim:Play()
   elseif not inBags and button.glowing then alert.ProcStartAnim:Stop();alert.ProcLoop:Stop();alert:Hide() end
  else
   local pulse=type(button.pulse)=='table' and button.pulse or nil
   if inBags then button.glow:Show();if pulse and not pulse:IsPlaying() then pulse:Play() end
   else button.glow:Hide();if pulse then pulse:Stop() end end
  end
  button.glowing=inBags
  local low=C.IsLow(slot)
  button:SetBackdropBorderColor(unpack(low and colours.highlight or colours.border))
  button:Show()
 end
 for index=#slots+1,#C.buttons do C.buttons[index]:Hide();Arm(C.buttons[index],{},false) end
 frame:SetSize(16+#slots*SIZE+(#slots-1)*GAP,26+SIZE+24)
 C.slots=slots
end
function C.Show(preview)
 if InCombatLockdown() then return false end
 local frame=C.Build()
 local position=RC.Settings().consumablesPosition
 frame:ClearAllPoints()
 if type(position)=='table' and type(position.x)=='number' and type(position.y)=='number' then frame:SetPoint('CENTER',UIParent,'CENTER',position.x,position.y)
 else frame:SetPoint('CENTER',UIParent,'CENTER',0,-140) end
 if C.hideTimer then C.hideTimer:Cancel();C.hideTimer=nil end
 C.preview=preview
 frame:Show();C.Refresh()
 return true
end
-- Protected buttons cannot be hidden during combat lockdown; PLAYER_REGEN_DISABLED
-- fires just before lockdown, so the combat hide still works.
function C.Hide()
 if C.hideTimer then C.hideTimer:Cancel();C.hideTimer=nil end
 if C.frame and not InCombatLockdown() then C.frame:Hide() end
end
function C.OnReadyCheck(initiator)
 if addon.ModuleEnabled and not addon.ModuleEnabled('readycheck') then return end
 local settings=RC.Settings()
 if not settings.consumables or not RC.ShouldRun() then return end
 -- Event order between modules is not guaranteed; resolve the starter here.
 if RC.Report then RC.Report.OnReadyCheck(initiator) end
 if settings.consumablesSkipStarter and RC.Report and RC.Report.startedByMe then return end
 C.Show(false)
end
function C.Finish()
 if C.frame and C.frame:IsShown() and not C.preview and C_Timer and C_Timer.NewTimer then C.hideTimer=C_Timer.NewTimer(5,C.Hide) end
end
local events=CreateFrame('Frame')
for _,event in ipairs({'READY_CHECK','READY_CHECK_FINISHED','PLAYER_REGEN_DISABLED','BAG_UPDATE_DELAYED','UNIT_INVENTORY_CHANGED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event,...)
 if event=='READY_CHECK' then C.OnReadyCheck(...)
 elseif event=='READY_CHECK_FINISHED' then C.Finish()
 elseif event=='PLAYER_REGEN_DISABLED' then C.Hide()
 else C.Refresh() end
end)
