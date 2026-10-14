local _,addon=...
-- Personal ready-check warnings: each player sees what to fix on their own
-- character. Gear checks read only the player's equipment; buff checks read
-- public aura data and are skipped while the game marks auras secret.
local RC=addon.ReadyCheck
local O=RC.Overview
local P={};RC.Personal=P

local slotNames={[1]='Head',[2]='Neck',[3]='Shoulder',[5]='Chest',[6]='Waist',[7]='Legs',[8]='Feet',[9]='Wrist',[10]='Hands',
 [11]='Ring 1',[12]='Ring 2',[13]='Trinket 1',[14]='Trinket 2',[15]='Back',[16]='Main hand',[17]='Off hand'}
local gearSlots={1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17}
local enchantSlots={[1]=true,[3]=true,[5]=true,[7]=true,[8]=true,[11]=true,[12]=true,[16]=true,[17]=true}
local armourSlots={[1]=true,[3]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true}
local tierSlots={1,3,5,7,10}
local armourByClass={WARRIOR=4,PALADIN=4,DEATHKNIGHT=4,HUNTER=3,SHAMAN=3,EVOKER=3,ROGUE=2,MONK=2,DRUID=2,DEMONHUNTER=2,PRIEST=1,MAGE=1,WARLOCK=1}
local armourNames={'cloth','leather','mail','plate'}
local EMBELLISHED_BONUS=8960
P.slotNames=slotNames

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function ItemInfo(link)
 if not link or not C_Item or not C_Item.GetItemInfo then return end
 return C_Item.GetItemInfo(link)
