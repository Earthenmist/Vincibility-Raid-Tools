local _,addon=...
local R,S,D=addon.Reminders,addon.ReminderSharing,addon.ReminderDisplay
-- Read client catalogues only when the editor needs them. Journal IDs, UI-map
-- IDs and encounter-event IDs are distinct; only game IDs enter saved filters.
local Choices={}
addon.ReminderChoices=Choices
local function Public(value,kind) return R.Public(value) and type(value)==kind end
-- Adventure Guide entries that are not real instances (the Mythic+ season
-- summary has no bosses to plan), hidden from every boss menu.
Choices.hiddenInstances={['Keystone Dungeons']=true}
function Choices.Instances()
 if InCombatLockdown() or R.encounter then return nil,'Choose raid data outside combat and encounters.' end
 if Choices.instances then return Choices.instances end
 if not EJ_GetInstanceByIndex and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn('Blizzard_EncounterJournal') end
 if not EJ_GetInstanceByIndex or not EJ_GetNumTiers or not EJ_SelectTier or not EJ_GetCurrentTier then
  return nil,'Adventure Guide data is unavailable. Open the guide, then try again.'
 end
 local tier=EJ_GetCurrentTier();local entries,seen={},{}
 local ok=pcall(function()
  for t=math.min(EJ_GetNumTiers(),32),1,-1 do
   EJ_SelectTier(t)
   local tierName=EJ_GetTierInfo and EJ_GetTierInfo(t) or ''
   for _,raid in ipairs({true,false}) do
    for index=1,100 do
     local journalID,name,_,_,_,_,_,uiMapID,_,_,mapID=EJ_GetInstanceByIndex(index,raid)
     if not journalID then break end
     if Public(journalID,'number') and Public(name,'string') and Public(mapID,'number') and mapID>0 and not seen[t..':'..mapID] and not Choices.hiddenInstances[name] then
      seen[t..':'..mapID]=true
      -- uiMapID is the instance's client map art (dungeonAreaMapID); zoneID is the game instance ID.
      entries[#entries+1]={name=name,zoneID=mapID,journalID=journalID,uiMapID=Public(uiMapID,'number') and uiMapID>0 and uiMapID or nil,kind=raid and 'raid' or 'party',tier=t,tierName=Public(tierName,'string') and tierName or tostring(t),
       label=name..(Public(tierName,'string') and tierName~='' and ' · '..tierName or '')..(raid and ' · Raid' or ' · Dungeon')}
     end
    end
   end
  end
 end)
 if Public(tier,'number') then EJ_SelectTier(tier) end
 if not ok or #entries==0 then return nil,'Adventure Guide raid/dungeon data is not ready. Open the guide, then try again.' end
 Choices.instances=entries;return entries
