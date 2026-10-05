local _, addon = ...
local function Now() return addon.Now and addon.Now() or (time and time() or 0) end
-- Native VRT schema/event engine.
-- forced: session-only UIDs loaded from the editor's test panel.
local R={catalogue={},active={},jobs={},clock=0,revision=0,forced={}}
local timers={}
addon.Reminders=R
local names={
 'Combat log','Boss phase (DBM/BigWigs)','Boss pull','Unit health','Unit power','Boss mod message (DBM/BigWigs)',
 'Boss mod timer (DBM/BigWigs)','Chat message','Boss frame','Unit aura','Unit absorb','Unit target',
 'Spell cooldown','Spell cast success','UI widget','Group roster','Players in range',
 'Unit cast','Note timer (player)','Enemies in range','Note timer (everyone)','Mythic+ start',
}
-- WoW raid markers are message content, separate from the optional leading icon.
local markerNames={'star','circle','diamond','triangle','moon','square','cross','skull'}
R.MarkerTokens={}
for id,name in ipairs(markerNames) do R.MarkerTokens[name]=id;R.MarkerTokens['rt'..id]=id end
R.MarkerTokens.x=7
function R.FormatMessage(message,params,spoken)
 params=params or {}
 return message:gsub('{([%w]+)}',function(key)
  local id=R.MarkerTokens[key:lower()]
  if id then
   if spoken then return markerNames[id] end
   return '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_'..id..':0|t'
  end
  return params[key]~=nil and tostring(params[key]) or '{'..key..'}'
 end)
end
local native={[2]=true,[3]=true,[6]=true,[7]=true,[16]=true,[19]=true,[21]=true,[22]=true}
for id,name in ipairs(names) do
 R.catalogue[id]={id=id,name=name,available=native[id] or false,
  reason=not native[id] and 'Provider unavailable; the definition can be saved and shared.' or nil}
end
function R.Public(value) return not issecretvalue or not issecretvalue(value) end
local function Safe(value,kind) return R.Public(value) and type(value)==kind end
local function Finite(value) return Safe(value,'number') and value==value and math.abs(value)<1e12 end
local function Copy(value)
 if type(value)~='table' then return value end
 local result={};for key,v in pairs(value) do result[key]=Copy(v) end;return result
end
R.Copy=Copy
function R.Store()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if db.reminders==nil then db.reminders={schema=1,global={},serial=0} end
 if type(db.reminders)~='table' or db.reminders.schema~=1 or type(db.reminders.global)~='table' then
  return nil,'Unsupported saved reminder schema; existing data preserved.'
 end
 -- Sync version: older reminders get an updated time once.
 for _,data in pairs(db.reminders.global) do if type(data)=='table' and type(data.updated)~='number' then data.updated=0 end end
 -- Runtime migration only: point old MRT/VRT bundled-sound paths at Media/Sounds.
 if R.ResolveSoundFile and not InCombatLockdown() and not R.encounter then
  for _,data in pairs(db.reminders.global) do
   if type(data)=='table' and type(data.soundFile)=='string' then data.soundFile=R.ResolveSoundFile(data.soundFile) end
  end
 end
 return db.reminders
end
local fields={uid='string',name='string',message='string',raid='string',boss='string',bossID='number',
 zoneID='number',difficulty='number',duration='number',display='string',icon='number',enabled='boolean',
 leaderOnly='boolean',tanks='boolean',healers='boolean',players='string',logic='string',triggers='table',sound='boolean',countdown='boolean',
 tts='boolean',soundFile='string',soundFileID='number',updated='number'}
local triggerFields={event='number',text='string',spellID='number',phase='string',counter='number',
 delay='number',active='number',remaining='number',invert='boolean',unit='string',value='number',
 subevent='string',source='string',target='string',noteTime='number',widgetID='number'}
