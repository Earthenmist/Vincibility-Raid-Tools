local _,addon=...
-- In-fight assignment reminders. At ENCOUNTER_START the player's own
-- assignments for that boss (name, role, raid group or everyone) get an
-- expected cast time from the preloaded timeline; when the boss mod (DBM, or
-- BigWigs if DBM is not loaded) starts the Nth bar for the linked ability the
-- time follows that bar instead. With only Blizzard's boss warnings the times
-- stay on the timeline: Blizzard keeps its timeline spells secret from addons. Each assignment shows
-- per its own "show as" choices: a countdown bar and icon from 10 s before, a
-- text alert and/or sound 3 s before. Uses the reminder display areas; nothing
-- is added to the reminder library.
local A=addon.Assignments
local Run={items={},dbmCounts={},running=false};A.Runtime=Run
Run.barLead,Run.alertLead=10,3
A.defaultShow={bar=true,text=true,icon=false,sound=false}

local function Public(value) return not issecretvalue or not issecretvalue(value) end
function A.ShowFlags(entry)
 local show=type(entry.show)=='table' and entry.show or A.defaultShow
 return {bar=show.bar==true,text=show.text==true,icon=show.icon==true,sound=show.sound==true}
end
local function SpellInfo(id) return id and A.SpellInfo and A.SpellInfo(id) end
-- What to call it: spell name (and note) or the action text.
function A.AssignmentLabel(entry)
 if entry.spellID then
  local info=SpellInfo(entry.spellID)
  local name=info and info.name or ('Spell '..entry.spellID)
  return (entry.text and entry.text~='') and (name..' - '..entry.text) or name
 end
 return entry.text or ''
end
local function Ability(timeline,anchor)
 for _,ability in ipairs(timeline and timeline.abilities or {}) do if ability.name==anchor.ability then return ability end end
end
-- Every assignment for a boss with an expected time from pull; mine=true for
-- the player's own (only those raise personal reminders; the leader overview
-- lists all of them).
function Run.Build(encounterID,difficulty)
 local plan=A.Plan(encounterID)
 local timeline=A.Timeline(encounterID,difficulty)
 local items={}
 for _,entry in ipairs(plan and plan.entries or {}) do
  do
   local ability=entry.anchor and Ability(timeline,entry.anchor)
   local expected=ability and ability.times[entry.anchor.cast] or entry.time
   local abilityInfo=ability and SpellInfo(ability.spellID)
   local spellInfo=SpellInfo(entry.spellID)
   items[#items+1]={entry=entry,mine=A.IsMine(entry),expected=expected,show=A.ShowFlags(entry),label=A.AssignmentLabel(entry),
    ability=entry.anchor and entry.anchor.ability,cast=entry.anchor and entry.anchor.cast,
    abilitySpell=ability and ability.spellID,icon=(spellInfo and spellInfo.iconID) or (abilityInfo and abilityInfo.iconID)}
  end
 end
 table.sort(items,function(a,b) return a.expected<b.expected end)
 return items
end
local function Display(data)
 if addon.ReminderDisplay and addon.ReminderDisplay.Show then addon.ReminderDisplay.Show(data,{}) end
end
-- The assignment's chosen sound, or the raid warning; then speech if enabled.
local function Speak(text,soundFile)
 local db=VincibilityRaidToolsDB or {}
 A.PlayAssignmentSound(soundFile)
 if db.reminderTTS and C_VoiceChat and C_VoiceChat.SpeakText then
  local voice=db.reminderVoice
  if not voice and C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then voice=C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard) end
  if type(voice)=='number' then pcall(C_VoiceChat.SpeakText,voice,text,0,100,false) end
 end
end
function Run.Start(encounterID,difficulty)
 if addon.ModuleEnabled and not addon.ModuleEnabled('assignments') then Run.items={};Run.running=false;return end
 -- A real pull replaces a running test: drop its bar without reopening the window.
 if Run.test and A.Overview and A.Overview.HideTestBar then A.Overview.HideTestBar(false) end
 Run.items=Run.Build(encounterID,difficulty)
 Run.dbmCounts={};Run.started=GetTime();Run.running=#Run.items>0;Run.encounter=encounterID;Run.test=false
end
function Run.Stop()
 local wasTest=Run.test
 Run.running=false;Run.test=false;Run.items={};Run.dbmCounts={}
 if wasTest then
  if A.Overview and A.Overview.HideTestBar then A.Overview.HideTestBar(true) end
  if addon.RefreshAssignmentsPage then addon.RefreshAssignmentsPage() end
 end