end
function Choices.Bosses(instance)
 if InCombatLockdown() or R.encounter then return nil,'Choose boss data outside combat and encounters.' end
 if not instance then return {} end
 if not EJ_GetEncounterInfoByIndex or not EJ_SelectInstance then return nil,'Adventure Guide boss data is unavailable.' end
 local tier=EJ_GetCurrentTier and EJ_GetCurrentTier()
 local previous=EncounterJournal and EncounterJournal.instanceID
 local encounter=EncounterJournal and EncounterJournal.encounterID
 if not previous and EJ_GetInstanceInfo then
  local _,_,_,_,_,_,_,_,_,mapID=EJ_GetInstanceInfo()
  for _,entry in ipairs(Choices.instances or {}) do if entry.zoneID==mapID then previous=entry.journalID;break end end
 end
 local difficulty=EJ_GetDifficulty and EJ_GetDifficulty()
 local entries={}
 local ok=pcall(function()
  if instance.tier and EJ_SelectTier then EJ_SelectTier(instance.tier) end
  -- Even an explicit instance argument yields no bosses on a fresh journal
  -- session until EJ_SelectInstance has initialized the encounter catalogue.
  EJ_SelectInstance(instance.journalID)
  for index=1,100 do
   local name,_,journalEncounterID,_,_,_,encounterID=EJ_GetEncounterInfoByIndex(index,instance.journalID)
   if not name then break end
   if Public(name,'string') and Public(encounterID,'number') and encounterID>0 then
    entries[#entries+1]={name=name,label=name,bossID=encounterID,journalEncounterID=Public(journalEncounterID,'number') and journalEncounterID or nil}
   end
  end
 end)
 if Public(tier,'number') and EJ_SelectTier then EJ_SelectTier(tier) end
 if Public(previous,'number') and previous>0 then
  EJ_SelectInstance(previous)
  if Public(encounter,'number') and encounter>0 and EJ_SelectEncounter then EJ_SelectEncounter(encounter) end
 end
 if Public(difficulty,'number') and EJ_SetDifficulty then EJ_SetDifficulty(difficulty) end
 if not ok or #entries==0 then return nil,'Boss data is not ready for '..instance.name..'. Open this instance in the Adventure Guide, then try again.' end
 return entries
end
-- Library presentation only: infer a boss-only reminder's parent without
-- changing its saved encounter/instance filters or imported source snapshot.
function Choices.LibraryCatalogue(records)
 local index=Choices.libraryIndex or {zones={},bosses={},loaded={},retry={}}
 Choices.libraryIndex=index
 if #records==0 or InCombatLockdown() or R.encounter then return index end
 local instances=Choices.Instances();if not instances then return index end
 local needed,zones={},{}
 for _,d in ipairs(records) do if d.bossID then needed[d.bossID]=true end;if d.zoneID then zones[d.zoneID]=true end end
 for order,instance in ipairs(instances) do
  if not index.zones[instance.zoneID] then index.zones[instance.zoneID]={instance=instance,order=order} end
 end
 local now=GetTime and GetTime() or 0
 local function Read(instance,order)
  if index.loaded[instance.journalID] or (index.retry[instance.journalID] or 0)>now then return end
  local bosses=Choices.Bosses(instance)
  if not bosses then index.retry[instance.journalID]=now+10;return end
  index.loaded[instance.journalID]=true
  for position,boss in ipairs(bosses) do
   if not index.bosses[boss.bossID] then index.bosses[boss.bossID]={name=boss.name,instance=instance,order=position,instanceOrder=order} end
  end
 end
 -- Load explicit instance scopes first; most libraries resolve in a few reads.
 for order,instance in ipairs(instances) do if zones[instance.zoneID] then Read(instance,order) end end
 local function Missing() for id in pairs(needed) do if not index.bosses[id] then return true end end;return false end
 if Missing() and (index.searchAfter or 0)<=now then
  for order,instance in ipairs(instances) do
   Read(instance,order);if not Missing() then break end
  end
  if Missing() then index.searchAfter=now+10 end
 end
 return index
end
function Choices.LibraryGroups(records,index)
 local groups,byKey,parents={}, {},{}
 -- A unique explicit scope in this library also supplies a safe display-only
 -- parent when journal boss data is temporarily unavailable.
 for _,data in ipairs(records) do
  if data.bossID and data.zoneID then
   if parents[data.bossID]==nil then parents[data.bossID]=data.zoneID
   elseif parents[data.bossID]~=data.zoneID then parents[data.bossID]=false end
  end
 end
 for _,data in ipairs(records) do
  local boss=data.bossID and index.bosses[data.bossID]
  local zoneID=data.zoneID or (boss and boss.instance.zoneID) or (data.bossID and parents[data.bossID]) or nil
  local scope=zoneID and index.zones[zoneID]
  local instance=scope and scope.instance or (not data.zoneID and boss and boss.instance)
  local key=zoneID and 'instance:'..zoneID or data.bossID and 'unassigned' or 'folder:'..(data.raid or 'Global')
  local group=byKey[key]
  if not group then
   group={key=key,name=instance and instance.name or zoneID and ('Raid / dungeon '..zoneID) or data.bossID and 'Unassigned bosses' or (data.raid or 'Global'),
    order=scope and scope.order or boss and boss.instanceOrder or 9999,bosses={},byBoss={}}
   byKey[key]=group;groups[#groups+1]=group
  end
  local bossKey=key..(data.bossID and '/boss:'..data.bossID or '/section:'..(data.boss or 'General'))
  local section=group.byBoss[bossKey]
  if not section then
   section={key=bossKey,name=boss and boss.name or data.bossID and ('Boss '..data.bossID) or (data.boss or 'General'),
    order=boss and boss.order or data.bossID and 9998 or 9999,records={}}
   group.byBoss[bossKey]=section;group.bosses[#group.bosses+1]=section
  end
  section.records[#section.records+1]=data
 end
 table.sort(groups,function(a,b) if a.order~=b.order then return a.order<b.order end;if a.name~=b.name then return a.name<b.name end;return a.key<b.key end)
 for _,group in ipairs(groups) do
  table.sort(group.bosses,function(a,b) if a.order~=b.order then return a.order<b.order end;if a.name~=b.name then return a.name<b.name end;return a.key<b.key end)
  for _,boss in ipairs(group.bosses) do table.sort(boss.records,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.uid<b.uid end) end
 end
 return groups
end
function Choices.Tiers(entries)
 local tiers,seen={},{}
 for _,entry in ipairs(entries) do
  if not seen[entry.tier] then tiers[#tiers+1]={tier=entry.tier,label=entry.tierName};seen[entry.tier]=true end
 end
 return tiers
end
function Choices.ForTier(entries,tier,kind)
 local choices={}
 for _,entry in ipairs(entries) do if entry.tier==tier and entry.kind==kind then choices[#choices+1]=entry end end
 table.sort(choices,function(a,b) return a.name<b.name end)
 return choices
end
function Choices.Difficulties(instance)
 local entries={};if not GetDifficultyInfo then return entries end
 local ids,seen={14,15,16,17,1,2,23,8},{}
 if DifficultyUtil and DifficultyUtil.ID then
  local extra={}
  for _,id in pairs(DifficultyUtil.ID) do if Public(id,'number') then extra[#extra+1]=id end end
  table.sort(extra);for _,id in ipairs(extra) do ids[#ids+1]=id end
 end
 for _,id in ipairs(ids) do
  if not seen[id] then
   seen[id]=true
   local name,kind,_,_,_,_,_,_,min,max=GetDifficultyInfo(id)
   if Public(name,'string') and Public(kind,'string') and (kind=='raid' or kind=='party') and (not instance or kind==instance.kind) then
    local label=name
    if Public(min,'number') and Public(max,'number') and min==max and max>5 then label=label..' ('..max..' players)' end
    if not instance then label=label..(kind=='raid' and ' · Raid' or ' · Dungeon') end
    entries[#entries+1]={value=id,label=label,name=name}
   end
  end
 end
 return entries
end
function Choices.Icons()
 if Choices.icons then return Choices.icons end
 local raw,entries,seen={},{},{}
 if GetMacroIcons then GetMacroIcons(raw) end
 if GetMacroItemIcons then GetMacroItemIcons(raw) end
 for _,value in ipairs(raw) do
  local id=R.Public(value) and tonumber(value)
  if id and id>0 and id%1==0 and not seen[id] then entries[#entries+1]=id;seen[id]=true end
 end
 if #entries>0 then Choices.icons=entries end
 return entries
end
function Choices.SpellIcon(text)
 if not C_Spell or not C_Spell.GetSpellInfo then return nil,'Spell data is unavailable.' end
 local value=text:match('^%s*(.-)%s*$')
 if value=='' then return nil,'Enter a spell name.' end
 local info=C_Spell.GetSpellInfo(tonumber(value) or value)
 if info and Public(info.iconID,'number') then return info.iconID end
 return nil,'Spell not found. Enter its full name, or browse the icons below.'
end
function addon.BuildRemindersPage(page,window,H)
 local Text,Button,Surface=H.Text,H.Button,H.Surface
 local ui={offset=0,collapsed={},rows={},selected=nil};window.remindersPage=ui
 Text(page,'Global library · native VRT reminders',0,-27,12,'muted')
 -- Same layout as Notes: tall list, buttons below it, status and summary at the bottom.
 local ROWS=14
 local list=Surface('Frame',page);list:SetPoint('TOPLEFT',0,-60);list:SetSize(864,480);list:EnableMouseWheel(true);ui.list=list
 ui.status=Text(page,'',0,0,11,'accent',600);ui.status:ClearAllPoints();ui.status:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-4)
 ui.summary=Text(page,'',0,0,10,'muted',850);ui.summary:ClearAllPoints();ui.summary:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-20)
 ui.progress=Surface('Frame',page,'raised');ui.progress:SetPoint('TOPLEFT',0,-544);ui.progress:SetSize(864,7);ui.progress:Hide()
 ui.progressFill=ui.progress:CreateTexture(nil,'ARTWORK');ui.progressFill:SetPoint('TOPLEFT',1,-1);ui.progressFill:SetSize(1,5);ui.progressFill:SetColorTexture(unpack(H.colours.highlight))
 ui.pending=Text(page,'',0,-598,11,'text',590)
 function ui.RefreshProgress()
  local fraction,label=S.Progress()
  if fraction then
   ui.status:SetText(label);ui.progressFill:SetWidth(math.max(1,math.floor(862*fraction)));ui.progress:Show()
  else ui.status:SetText((R.lastError or S.status)..(R.pending and ' Library changes take effect after the encounter.' or ''));ui.progress:Hide() end
 end
 addon.RefreshReminderTransferProgress=ui.RefreshProgress
 local function Notice(ok,err) if not ok then ui.status:SetText(err or 'Action unavailable.') end end
 local function EntryFields(parent,key,label,x,y,width)
  local caption=Text(parent,label,x,y,10,'muted',width)
  local entry=Surface('EditBox',parent,'background')
  entry:SetFont(STANDARD_TEXT_FONT,12,'');entry:SetTextColor(unpack(H.colours.text));entry:SetTextInsets(7,7,0,0)
  entry:SetBackdropBorderColor(0.72,0.76,0.81,0.35)
  entry:SetScript('OnEditFocusGained',function(self) self:SetBackdropBorderColor(unpack(H.colours.highlight)) end)
  entry:SetScript('OnEditFocusLost',function(self) self:SetBackdropBorderColor(0.72,0.76,0.81,0.35) end)
  entry:SetAutoFocus(false);entry:SetSize(width,24);entry:SetPoint('TOPLEFT',x+4,y-17);entry:SetMaxLetters(key=='message' and 2048 or 160)
  entry:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
  entry.caption=caption
  return entry
 end
 local function Check(parent,x,y,label,width)
  local check=Surface('CheckButton',parent,'background');check:SetSize(20,20);check:SetPoint('TOPLEFT',x,y)
  check:SetBackdropBorderColor(0.72,0.76,0.81,0.5)
  local mark=check:CreateTexture(nil,'ARTWORK');mark:SetSize(12,12);mark:SetPoint('CENTER');mark:SetColorTexture(unpack(H.colours.highlight));check:SetCheckedTexture(mark)
  check.label=Text(check,label,27,-3,12,'text',width)
  check:SetScript('OnEnter',function(self) self:SetBackdropBorderColor(unpack(H.colours.highlight)) end)
  check:SetScript('OnLeave',function(self) self:SetBackdropBorderColor(0.72,0.76,0.81,0.5) end)
  return check
 end
 local editor=Surface('Frame',window);ui.editor=editor
 editor:SetSize(1000,620);editor:SetPoint('CENTER');editor:SetFrameLevel(window:GetFrameLevel()+40);editor:EnableMouse(true);editor:Hide()
 Text(editor,'Reminder editor',16,-12,17,'text',950)
 ui.inputs={}
 local specs={
  {'name','Name',16,-44,290},{'message','Message',330,-44,640},
  {'duration','Duration (seconds)',16,-138,100},
  {'players','Players (comma-separated; with Tanks/Healers, either matches)',450,-138,310},
 }
 for _,spec in ipairs(specs) do ui.inputs[spec[1]]=EntryFields(editor,unpack(spec)) end
 Text(editor,'Raid / dungeon',16,-91,10,'muted',290)
 Text(editor,'Boss',330,-91,10,'muted',290)
 Text(editor,'Difficulty',264,-138,10,'muted',160)
 Text(editor,'Icon',140,-138,10,'muted',100)
 local choiceMenu=Surface('Frame',editor);ui.choiceMenu=choiceMenu
 choiceMenu:SetSize(600,430);choiceMenu:SetPoint('CENTER');choiceMenu:SetFrameLevel(editor:GetFrameLevel()+20);choiceMenu:EnableMouseWheel(true);choiceMenu:EnableMouse(true);choiceMenu:Hide()
 choiceMenu.title=Text(choiceMenu,'',16,-14,14,'text',550)
 choiceMenu.search=EntryFields(choiceMenu,'search','Search by name',16,-42,552)
 choiceMenu.rows={};choiceMenu.range=Text(choiceMenu,'',16,-398,10,'muted',420)
 Button(choiceMenu,'Close',454,-394,130,function() choiceMenu:Hide() end)
 local function DrawChoices()
  local query=choiceMenu.search:GetText():lower()
  choiceMenu.filtered={}
  for _,entry in ipairs(choiceMenu.entries or {}) do
   if entry.label:lower():find(query,1,true) then choiceMenu.filtered[#choiceMenu.filtered+1]=entry end
  end
  choiceMenu.offset=math.min(choiceMenu.offset or 0,math.max(0,#choiceMenu.filtered-9))
  for index,row in ipairs(choiceMenu.rows) do
   row.entry=choiceMenu.filtered[index+choiceMenu.offset]
   row:ClearAllPoints();row:SetPoint('TOPLEFT',8,-(choiceMenu.raidMode and 120 or 82)-(index-1)*29)
   if row.entry then row.label:SetText(choiceMenu.raidMode and row.entry.name or row.entry.label);row:Show() else row:Hide() end
  end
  choiceMenu.range:SetText(#choiceMenu.filtered==0 and 'No matching choices.' or string.format('%d–%d of %d · scroll for more',choiceMenu.offset+1,math.min(choiceMenu.offset+9,#choiceMenu.filtered),#choiceMenu.filtered))
 end
 for index=1,9 do
  local row
  row=Button(choiceMenu,'',8,-82-(index-1)*29,576,function()
   if not row.entry then return end
   local entry=row.entry;choiceMenu:Hide();choiceMenu.choose(entry)
  end);row.label:SetWidth(550);row.label:SetWordWrap(false);choiceMenu.rows[index]=row
 end
 choiceMenu.search:SetScript('OnTextChanged',function() choiceMenu.offset=0;DrawChoices() end)
 choiceMenu:SetScript('OnMouseWheel',function(_,delta) choiceMenu.offset=math.max(0,math.min(math.max(0,#choiceMenu.filtered-9),(choiceMenu.offset or 0)-delta));DrawChoices() end)
 local function OpenChoices(title,entries,choose,raidMode)
  ui.typeMenu:Hide();if ui.customSound then ui.customSound:Hide() end;if ui.iconPicker then ui.iconPicker:Hide() end
  choiceMenu.raidMode=raidMode;choiceMenu.filters[raidMode and 'Show' or 'Hide'](choiceMenu.filters)
  choiceMenu.title:SetText(title);choiceMenu.entries=entries;choiceMenu.choose=choose;choiceMenu.offset=0
  choiceMenu.search:SetText('');DrawChoices();choiceMenu:Show()
 end
 local function InstanceFor(data)
  local entries=Choices.Instances()
  for _,entry in ipairs(entries or {}) do if entry.zoneID==data.zoneID then return entry end end
 end
 local function RefreshSelections()
  local data=ui.draft
  ui.raidButton.label:SetText((ui.instance and ui.instance.name or data.zoneID and (data.raid or 'Saved instance') or 'All raids / dungeons')..'  v')
  ui.bossButton.label:SetText((data.bossID and (data.boss or 'Saved boss') or 'All bosses')..'  v')
  local name=data.difficulty and GetDifficultyInfo and GetDifficultyInfo(data.difficulty)
  ui.difficultyButton.label:SetText((name or (data.difficulty and 'Saved difficulty' or 'Any difficulty'))..'  v')
  ui.iconButton.image:SetTexture(data.icon or 134400)
 end
 local OpenRaidChoices
 choiceMenu.filters=CreateFrame('Frame',nil,choiceMenu);choiceMenu.filters:SetAllPoints(choiceMenu);choiceMenu.filters:Hide()
 choiceMenu.expansion=Button(choiceMenu.filters,'',16,-80,350,function()
  local entries=Choices.Instances();if not entries then return end
  OpenChoices('Choose an expansion',Choices.Tiers(entries),function(entry) ui.raidTier=entry.tier;OpenRaidChoices() end)
 end)
 choiceMenu.expansion.label:SetWordWrap(false)
 choiceMenu.raids=Button(choiceMenu.filters,'Raids',376,-80,96,function() ui.raidKind='raid';OpenRaidChoices() end)
 choiceMenu.dungeons=Button(choiceMenu.filters,'Dungeons',480,-80,104,function() ui.raidKind='party';OpenRaidChoices() end)
 local function ChooseInstance(entry)
  if ui.draft.zoneID~=entry.zoneID then
   ui.draft.bossID=nil;ui.draft.boss='General';ui.draft.difficulty=nil
  end
  ui.instance=entry.zoneID and entry or nil;ui.draft.zoneID=entry.zoneID;ui.draft.raid=entry.name or 'Global';RefreshSelections()
 end
 OpenRaidChoices=function()
  local entries,err=Choices.Instances();if not entries then ui.editorStatus:SetText(err);return end
  local tiers=Choices.Tiers(entries)
  ui.raidTier=ui.raidTier or tiers[1].tier;ui.raidKind=ui.raidKind or 'raid'
  local options={{label='All raids / dungeons',name='All raids / dungeons'}}
  for _,entry in ipairs(Choices.ForTier(entries,ui.raidTier,ui.raidKind)) do options[#options+1]=entry end
  local tierName='Expansion'
  for _,entry in ipairs(tiers) do if entry.tier==ui.raidTier then tierName=entry.label end end
  choiceMenu.expansion.label:SetText(tierName..'  v')
  choiceMenu.raids:SetEnabled(ui.raidKind~='raid');choiceMenu.dungeons:SetEnabled(ui.raidKind~='party')
  OpenChoices(ui.raidKind=='raid' and 'Choose a raid' or 'Choose a dungeon',options,ChooseInstance,true)
 end
 ui.raidButton=Button(editor,'',16,-107,290,OpenRaidChoices)
 ui.bossButton=Button(editor,'',330,-107,290,function()
  if not ui.instance then ui.editorStatus:SetText('Choose a raid or dungeon first. Existing saved boss filters are preserved.');return end
  local entries,err=Choices.Bosses(ui.instance);if not entries then ui.editorStatus:SetText(err);return end
  local options={{label='All bosses'}};for _,entry in ipairs(entries) do options[#options+1]=entry end
  OpenChoices('Choose a boss in '..ui.instance.name,options,function(entry)
   ui.draft.bossID=entry.bossID;ui.draft.boss=entry.name or 'General';RefreshSelections()
  end)
 end)
 ui.difficultyButton=Button(editor,'',264,-155,160,function()
  local options={{label='Any difficulty'}};for _,entry in ipairs(Choices.Difficulties(ui.instance)) do options[#options+1]=entry end
  OpenChoices('Choose a difficulty',options,function(entry) ui.draft.difficulty=entry.value;RefreshSelections() end)
 end)
 for _,button in ipairs({ui.raidButton,ui.bossButton,ui.difficultyButton}) do button.label:SetWordWrap(false) end
 Button(editor,'Use current raid / dungeon',644,-107,330,function()
  local name,kind,_,_,_,_,_,mapID=GetInstanceInfo()
  if not Public(mapID,'number') or (kind~='raid' and kind~='party') then ui.editorStatus:SetText('You are not inside a raid or dungeon.');return end
  local found=InstanceFor({zoneID=mapID})
  if not found then ui.editorStatus:SetText('This instance is not available in the Adventure Guide catalogue.');return end
  if ui.draft.zoneID~=mapID then ui.draft.bossID=nil;ui.draft.boss='General';ui.draft.difficulty=nil end
  ui.instance=found;ui.draft.zoneID=mapID;ui.draft.raid=found.name;RefreshSelections()
 end)
 local iconPicker=Surface('Frame',editor);ui.iconPicker=iconPicker
 iconPicker:SetSize(620,470);iconPicker:SetPoint('CENTER');iconPicker:SetFrameLevel(editor:GetFrameLevel()+20);iconPicker:EnableMouse(true);iconPicker:EnableMouseWheel(true);iconPicker:Hide()
 Text(iconPicker,'Choose an icon',16,-12,16,'text',570)
 iconPicker.spell=EntryFields(iconPicker,'spell','Find an icon using a spell name',16,-44,400)
 iconPicker.status=Text(iconPicker,'',16,-395,11,'accent',570);iconPicker.tiles={}
 local function PickIcon(id) ui.draft.icon=id;iconPicker:Hide();RefreshSelections() end
 local function DrawIcons()
  for index,tile in ipairs(iconPicker.tiles) do
   tile.id=iconPicker.icons[index+iconPicker.offset]
   if tile.id then tile.image:SetTexture(tile.id);tile:Show() else tile:Hide() end
  end
  iconPicker.status:SetText(#iconPicker.icons==0 and 'No icon catalogue available. Use a spell name above.' or string.format('%d–%d of %d · scroll to browse',iconPicker.offset+1,math.min(iconPicker.offset+72,#iconPicker.icons),#iconPicker.icons))
 end
 local function SpellIcon()
  local id,err=Choices.SpellIcon(iconPicker.spell:GetText())
  if id then PickIcon(id) else iconPicker.status:SetText(err) end
 end
 Button(iconPicker,'Use spell icon',440,-61,160,SpellIcon)
 iconPicker.spell:SetScript('OnEnterPressed',SpellIcon)
 for index=1,72 do
  local tile=Surface('Button',iconPicker);tile:SetSize(42,42);tile:SetPoint('TOPLEFT',16+((index-1)%12)*49,-108-math.floor((index-1)/12)*46)
  tile.image=tile:CreateTexture(nil,'ARTWORK');tile.image:SetSize(36,36);tile.image:SetPoint('CENTER')
  tile:SetScript('OnClick',function() if not InCombatLockdown() and tile.id then PickIcon(tile.id) end end);iconPicker.tiles[index]=tile
 end
 local function ScrollIcons(delta) iconPicker.offset=math.max(0,math.min(math.max(0,math.ceil(#iconPicker.icons/72)-1)*72,iconPicker.offset+delta*72));DrawIcons() end
 iconPicker:SetScript('OnMouseWheel',function(_,delta) ScrollIcons(-delta) end)
 Button(iconPicker,'Default icon',16,-424,150,function() PickIcon(nil) end)
 Button(iconPicker,'Previous',180,-424,120,function() ScrollIcons(-1) end)
 Button(iconPicker,'Next',310,-424,120,function() ScrollIcons(1) end)
 Button(iconPicker,'Close',460,-424,140,function() iconPicker:Hide() end)
 ui.iconButton=Button(editor,'Icon  v',140,-155,100,function()
  choiceMenu:Hide();ui.typeMenu:Hide();iconPicker.icons=Choices.Icons();iconPicker.offset=0;DrawIcons();iconPicker:Show()
 end)
 ui.iconButton.label:ClearAllPoints();ui.iconButton.label:SetPoint('LEFT',35,0);ui.iconButton.label:SetWidth(60)
 ui.iconButton.image=ui.iconButton:CreateTexture(nil,'ARTWORK');ui.iconButton.image:SetSize(22,22);ui.iconButton.image:SetPoint('LEFT',5,0)
 ui.display=Button(editor,'Texts',784,-155,190,function()
  local kinds={'Texts','Icons','Bars','Circles','Debuff Overview'}
  for i,kind in ipairs(kinds) do if ui.draft.display==kind then ui.draft.display=kinds[i%#kinds+1];break end end
  ui.display.label:SetText(ui.draft.display)
 end)
 ui.checks={}
 for i,spec in ipairs({{'enabled','Enabled'},{'leaderOnly','Leader only'},{'tanks','Tanks'},{'healers','Healers'},{'countdown','Countdown'},{'sound','Sound'},{'tts','TTS'}}) do
  local key,label=unpack(spec)
  local check=Check(editor,16+(i-1)*138,-198,label,110);ui.checks[key]=check
 end
 Text(editor,'TTS requires the opt-in in Settings > General. Tokens: {counter}, {phase}, {spellID}; raid markers: {rt1}–{rt8} or names such as {triangle}.',16,-231,10,'muted',950)
 ui.triggerInputs={}
 local triggerSpecs={
  {'spellID','Spell ID (message/timer)'},{'text','Text contains (plain text)'},{'phase','Phase (exact)'},{'counter','Occurrence (blank = all)'},
  {'delay','Delay (seconds)'},{'active','Active window (seconds)'},{'remaining','Timer seconds remaining'},{'noteTime','Pull-relative note time'},
  {'unit','Unit (unavailable types)'},{'value','Value (unavailable types)'},{'subevent','Combat log subevent'},{'source','Source name'},
  {'target','Target name'},{'widgetID','Status-bar widget ID'},
 }
 for i,spec in ipairs(triggerSpecs) do
  ui.triggerInputs[spec[1]]=EntryFields(editor,spec[1],spec[2],16+((i-1)%4)*244,-348-math.floor((i-1)/4)*44,218)
 end
 ui.invert=Check(editor,264,-481,'Invert trigger',210)
 Text(editor,'Sound',16,-505,10,'muted',800)
 -- Keep the validated source separate from the visible named selector.
 ui.soundSource=EntryFields(editor,'soundSource','',0,0,950);ui.soundSource:SetMaxLetters(512);ui.soundSource:Hide();ui.soundSource.caption:Hide()
 local sounds={};for _,relative in ipairs(R.SoundPaths()) do
  sounds[#sounds+1]={label=relative:gsub('%.ogg$',''):gsub('/',' / '),value='Interface\\AddOns\\VincRaidTools\\Media\\Sounds\\'..relative:gsub('/','\\')}
 end
 table.sort(sounds,function(a,b) return a.label:lower()<b.label:lower() end)
 local function SoundKey(value) return R.ResolveSoundFile(value):lower():gsub('\\','/') end
 local function SoundName(value)
  if value=='' then return 'Built-in raid warning' end
  for _,entry in ipairs(sounds) do if SoundKey(entry.value)==SoundKey(value) then return entry.label end end
  return tonumber(value) and ('Custom file ID: '..value) or ('Custom: '..(value:match('[^\\/]+$') or value))
 end
 local custom=Surface('Frame',editor);ui.customSound=custom;custom:SetSize(600,190);custom:SetPoint('CENTER');custom:SetFrameLevel(editor:GetFrameLevel()+25);custom:EnableMouse(true);custom:Hide()
 Text(custom,'Custom sound',16,-14,16,'text',560)
 ui.customSoundInput=EntryFields(custom,'customSound','Sound file path or file ID',16,-48,560);ui.customSoundInput:SetMaxLetters(512)
 ui.customSoundStatus=Text(custom,'',16,-100,11,'accent',560)
 Button(custom,'Apply',16,-145,270,function()
  local value=ui.customSoundInput:GetText():match('^%s*(.-)%s*$');local audio,err=R.SoundSource(value)
  if not audio then ui.customSoundStatus:SetText(err);return end
  ui.soundSource:SetText(value);custom:Hide()
 end)
 Button(custom,'Cancel',302,-145,274,function() custom:Hide() end)
 ui.soundButton=Button(editor,'Built-in raid warning  v',16,-522,810,function()
  custom:Hide();local entries={{label='Built-in raid warning',value=''}}
  for _,entry in ipairs(sounds) do entries[#entries+1]=entry end
  local current=ui.soundSource:GetText();if current~='' and SoundName(current):find('^Custom') then entries[#entries+1]={label=SoundName(current),value=current} end
  entries[#entries+1]={label='Custom sound...',custom=true}
  OpenChoices('Choose a sound',entries,function(entry)
   if entry.custom then ui.customSoundInput:SetText(ui.soundSource:GetText());ui.customSoundStatus:SetText('');custom:Show()
   else ui.soundSource:SetText(entry.value) end
  end)
 end)
 ui.soundButton.label:SetWidth(790);ui.soundButton.label:SetWordWrap(false)
 ui.soundSource:SetScript('OnTextChanged',function(self) ui.soundButton.label:SetText(SoundName(self:GetText())..'  v') end)
 ui.previewSound=Button(editor,'Preview sound',840,-522,130,function()
  local audio,err=R.SoundSource(ui.soundSource:GetText());if not audio then ui.editorStatus:SetText(err);return end
  local ok,played
  if audio.soundFile or audio.soundFileID then
   if PlaySoundFile then ok,played=pcall(PlaySoundFile,R.ResolveSoundFile(audio.soundFile or audio.soundFileID),'Master') end
  elseif PlaySound then ok,played=pcall(PlaySound,SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,'Master') end
  if not ok or played==false then ui.editorStatus:SetText('Sound unavailable on this client.') end
 end)
 ui.editorStatus=Text(editor,'',16,-551,11,'accent',950)
 local function ReadInputs()
  local t=ui.draft.triggers[ui.triggerIndex]
  for key,entry in pairs(ui.triggerInputs) do
   local value=entry:GetText():match('^%s*(.-)%s*$')
   if value=='' then t[key]=nil
   elseif ({text=true,phase=true,unit=true,subevent=true,source=true,target=true})[key] then t[key]=value
   else local number=tonumber(value);if not number then return false,key..' must be numeric.' end;t[key]=number end
  end
  t.invert=ui.invert:GetChecked() and true or false
  return true
 end
 local function DrawTrigger()
  local t=ui.draft.triggers[ui.triggerIndex];local def=R.catalogue[t.event]
  ui.triggerTitle:SetText('Trigger '..ui.triggerIndex..' of '..#ui.draft.triggers)
  ui.type.label:SetText(def.name..'  v')
  local help={
   [4]='Health percentage at or below Value; public values only.',[5]='Power percentage at or below Value; public values only.',
   [7]='Matches a boss-mod timer; fires at Remaining seconds plus Delay.',
   [8]='Player raid/party/say/yell chat only. Restricted monster chat events are not registered.',
   [10]='Aura stacks at or above Value (default 1); public aura data only.',
   [13]='Cooldown seconds at or below Value (default 0 = ready); public data only.',
   [15]='Status-bar widget value at or above Value; other widget visualizations are not supported yet.',
   [16]='Fires on a group roster change.',[17]='Count within the public UnitInRange bucket, at or above Value.',
   [19]='Pull-relative time stored here, filtered by this reminder’s Players. Note text is not parsed.',
   [20]='Attackable nameplates within the public interact-distance bucket, at or above Value.',
   [21]='Pull-relative time stored here. Note text is not parsed.',
  }
  local status=def.reason or help[t.event] or 'ALL combines active windows; ANY matches each trigger independently.'
  if R.bossModTriggers and R.bossModTriggers[t.event] and not R.BossMod() then status='Needs DBM or BigWigs. Neither is loaded, so this trigger will not fire.' end
  ui.editorStatus:SetText(status)
  for key,entry in pairs(ui.triggerInputs) do entry:SetText(t[key]~=nil and tostring(t[key]) or '') end
  local perType={
   [1]={'spellID','subevent','source','target'},[2]={'phase'},[3]={},[4]={'unit','value'},[5]={'unit','value'},
   [6]={'spellID','text'},[7]={'spellID','text','remaining'},[8]={'text','source'},[9]={'unit'},
   [10]={'unit','spellID','value'},[11]={'unit','value'},[12]={'unit','target'},[13]={'spellID','value'},
   [14]={'unit','spellID'},[15]={'widgetID','value'},[16]={},[17]={'value'},[18]={'unit','spellID'},
   [19]={'noteTime'},[20]={'value'},[21]={'noteTime'},[22]={},
  }
  for _,entry in pairs(ui.triggerInputs) do entry:Hide();entry.caption:Hide() end
  local visible={'delay','active','counter'}
  for _,key in ipairs(perType[t.event]) do visible[#visible+1]=key end
  for index,key in ipairs(visible) do
   local entry=ui.triggerInputs[key];local x,y=16+((index-1)%4)*244,-348-math.floor((index-1)/4)*44
   entry:ClearAllPoints();entry:SetPoint('TOPLEFT',x+4,y-17)
   entry.caption:ClearAllPoints();entry.caption:SetPoint('TOPLEFT',x,y);entry:Show();entry.caption:Show()
  end
  ui.invert:SetChecked(t.invert);ui.logic.label:SetText(ui.draft.logic..' triggers')
 end
 ui.triggerTitle=Text(editor,'',16,-270,12,'text',200)
 ui.logic=Button(editor,'ALL triggers',225,-263,150,function()
  ui.draft.logic=ui.draft.logic=='ALL' and 'ANY' or 'ALL';DrawTrigger()
 end)
 Button(editor,'Previous',389,-263,120,function()
  local ok,err=ReadInputs();if not ok then ui.editorStatus:SetText(err);return end
  ui.triggerIndex=math.max(1,ui.triggerIndex-1);DrawTrigger()
 end)
 Button(editor,'Next',519,-263,100,function()
  local ok,err=ReadInputs();if not ok then ui.editorStatus:SetText(err);return end
  ui.triggerIndex=math.min(#ui.draft.triggers,ui.triggerIndex+1);DrawTrigger()
 end)
 Button(editor,'Add trigger',629,-263,150,function()
  local ok,err=ReadInputs();if not ok then ui.editorStatus:SetText(err);return end
  if #ui.draft.triggers>=8 then ui.editorStatus:SetText('Maximum eight triggers.');return end
  table.insert(ui.draft.triggers,{event=3,delay=0});ui.triggerIndex=#ui.draft.triggers;DrawTrigger()
 end)
 Button(editor,'Remove trigger',789,-263,181,function()
  if #ui.draft.triggers>1 then table.remove(ui.draft.triggers,ui.triggerIndex);ui.triggerIndex=math.min(ui.triggerIndex,#ui.draft.triggers);DrawTrigger() end
 end)
 local menu=Surface('Frame',editor);ui.typeMenu=menu;menu:SetSize(418,296);menu:SetPoint('TOPLEFT',16,-338);menu:SetFrameLevel(editor:GetFrameLevel()+20);menu:EnableMouseWheel(true);menu:Hide()
 ui.type=Button(editor,'',16,-303,418,function() choiceMenu:Hide();iconPicker:Hide();ui.typeOffset=0;if menu:IsShown() then menu:Hide() else ui.DrawTypes();menu:Show() end end)
 ui.typeRows={}
 function ui.DrawTypes()
  for i,row in ipairs(ui.typeRows) do
   row.event=i+ui.typeOffset;local def=R.catalogue[row.event]
   row.label:SetText(def.name..(def.available and '' or ' (unavailable)'))
  end
 end
 for i=1,9 do
  local row
  row=Button(menu,'',8,-8-(i-1)*31,402,function()
   local ok,err=ReadInputs();if not ok then ui.editorStatus:SetText(err);return end
   ui.draft.triggers[ui.triggerIndex]={event=row.event};menu:Hide();DrawTrigger()
  end);row.label:SetWidth(385);ui.typeRows[i]=row
 end
 menu:SetScript('OnMouseWheel',function(_,delta) ui.typeOffset=math.max(0,math.min(13,ui.typeOffset-delta));ui.DrawTypes() end)
 local function ReadDraft()
  local ok,err=ReadInputs();if not ok then return nil,err end
  local data=R.Copy(ui.draft)
  for key,entry in pairs(ui.inputs) do
   local value=entry:GetText():match('^%s*(.-)%s*$')
   if key=='duration' then
    if value=='' then data[key]=nil
    else data[key]=tonumber(value);if not data[key] then return nil,key..' must be numeric.' end end
   else data[key]=value end
  end
  for key,check in pairs(ui.checks) do data[key]=check:GetChecked() and true or false end
  local audio;audio,err=R.SoundSource(ui.soundSource:GetText():match('^%s*(.-)%s*$'))
  if not audio then return nil,err end
  data.soundFile=audio.soundFile;data.soundFileID=audio.soundFileID
  local valid;valid,err=R.Validate(data);if not valid then return nil,err end;return data
 end
 Button(editor,'Save reminder',16,-573,200,function()
  local data,err=ReadDraft();if not data then ui.editorStatus:SetText(err);return end
  local ok;ok,err=R.Save(data)
  if not ok then ui.editorStatus:SetText(err);return end
  ui.selected=data.uid;editor:Hide();ui.Reveal(data.uid)
 end)
 Button(editor,'Test display',230,-573,170,function()
  local data,err=ReadDraft();if not data then ui.editorStatus:SetText(err);return end
  R.Emit(data,{},true)
 end)
 -- Test panel: load the saved reminder ignoring its filters, then let real
 -- boss-mod events fire it or activate its triggers by hand.
 local tester=Surface('Frame',editor);ui.tester=tester
 tester:SetSize(620,470);tester:SetPoint('CENTER');tester:SetFrameLevel(editor:GetFrameLevel()+20);tester:EnableMouse(true);tester:Hide()
 Text(tester,'Test reminder',16,-12,16,'text',580)
 Text(tester,'Load reminder uses the last saved version and ignores its raid, boss, difficulty and player filters until you unload it or /reload. Real boss-mod events, such as DBM test bars, can then fire it; or activate triggers below. Leader only still applies.',16,-40,11,'muted',588)
 tester.rows={}
 tester.status=Text(tester,'',16,-400,11,'accent',588)
 function ui.DrawTester()
  if not tester:IsShown() then return end
  local db=R.Store();local saved=db and db.global[ui.draft.uid]
  local entry=R.forced[ui.draft.uid] and R.active[ui.draft.uid]
  tester.load.label:SetText(entry and 'Loaded for testing' or 'Load reminder')
  tester.load:SetEnabled(not entry);tester.unload:SetEnabled(entry and true or false)
  for i,row in ipairs(tester.rows) do
   local t=entry and entry.data.triggers[i]
   if t then
    local name=R.catalogue[t.event].name
    if R.stateEvents[t.event] then
     row.label:SetText((entry.states[i] and 'Deactivate' or 'Activate')..' trigger '..i..': '..name..(entry.states[i] and '  (ON)' or '  (OFF)'))
    else row.label:SetText('Activate trigger '..i..': '..name..'  (fires once'..((entry.counts[i] or 0)>0 and ', '..entry.counts[i]..' so far)' or ')')) end
    row:Show()
   else row:Hide() end
  end
  local notes={}
  if not saved then notes[#notes+1]='Save the reminder before testing.' end
  if saved and saved.leaderOnly and not (IsInRaid() and UnitIsGroupLeader('player')) then notes[#notes+1]='Leader only: output appears only while you are raid leader.' end
  if saved and (saved.tanks or saved.healers) then notes[#notes+1]='Role filter: shown for '..((saved.tanks and saved.healers) and 'tanks and healers' or (saved.tanks and 'tanks' or 'healers'))..(saved.players and saved.players~='' and ' and the named players' or '')..'.' end
  if entry and #entry.data.triggers>1 and entry.data.logic=='ALL' then notes[#notes+1]='ALL needs triggers active together; set an Active window to combine pulses.' end
  tester.status:SetText(ui.testStatus or table.concat(notes,' '))
 end
 local function TestNotice(ok,err) ui.testStatus=not ok and err or nil;ui.DrawTester() end
 tester.load=Button(tester,'Load reminder',16,-100,290,function() TestNotice(R.LoadForTest(ui.draft.uid));ui.Refresh() end)
 tester.unload=Button(tester,'Unload',316,-100,288,function() R.UnloadTest(ui.draft.uid);TestNotice(true);ui.Refresh() end)
 for i=1,8 do
  tester.rows[i]=Button(tester,'',16,-140-(i-1)*32,588,function()
   local entry=R.active[ui.draft.uid]
   TestNotice(R.TestTrigger(ui.draft.uid,i,not (entry and entry.states[i])))
  end)
  tester.rows[i].label:SetWordWrap(false);tester.rows[i]:Hide()
 end
 Button(tester,'Close',454,-428,150,function() tester:Hide() end)
 Button(editor,'Test triggers',414,-573,170,function()
  menu:Hide();choiceMenu:Hide();iconPicker:Hide();ui.testStatus=nil;tester:Show();ui.DrawTester()
 end)
 Button(editor,'Cancel',804,-573,170,function() editor:Hide() end)
 editor:SetScript('OnHide',function() menu:Hide();choiceMenu:Hide();iconPicker:Hide();tester:Hide();custom:Hide() end)
 function ui.Edit(data)
  if InCombatLockdown() or R.encounter then Notice(false,'Edit outside combat and encounters.');return end
  if not data then Notice(false,'Select a reminder first.');return end
  ui.draft=R.Copy(data);ui.triggerIndex=1
  ui.instance=InstanceFor(data);ui.raidTier=ui.instance and ui.instance.tier;ui.raidKind=ui.instance and ui.instance.kind or 'raid';RefreshSelections()
  for key,entry in pairs(ui.inputs) do entry:SetText(data[key]~=nil and tostring(data[key]) or '') end
  for key,check in pairs(ui.checks) do check:SetChecked(data[key]) end
  ui.soundSource:SetText(data.soundFile or (data.soundFileID and tostring(data.soundFileID)) or '')
  ui.display.label:SetText(data.display);DrawTrigger();editor:Show()
 end
 local transfer=Surface('Frame',window);ui.transfer=transfer;transfer:SetSize(840,470);transfer:SetPoint('CENTER');transfer:SetFrameLevel(window:GetFrameLevel()+40);transfer:EnableMouse(true);transfer:Hide()
 ui.transferTitle=Text(transfer,'',16,-16,17,'text',800)
 local scroll=Surface('ScrollFrame',transfer,'background');ui.transferScroll=scroll;scroll:SetPoint('TOPLEFT',18,-55);scroll:SetSize(782,310);scroll:EnableMouseWheel(true)
 local payload=CreateFrame('EditBox',nil,scroll);ui.payload=payload;payload:SetSize(775,310);payload:SetMultiLine(true);payload:SetAutoFocus(false);payload:SetMaxLetters(90010);payload:SetFont(STANDARD_TEXT_FONT,12,'');scroll:SetScrollChild(payload)
 payload:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 local function ScrollPayload(value)
  ui.payloadOffset=math.max(0,math.min(math.max(0,payload:GetHeight()-310),value));scroll:SetVerticalScroll(ui.payloadOffset)
 end
 payload:SetScript('OnTextChanged',function(self) self:SetHeight(math.max(310,(self:GetNumLines() or 1)*14+20));ScrollPayload(ui.payloadOffset or 0) end)
 scroll:SetScript('OnMouseWheel',function(_,delta) ScrollPayload((ui.payloadOffset or 0)-delta*42) end)
 ui.scrollUp=Button(transfer,'Up',804,-55,28,function() ScrollPayload((ui.payloadOffset or 0)-126) end)
 ui.scrollDown=Button(transfer,'Dn',804,-337,28,function() ScrollPayload((ui.payloadOffset or 0)+126) end)
 for _,button in ipairs({ui.scrollUp,ui.scrollDown}) do button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(28);button.label:SetJustifyH('CENTER');button.label:SetFont(STANDARD_TEXT_FONT,11,'') end
 ui.target=EntryFields(transfer,'target','Recipient: Player-Realm, or RAID',16,-377,370)
 ui.target:SetText('RAID')
 ui.transferStatus=Text(transfer,'',16,-434,11,'accent',800)
 local function Selected()
  local db=R.Store();return db and ui.selected and db.global[ui.selected]
 end
 local function Records(all)
  local db=R.Store();if not db then return {} end
  if not all and Selected() then return {R.Copy(Selected())} end
  local records={};for _,data in pairs(db.global) do records[#records+1]=R.Copy(data) end;return records
 end
 ui.transferApply=Button(transfer,'Apply / send',420,-388,200,function()
  if ui.transferMode=='import' then
   local text=payload:GetText():gsub('^VRT1:','');local pack,err=S.Decode(text)
   if not pack then ui.transferStatus:SetText(err);return end
   local ok;ok,err=S.Apply({pack=pack,sender='local import'})
   if ok then transfer:Hide();ui.Refresh() else ui.transferStatus:SetText(err) end
  elseif ui.transferMode=='send' then
   local ok,err=S.Send(ui.sendRecords,ui.target:GetText())
   if ok then transfer:Hide();ui.Refresh() else ui.transferStatus:SetText(err) end
  end
 end)
 Button(transfer,'Close',640,-388,180,function() transfer:Hide() end)
 local function Transfer(mode,scope,scopeName)
  if InCombatLockdown() or R.encounter then Notice(false,'Transfer outside combat and encounters.');return end
  ui.transferApply:SetShown(mode~='export');ui.target:SetShown(mode=='send');ui.target.caption:SetShown(mode=='send');payload:SetMaxLetters(90010)
  ui.transferMode=mode;ui.transferStatus:SetText('');ui.transferTitle:SetText(mode=='import' and 'Import VRT reminder pack' or mode=='send' and ('Send: '..(scopeName or 'selected reminder')) or 'Export VRT reminder pack')
  if mode=='import' then payload:SetText('VRT1:') else
   local records={};for _,data in ipairs(scope or Records()) do records[#records+1]=R.Copy(data) end;if #records==0 then Notice(false,'Add a reminder before sending or exporting.');return end
   local encoded,err=S.Pack(records)
   if not encoded then Notice(false,err);return end
   payload:SetText('VRT1:'..encoded);ui.sendRecords=records
   if mode=='send' then ui.transferStatus:SetText(#records..' reminder(s), including disabled copies. Enter RAID or Player-Realm, then Apply / send.') end
  end
  ScrollPayload(0);transfer:Show();payload:HighlightText()
 end
 local function HideTip(owner)
  if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==owner then GameTooltip:Hide() end
 end
 local function Tip(owner,data,action)
  if not GameTooltip or not data then return end
  GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');GameTooltip:SetText(data.name,1,1,1)
  GameTooltip:AddLine((data.enabled==false and 'Disabled' or 'Enabled')..' · '..data.display,0.8,0.8,0.8)
  if R.forced[data.uid] then GameTooltip:AddLine('Loaded for testing',0.72,0.76,0.81) end
  local unavailable=R.Unavailable(data);if unavailable then GameTooltip:AddLine(unavailable,1,0.65,0.3,true) end
  if action then GameTooltip:AddLine(action,0.72,0.76,0.81) end
  GameTooltip:Show()
 end
 local function StyleHeader(row)
  if not row.entry or not row.entry.header then return end
  local open=not ui.collapsed[row.entry.key]
  row:SetBackdropColor(unpack(row.hovered and {0.20,0.24,0.29,1} or row.entry.depth==0 and H.colours.raised or H.colours.panel))
  if row.hovered then row:SetBackdropBorderColor(unpack(H.colours.highlight))
  else row:SetBackdropBorderColor(0.72,0.76,0.81,open and 0.7 or 0.35) end
 end
 local function StyleCard(card)
  if not card.data then return end
  local disabled=card.data.enabled==false
  card.selected=ui.selected==card.data.uid
  card:SetBackdropColor(unpack(disabled and (card.hovered and {0.34,0.10,0.12,1} or {0.20,0.065,0.08,1}) or
   (card.hovered and {0.09,0.30,0.16,1} or {0.055,0.18,0.10,1})))
  if card.selected then card:SetBackdropBorderColor(unpack(H.colours.highlight));card.selection:Show()
  else card.selection:Hide();card:SetBackdropBorderColor(unpack(card.hovered and {0.8,0.85,0.9,1} or {0.22,0.27,0.3,1})) end
  card.label:SetTextColor(unpack(H.colours.text))
 end
 local function HoverCard(card,on,owner,action)
  card.hovered=on;StyleCard(card)
  if on then Tip(owner,card.data,action) else HideTip(owner) end
 end
 local function InlineAction(card,label,x,width,action,hint)
  local button=Button(card,label,x,0,width,action);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(width);button.label:SetJustifyH('CENTER');button.label:SetFont(STANDARD_TEXT_FONT,10,'')
  button:SetScript('OnEnter',function(self) self:SetBackdropColor(0.22,0.27,0.31,1);HoverCard(card,true,self,hint()) end)
  button:SetScript('OnLeave',function(self) self:SetBackdropColor(unpack(H.colours.raised));HideTip(self);card.hovered=card.IsMouseOver and card:IsMouseOver() or false;StyleCard(card) end)
  button:SetScript('OnHide',function(self) HideTip(self) end)
  return button
 end
 for i=1,ROWS do
  local row=Button(list,'',8,-8-(i-1)*33,848,function() end);ui.rows[i]=row;row.cards={}
  row.label:SetWidth(715)
  row.send=Button(row,'Send',738,0,100,function()
   if row.entry and row.entry.header then Transfer('send',row.entry.records,row.entry.name) end
  end)
  row.send:SetScript('OnEnter',function(self) self:SetBackdropColor(0.22,0.27,0.31,1);row.hovered=true;StyleHeader(row) end)
  row.send:SetScript('OnLeave',function(self) self:SetBackdropColor(unpack(H.colours.raised));row.hovered=row:IsMouseOver();StyleHeader(row) end)
  row:SetScript('OnEnter',function(self) self.hovered=true;StyleHeader(self) end)
  row:SetScript('OnLeave',function(self) self.hovered=false;StyleHeader(self) end)
  row:SetScript('OnHide',function(self) self.hovered=false end)
  for column=1,3 do
   local card=Button(row,'',20+(column-1)*276,0,270,function() end);row.cards[column]=card
   card.label:SetWidth(188);card.label:SetWordWrap(false);card.label:SetTextColor(unpack(H.colours.text))
   card.selection=card:CreateTexture(nil,'OVERLAY');card.selection:SetColorTexture(unpack(H.colours.highlight));card.selection:SetSize(3,24);card.selection:SetPoint('LEFT',1,0);card.selection:Hide()
   card:SetScript('OnClick',function(self)
    if InCombatLockdown() or not self.data then return end
    if ui.selected==self.data.uid then ui.selected=nil else ui.selected=self.data.uid end;ui.Refresh()
   end)
   card:SetScript('OnEnter',function(self) HoverCard(self,true,self,'Click to select; use Edit or On/Off.') end)
   card:SetScript('OnLeave',function(self) HoverCard(self,false,self) end)
   card:SetScript('OnHide',function(self) self.hovered=false;HideTip(self) end)
   card.edit=InlineAction(card,'Edit',202,34,function()
    if InCombatLockdown() or not card.data then return end
    ui.selected=card.data.uid;ui.Refresh();ui.Edit(card.data)
   end,function() return 'Edit this reminder' end)
   card.toggle=InlineAction(card,'On',240,26,function()
    if not card.data then return end
    if InCombatLockdown() or R.encounter then Notice(false,'Change reminder status outside combat and encounters.');return end
    local db=R.Store();local current=db and db.global[card.data.uid];if not current then return end
    local data=R.Copy(current);data.enabled=current.enabled==false
    local ok,err=R.Save(data);if not ok then Notice(false,err);return end
    if not data.enabled then R.UnloadTest(data.uid) end
    ui.selected=data.uid;ui.Refresh()
   end,function() return card.data and card.data.enabled==false and 'Enable this reminder' or 'Disable this reminder' end)
  end
 end
 list:SetScript('OnMouseWheel',function(_,delta) ui.offset=math.max(0,math.min(math.max(0,#ui.entries-ROWS),ui.offset-delta));ui.Refresh() end)
 Button(page,'Add',0,-556,84,function() local data,err=R.New();if data then ui.Edit(data) else Notice(false,err) end end)
 Button(page,'Edit',94,-556,84,function() ui.Edit(Selected()) end)
 Button(page,'Delete',188,-556,84,function()
  local data=Selected();if not data then Notice(false,'Select a reminder first.');return end
  StaticPopupDialogs.VRT_DELETE_REMINDER={text='Delete this VRT reminder?',button1='Delete',button2='Cancel',timeout=0,whileDead=true,hideOnEscape=true,
   OnAccept=function() Notice(R.Remove(data.uid));ui.selected=nil;ui.Refresh() end}
  StaticPopup_Show('VRT_DELETE_REMINDER')
 end)
 Button(page,'Preview alerts',282,-556,124,function() Notice(D.StartPreview()) end)
 ui.sendSelected=Button(page,'Send selected',434,-556,110,function()
  local data=Selected();if not data then Notice(false,'Select a reminder first, or use Send all.');return end
  Transfer('send',{data},data.name)
 end)
 Button(page,'Import pack',654,-556,110,function() Transfer('import') end)
 Button(page,'Export',774,-556,90,function() Transfer('export') end)
 ui.accept=Button(page,'Accept',618,-592,118,function() local ok,err=S.Accept(1);Notice(ok,err);ui.Refresh() end)
 ui.decline=Button(page,'Decline',746,-592,118,function() S.Decline(1);ui.Refresh() end)
 ui.sendAll=Button(page,'Send all',554,-556,90,function() Transfer('send',Records(true),'all reminders') end)
 function ui.Refresh()
  local db,err=R.Store();if not db then ui.status:SetText(err);return end
  local sorted={};for _,data in pairs(db.global) do sorted[#sorted+1]=data end
  local groups=Choices.LibraryGroups(sorted,Choices.LibraryCatalogue(sorted))
  local entries={}
  for _,group in ipairs(groups) do
   if ui.collapsed[group.key]==nil then ui.collapsed[group.key]=true end
   local groupRecords={};for _,boss in ipairs(group.bosses) do for _,data in ipairs(boss.records) do groupRecords[#groupRecords+1]=data end end
   entries[#entries+1]={header=true,key=group.key,name=group.name,depth=0,records=groupRecords}
   if not ui.collapsed[group.key] then
    for _,boss in ipairs(group.bosses) do
     if ui.collapsed[boss.key]==nil then ui.collapsed[boss.key]=true end
     entries[#entries+1]={header=true,key=boss.key,name=boss.name,depth=1,records=boss.records}
     if not ui.collapsed[boss.key] then
      for first=1,#boss.records,3 do
       local cards={};for index=first,math.min(first+2,#boss.records) do cards[#cards+1]=boss.records[index] end
       entries[#entries+1]={cards=cards,depth=2}
      end
     end
    end
   end
  end
  ui.groups=groups
  ui.entries=entries;ui.offset=math.min(ui.offset,math.max(0,#entries-ROWS))
  for i,row in ipairs(ui.rows) do
   local entry=entries[i+ui.offset];row.entry=entry
   if not entry then
    row:Hide();row.send:Hide();for _,card in ipairs(row.cards) do card.data=nil;card:Hide() end
   else
    row:Show();row:EnableMouse(entry.header and true or false)
    if entry.header then
     row.send:Show();row.label:Show();row.label:ClearAllPoints();row.label:SetPoint('LEFT',10+entry.depth*20,0);row.label:SetWidth(715-entry.depth*20)
     row.label:SetText((ui.collapsed[entry.key] and '+  ' or '-  ')..entry.name);StyleHeader(row)
     for _,card in ipairs(row.cards) do card.data=nil;card:Hide() end
    else
     row.send:Hide();row.label:Hide();row:SetBackdropColor(0,0,0,0);row:SetBackdropBorderColor(0,0,0,0)
     for column,card in ipairs(row.cards) do
      card.data=entry.cards[column]
      if card.data then
       card:Show();card.label:SetText(card.data.name);card.toggle.label:SetText(card.data.enabled==false and 'On' or 'Off');StyleCard(card)
      else card:Hide() end
     end
    end
   end
  end
  ui.summary:SetText(#sorted..' global reminder(s). Send all sends everything; Send on a raid/boss header sends that group; select one for Send selected.')
  if #sorted==0 then ui.summary:SetText('No VRT reminders yet. Add a reminder or import a VRT pack.') end
  ui.RefreshProgress()
  if ui.DrawTester then ui.DrawTester() end
  local request=S.pending[1]
  if request then ui.pending:SetText(#request.pack.reminders..' reminder(s) from '..request.sender..' ('..#S.pending..' pack(s) pending)');ui.accept:Show();ui.decline:Show()
  else ui.pending:SetText('Trusted senders (Settings > Sync) apply automatically. Others: accept or decline here.');ui.accept:Hide();ui.decline:Hide() end
 end
 function ui.Reveal(uid)
  ui.Refresh()
  for _,group in ipairs(ui.groups) do
   for _,boss in ipairs(group.bosses) do
    for _,data in ipairs(boss.records) do
     if data.uid==uid then ui.collapsed[group.key]=false;ui.collapsed[boss.key]=false end
    end
   end
  end
  ui.Refresh()
  for index,entry in ipairs(ui.entries) do for _,data in ipairs(entry.cards or {}) do if data.uid==uid then ui.offset=math.max(0,index-ROWS) end end end
  ui.Refresh()
 end
 addon.RefreshRemindersPage=ui.Refresh
 addon.CloseReminderEditor=function() editor:Hide();transfer:Hide() end
 page:SetScript('OnHide',function() editor:Hide();transfer:Hide() end)
 -- Raid and boss headers only change expansion; cards own reminder selection.
 for _,row in ipairs(ui.rows) do
  row:SetScript('OnClick',function()
   if InCombatLockdown() or not row.entry or not row.entry.header then return end
   ui.collapsed[row.entry.key]=not ui.collapsed[row.entry.key]
   ui.Refresh()
  end)
 end
 ui.Refresh()
end
