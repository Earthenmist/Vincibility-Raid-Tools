local _,addon=...
local titles={
    [3379]='Tidebound Grotto',
    [3513]="Kith'ix",
    [3470]="Nek'zali - Heroic", [3445]='Entombed Sentinels - Heroic',
    [3455]='Vashnik - Heroic', [3497]='Lost Explorers - Heroic',
    [3420]='Sszorak - Heroic', [3421]='Twin Fangs - Heroic',
    [3429]='Coiled Altar - Heroic', [3492]="Ula'tek - Heroic",
}
-- Room labels are in-game subzone names. Keep this small, instance-scoped table
-- here so native drawings can open before a pull.
local englishRooms={
    ['The Tidebound Grotto']=3379,
    ['The Soulcoil Well']=3470,
    ['Pit of Fangs']=3421,
    ['The Venomducts']=3445,
    ['The Chamber of Virulence']=3455,
    ["Mor'zahi's Tomb"]=3497,
    ['Altar of the Six Winds']=3420,
    ['The Coiled Altar']=3429,
    ["The Tomb of Ula'tek"]=3492,
}
-- Instance ID -> boss for raids with one boss (12.1.5: The Unbinding of Kith'ix).
local singleBoss={[3095]=3513}
local currentBoss,suppressed
local status='Waiting for a boss area.'
local function Normalize(name)
    return tostring(name or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('’',"'"):lower():gsub('^the%s+',''):gsub('%s+',' '):match('^%s*(.-)%s*$')
end
local function GetBoss()
    local inside,kind=IsInInstance()
    local _,_,difficulty,_,_,_,_,instance=GetInstanceInfo()
    if not inside or kind~='raid' then return nil end
    -- Single-boss raids: the whole instance is the boss area, in any client language.
    if singleBoss[instance] then return singleBoss[instance] end
    if not ((instance==3004 and difficulty==15) or instance==2987) then return nil end
    -- Only English room names are mapped; other client locales do not auto-show.
    local locale=GetLocale()
    local boss=(locale=='enUS' or locale=='enGB') and englishRooms[GetSubZoneText()]
    return titles[boss] and boss or nil
end
function addon.GetNativeBossID()
 return GetBoss()
end
local function NativeMatch(boss)
 local native=addon.NativeVisualNotes
 if not native then return end
 local store=native.Store();if not store then return end
 local found
 for _,note in ipairs(store.items) do
  local assigned=note.bossID==boss
  if not assigned and not note.bossID then
   assigned=Normalize(note.name)==Normalize(titles[boss])
   if not assigned and note.map and note.map.label then
    for _,preset in ipairs(native.bossMaps) do
     if preset[6]==boss and Normalize(note.map.label)==Normalize(preset[1]) then assigned=true;break end
    end
   end
  end
  if assigned then
   if found then return false end
   found=note
  end
 end
 return found
end
local function HideNative()
 if addon.NativeVisualNotes then addon.NativeVisualNotes.HidePopup() end
end
function addon.OnNativeVisualPopupClosed()
 if currentBoss then suppressed=currentBoss;status='Closed for this boss area.' end
end
function addon.GetVisualNoteStatus() return status end
function addon.UpdateVisualNote()
    if InCombatLockdown() then return end
    local db=VincibilityRaidToolsDB
    if not db then return end
    -- Off until the player turns it on in Settings.
    if not db.autoVisualNotesChosen then db.autoVisualNotes=false end
    if addon.ModuleEnabled and not addon.ModuleEnabled('visual') then HideNative();status='Visual Notes module is disabled.';return end
    local boss=GetBoss()
    if boss~=currentBoss then
        HideNative();suppressed=nil;currentBoss=boss
    end
    if not db.autoVisualNotes then HideNative();status='Automatic visual notes disabled.';return end
    if not boss then HideNative();status='Waiting for a supported boss area.';return end
    if suppressed==boss then status='Closed for this boss area.';return end
    if addon.NativeVisualNotes and addon.NativeVisualNotes.IsEditing and addon.NativeVisualNotes.IsEditing() then
        HideNative();status='Paused while editing Visual Notes.';return
    end
    if addon.NativeVisualNotes and addon.NativeVisualNotes.IsManualPopup and addon.NativeVisualNotes.IsManualPopup() then
        status='Manual VRT visual note preview open.';return
    end
    local native=NativeMatch(boss)
    if native==false then HideNative();status='Duplicate VRT visual notes for '..titles[boss];return end
    if native then
        local ok,err=addon.NativeVisualNotes.ShowPopup(native,false)
        status=ok and 'Showing VRT: '..native.name or 'VRT visual note needs review: '..tostring(err)
        return
    end
    HideNative();status='No VRT visual note: '..titles[boss]
end
function addon.SetAutoVisualNotes(enabled)
    VincibilityRaidToolsDB.autoVisualNotes=enabled and true or false
    VincibilityRaidToolsDB.autoVisualNotesChosen=true
    suppressed=nil
    addon.UpdateVisualNote()
end
local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_ENTERING_WORLD','ZONE_CHANGED','ZONE_CHANGED_INDOORS','ZONE_CHANGED_NEW_AREA','PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED'}) do events:RegisterEvent(event) end
local generation=0
events:SetScript('OnEvent',function(_,event)
    generation=generation+1
    if event=='PLAYER_REGEN_DISABLED' then
        HideNative();return
    end
    local request=generation
    C_Timer.After(1,function() if request==generation then addon.UpdateVisualNote() end end)
end)