local function CheckFields(data,allowed)
 if type(data)~='table' or getmetatable(data) then return false end
 for key,value in pairs(data) do
  if not R.Public(key) or not R.Public(value) or not allowed[key] or type(value)~=allowed[key] then return false end
  if type(value)=='number' and not Finite(value) then return false end
  if type(value)=='string' and (#value>2048 or value:find('%z')) then return false end
 end
 return true
end
-- Bundled media in Media/Sounds; source notices live beside it.
local bundledSounds={
 ['airhorn.ogg']='AirHorn.ogg',
 ['applause.ogg']='Applause.ogg',
 ['catmeow2.ogg']='CatMeow2.ogg',
 ['david/1.ogg']='David/1.ogg',
 ['david/2.ogg']='David/2.ogg',
 ['david/3.ogg']='David/3.ogg',
 ['david/4.ogg']='David/4.ogg',
 ['david/5.ogg']='David/5.ogg',
 ['jim/1.ogg']='Jim/1.ogg',
 ['jim/2.ogg']='Jim/2.ogg',
 ['jim/3.ogg']='Jim/3.ogg',
 ['jim/4.ogg']='Jim/4.ogg',
 ['jim/5.ogg']='Jim/5.ogg',
 ['kittenmeow.ogg']='KittenMeow.ogg',
 ['ringingphone.ogg']='RingingPhone.ogg',
}
-- Sounds no longer bundled (no licence for public distribution) map to VRT's
-- own versions, so saved reminders, assignments and aura sounds keep playing.
local function Replacement(relative)
 local number=relative:match('^amy/(%d+)%.ogg$')
 if number then return 'VRT/Countdown/Female/'..math.max(1,math.min(10,tonumber(number)))..'.ogg' end
 local voice;voice,number=relative:match('^heroes/[^/]+/(%a+)/(%d+)%.ogg$')
 if number then return 'VRT/Countdown/'..(voice=='male' and 'Male' or 'Female')..'/'..math.max(1,math.min(10,tonumber(number)))..'.ogg' end
 return ({['interrupt.ogg']='VRT/Callouts/Interrupt.ogg',['next.ogg']='VRT/Callouts/Next.ogg',['bam.ogg']='VRT/Alerts/Bam.ogg',
  ['swordecho.ogg']='VRT/Alerts/Sword echo.ogg',['bikehorn.ogg']='VRT/Alerts/Bike horn.ogg'})[relative]
end
R.BundledSoundPaths=bundledSounds
-- VRT's own sounds, relative to Media/Sounds. Kenney's Voiceover Pack lines
-- are CC0 (Kenney/License.txt); the VRT pack is owned by the author and free to
-- redistribute (VRT/LICENCE.txt).
R.VRTSoundPaths={'Kenney/Female/Look out.ogg','Kenney/Male/Look out.ogg',
 'VRT/Callouts/Blue on you.ogg', 'VRT/Callouts/Careful fall.ogg', 'VRT/Callouts/Collect.ogg', 'VRT/Callouts/Frost on you.ogg', 'VRT/Callouts/Heal absorb on you.ogg', 'VRT/Callouts/Light on you.ogg', 'VRT/Callouts/Move to boss.ogg', 'VRT/Callouts/Red on you.ogg', 'VRT/Callouts/Rune on you.ogg', 'VRT/Callouts/Void on you.ogg',
 'VRT/Callouts/AoE soon.ogg', 'VRT/Callouts/Bomb on you.ogg', 'VRT/Callouts/Break the chain.ogg', 'VRT/Callouts/Debuff on you.ogg',
 'VRT/Callouts/Defensive.ogg', 'VRT/Callouts/Dispel.ogg', 'VRT/Callouts/Dodge.ogg', 'VRT/Callouts/Drop pool.ogg',
 'VRT/Callouts/Fixated.ogg', 'VRT/Callouts/Heal all.ogg', 'VRT/Callouts/Interrupt.ogg', 'VRT/Callouts/Keep moving.ogg',
 'VRT/Callouts/Move to edge.ogg', 'VRT/Callouts/Move to pillar.ogg', 'VRT/Callouts/Next.ogg', 'VRT/Callouts/On you.ogg',
 'VRT/Callouts/Raid cooldown.ogg', 'VRT/Callouts/Run out.ogg', 'VRT/Callouts/Safe now.ogg', 'VRT/Callouts/Soak.ogg',
 'VRT/Callouts/Spread.ogg', 'VRT/Callouts/Stack.ogg', 'VRT/Callouts/Switch target.ogg', 'VRT/Callouts/Tank swap.ogg',
 'VRT/Callouts/Targeted.ogg', 'VRT/Callouts/Taunt.ogg', 'VRT/Callouts/Watch your step.ogg', 'VRT/Directions/East.ogg',
 'VRT/Directions/Left.ogg', 'VRT/Directions/North.ogg', 'VRT/Directions/Right.ogg', 'VRT/Directions/South.ogg',
 'VRT/Directions/West.ogg', 'VRT/Countdown/Female/1.ogg', 'VRT/Countdown/Female/2.ogg', 'VRT/Countdown/Female/3.ogg',
 'VRT/Countdown/Female/4.ogg', 'VRT/Countdown/Female/5.ogg', 'VRT/Countdown/Female/6.ogg', 'VRT/Countdown/Female/7.ogg',
 'VRT/Countdown/Female/8.ogg', 'VRT/Countdown/Female/9.ogg', 'VRT/Countdown/Female/10.ogg', 'VRT/Countdown/Male/1.ogg',
 'VRT/Countdown/Male/2.ogg', 'VRT/Countdown/Male/3.ogg', 'VRT/Countdown/Male/4.ogg', 'VRT/Countdown/Male/5.ogg',
 'VRT/Countdown/Male/6.ogg', 'VRT/Countdown/Male/7.ogg', 'VRT/Countdown/Male/8.ogg', 'VRT/Countdown/Male/9.ogg',
 'VRT/Countdown/Male/10.ogg', 'VRT/Alerts/Bam.ogg', 'VRT/Alerts/Bike horn.ogg', 'VRT/Alerts/Gong.ogg',
 'VRT/Alerts/Positive ding.ogg', 'VRT/Alerts/Soft chime.ogg', 'VRT/Alerts/Sword echo.ogg', 'VRT/Alerts/Urgent klaxon.ogg'}
-- Every selectable bundled sound (relative paths), for the sound pickers.
function R.SoundPaths()
 local list={}
 for _,relative in pairs(bundledSounds) do list[#list+1]=relative end
 for _,relative in ipairs(R.VRTSoundPaths) do list[#list+1]=relative end
 return list
end
function R.ResolveSoundFile(path)
 if type(path)~='string' or not R.Public(path) then return path end
 -- Map MRT's original paths, VRT's pre-1.28.3 Media/MRTSounds folder and sounds
 -- no longer bundled to what Media/Sounds ships now.
 local lower=path:lower():gsub('\\','/')
 local relative=lower:match('^interface/addons/mrt/media/sounds/(.+)$') or lower:match('^interface/addons/vincraidtools/media/mrtsounds/(.+)$')
  or lower:match('^interface/addons/vincraidtools/media/sounds/(.+)$')
 if not relative then return path end
 local replaced=Replacement(relative)
 if replaced then return 'Interface\\AddOns\\VincRaidTools\\Media\\Sounds\\'..replaced:gsub('/','\\') end
 local bundled=bundledSounds[relative]
 if bundled then return 'Interface\\AddOns\\VincRaidTools\\Media\\Sounds\\'..bundled:gsub('/','\\') end
 return path
end
-- Audio remains a bounded data reference, never an action/expression.
function R.SoundSource(value)
 if not R.Public(value) then return nil,'Invalid sound source.' end
 local id=tonumber(value)
 if id then
  if id>=1 and id%1==0 and id<1e12 then return {soundFileID=id} end
  return nil,'Sound file ID must be a positive integer.'
 end
 if type(value)~='string' or #value>512 or value:find('%c') then return nil,'Invalid sound file path.' end
 if value=='' then return {} end
 local lower=value:lower()
 if not (lower:match('^interface[\\/]') or lower:match('^sound[\\/]')) or
  not value:match('^[%w%s_%-%.\\/]+$') or value:find('..',1,true) or
  not (lower:match('%.ogg$') or lower:match('%.mp3$') or lower:match('%.wav$')) then
  return nil,'Use an Interface/Sound .ogg, .mp3 or .wav path, or a sound file ID.'
 end
 return {soundFile=value}
end
function R.Validate(data)
 if not CheckFields(data,fields) then return false,'Invalid reminder fields.' end
 if data.soundFile and data.soundFileID then return false,'Choose one sound source.' end
 if data.soundFile or data.soundFileID then
  local audio=R.SoundSource(data.soundFile or data.soundFileID)
  if not audio or (data.soundFile and audio.soundFile~=data.soundFile) or (data.soundFileID and audio.soundFileID~=data.soundFileID) then return false,'Invalid sound source.' end
 end
 if not data.uid or #data.uid>120 or not data.uid:match('^VRT%-%w[%w%-]*$') then return false,'Invalid VRT identity.' end
 if not data.name or #data.name==0 or #data.name>100 or not data.message or #data.message==0 then return false,'Name and message are required.' end
 if not data.duration or data.duration<1 or data.duration>300 then return false,'Duration must be 1–300 seconds.' end
 if not ({Texts=true,Icons=true,Bars=true,Circles=true,["Debuff Overview"]=true})[data.display] then return false,'Choose a display.' end
 if data.logic~='ALL' and data.logic~='ANY' then return false,'Choose ALL or ANY trigger matching.' end
 if not data.triggers or #data.triggers<1 or #data.triggers>8 then return false,'Use 1–8 triggers.' end
 local triggerCount=0
 for key in pairs(data.triggers) do
  triggerCount=triggerCount+1
  if type(key)~='number' or key%1~=0 or key<1 or key>#data.triggers then return false,'Invalid trigger array.' end
 end
 if triggerCount~=#data.triggers then return false,'Trigger arrays cannot contain gaps.' end
 for _,t in ipairs(data.triggers) do
  if not CheckFields(t,triggerFields) or not R.catalogue[t.event] then return false,'Invalid trigger definition.' end
  for _,key in ipairs({'delay','active','remaining','noteTime'}) do
   if t[key] and (t[key]<0 or t[key]>3600) then return false,'Trigger time must be 0–3600 seconds.' end
  end
  if t.counter and (t.counter<1 or t.counter%1~=0) then return false,'Occurrence must be a positive whole number.' end
 end
 for _,key in ipairs({'bossID','zoneID','difficulty','icon'}) do
  if data[key] and (data[key]<1 or data[key]%1~=0) then return false,'IDs must be positive whole numbers.' end
 end
 return true
end
function R.New()
 local db,err=R.Store();if not db then return nil,err end
 db.serial=(db.serial or 0)+1
 local guid=UnitGUID and UnitGUID('player')
 local owner=Safe(guid,'string') and guid:gsub('[^%w]','') or 'Local'
 local uid=string.format('VRT-%s-%d-%d',owner,time(),db.serial)
 return {uid=uid,name='New reminder',message='Stack on marker',raid='Global',boss='General',duration=6,
  display='Texts',enabled=true,logic='ALL',triggers={{event=3,delay=0}},countdown=true}
end
function R.Changed()
 R.revision=R.revision+1
 if not R.encounter and not InCombatLockdown() then R.Rebuild() else R.pending=true end
end
function R.Save(data)
 local valid,err=R.Validate(data);if not valid then return false,err end
 if InCombatLockdown() then return false,'Edit reminders after combat.' end
 local db;db,err=R.Store();if not db then return false,err end
 local count=0;for _ in pairs(db.global) do count=count+1 end
 if not db.global[data.uid] and count>=200 then return false,'The global library limit is 200 reminders.' end
 local previous=db.global[data.uid]
 local saved=Copy(data);saved.updated=math.max(Now(),(previous and previous.updated or 0)+1);db.global[data.uid]=saved;R.Changed()
 if addon.SyncChanged then addon.SyncChanged('reminders') end
 return true
end
function R.Remove(uid)
 if InCombatLockdown() then return false,'Remove reminders after combat.' end
 local db,err=R.Store();if not db then return false,err end
 db.global[uid]=nil;R.forced[uid]=nil;R.Changed()
 if addon.MarkDeleted then addon.MarkDeleted('reminders',uid) end
 if addon.SyncChanged then addon.SyncChanged('reminders') end
 return true
end
function R.Unavailable(data)
 for _,t in ipairs(data.triggers or {}) do
  local def=R.catalogue[t.event]
  if not def or not def.available then return def and def.reason or 'Unknown trigger.' end
 end
end
function R.Rebuild()
 local db=R.Store();if not db then return end
 R.active={};R.jobs={};R.pending=false
 for uid,data in pairs(db.global) do
  -- Unavailable triggers never receive real events, so a test load can still run them by hand.
  if R.Validate(data) and data.enabled~=false and (R.forced[uid] or not R.Unavailable(data)) then
   local snapshot=Copy(data)
   R.active[uid]={data=snapshot,counts={},states={},known={},versions={},expiryVersions={},observed={},manual={}}
  end
 end
end
-- Assigned group role, or the current spec's role when none is assigned.
function R.PlayerRole()
 local role=UnitGroupRolesAssigned and UnitGroupRolesAssigned('player')
 if not Safe(role,'string') or role=='NONE' then
  local spec=GetSpecialization and GetSpecialization()
  role=spec and GetSpecializationRole and GetSpecializationRole(spec) or nil
 end
 return Safe(role,'string') and role or nil
end
-- Recipients: ticked roles OR named players (blank = everyone). Leader only
-- always applies; a test load bypasses the recipient filters.
function R.CanOutput(data)
 if data.leaderOnly and (not IsInRaid() or not UnitIsGroupLeader('player')) then return false end
 if R.forced[data.uid] then return true end
 local hasRoles=data.tanks or data.healers
 local hasNames=data.players and data.players~=''
 if not hasRoles and not hasNames then return true end
 if hasRoles then
  local role=R.PlayerRole()
  if (data.tanks and role=='TANK') or (data.healers and role=='HEALER') then return true end
 end
 if hasNames then
  local full=GetUnitName and GetUnitName('player',true)
  if not Safe(full,'string') then return false end
  local plain=full:match('^[^-]+')
  for name in data.players:gmatch('[^,;\n]+') do
   name=name:match('^%s*(.-)%s*$')
   if name:lower()==full:lower() or (not name:find('-',1,true) and name:lower()==plain:lower()) then return true end
  end
 end
 return false
end
local function Scope(data)
 if R.forced[data.uid] then return true end
 if data.bossID and data.bossID~=R.encounter then return false end
 if data.difficulty and data.difficulty~=R.difficulty then return false end
 if data.zoneID then
  local id=select(8,GetInstanceInfo())
  if not R.Public(id) or id~=data.zoneID then return false end
 end
 return true
end
local function Matches(t,p)
 if t.spellID and t.spellID~=p.spellID then return false end
 if t.phase and t.phase~='' and t.phase~=tostring(p.phase or '') then return false end
 if t.text and t.text~='' and not (p.text or ''):lower():find(t.text:lower(),1,true) then return false end
 if t.subevent and t.subevent~='' and t.subevent~=p.subevent then return false end
 if t.source and t.source~='' and t.source~=p.source then return false end
 if t.target and t.target~='' and t.target~=p.target then return false end
 if t.unit and t.unit~='' and p.unit and t.unit~=p.unit then return false end
 return true
end
function R.Schedule(delay,fn,key)
 if #R.jobs>=4096 then R.lastError='Pending trigger limit reached.';return false end
 R.jobs[#R.jobs+1]={due=R.clock+delay,fn=fn,key=key}
 return true
end
function R.Cancel(key)
 for i=#R.jobs,1,-1 do if R.jobs[i].key==key then table.remove(R.jobs,i) end end
end
function R.Emit(data,params,test)
 if not test and not R.CanOutput(data) then return end
 if addon.ReminderDisplay then addon.ReminderDisplay.Show(data,params or {},test) end
end
local function Evaluate(entry,p)
 local data=entry.data
 local result=data.logic=='ALL'
 for i,t in ipairs(data.triggers) do
  local on=entry.states[i] and true or false
  if t.invert and entry.known[i] then on=not on end
  if not entry.known[i] then on=false end
  if data.logic=='ALL' then result=result and on else result=result or on end
 end
 if result and not entry.latched then R.Emit(data,p) end
 entry.latched=result
end
local function Activate(entry,i,p)
 entry.known[i]=true;entry.states[i]=true;Evaluate(entry,p)
 entry.expiryVersions[i]=(entry.expiryVersions[i] or 0)+1
 local version=entry.expiryVersions[i]
 R.Schedule(entry.data.triggers[i].active or 0.2,function()
  if entry.expiryVersions[i]==version then entry.states[i]=false;Evaluate(entry,p) end
 end)
end
-- State-based providers maintain a condition, unlike brief event pulses.
function R.Observe(entry,i,condition,params,manual)
 if not Scope(entry.data) then return end
 -- A manually activated test trigger is not overridden by live polling.
 if not manual and entry.manual[i]~=nil then return end
 if condition==nil then
  entry.observed[i]=nil;entry.known[i]=nil;entry.states[i]=false
  entry.versions[i]=(entry.versions[i] or 0)+1;Evaluate(entry,params or {});return
 end
 if entry.observed[i]==condition then return end
 entry.observed[i]=condition;entry.known[i]=true
 entry.versions[i]=(entry.versions[i] or 0)+1
 if not condition then entry.states[i]=false;Evaluate(entry,params or {});return end
 entry.counts[i]=(entry.counts[i] or 0)+1
 local t=entry.data.triggers[i]
 if t.counter and t.counter~=entry.counts[i] then entry.states[i]=false;Evaluate(entry,params or {});return end
 local version=entry.versions[i];local p=Copy(params or {});p.counter=entry.counts[i]
 local function Set()
  if entry.versions[i]~=version then return end
  entry.states[i]=true;Evaluate(entry,p)
  if t.active and t.active>0 then R.Schedule(t.active,function()
   if entry.versions[i]==version then entry.states[i]=false;Evaluate(entry,p) end
  end) end
 end
 if (t.delay or 0)>0 then R.Schedule(t.delay,Set) else Set() end
end
function R.Dispatch(event,p)
 if addon.ModuleEnabled and not addon.ModuleEnabled('reminders') then return end
 p=p or {}
 -- Never inspect/compare/serialize a secret callback argument.
 for _,v in pairs(p) do if not R.Public(v) then return end end
 if p.text~=nil and type(p.text)~='string' then return end
 if p.phase~=nil and type(p.phase)~='string' and type(p.phase)~='number' then return end
 for _,entry in pairs(R.active) do
  if Scope(entry.data) then
   for i,t in ipairs(entry.data.triggers) do
    if t.event==event and (not p.onlyUID or p.onlyUID==entry.data.uid) and
     (not p.onlyIndex or p.onlyIndex==i) and Matches(t,p) then
     entry.counts[i]=(entry.counts[i] or 0)+1
     if not t.counter or t.counter==entry.counts[i] then
      entry.versions[i]=(entry.versions[i] or 0)+1
      local version=entry.versions[i]
      local params=Copy(p);params.counter=entry.counts[i]
      local delay=t.delay or 0
      if event==7 then delay=delay+math.max(0,(p.duration or 0)-(t.remaining or 0)) end
      if event==19 or event==21 then delay=delay+(t.noteTime or 0) end
      if delay==0 then Activate(entry,i,params) else
       R.Schedule(delay,function() if entry.versions[i]==version then Activate(entry,i,params) end end,p.timerKey)
      end
     end
    end
   end
  end
 end
end
-- Editor test panel: load one saved reminder for this session regardless of
-- raid/boss/difficulty/player filters, so real boss-mod events (such as DBM
-- test bars) can fire it, or activate its triggers by hand. Leader only still applies.
R.stateEvents={[4]=true,[5]=true,[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[15]=true,[17]=true,[18]=true,[20]=true}
function R.LoadForTest(uid)
 if InCombatLockdown() or R.encounter then return false,'Load test reminders outside combat and encounters.' end
 local db,err=R.Store();if not db then return false,err end
 local data=db.global[uid]
 if not data then return false,'Save the reminder before loading it for testing.' end
 if data.enabled==false then return false,'Enable and save the reminder before testing.' end
 R.forced[uid]=true;R.Rebuild();return true
end
function R.UnloadTest(uid)
 R.forced[uid]=nil
 if not R.encounter and not InCombatLockdown() then R.Rebuild() else R.pending=true end
end
function R.TestTrigger(uid,i,on)
 local entry=R.forced[uid] and R.active[uid]
 if not entry then return false,'Load the reminder for testing first.' end
 local t=entry.data.triggers[i];if not t then return false,'Unknown trigger.' end
 if R.stateEvents[t.event] then
  -- Hold the state until deactivated; live polling then takes over again.
  entry.manual[i]=on and true or nil
  R.Observe(entry,i,on and true or false,{unit=t.unit,spellID=t.spellID,widgetID=t.widgetID},true)
  return true
 end
 -- A pulse matching this trigger's own filters; timers fire at their Remaining point.
 R.Dispatch(t.event,{spellID=t.spellID,text=t.text,phase=t.phase,source=t.source,target=t.target,
  subevent=t.subevent,unit=t.unit,duration=t.remaining,onlyUID=uid,onlyIndex=i})
 return true
end
function R.Tick(elapsed)
 R.clock=R.clock+elapsed
 -- Jobs scheduled by a callback run on the next tick; never spin on zero delay.
 local ready={}
 for i=#R.jobs,1,-1 do
  if R.jobs[i].due<=R.clock then table.insert(ready,1,table.remove(R.jobs,i)) end
 end
 for _,job in ipairs(ready) do job.fn() end
end
function R.Start(id,difficulty)
 if addon.ModuleEnabled and not addon.ModuleEnabled('reminders') then return end
 if not R.Public(id) or not R.Public(difficulty) then return end
 if addon.ReminderDisplay and addon.ReminderDisplay.StopPreview then addon.ReminderDisplay.StopPreview(false) end
 R.encounter=id;R.difficulty=difficulty;R.Rebuild()
 R.Dispatch(3);R.Dispatch(19);R.Dispatch(21)
 -- Boss mods can start their opening bars before ENCOUNTER_START arrives.
 for key,timer in pairs(timers) do
  if not timer.paused and timer.ends>R.clock then
   R.Dispatch(7,{text=timer.text,duration=timer.ends-R.clock,spellID=timer.spellID,timerKey=key})
  end
 end
end
function R.Stop()
 R.encounter=nil;R.difficulty=nil;R.jobs={};R.active={};timers={}
 if addon.ReminderDisplay then addon.ReminderDisplay.Clear() end
 R.pending=true
 if not InCombatLockdown() then R.Rebuild() end
end
local function Timer(key,text,duration,spellID)
 if not Safe(key,'string') or not Safe(text,'string') or not Finite(duration) or not R.Public(spellID) then return end
 R.Cancel(key)
 for id,timer in pairs(timers) do if timer.ends<R.clock-60 then timers[id]=nil end end
 timers[key]={text=text,duration=duration,ends=R.clock+duration,spellID=Safe(spellID,'number') and spellID or nil}
 R.Dispatch(7,{text=text,duration=duration,spellID=timers[key].spellID,timerKey=key})
end
local function DBMCallback(event,...)
 local args={...};for i=1,select('#',...) do if not R.Public(select(i,...)) then return end end
 if event=='DBM_TimerBegin' then
  Timer('DBM:'..tostring(args[1]),args[2],args[3],args[6])
 elseif event=='DBM_TimerStop' or event=='DBM_TimerPause' then
  local key='DBM:'..tostring(args[1]);R.Cancel(key)
  if event=='DBM_TimerStop' then timers[key]=nil elseif timers[key] then timers[key].paused=true end
 elseif event=='DBM_TimerUpdate' then
  local key='DBM:'..tostring(args[1]);local old=timers[key]
  if old and Finite(args[2]) and Finite(args[3]) then Timer(key,old.text,args[3]-args[2],old.spellID) end
 elseif event=='DBM_TimerResume' then
  local key='DBM:'..tostring(args[1]);local old=timers[key]
  local bar=DBT and DBT.GetBar and DBT:GetBar(args[1])
  if old and bar and Finite(bar.timer) then Timer(key,old.text,bar.timer,old.spellID) end
 elseif event=='DBM_Announce' and Safe(args[1],'string') then
  R.Dispatch(6,{text=args[1],spellID=Safe(args[4],'number') and args[4] or nil})
 elseif event=='DBM_SetStage' and (Safe(args[3],'number') or Safe(args[3],'string')) then
  R.Dispatch(2,{phase=args[3]})
 end
end
local dbmReady,bwReady=false,false
-- Triggers fed only by a boss mod: phase, boss-mod message and boss-mod timer.
-- Blizzard's own boss warnings keep their spells and text secret from addons.
R.bossModTriggers={[2]=true,[6]=true,[7]=true}
function R.BossMod()
 if dbmReady or (DBM and type(DBM.RegisterCallback)=='function') then return 'DBM' end
 if bwReady or (BigWigsLoader and type(BigWigsLoader.RegisterMessage)=='function') then return 'BigWigs' end
end
function R.InstallCallbacks()
 if not dbmReady and DBM and type(DBM.RegisterCallback)=='function' then
  for _,event in ipairs({'DBM_TimerBegin','DBM_TimerStop','DBM_TimerPause','DBM_TimerResume','DBM_TimerUpdate','DBM_Announce','DBM_SetStage'}) do DBM:RegisterCallback(event,DBMCallback) end
  dbmReady=true
 end
 if not bwReady and BigWigsLoader and type(BigWigsLoader.RegisterMessage)=='function' then
  local function Callback(event,...)
   if dbmReady then return end -- One boss-mod feed avoids double counting.
   for i=1,select('#',...) do if not R.Public(select(i,...)) then return end end
   local mod,key,text,duration=...
   local id='BW:'..tostring(mod)..':'..tostring(key)
   if event=='BigWigs_Message' and Safe(text,'string') then R.Dispatch(6,{text=text,spellID=Safe(key,'number') and key or nil})
   elseif event=='BigWigs_SetStage' then R.Dispatch(2,{phase=key})
   elseif event=='BigWigs_StartBar' then Timer(id,text,duration,Safe(key,'number') and key or nil)
   elseif event=='BigWigs_StopBar' then
    local prefix='BW:'..tostring(mod)..':'
    for timerKey,old in pairs(timers) do if timerKey:sub(1,#prefix)==prefix and old.text==key then R.Cancel(timerKey);timers[timerKey]=nil end end
   elseif event=='BigWigs_StopBars' or event=='BigWigs_OnBossDisable' then
    local prefix='BW:'..tostring(mod)..':'
    for timerKey in pairs(timers) do if timerKey:sub(1,#prefix)==prefix then R.Cancel(timerKey);timers[timerKey]=nil end end
   end
  end
  for _,event in ipairs({'BigWigs_Message','BigWigs_SetStage','BigWigs_StartBar','BigWigs_StopBar','BigWigs_StopBars','BigWigs_OnBossDisable'}) do BigWigsLoader.RegisterMessage(R,event,Callback) end
  bwReady=true
 end
end
local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_ENTERING_WORLD','ENCOUNTER_START','ENCOUNTER_END','PLAYER_REGEN_ENABLED','GROUP_ROSTER_UPDATE','PARTY_LEADER_CHANGED','CHALLENGE_MODE_START','CHALLENGE_MODE_COMPLETED','CHALLENGE_MODE_RESET','ADDON_LOADED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event,...)
 if event=='ENCOUNTER_START' then local id,_,difficulty=...;R.Start(id,difficulty)
 elseif event=='ENCOUNTER_END' or event=='CHALLENGE_MODE_COMPLETED' or event=='CHALLENGE_MODE_RESET' then R.Stop()
 elseif event=='CHALLENGE_MODE_START' then R.Rebuild();R.Dispatch(22)
 elseif event=='GROUP_ROSTER_UPDATE' then R.Dispatch(16)
 elseif event=='PLAYER_REGEN_ENABLED' then if R.pending and not R.encounter then R.Rebuild() end
 elseif event=='PARTY_LEADER_CHANGED' then if addon.ReminderDisplay then addon.ReminderDisplay.Prune() end
 else
  R.InstallCallbacks()
  if (event=='PLAYER_LOGIN' or event=='PLAYER_ENTERING_WORLD') and not InCombatLockdown() and not R.encounter then R.Rebuild() end
 end
end)
events:SetScript('OnUpdate',function(_,elapsed) R.Tick(elapsed) end)
