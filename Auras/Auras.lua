local _,addon=...
-- Aura tracking with Blizzard's 12.1 aura APIs. Addons cannot read auras in
-- combat, so VRT only configures what Blizzard tracks and draws: aura sounds
-- (C_UnitAuras.AddAuraSound) and aura containers (Auras/AuraDisplays.lua).
-- Configuration is per boss, with "Every boss" (boss 0) for any fight; an
-- empty spell list means all boss and dispellable debuffs. Each boss's config
-- is one synced record. Sounds are registered out of combat for every boss at
-- once (boss debuff spell IDs are unique to their boss).
local U={};addon.Auras=U
U.units={{'player','Me'},{'cotank','Co-tank'},{'raid','Anyone'}}
U.triggers={{'applied','Applied'},{'stack','Gains a stack'},{'removed','Removed'}}
local MAX_SPELLS,MAX_SOUNDS=60,60

local function Now() return addon.Now and addon.Now() or (time and time() or 0) end
local function Busy()
 local R=addon.Reminders
 return InCombatLockdown() or (R and R.encounter) or false
end
local function Copy(value)
 if type(value)~='table' then return value end
 local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end
function U.Store()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.auras)~='table' then db.auras={schema=1,bosses={}} end
 local store=db.auras
 if type(store.bosses)~='table' then store.bosses={} end
 if type(store.display)~='table' then store.display={} end
 for _,key in ipairs({'overview','cotank'}) do
  if type(store.display[key])~='table' then store.display[key]={enabled=true} end
 end
 return store
end
-- Config for a boss (0 = all bosses); created when create is true.
function U.Boss(bossID,create,name)
 local store=U.Store()
 local config=store.bosses[bossID]
 if not config and create then config={name=name,sounds={},overview={},cotank={},updated=0};store.bosses[bossID]=config end
 if config and name and name~='' then config.name=name end
 return config
end
local function Touched(config)
 config.updated=math.max(Now(),(config.updated or 0)+1)
 U.dirty=true
 if addon.SyncChanged then addon.SyncChanged('auras') end
end
U.Touched=Touched

-- Validation (also used for synced records).
local function ValidSpell(id) return type(id)=='number' and id>0 and id<10000000 and id%1==0 end
local units,triggers={},{}
for _,unit in ipairs(U.units) do units[unit[1]]=true end
for _,trigger in ipairs(U.triggers) do triggers[trigger[1]]=true end
function U.ValidSound(sound)
 if type(sound)~='table' or not ValidSpell(sound.spell) or not units[sound.unit] or not triggers[sound.when] then return false end
 if type(sound.sound)~='string' or #sound.sound>512 then return false end
 local A=addon.Assignments
 if A and A.Validate then return A.Validate({time=0,who={'ALL'},text='x',soundFile=sound.sound}) end
 return true