end
-- Fields after "item:" in an item link; bonus IDs follow the count in field 13.
function P.LinkFields(link)
 local body=type(link)=='string' and link:match('item:([%-%d:]+)')
 if not body then return {} end
 local fields={};for value in (body..':'):gmatch('([^:]*):') do fields[#fields+1]=value end
 return fields
end
function P.BonusIDs(link)
 local fields=P.LinkFields(link);local count=tonumber(fields[13] or '') or 0
 local ids={};for index=1,count do local id=tonumber(fields[13+index] or '');if id then ids[id]=true end end
 return ids
end
function P.HasEnchant(link)
 local enchant=P.LinkFields(link)[2]
 return enchant~=nil and enchant~='' and enchant~='0'
end
function P.EmptySockets(link)
 if not C_Item or not C_Item.GetItemStats then return 0 end
 local ok,stats=pcall(C_Item.GetItemStats,link)
 if not ok or type(stats)~='table' then return 0 end
 local sockets=0;for key,count in pairs(stats) do if type(key)=='string' and key:find('EMPTY_SOCKET_') then sockets=sockets+(tonumber(count) or 0) end end
 local filled=0
 if C_Item.GetItemGem then for index=1,sockets do if C_Item.GetItemGem(link,index) then filled=filled+1 end end end
 return math.max(0,sockets-filled)
end
local function ItemLevel(link)
 if C_Item and C_Item.GetDetailedItemLevelInfo then local level=C_Item.GetDetailedItemLevelInfo(link);if level then return level end end
 return select(4,ItemInfo(link))
end
local function SpecID()
 local index=GetSpecialization and GetSpecialization()
 return index and GetSpecializationInfo and (GetSpecializationInfo(index))
end

function P.GearWarnings(personal)
 local warnings={}
 local _,class=UnitClass('player')
 local average=GetAverageItemLevel and select(2,GetAverageItemLevel()) or 0
 local embellished,repair=0,false
 local sets={}
 for _,slot in ipairs(gearSlots) do
  local link=GetInventoryItemLink('player',slot)
  if link then
   if personal.enchants and enchantSlots[slot] and not P.HasEnchant(link) then
    local skip=slot==17 and select(12,ItemInfo(link))==4 -- shields/off-hand frills cannot be enchanted
    if not skip then warnings[#warnings+1]='Missing enchant: '..slotNames[slot] end
   end
   if personal.gems then
    local empty=P.EmptySockets(link)
    if empty>0 then warnings[#warnings+1]='Empty socket'..(empty>1 and 's' or '')..': '..slotNames[slot] end
   end
   if personal.itemLevel and average>0 then
    local level=ItemLevel(link)
    if level and level<average-15 then warnings[#warnings+1]=string.format('Low item level: %s (%d)',slotNames[slot],level) end
   end
   if personal.missingItems and armourSlots[slot] and armourByClass[class] then
    local classID,subclassID=select(12,ItemInfo(link))
    if classID==4 and subclassID and subclassID>=1 and subclassID<=4 and subclassID~=armourByClass[class] then
     warnings[#warnings+1]='Wrong armour type: '..slotNames[slot]..' ('..armourNames[subclassID]..')'
    end
   end
   if P.BonusIDs(link)[EMBELLISHED_BONUS] then embellished=embellished+1 end
   if GetInventoryItemDurability then
    local current,maximum=GetInventoryItemDurability(slot)
    if current and maximum and maximum>0 and current/maximum<=.2 then repair=true end
   end
  elseif personal.missingItems then
   local needed=true
   if slot==17 then
    local main=GetInventoryItemLink('player',16)
    local equipLoc=main and select(9,ItemInfo(main))
    needed=equipLoc=='INVTYPE_WEAPON' or equipLoc=='INVTYPE_WEAPONMAINHAND' or SpecID()==72
   end
   if needed then warnings[#warnings+1]='Not equipped: '..slotNames[slot] end
  end
 end
 if personal.tier then
  for _,slot in ipairs(tierSlots) do
   local setID=select(16,ItemInfo(GetInventoryItemLink('player',slot)))
   if type(setID)=='number' and setID>0 then sets[setID]=(sets[setID] or 0)+1 end
  end
  local best=0;for _,count in pairs(sets) do best=math.max(best,count) end
  if best<2 then warnings[#warnings+1]='No tier set bonus equipped'
  elseif best<4 then warnings[#warnings+1]='Only the 2-piece tier bonus is equipped' end
 end
 if personal.embellishments and embellished<2 then warnings[#warnings+1]=string.format('Embellishments: %d of 2 equipped',embellished) end
 if personal.repair and repair then warnings[#warnings+1]='Gear needs repair' end
 return warnings
end

-- Buff checks.
local function GroupUnits()
 local units={}
 for _,unit in ipairs(O.Units()) do
  if UnitIsVisible(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then units[#units+1]=unit end
 end
 return units
end
local function MyAura(unit,spellID)
 for index=1,80 do
  local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,unit,index,'HELPFUL')
  if not ok or not aura then return end
  if Public(aura.spellId) and aura.spellId==spellID and Public(aura.sourceUnit) and aura.sourceUnit and UnitIsUnit(aura.sourceUnit,'player') then return aura end
 end
end
local function Known(spellID)
 if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then return C_SpellBook.IsSpellKnownOrInSpellBook(spellID,nil,true) end
 return IsPlayerSpell and IsPlayerSpell(spellID) or false
end
-- One of my buffs that should be on someone matching filter; missing or expiring.
local function Placed(spellID,label,filter)
 for _,unit in ipairs(GroupUnits()) do
  if filter(unit) then
   local aura=MyAura(unit,spellID)
   if aura then
    local remaining=Public(aura.expirationTime) and aura.expirationTime and aura.expirationTime>0 and aura.expirationTime-GetTime()
    if remaining and remaining<600 then return 'Refresh '..label end
    return
   end
  end
 end
 return label..' missing'
end
function P.BuffWarnings(personal)
 local warnings={}
 if O.Restricted() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return warnings end
 local _,class=UnitClass('player')
 if personal.rebuff then
  for _,buff in ipairs(O.raidBuffs) do
   if buff.class==class then
    local missing=0
    for _,unit in ipairs(GroupUnits()) do if not O.ScanUnit(unit).buffs[buff.key] then missing=missing+1 end end
    if missing>0 then warnings[#warnings+1]=string.format('Rebuff %s (%d missing)',buff.name,missing) end
   end
  end
 end
 if personal.classUtility then
  local healer=function(unit) return UnitGroupRolesAssigned(unit)=='HEALER' end
  local other=function(unit) return not UnitIsUnit(unit,'player') end
  if class=='WARLOCK' then
   local cooldown=C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(20707)
   local waiting=cooldown and Public(cooldown.duration) and cooldown.duration>0 and cooldown.startTime+cooldown.duration-GetTime()>30
   if not waiting then warnings[#warnings+1]=Placed(20707,'Soulstone',healer) end
  elseif class=='EVOKER' then
   if Known(369459) then warnings[#warnings+1]=Placed(369459,'Source of Magic',function(unit) return healer(unit) and other(unit) end) end
   if SpecID()==1473 and Known(360827) then warnings[#warnings+1]=Placed(360827,'Blistering Scales',other) end
  elseif class=='DRUID' and Known(474750) then
   warnings[#warnings+1]=Placed(474750,'Symbiotic Relationship',other)
  end
 end
 return warnings
end
function P.GroupLine(personal)
 if not personal.group or not IsInRaid() then return end
 local index=UnitInRaid and UnitInRaid('player')
 local subgroup=index and select(3,GetRaidRosterInfo(index))
 return subgroup and ('You are in group '..subgroup)
end
function P.Collect()
 local personal=RC.Settings().personal
 local lines={}
 for _,warning in ipairs(P.BuffWarnings(personal)) do lines[#lines+1]=warning end
 for _,warning in ipairs(P.GearWarnings(personal)) do lines[#lines+1]=warning end
 return lines,P.GroupLine(personal)
end

-- Display.
local colours=O.colours
function P.Build()
 if P.frame then return P.frame end
 local frame=CreateFrame('Frame','VincibilityReadyCheckWarnings',UIParent,'BackdropTemplate');P.frame=frame
 frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 frame:SetBackdropColor(unpack(colours.background));frame:SetBackdropBorderColor(unpack(colours.highlight))
 frame:SetFrameStrata('HIGH');frame:SetClampedToScreen(true);frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag('LeftButton');frame:Hide()
 frame:SetScript('OnDragStart',function(self) self:StartMoving() end)
 frame:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local x,y=self:GetCenter();local px,py=UIParent:GetCenter()
  if x and px then RC.Settings().warningsPosition={x=math.floor(x-px+.5),y=math.floor(y-py+.5)} end
 end)
 frame.title=frame:CreateFontString(nil,'OVERLAY');frame.title:SetFont(STANDARD_TEXT_FONT,13,'');frame.title:SetTextColor(unpack(colours.text))
 frame.title:SetPoint('TOPLEFT',10,-8);frame.title:SetText('Before the pull')
 frame.body=frame:CreateFontString(nil,'OVERLAY');frame.body:SetFont(STANDARD_TEXT_FONT,12,'');frame.body:SetJustifyH('LEFT');frame.body:SetJustifyV('TOP')
 frame.body:SetPoint('TOPLEFT',10,-30);frame.body:SetWidth(300)
 frame.close=O.CloseButton(frame,function() P.Hide() end)
 return frame
end
local function Speak(lines)
 if not RC.Settings().tts or #lines==0 or not (C_VoiceChat and C_VoiceChat.SpeakText) then return end
 local db=VincibilityRaidToolsDB or {}
 local voice=db.reminderVoice
 if not voice and C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then voice=C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard) end
 if type(voice)=='number' then pcall(C_VoiceChat.SpeakText,voice,table.concat(lines,'. '),0,100,false) end
end
function P.Show(lines,groupLine,preview)
 local frame=P.Build()
 local text={}
 for _,line in ipairs(lines) do text[#text+1]='|cffff6060'..line..'|r' end
 if groupLine then text[#text+1]='|cff66ccff'..groupLine..'|r' end
 if #text==0 then
  if not preview then P.Hide();return false end
  text[1]='|cff60d070Nothing to fix.|r'
 end
 frame.title:SetText(preview and 'Before the pull (preview)' or 'Before the pull')
 frame.body:SetText(table.concat(text,'\n'))
 frame:SetSize(320,40+#text*15)
 local position=RC.Settings().warningsPosition
 frame:ClearAllPoints()
 if type(position)=='table' and type(position.x)=='number' and type(position.y)=='number' then frame:SetPoint('CENTER',UIParent,'CENTER',position.x,position.y)
 else frame:SetPoint('CENTER',UIParent,'CENTER',0,180) end
 if P.hideTimer then P.hideTimer:Cancel();P.hideTimer=nil end
 frame:Show()
 if not preview then Speak(lines) end
 return true
end
function P.Hide()
 if P.hideTimer then P.hideTimer:Cancel();P.hideTimer=nil end
 if P.frame then P.frame:Hide() end
end
function P.Run(preview)
 local lines,groupLine=P.Collect()
 return P.Show(lines,groupLine,preview)
end
function P.OnReadyCheck()
 if addon.ModuleEnabled and not addon.ModuleEnabled('readycheck') then return end
 if not RC.ShouldRun() then return end
 -- Let buffs from the last few seconds arrive before reading them.
 if C_Timer and C_Timer.After then C_Timer.After(1,function() if not InCombatLockdown() then P.Run(false) end end) else P.Run(false) end
end
function P.Finish()
 if P.frame and P.frame:IsShown() and C_Timer and C_Timer.NewTimer then P.hideTimer=C_Timer.NewTimer(5,P.Hide) end
end
local events=CreateFrame('Frame')
for _,event in ipairs({'READY_CHECK','READY_CHECK_FINISHED','PLAYER_REGEN_DISABLED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event)
 if event=='READY_CHECK' then P.OnReadyCheck()
 elseif event=='READY_CHECK_FINISHED' then P.Finish()
 else P.Hide() end
end)
