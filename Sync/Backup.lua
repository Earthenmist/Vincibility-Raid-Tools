local _,addon=...
-- Backup & Restore (Settings): snapshots of everything that syncs (text and
-- visual notes, reminders, boss plans, team roster, aura tracking), kept in
-- SavedVariables. Made automatically just before VRT applies changes from
-- someone else (at most every few minutes) and on demand. A restore is a
-- fresh edit: each restored record gets a version newer than the current one,
-- and records the backup did not have are deleted (or emptied, for boss plans
-- and aura setups), so normal sync carries the restore to everyone instead of
-- older copies overwriting it. A backup of the current state is made first,
-- so a restore can itself be undone. Your own settings are saved too and
-- restored only on this client (never synced).
local B={};addon.Backup=B
local MAX,AUTO_GAP=10,300

local function Sync() return addon.Sync end
local function Now() return addon.Now and addon.Now() or (time and time() or 0) end
local function Busy()
 local R=addon.Reminders
 return InCombatLockdown() or (R and R.encounter) or false
end
local function Copy(value)
 if type(value)~='table' then return value end
 local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end
local function Same(a,b) local I=addon.SyncIBLT;return I.Canonical(a)==I.Canonical(b) end
-- Settings: every top-level saved value except the synced libraries, the
-- backups themselves and sync bookkeeping; plus the personal parts kept inside
-- the assignment and aura stores.
local DATA={notes=true,visualNotes=true,reminders=true,assignments=true,auras=true,backups=true,syncTombstones=true,uidSerial=true,startingNote=true}
local NESTED={assignments={'view','overview','autoSharePlan','source','lastBoss','lastBossName'},auras={'display','personal'}}
local function SaveSettings(db)
 local saved={top={},nested={}}
 for key,value in pairs(db) do if type(key)=='string' and not DATA[key] then saved.top[key]=Copy(value) end end
 for store,fields in pairs(NESTED) do
  saved.nested[store]={}
  for _,field in ipairs(fields) do if type(db[store])=='table' then saved.nested[store][field]=Copy(db[store][field]) end end
 end
 return saved
end
local function RestoreSettings(db,saved)
 for key in pairs(db) do if type(key)=='string' and not DATA[key] and saved.top[key]==nil then db[key]=nil end end
 for key,value in pairs(saved.top) do db[key]=Copy(value) end
 for store,fields in pairs(NESTED) do
  if type(db[store])=='table' then
   for _,field in ipairs(fields) do db[store][field]=Copy((saved.nested[store] or {})[field]) end
  end
 end
 -- Apply what can change live; the rest (window scale, positions) on /reload.
 for _,refresh in ipairs({addon.UpdateCompactPanelSettings,addon.UpdateRaidPanelVisibility,addon.UpdateNativeTextNote,addon.UpdateVisualNote}) do pcall(refresh) end
 if addon.SetMinimapButtonShown and addon.GetMinimapButtonShown then pcall(addon.SetMinimapButtonShown,addon.GetMinimapButtonShown()) end
 local U=addon.Auras;if U then U.dirty=true;pcall(U.RegisterSounds) end
 if addon.AuraDisplays then pcall(addon.AuraDisplays.Refresh) end
 if addon.RefreshNavigation then pcall(addon.RefreshNavigation) end
end
function B.List()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.backups)~='table' then db.backups={} end
 return db.backups