end
function U.ValidConfig(config)
 if type(config)~='table' then return false end
 if config.name~=nil and (type(config.name)~='string' or #config.name>80) then return false end
 if type(config.sounds)~='table' or #config.sounds>MAX_SOUNDS then return false end
 for _,sound in ipairs(config.sounds) do if not U.ValidSound(sound) then return false end end
 for _,key in ipairs({'overview','cotank'}) do
  if type(config[key])~='table' or #config[key]>MAX_SPELLS then return false end
  for _,id in ipairs(config[key]) do if not ValidSpell(id) then return false end end
 end
 return true
end

-- Edits (out of combat).
function U.AddSpell(bossID,name,list,spellID)
 if Busy() then return false,'Edit auras after combat.' end
 if list~='overview' and list~='cotank' then return false,'Unknown list.' end
 spellID=tonumber(spellID);if not ValidSpell(spellID) then return false,'Enter a spell ID.' end
 local config=U.Boss(bossID,true,name)
 for _,id in ipairs(config[list]) do if id==spellID then return false,'Already in the list.' end end
 if #config[list]>=MAX_SPELLS then return false,'The list is full.' end
 config[list][#config[list]+1]=spellID;Touched(config)
 return true,'Added.'
end
function U.RemoveSpell(bossID,list,index)
 if Busy() then return false,'Edit auras after combat.' end
 local config=U.Boss(bossID);if not config or not config[list] or not config[list][index] then return false,'Nothing to remove.' end
 table.remove(config[list],index);Touched(config);return true,'Removed.'
end
function U.AddSound(bossID,name,sound)
 if Busy() then return false,'Edit auras after combat.' end
 if not U.ValidSound(sound) then return false,'Choose a spell ID, who, when and a sound.' end
 local config=U.Boss(bossID,true,name)
 if #config.sounds>=MAX_SOUNDS then return false,'The sound list is full.' end
 config.sounds[#config.sounds+1]=Copy(sound);Touched(config)
 return true,'Sound added.'
end
function U.RemoveSound(bossID,index)
 if Busy() then return false,'Edit auras after combat.' end
 local config=U.Boss(bossID);if not config or not config.sounds[index] then return false,'Nothing to remove.' end
 table.remove(config.sounds,index);Touched(config);return true,'Sound removed.'
end
-- Replace a boss config from sync, keeping the sender's version.
function U.Replace(bossID,config,updated)
 if Busy() then return false,'after combat' end
 if type(bossID)~='number' or bossID<0 or not U.ValidConfig(config) then return false,'invalid aura config' end
 local copy=Copy(config);copy.updated=updated
 U.Store().bosses[bossID]=copy;U.dirty=true
 if addon.RefreshAurasPage then addon.RefreshAurasPage() end
 return true
end

-- Spell lists in effect: every boss's list plus the defaults (empty = all).
function U.SpellSet(list)
 local set,any={},false
 for _,config in pairs(U.Store().bosses) do
  for _,id in ipairs(config[list] or {}) do set[id]=true;any=true end
 end
 return any and set or nil
end

-- Co-tank units: the other tanks in the group (all tanks if you are not one).
function U.CoTankUnits()
 local list={}
 if not IsInGroup() then return list end
 local units={}
 if IsInRaid() then for index=1,GetNumGroupMembers() do units[#units+1]='raid'..index end
 else for index=1,4 do units[#units+1]='party'..index end end
 for _,unit in ipairs(units) do
  if UnitExists(unit) and not UnitIsUnit(unit,'player') and UnitGroupRolesAssigned(unit)=='TANK' then list[#list+1]=unit end
 end
 return list
end
function U.GroupUnits()
 local list={}
 if IsInRaid() then for index=1,GetNumGroupMembers() do list[#list+1]='raid'..index end
 else list[1]='player';if IsInGroup() then for index=1,4 do if UnitExists('party'..index) then list[#list+1]='party'..index end end end end
 return list
end

-- Sounds: (re)register every configured sound out of combat.
local registered={}
local function Trigger(when)
 -- Enum.UnitAuraSoundTrigger in 12.1 (a bare global is kept as a fallback).
 local enum=(Enum and Enum.UnitAuraSoundTrigger) or UnitAuraSoundTrigger
 if not enum then return nil end
 return when=='stack' and enum.ApplicationsIncreased or when=='removed' and enum.Removed or enum.Added
end
local function SoundPath(file)
 local A=addon.Assignments
 if A and A.SoundCandidates then return A.SoundCandidates(file)[1] end
 return file
end
-- Personal choices (never synced): play aura sounds at all, and sounds this
-- player has switched off. Keyed by boss, spell, who and when, so a synced
-- setup keeps the choice.
function U.SoundKey(bossID,sound) return bossID..':'..sound.spell..':'..sound.unit..':'..sound.when end
function U.Personal()
 local store=U.Store()
 if type(store.personal)~='table' then store.personal={} end
 if type(store.personal.muted)~='table' then store.personal.muted={} end
 if store.personal.sounds==nil then store.personal.sounds=true end
 return store.personal
end
function U.SoundEnabled(bossID,sound) local personal=U.Personal();return personal.sounds~=false and not personal.muted[U.SoundKey(bossID,sound)] end
function U.SetSoundEnabled(bossID,sound,on)
 U.Personal().muted[U.SoundKey(bossID,sound)]=(not on) or nil;U.dirty=true
end
function U.SetSoundsEnabled(on) U.Personal().sounds=on and true or false;U.dirty=true end
function U.RegisterSounds()
 local api=C_UnitAuras
 if not (api and api.AddAuraSound and api.RemoveAuraSound) or Busy() then return false end
 for _,id in ipairs(registered) do pcall(api.RemoveAuraSound,id) end
 registered={}
 if addon.ModuleEnabled and not addon.ModuleEnabled('auras') then U.dirty=false;return true,0 end
 for bossID,config in pairs(U.Store().bosses) do
  for _,sound in ipairs(config.sounds or {}) do
   local targets=not U.SoundEnabled(bossID,sound) and {} or sound.unit=='player' and {'player'} or sound.unit=='cotank' and U.CoTankUnits() or U.GroupUnits()
   local path=SoundPath(sound.sound);local trigger=Trigger(sound.when)
   if path and trigger then
    for _,unit in ipairs(targets) do
     local ok,id=pcall(api.AddAuraSound,trigger,{unitToken=unit,spellID=sound.spell,soundFileName=path,outputChannel='Master'},1)
     if ok and id then registered[#registered+1]=id end
    end
   end
  end
 end
 U.dirty=false
 return true,#registered
end
function U.RegisteredCount() return #registered end

local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','GROUP_ROSTER_UPDATE','PLAYER_ROLES_ASSIGNED','PLAYER_REGEN_ENABLED','ENCOUNTER_END','PLAYER_ENTERING_WORLD','PLAYER_SPECIALIZATION_CHANGED'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event)
 if event=='PLAYER_LOGIN' and U.SeedDefaults then U.SeedDefaults() end
 if event=='GROUP_ROSTER_UPDATE' or event=='PLAYER_ROLES_ASSIGNED' or event=='PLAYER_LOGIN' or event=='PLAYER_ENTERING_WORLD' then U.dirty=true end
 if U.dirty and not Busy() then U.RegisterSounds() end
 if addon.AuraDisplays and addon.AuraDisplays.Refresh then addon.AuraDisplays.Refresh() end
end)
local elapsed=0
frame:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt;if elapsed<2 then return end;elapsed=0
 if U.dirty and not Busy() then U.RegisterSounds();if addon.AuraDisplays then addon.AuraDisplays.Refresh() end end
end)
