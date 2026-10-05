local _,addon=...
-- Global record identity for sync. Every note, visual note and reminder has a
-- uid that is the same on every client (author GUID, time and a counter), and
-- an updated time so the newest edit wins. Deletions leave a tombstone so a
-- sync cannot bring a deleted record back. Boss plans and the team roster are
-- one record each and only need an updated time.
local TOMBSTONE_DAYS=60

local function DB() VincibilityRaidToolsDB=VincibilityRaidToolsDB or {};return VincibilityRaidToolsDB end
-- Edit times for sync come from the realm, not this computer's clock, so a
-- player whose clock is wrong cannot make old edits look newest. Falls back
-- to the local clock where the realm time is unavailable.
function addon.Now()
 local server=GetServerTime and GetServerTime()
 if type(server)=='number' and server>0 then return server end
 return time and time() or 0
end
function addon.NewUID(kind)
 local db=DB()
 db.uidSerial=(type(db.uidSerial)=='number' and db.uidSerial or 0)+1
 local guid=UnitGUID and UnitGUID('player')
 local owner=(type(guid)=='string' and (not issecretvalue or not issecretvalue(guid))) and guid:gsub('[^%w]','') or 'Local'
 return string.format('VRT-%s-%s-%d-%d',kind,owner,time(),db.uidSerial)
end
function addon.ValidUID(uid) return type(uid)=='string' and #uid<=120 and uid:match('^VRT%-[%w%-]+$')~=nil end
-- Tombstones: [kind][uid]=deleted time.
function addon.Tombstones(kind)
 local db=DB()
 if type(db.syncTombstones)~='table' then db.syncTombstones={} end
 if type(db.syncTombstones[kind])~='table' then db.syncTombstones[kind]={} end
 return db.syncTombstones[kind]
end
function addon.MarkDeleted(kind,uid,when)
 if not addon.ValidUID(uid) then return end
 local list=addon.Tombstones(kind)
 local stamp=when or addon.Now()
 if not list[uid] or list[uid]<stamp then list[uid]=stamp end
 -- Forget tombstones nobody can still be holding a copy for.
 local cutoff=addon.Now()-TOMBSTONE_DAYS*86400
 for key,deleted in pairs(list) do if type(deleted)~='number' or deleted<cutoff then list[key]=nil end end
end
-- A local edit: let sync tell others (debounced there).
function addon.SyncChanged(kind) if addon.Sync and addon.Sync.Changed then addon.Sync.Changed(kind) end end