end
-- Test pull: run a boss plan on its timeline without an encounter, so
-- reminders and the leader view can be checked. Not in combat or during a
-- real fight; ends a few seconds after the last assignment.
function Run.StartTest(encounterID,difficulty)
 if InCombatLockdown() then return false,'Test pulls are not available in combat.' end
 if Run.running and not Run.test then return false,'A boss fight is in progress.' end
 -- Reminder previews swallow real displays; end one first.
 local display=addon.ReminderDisplay
 if display and display.preview and display.StopPreview then display.StopPreview(false) end
 Run.Start(encounterID,difficulty)
 if not Run.running then return false,'This boss has no assignments to test.' end
 Run.test=true
 local last=0;for _,item in ipairs(Run.items) do last=math.max(last,item.expected) end
 Run.testEnd=last+5
 if A.Overview and A.Overview.OnStart then A.Overview.OnStart() end
 if A.Overview and A.Overview.ShowTestBar then A.Overview.ShowTestBar() end
 local mine=#Run.Mine()
 return true,string.format('Test pull running: %d assignment%s, %d yours. Click Stop test to end it.',#Run.items,#Run.items==1 and '' or 's',mine)
end
-- Show whatever is due; bars re-show (same uid) when DBM moves the time.
function Run.Tick()
 if not Run.running then return end
 local now=GetTime()-Run.started
 if Run.test and now>Run.testEnd then Run.Stop();return end
 for _,item in ipairs(Run.items) do
  local left=item.expected-now
  local id=item.entry.id
  if item.mine then
  local suffix=item.ability and (' > '..item.ability..(item.cast and (' ('..item.cast..')') or '')) or ''
  if left>-1 then
   if left<=Run.barLead and (item.barShownFor~=item.expected) then
    item.barShownFor=item.expected
    local duration=math.max(.5,left)
    -- Countdowns leave at zero; the text alert marks the moment itself.
    if item.show.bar then Display({uid='VRT-assign-bar-'..id,message=item.label..suffix,duration=duration,display='Bars',icon=item.icon,countdown=true,sticky=0}) end
    if item.show.icon then Display({uid='VRT-assign-icon-'..id,message=item.label,duration=duration,display='Icons',icon=item.icon,countdown=true,sticky=0}) end
   end
   if left<=Run.alertLead and not item.alerted then
    item.alerted=true
    if item.show.text then Display({uid='VRT-assign-text-'..id,message=item.label,duration=math.max(1,Run.alertLead),display='Texts',icon=item.icon}) end
    if item.show.sound then Speak(item.label,item.entry.soundFile) end
   end
  end
  end
 end
end
function Run.Mine()
 local list={}
 for _,item in ipairs(Run.items) do if item.mine then list[#list+1]=item end end
 return list
end
-- DBM bar for the Nth cast of a linked ability: follow its countdown.
function Run.OnTimer(text,duration,spellID)
 if not Run.running or type(duration)~='number' then return end
 local matched={}
 for _,item in ipairs(Run.items) do
  if item.ability and not matched[item.ability] then
   local bySpell=spellID and item.abilitySpell==spellID
   local byName=type(text)=='string' and text:lower():find(item.ability:lower(),1,true)
   if bySpell or byName then matched[item.ability]=true end
  end
 end
 for ability in pairs(matched) do
  Run.dbmCounts[ability]=(Run.dbmCounts[ability] or 0)+1
  local count=Run.dbmCounts[ability]
  for _,item in ipairs(Run.items) do
   if item.ability==ability and item.cast==count and not item.alerted then item.expected=(GetTime()-Run.started)+duration;item.followsDBM=true end
  end
 end
end
local function DBMTimer(_,id,text,duration,_,_,spellID)
 for _,value in ipairs({id,text,duration,spellID}) do if not Public(value) then return end end
 Run.OnTimer(text,tonumber(duration),tonumber(spellID))
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','ENCOUNTER_START','ENCOUNTER_END'}) do frame:RegisterEvent(event) end
-- BigWigs_StartBar(module, key, text, seconds, icon, ...): key is the spell ID
-- in BigWigs boss modules. Ignored when DBM feeds us, so bars count once.
local function BigWigsBar(_,_,key,text,duration)
 if Run.dbmHooked then return end
 for _,value in ipairs({key,text,duration}) do if not Public(value) then return end end
 Run.OnTimer(type(text)=='string' and text or nil,tonumber(duration),type(key)=='number' and key or nil)
end
-- Which boss mod drives bar following: 'DBM', 'BigWigs' or nil (timeline only).
function Run.Source() return Run.dbmHooked and 'DBM' or Run.bigWigsHooked and 'BigWigs' or nil end
function Run.HookBossMods()
 if DBM and type(DBM.RegisterCallback)=='function' and not Run.dbmHooked then
  DBM:RegisterCallback('DBM_TimerBegin',DBMTimer);Run.dbmHooked=true
 end
 if not Run.dbmHooked and BigWigsLoader and type(BigWigsLoader.RegisterMessage)=='function' and not Run.bigWigsHooked then
  BigWigsLoader.RegisterMessage(Run,'BigWigs_StartBar',BigWigsBar);Run.bigWigsHooked=true
 end
end
frame:SetScript('OnEvent',function(_,event,...)
 if event=='ENCOUNTER_START' then local id,_,difficulty=...;Run.Start(id,difficulty)
 elseif event=='ENCOUNTER_END' then Run.Stop()
 elseif event=='PLAYER_LOGIN' then Run.HookBossMods()
 end
end)
local elapsed=0
frame:SetScript('OnUpdate',function(_,delta) elapsed=elapsed+delta;if elapsed>=.1 then elapsed=0;Run.Tick() end end)
