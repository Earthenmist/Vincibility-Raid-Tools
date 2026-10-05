local _,addon=...
-- Boss assignment plans: who uses which spell at what time (optionally in a
-- phase). Plans are keyed by encounter ID. Import accepts MRT note lines
-- ({time:1:30,p2} Name {spell:31821}) and NSRT reminder lines
-- (time:90;tag:Name healer;spellid:31821;text:...;ph:2). Export writes MRT
-- note lines. Linking plans to reminders is a later step.
local A={};addon.Assignments=A
local MAX_ENTRIES,MAX_TIME=300,3600
A.roles={tanks='TANK',tank='TANK',healers='HEALER',healer='HEALER',dps='DAMAGER',damage='DAMAGER',melee='MELEE',ranged='RANGED',everyone='ALL',all='ALL'}
A.roleLabels={TANK='Tanks',HEALER='Healers',DAMAGER='DPS',MELEE='Melee DPS',RANGED='Ranged DPS',ALL='Everyone'}
-- Role words written on export; ParseWho reads them back.
A.roleWords={TANK='tanks',HEALER='healers',DAMAGER='dps',MELEE='melee',RANGED='ranged',ALL='everyone'}
-- Raid groups: stored as G1..G8, shown as "Group 1", written as "group1".
for group=1,8 do
 A.roles['group'..group]='G'..group;A.roles['g'..group]='G'..group
 A.roleLabels['G'..group]='Group '..group;A.roleWords['G'..group]='group'..group
end
function A.PlayerGroup()
 if not (IsInRaid and IsInRaid()) then return nil end
 local index=UnitInRaid and UnitInRaid('player')
 local subgroup=index and GetRaidRosterInfo and select(3,GetRaidRosterInfo(index))
 return type(subgroup)=='number' and subgroup or nil
end

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Trim(text) return (tostring(text or ''):gsub('^%s+',''):gsub('%s+$','')) end
local function Copy(value)
 if type(value)~='table' then return value end
 local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end

function A.Store()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if db.assignments==nil then db.assignments={schema=1,plans={},serial=0} end
 local store=db.assignments
 if type(store)~='table' or store.schema~=1 or type(store.plans)~='table' then return nil,'Assignment storage needs review.' end
 if type(store.serial)~='number' then store.serial=0 end
 return store
end

-- Time: "1:30", "01:30", "90" or "90.5" -> seconds.
function A.ParseTime(text)
 text=Trim(text)
 local minutes,seconds=text:match('^(%d+):(%d+%.?%d*)$')
 local value=minutes and tonumber(minutes)*60+tonumber(seconds) or tonumber(text)
 if minutes and tonumber(seconds)>=60 then return nil end
 if value and value>=0 and value<=MAX_TIME then return value end
end
function A.FormatTime(seconds)
 seconds=math.floor((seconds or 0)+.5)
 return string.format('%d:%02d',math.floor(seconds/60),seconds%60)
end