end
-- Content fingerprint of every kind, to skip automatic backups of nothing new.
local function Signature()
 local S,parts=Sync(),{}
 for _,kind in ipairs(S.kinds) do local snapshot=S.Snapshot(kind.key);parts[#parts+1]=kind.key..snapshot.count..':'..snapshot.a..':'..snapshot.b end
 return table.concat(parts,'|')
end
function B.Create(reason,automatic)
 local S=Sync();if not S then return false,'Sync is unavailable.' end
 local list=B.List()
 local signature=Signature()
 if automatic and list[1] and list[1].sig==signature then return false,'Nothing changed since the last backup.' end
 local backup={at=Now(),reason=reason or 'Manual backup',auto=automatic and true or nil,sig=signature,kinds={},counts={}}
 for _,kind in ipairs(S.kinds) do
  local records={}
  for _,record in ipairs(S.Records(kind.key)) do if not record.x then records[#records+1]={u=record.u,d=Copy(record.d)} end end
  backup.kinds[kind.key]=records;backup.counts[kind.key]=#records
 end
 backup.settings=SaveSettings(VincibilityRaidToolsDB)
 table.insert(list,1,backup)
 -- Keep the newest ten; automatic backups go before manual ones.
 while #list>MAX do
  local drop=#list
  for index=#list,1,-1 do if list[index].auto then drop=index;break end end
  table.remove(list,drop)
 end
 if addon.RefreshBackupsTab then addon.RefreshBackupsTab() end
 return true,'Backup made.'
end
-- Called just before changes from someone else are applied.
function B.BeforeIncoming(source)
 if B.restoring then return end
 if B.lastAuto and Now()-B.lastAuto<AUTO_GAP then return end
 B.lastAuto=Now()
 local name=type(source)=='string' and source:gsub('%-.*$','') or 'someone'
 B.Create('Before changes from '..name,true)
end
-- Boss plans and aura setups cannot be deleted by sync; restore them empty.
local function Emptied(key,uid,current)
 if key=='plans' then
  local boss=tonumber(uid:match('^plan%-(%d+)$'))
  return boss and {boss=boss,name=current.d and current.d.name,entries={}}
 elseif key=='auras' then
  local data=Copy(current.d or {});data.sounds,data.overview,data.cotank={},{},{}
  return data
 end
end
-- Restore a backup (by list position), everything or one kind.
function B.Restore(index,only)
 if Busy() then return false,'Restore out of combat and encounters.' end
 local S=Sync();local backup=B.List()[index]
 if not S or not backup then return false,'Choose a backup first.' end
 if only=='settings' and not backup.settings then return false,'That backup was made before settings were included.' end
 if only and only~='settings' and not backup.kinds[only] then return false,'That backup has nothing of that kind.' end
 B.Create('Before restoring a backup',false)
 B.restoring=true
 local changed,failed=0,0
 local function Apply(key,record)
  local ok=S.ApplyRecord(key,record,'restore')
  if ok then changed=changed+1 elseif ok==nil then failed=failed+1 end
 end
 for _,kind in ipairs(S.kinds) do
  local key=kind.key
  if (not only or only==key) and backup.kinds[key] then
   local current={};for _,record in ipairs(S.Records(key)) do current[record.u]=record end
   local wanted={}
   for _,saved in ipairs(backup.kinds[key]) do
    wanted[saved.u]=true
    local now=current[saved.u]
    -- Newer than the copy everyone has now, whatever their clocks say.
    if not now or now.x or not Same(now.d,saved.d) then Apply(key,{u=saved.u,v=math.max(Now(),(now and now.v or 0)+1),d=Copy(saved.d)}) end
   end
   for uid,now in pairs(current) do
    if not wanted[uid] and not now.x then
     local version=math.max(Now(),now.v+1)
     if key=='plans' or key=='auras' then
      local data=Emptied(key,uid,now)
      if data and not Same(now.d,data) then Apply(key,{u=uid,v=version,d=data}) end
     else Apply(key,{u=uid,v=version,x=true}) end
    end
   end
   S.Changed(key);if S.AfterApply then S.AfterApply(key) end
  end
 end
 B.restoring=false
 local settings=(not only or only=='settings') and backup.settings
 if settings then RestoreSettings(VincibilityRaidToolsDB,settings) end
 if addon.RefreshBackupsTab then addon.RefreshBackupsTab() end
 if only=='settings' then return true,'Your settings are restored. Type /reload to apply window size and positions.' end
 if failed>0 then return true,string.format('Restored with %d change%s; %d item%s could not be restored.',changed,changed==1 and '' or 's',failed,failed==1 and '' or 's') end
 local extra=settings and ' Your settings are restored too (/reload for window size and positions).' or ''
 if changed==0 and not settings then return true,'Nothing to restore: already matches that backup.' end
 return true,(changed==0 and 'No data changes.' or string.format('Restored %d change%s. Sync will send them to everyone.',changed,changed==1 and '' or 's'))..extra
end