-- Who: names and role words (tanks, healers, dps, melee, ranged, everyone),
-- comma or space separated. "Melee DPS"/"Ranged DPS" (as displayed) are one target.
function A.ParseWho(text)
 local list,seen={},{}
 -- "Group 1" (as displayed) is one target, not two words.
 text=Trim(text):gsub('[Gg][Rr][Oo][Uu][Pp]%s+(%d)','group%1')
 text=text:gsub('([Mm][Ee][Ll][Ee][Ee])%s+[Dd][Pp][Ss]','%1'):gsub('([Rr][Aa][Nn][Gg][Ee][Dd])%s+[Dd][Pp][Ss]','%1')
 for word in text:gmatch('[^,;%s]+') do
  local key=A.roles[word:lower()] or word
  if not seen[key:lower()] then seen[key:lower()]=true;list[#list+1]=key end
 end
 return list
end
function A.FormatWho(list)
 local out={}
 for _,item in ipairs(list or {}) do out[#out+1]=A.roleLabels[item] or item end
 return table.concat(out,', ')
end

function A.Validate(entry)
 if type(entry)~='table' then return false,'Invalid assignment.' end
 if type(entry.time)~='number' or entry.time<0 or entry.time>MAX_TIME then return false,'Use a time between 0:00 and 60:00.' end
 if entry.phase~=nil and (type(entry.phase)~='number' or entry.phase<1 or entry.phase>9 or entry.phase%1~=0) then return false,'Phase must be 1 to 9.' end
 if type(entry.who)~='table' or #entry.who==0 or #entry.who>40 then return false,'Choose who the assignment is for.' end
 for _,name in ipairs(entry.who) do if type(name)~='string' or name=='' or #name>60 then return false,'Invalid name.' end end
 if entry.spellID~=nil and (type(entry.spellID)~='number' or entry.spellID<1 or entry.spellID%1~=0 or entry.spellID>10000000) then return false,'Invalid spell.' end
 if entry.text~=nil and (type(entry.text)~='string' or #entry.text>200) then return false,'Note is limited to 200 characters.' end
 if not entry.spellID and (not entry.text or entry.text=='') then return false,'Add a spell or a note.' end
 -- Optional sound file for the Sound display (a bundled or game sound path).
 if entry.soundFile~=nil then
  local file=entry.soundFile
  if type(file)=='string' and file:match('^DBM:%l+$') then
   if #file>40 then return false,'Invalid sound.' end
  else
   if type(file)~='string' or #file>512 or not (file:lower():match('^interface[\\/]') or file:lower():match('^sound[\\/]')) or not file:lower():match('%.ogg$') then return false,'Invalid sound.' end
   local R=addon.Reminders
   if R and R.SoundSource then local audio=R.SoundSource(file);if not audio or audio.soundFile~=file then return false,'Invalid sound.' end end
  end
 end
 if entry.show~=nil then
  if type(entry.show)~='table' then return false,'Invalid display choice.' end
  for key,value in pairs(entry.show) do
   if (key~='bar' and key~='text' and key~='icon' and key~='sound') or type(value)~='boolean' then return false,'Invalid display choice.' end
  end
 end
 local anchor=entry.anchor
 if anchor~=nil and (type(anchor)~='table' or type(anchor.ability)~='string' or anchor.ability=='' or #anchor.ability>80
  or type(anchor.cast)~='number' or anchor.cast<1 or anchor.cast>99 or anchor.cast%1~=0) then return false,'Invalid boss ability link.' end
 return true
end

-- Preloaded boss timelines (Assignments/Timelines.lua, generated from Warcraft Logs).
function A.TimelineDifficulties(bossID)
 local boss=addon.AssignmentTimelines and addon.AssignmentTimelines[bossID]
 local list={}
 for difficulty in pairs(boss or {}) do if type(difficulty)=='number' then list[#list+1]=difficulty end end
 table.sort(list);return list
end
function A.Timeline(bossID,difficulty)
 local boss=addon.AssignmentTimelines and addon.AssignmentTimelines[bossID]
 return boss and boss[difficulty]
end
A.difficultyNames={[14]='Normal',[15]='Heroic',[16]='Mythic'}
-- Casts in time order with phase headers: {kind='phase',name,time} or
-- {kind='cast',ability,spellID,cast,time}.
function A.TimelineRows(bossID,difficulty)
 local timeline=A.Timeline(bossID,difficulty)
 if not timeline then return {} end
 local casts={}
 for _,ability in ipairs(timeline.abilities) do
  for index,time in ipairs(ability.times) do casts[#casts+1]={kind='cast',ability=ability.name,spellID=ability.spellID,cast=index,total=#ability.times,time=time} end
 end
 table.sort(casts,function(a,b) if a.time~=b.time then return a.time<b.time end;return a.ability<b.ability end)
 local rows,phase={},1
 local phases=timeline.phases or {}
 for _,cast in ipairs(casts) do
  while phases[phase] and phases[phase].start<=cast.time do
   rows[#rows+1]={kind='phase',name=phases[phase].name,time=phases[phase].start,intermission=phases[phase].intermission}
   phase=phase+1
  end
  rows[#rows+1]=cast
 end
 while phases[phase] do rows[#rows+1]={kind='phase',name=phases[phase].name,time=phases[phase].start};phase=phase+1 end
 return rows
end
function A.EntriesForCast(bossID,ability,cast)
 local plan=A.Plan(bossID);local list={}
 for _,entry in ipairs(plan and plan.entries or {}) do
  if entry.anchor and entry.anchor.ability==ability and entry.anchor.cast==cast then list[#list+1]=entry end
 end
 return list
end

function A.Plan(bossID,create,name)
 local store,err=A.Store();if not store then return nil,err end
 if type(bossID)~='number' then return nil,'Choose a boss first.' end
 local plan=store.plans[bossID]
 if not plan and create then plan={bossID=bossID,name=name,entries={}};store.plans[bossID]=plan end
 if plan and name and name~='' then plan.name=name end
 return plan
end
-- A local edit to a boss plan: new version time, and tell sync.
local function Now() return addon.Now and addon.Now() or (time and time() or 0) end
local function Touched(plan)
 plan.updated=math.max(Now(),(plan.updated or 0)+1)
 if addon.SyncChanged then addon.SyncChanged('plans') end
end
local function Sort(plan)
 table.sort(plan.entries,function(a,b)
  if (a.phase or 0)~=(b.phase or 0) then return (a.phase or 0)<(b.phase or 0) end
  if a.time~=b.time then return a.time<b.time end
  return tostring(a.id)<tostring(b.id)
 end)
end
-- Add (id nil) or update an assignment.
function A.Save(bossID,bossName,entry,id)
 if InCombatLockdown() then return false,'Edit assignments after combat.' end
 local ok,err=A.Validate(entry);if not ok then return false,err end
 local plan;plan,err=A.Plan(bossID,true,bossName);if not plan then return false,err end
 local store=A.Store()
 local copy=Copy(entry)
 if id then
  for index,existing in ipairs(plan.entries) do if existing.id==id then copy.id=id;plan.entries[index]=copy;Sort(plan);Touched(plan);return true,'Assignment updated.',id end end
  return false,'That assignment no longer exists.'
 end
 if #plan.entries>=MAX_ENTRIES then return false,'A plan holds at most '..MAX_ENTRIES..' assignments.' end
 store.serial=store.serial+1;copy.id='VRT-assign-'..store.serial
 plan.entries[#plan.entries+1]=copy;Sort(plan);Touched(plan)
 return true,'Assignment added.',copy.id
end
-- Replace a whole boss plan (from a share). Every entry must validate; ids
-- are reassigned locally so they never collide with this client's own.
-- updated: the sender's version time (sync and shares keep it, so clients
-- converge); nil means a local replace (a new version).
function A.ReplacePlan(bossID,bossName,entries,updated)
 if InCombatLockdown() then return false,'Update plans after combat.' end
 if type(bossID)~='number' or type(entries)~='table' or #entries>MAX_ENTRIES then return false,'Invalid plan.' end
 local copies={}
 for _,entry in ipairs(entries) do
  local copy=Copy(entry);copy.id=nil
  local ok,err=A.Validate(copy);if not ok then return false,err end
  copies[#copies+1]=copy
 end
 local plan,err=A.Plan(bossID,true,bossName);if not plan then return false,err end
 local store=A.Store()
 for _,copy in ipairs(copies) do store.serial=store.serial+1;copy.id='VRT-assign-'..store.serial end
 plan.entries=copies;Sort(plan)
 if type(updated)=='number' then plan.updated=updated else Touched(plan) end
 return true,string.format('Plan for %s updated (%d assignment%s).',bossName or 'boss',#copies,#copies==1 and '' or 's')
end
function A.Delete(bossID,id)
 if InCombatLockdown() then return false,'Edit assignments after combat.' end
 local plan=A.Plan(bossID);if not plan then return false,'No plan for this boss.' end
 for index,entry in ipairs(plan.entries) do if entry.id==id then table.remove(plan.entries,index);Touched(plan);return true,'Assignment removed.' end end
 return false,'That assignment no longer exists.'
end
function A.Clear(bossID)
 if InCombatLockdown() then return false,'Edit assignments after combat.' end
 local plan=A.Plan(bossID);if not plan then return true,'Nothing to clear.' end
 plan.entries={};Touched(plan);return true,'Plan cleared.'
end

-- Is this assignment for the current player?
-- Melee or ranged damage specs (by specialization ID); tanks and healers are neither.
A.meleeSpecs={[251]=true,[252]=true,[577]=true,[103]=true,[255]=true,[269]=true,[70]=true,[259]=true,[260]=true,[261]=true,[263]=true,[71]=true,[72]=true}
A.rangedSpecs={[102]=true,[253]=true,[254]=true,[62]=true,[63]=true,[64]=true,[258]=true,[262]=true,[265]=true,[266]=true,[267]=true,[1467]=true,[1473]=true,[1480]=true}
function A.PlayerRange()
 local index=GetSpecialization and GetSpecialization()
 local specID=index and GetSpecializationInfo and GetSpecializationInfo(index)
 if A.meleeSpecs[specID] then return 'MELEE' elseif A.rangedSpecs[specID] then return 'RANGED' end
end
function A.IsMine(entry)
 local full=GetUnitName and GetUnitName('player',true)
 local name=UnitName and UnitName('player')
 local role=addon.Reminders and addon.Reminders.PlayerRole and addon.Reminders.PlayerRole()
 for _,who in ipairs(entry.who or {}) do
  if who=='ALL' or (role and who==role) then return true end
  if (who=='MELEE' or who=='RANGED') and role~='TANK' and role~='HEALER' and who==A.PlayerRange() then return true end
  local group=who:match('^G(%d)$')
  if group then
   if tonumber(group)==A.PlayerGroup() then return true end
  else
  local lower=who:lower()
  if (name and lower==name:lower()) or (full and lower==full:lower()) then return true end
  end
 end
 return false
end

-- Import.
local function StripColours(text) return (text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
local function ParseNSRT(line)
 local time=tonumber(line:match('time:(%d*%.?%d+)'))
 if not time then return end
 local who=A.ParseWho(line:match('tag:([^;]+)') or 'everyone')
 if #who==0 then who={'ALL'} end
 return {{time=time,phase=tonumber(line:match('ph:(%d+)')),who=who,spellID=tonumber(line:match('spellid:(%d+)')),text=line:match('text:([^;]+)') and Trim(line:match('text:([^;]+)')) or nil}}
end
local function ParseMRT(line)
 local spec,rest=line:match('^%s*{time:([^}]+)}(.*)$')
 if not spec then return end
 local clock,options=spec:match('^([^,]+),?(.*)$')
 local time=A.ParseTime(clock or '')
 if not time then return end
 local phase=tonumber((options or ''):match('p(%d+)'))
 rest=StripColours(rest)
 local entries,names={},{}
 local position=1
 local any=false
 while true do
  local s,e,id=rest:find('{spell:(%d+)}',position)
  local segment=rest:sub(position,(s or 0)-1)
  if not s then segment=rest:sub(position) end
  -- Names before a spell token; raid-marker and other tokens are ignored.
  local words={}
  for word in segment:gsub('{[^}]*}',' '):gmatch('[^,;%s]+') do words[#words+1]=word end
  if s then
   if #words>0 then names=words end
   local who=A.ParseWho(table.concat(names,' '))
   if #who==0 then who={'ALL'} end
   entries[#entries+1]={time=time,phase=phase,who=who,spellID=tonumber(id)}
   any=true
   position=e+1
  else
   if not any then
    local text=Trim(segment:gsub('{[^}]*}',''))
    if text~='' then entries[#entries+1]={time=time,phase=phase,who={'ALL'},text=text} end
   end
   break
  end
 end
 return entries
end
-- Parse pasted text into assignments; returns entries and skipped line count.
function A.ParseText(text)
 local entries,skipped={},0
 -- WoW edit boxes escape a pasted "|" as "||" (colour codes in website exports).
 text=tostring(text or ''):gsub('||','|')
 for line in (tostring(text or '')..'\n'):gmatch('([^\r\n]*)\r?\n') do
  if Trim(line)~='' then
   local parsed=line:find('{time:',1,true) and ParseMRT(line) or (line:find('time:',1,true) and ParseNSRT(line)) or nil
   local added=false
   for _,entry in ipairs(parsed or {}) do if A.Validate(entry) then entries[#entries+1]=entry;added=true end end
   if not added then skipped=skipped+1 end
  end
 end
 return entries,skipped
end
-- Import into a boss plan; replace clears it first. Atomic: nothing changes on failure.
function A.Import(bossID,bossName,text,replace)
 if InCombatLockdown() then return false,'Import after combat.' end
 local entries,skipped=A.ParseText(text)
 if #entries==0 then return false,'No assignments found ('..skipped..' line'..(skipped==1 and '' or 's')..' skipped).' end
 local plan,err=A.Plan(bossID,true,bossName);if not plan then return false,err end
 local existing=replace and 0 or #plan.entries
 if existing+#entries>MAX_ENTRIES then return false,'A plan holds at most '..MAX_ENTRIES..' assignments.' end
 local store=A.Store()
 if replace then plan.entries={} end
 for _,entry in ipairs(entries) do store.serial=store.serial+1;entry.id='VRT-assign-'..store.serial;plan.entries[#plan.entries+1]=entry end
 Touched(plan)
 Sort(plan)
 return true,string.format('Imported %d assignment%s%s.',#entries,#entries==1 and '' or 's',skipped>0 and (', skipped '..skipped..' line'..(skipped==1 and '' or 's')) or '')
end
-- Export as MRT note lines (the most widely accepted format).
function A.Export(bossID)
 local plan=A.Plan(bossID)
 if not plan or #plan.entries==0 then return '' end
 local lines={}
 for _,entry in ipairs(plan.entries) do
  local who={}
  for _,item in ipairs(entry.who) do who[#who+1]=A.roleWords[item] or item end
  -- A note for everyone needs no names: MRT lines without a spell import as everyone.
  if not entry.spellID and #entry.who==1 and entry.who[1]=='ALL' then who={} end
  local line='{time:'..A.FormatTime(entry.time)..(entry.phase and (',p'..entry.phase) or '')..'}'..(#who>0 and (' '..table.concat(who,' ')) or '')
  if entry.spellID then line=line..' {spell:'..entry.spellID..'}' end
  if entry.text and entry.text~='' then line=line..' '..entry.text end
  lines[#lines+1]=line
 end
 return table.concat(lines,'\n')
end
-- Assignment sounds. soundFile is a bundled/game path, or "DBM:<line>" for a
-- DBM voice-pack line. Every DBM voice pack uses the same file names, so the
-- line plays in each player's chosen pack (VEM ships with DBM). No DBM audio is
-- copied into VRT; if no pack has the line, the raid warning plays.
A.DBMVoices={
 {'helpsoak','Help soak'},{'soakincoming','Soak incoming'},{'gathershare','Stack (gather and share)'},
 {'scatter','Spread out'},{'runout','Run out'},{'watchstep','Watch your step'},{'keepmove','Keep moving'},
 {'stopmove','Stop moving'},{'kickcast','Interrupt (kick cast)'},{'interruptsoon','Interrupt soon'},
 {'defensive','Use defensive'},{'tauntboss','Taunt boss'},{'changemt','Tank swap'},{'dispelnow','Dispel now'},
 {'healall','Heal all'},{'aesoon','AoE soon'},{'targetchange','Switch target'},{'safenow','Safe now'},
 -- Personal debuff call-outs (used by the aura sound defaults).
 {'targetyou','Targeted (on you)'},{'fixateyou','Fixate on you'},{'debuffyou','Debuff on you'},{'bombyou','Bomb on you'},
 {'absorbyou','Heal absorb on you'},{'poolyou','Pool on you'},{'runeyou','Rune on you'},{'frostyou','Frost on you'},
 {'lightyou','Light on you'},{'voidyou','Void on you'},{'redyou','Red on you'},{'blueyou','Blue on you'},
 {'left','Left'},{'right','Right'},{'north','North'},{'south','South'},{'east','East'},{'west','West'},
 {'breakchain','Break the chain'},{'carefly','Careful (fall)'},{'movetopillar','Move to pillar'},{'movetoboss','Move to boss'},
 {'gatheritem','Collect'},
}
local dbmVoiceNames={};for _,voice in ipairs(A.DBMVoices) do dbmVoiceNames[voice[1]]=voice[2] end
function A.DBMVoiceLine(file) return type(file)=='string' and file:match('^DBM:(%l+)$') end
function A.SoundName(file)
 if not file then return 'Raid warning' end
 local line=A.DBMVoiceLine(file)
 if line then return 'DBM voice: '..(dbmVoiceNames[line] or line) end
 local name=file:match('[Ss]ounds[\\/](.+)%.ogg$') or file:match('([^\\/]+)$') or file
 return (name:gsub('[\\/]',' / '))
end
-- VRT's own recording of a DBM voice line, used when no DBM voice pack is
-- installed (relative to Media/Sounds/VRT).
A.VoiceFallback={
 targetyou='Callouts/Targeted',fixateyou='Callouts/Fixated',debuffyou='Callouts/Debuff on you',bombyou='Callouts/Bomb on you',
 poolyou='Callouts/Drop pool',scatter='Callouts/Spread',helpsoak='Callouts/Soak',soakincoming='Callouts/Soak',
 gathershare='Callouts/Stack',runout='Callouts/Run out',watchstep='Callouts/Watch your step',keepmove='Callouts/Keep moving',
 kickcast='Callouts/Interrupt',interruptsoon='Callouts/Interrupt',defensive='Callouts/Defensive',tauntboss='Callouts/Taunt',
 changemt='Callouts/Tank swap',dispelnow='Callouts/Dispel',healall='Callouts/Heal all',aesoon='Callouts/AoE soon',
 targetchange='Callouts/Switch target',safenow='Callouts/Safe now',breakchain='Callouts/Break the chain',movetopillar='Callouts/Move to pillar',
 absorbyou='Callouts/Heal absorb on you',runeyou='Callouts/Rune on you',frostyou='Callouts/Frost on you',lightyou='Callouts/Light on you',
 voidyou='Callouts/Void on you',redyou='Callouts/Red on you',blueyou='Callouts/Blue on you',carefly='Callouts/Careful fall',
 movetoboss='Callouts/Move to boss',gatheritem='Callouts/Collect',
 left='Directions/Left',right='Directions/Right',north='Directions/North',south='Directions/South',east='Directions/East',west='Directions/West',
}
-- A DBM voice pack is installed (loaded, or present and enabled).
local function HasVoicePack(name)
 local api=C_AddOns
 if not api then return false end
 if api.IsAddOnLoaded and api.IsAddOnLoaded(name) then return true end
 if api.GetAddOnInfo then local ok,_,_,_,loadable=pcall(api.GetAddOnInfo,name);return ok and loadable==true end
 return false
end
-- Files to try, in order, for a sound choice. DBM voice lines play from the
-- player's DBM voice pack when one is installed, otherwise from VRT's own
-- recording of the line; the first entry is what aura sounds register.
function A.SoundCandidates(file)
 local line=A.DBMVoiceLine(file)
 if line then
  local list,packs={},{}
  local chosen=DBM and DBM.Options and DBM.Options.ChosenVoicePack2
  if type(chosen)=='string' and chosen:match('^%w+$') and chosen~='None' then packs[#packs+1]='DBM-VP'..chosen end
  if chosen~='VEM' then packs[#packs+1]='DBM-VPVEM' end
  local installed=false
  for _,pack in ipairs(packs) do if HasVoicePack(pack) then installed=true end end
  local own=A.VoiceFallback[line] and ('Interface\\AddOns\\VincRaidTools\\Media\\Sounds\\VRT\\'..A.VoiceFallback[line]:gsub('/','\\')..'.ogg')
  if own and not installed then list[#list+1]=own end
  for _,pack in ipairs(packs) do list[#list+1]='Interface\\AddOns\\'..pack..'\\'..line..'.ogg' end
  if own and installed then list[#list+1]=own end
  return list
 end
 local R=addon.Reminders
 return {R and R.ResolveSoundFile and R.ResolveSoundFile(file) or file}
end
-- Play an assignment sound; the raid warning if nothing else can play.
function A.PlayAssignmentSound(file)
 if file and PlaySoundFile then
  for _,path in ipairs(A.SoundCandidates(file)) do
   local ok,played=pcall(PlaySoundFile,path,'Master')
   if ok and played~=false then return true end
  end
 end
 if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,'Master') end
 return false
end
function A.SpellInfo(input)
 if not (C_Spell and C_Spell.GetSpellInfo) then return end
 local value=tonumber(input) or Trim(input)
 if value=='' then return end
 local ok,info=pcall(C_Spell.GetSpellInfo,value)
 if ok and type(info)=='table' and Public(info.spellID) and info.spellID then return info end
end
