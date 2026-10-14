local _, addon = ...
local function Now() return addon.Now and addon.Now() or (time and time() or 0) end

-- Native VRT text-note library.
local N={};addon.NativeNotes=N
local function Copy(value)
 if type(value)~='table' then return value end
 local result={};for k,v in pairs(value) do result[k]=Copy(v) end;return result
end
local function Ready()
 return not InCombatLockdown() and not (addon.Reminders and addon.Reminders.encounter)
end
function N.Store()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if db.notes==nil then db.notes={schema=1,items={},serial=0} end
 if type(db.notes)~='table' or db.notes.schema~=1 or type(db.notes.items)~='table' or type(db.notes.serial)~='number' or db.notes.serial~=db.notes.serial or db.notes.serial<0 or db.notes.serial%1~=0 or db.notes.serial>1e9 then return nil,'VRT note storage needs review.' end
 -- Sync identity: give older notes a global uid and a version time once.
 for _,entry in ipairs(db.notes.items) do
  if type(entry)=='table' then
   if not (addon.ValidUID and addon.ValidUID(entry.uid)) and addon.NewUID then entry.uid=addon.NewUID('note') end
   if type(entry.updatedAt)~='number' then entry.updatedAt=type(entry.createdAt)=='number' and entry.createdAt or 0 end
  end
 end
 return db.notes
end
local function ValidBoss(boss)
 return boss==nil or type(boss)=='number' and boss==boss and boss>0 and boss<=1000000 and boss%1==0
end
function N.Find(id)
 local store=N.Store();if not store then return end
 for _,entry in ipairs(store.items) do if entry.id==id then return entry end end
end
function N.Save(id,name,text,bossID)
 if not Ready() then return false,'Edit outside combat and encounters.' end
 if type(name)~='string' or name=='' or #name>240 or type(text)~='string' or #text>200000 then return false,'Use a title and text of at most 200 KB.' end
 if bossID~=false and not ValidBoss(bossID) then return false,'Choose a valid boss.' end
 local store,err=N.Store();if not store then return false,err end
 local bytes=0;local selected
 for i,entry in ipairs(store.items) do if entry.id==id then selected=i else bytes=bytes+#entry.text end end
 if id and not selected then return false,'Selected VRT note no longer exists.' end
 if not selected and #store.items>=500 then return false,'VRT library would exceed 500 notes.' end
 if bytes+#text>4000000 then return false,'VRT library would exceed 4 MB.' end
 local entry=selected and Copy(store.items[selected]) or {}
 if not selected then store.serial=store.serial+1;entry.id='VRT-note-'..store.serial;entry.createdAt=Now() end
 if not (addon.ValidUID and addon.ValidUID(entry.uid)) and addon.NewUID then entry.uid=addon.NewUID('note') end
 entry.name=name;entry.text=text
 if bossID~=nil then entry.bossID=bossID~=false and bossID or nil end
 entry.updatedAt=math.max(Now(),(entry.updatedAt or 0)+1)
 if selected then store.items[selected]=entry else store.items[#store.items+1]=entry end
 if addon.SyncChanged then addon.SyncChanged('notes') end
 return true,'Saved VRT note.',entry.id
end
function N.Delete(id)
 if not Ready() then return false,'Delete outside combat and encounters.' end
 local store,err=N.Store();if not store then return false,err end
 for i,entry in ipairs(store.items) do if entry.id==id then
  table.remove(store.items,i)
  if addon.MarkDeleted then addon.MarkDeleted('notes',entry.uid) end
  local db=VincibilityRaidToolsDB
  if db.nativeStartingNoteID==id then db.nativeStartingNoteID=nil end
  if addon.SyncChanged then addon.SyncChanged('notes') end
  return true,'Deleted VRT note.'
 end end
 return false,'Selected VRT note no longer exists.'
end
function N.ListLayout()
 local rows=16
 return rows,-60,rows*29+16
end
function addon.BuildNativeNotesPage(page,window,H)
 local Text,Button,Surface=H.Text,H.Button,H.Surface
 local visibleRows,listTop,listHeight=N.ListLayout()
 local ui={rows={},offset=0};window.nativeNotes=ui
 Text(page,'VRT text notes. Choose a starting note in Settings; boss notes open in their rooms.',0,-27,12,'muted',850)
 -- Status and summary sit at the bottom, under the buttons.
 ui.status=Text(page,'',0,0,11,'accent',600);ui.status:ClearAllPoints();ui.status:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-4)
 ui.summary=Text(page,'',0,0,10,'muted',850);ui.summary:ClearAllPoints();ui.summary:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-20)
 ui.pendingText=Text(page,'',0,-458,11,'accent',590)
 local list=Surface('Frame',page);ui.list=list;list:SetPoint('TOPLEFT',0,listTop);list:SetSize(864,listHeight);list:EnableMouseWheel(true)
 local editor=Surface('Frame',window);ui.editor=editor;editor:SetSize(950,540);editor:SetPoint('CENTER');editor:SetFrameLevel(window:GetFrameLevel()+40);editor:EnableMouse(true);editor:Hide()
 Text(editor,'VRT text-note editor',16,-12,17,'text',900)
 Text(editor,'Edit the note text and its boss assignment here.',16,-40,11,'muted',900)
 local titlePanel=Surface('Frame',editor,'background');titlePanel:SetSize(916,28);titlePanel:SetPoint('TOPLEFT',18,-66)
 ui.title=CreateFrame('EditBox',nil,titlePanel);ui.title:SetSize(896,24);ui.title:SetPoint('LEFT',8,0)
 ui.title:SetAutoFocus(false);ui.title:SetMaxLetters(240);ui.title:SetFont(STANDARD_TEXT_FONT,13,'');ui.title:SetTextColor(.91,.918,.941)
 ui.title:EnableMouse(true)
 ui.title:SetScript('OnEditFocusGained',function() titlePanel:SetBackdropBorderColor(.78,.11,.25,1) end)
 ui.title:SetScript('OnEditFocusLost',function() titlePanel:SetBackdropBorderColor(.18,.196,.235,1) end)
 ui.title:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 -- Boss picker: No boss, then Raids/Dungeons > expansion > instance > boss from
 -- the Adventure Guide. Current-raid presets keep their established names and
 -- are the fallback when guide data is unavailable.
 local bossMaps=addon.NativeVisualNotes and addon.NativeVisualNotes.bossMaps or {}
 local presetNames,knownNames={},{}
 for _,spec in ipairs(bossMaps) do presetNames[spec[6]]=spec[1] end
 local function BossName(id)
  if not id then return 'No boss' end
  if presetNames[id] or knownNames[id] then return presetNames[id] or knownNames[id] end
  local index=addon.ReminderChoices and addon.ReminderChoices.libraryIndex
  local boss=index and index.bosses and index.bosses[id]
  if boss and boss.instance then return boss.instance.name..': '..boss.name end
  return 'Boss ID '..id
 end
 local visibleBossRows=12
 local bossMenu=Surface('Frame',editor);ui.bossMenu=bossMenu
 bossMenu:SetSize(420,34+visibleBossRows*29);bossMenu:SetPoint('TOPLEFT',18,-132);bossMenu:SetFrameLevel(editor:GetFrameLevel()+10)
 bossMenu:EnableMouse(true);bossMenu:EnableMouseWheel(true);bossMenu:Hide()
 ui.bossPath=Text(bossMenu,'',10,-12-visibleBossRows*29,10,'muted',400)
 local bossItems,bossStack,bossRows,bossOffset={},{},{},0
 local function RootItems()
  local items={{label='No boss',boss=false}}
  local catalogue=addon.ReminderChoices
  local instances=catalogue and catalogue.Instances()
  if instances then
   for _,group in ipairs({{'raid','Raids'},{'party','Dungeons'}}) do
    local expansions,byTier={},{}
    for _,instance in ipairs(instances) do
     if instance.kind==group[1] then
      local expansion=byTier[instance.tier]
      if not expansion then expansion={label=instance.tierName,items={}};byTier[instance.tier]=expansion;expansions[#expansions+1]=expansion end
      expansion.items[#expansion.items+1]={label=instance.name,load=function()
       local bosses,err=catalogue.Bosses(instance);if not bosses then return nil,err end
       local list={}
       for _,boss in ipairs(bosses) do
        list[#list+1]={label=boss.name,boss=boss.bossID,full=presetNames[boss.bossID] or instance.name..': '..boss.name}
       end
       return list
      end}
     end
    end
    if #expansions>0 then items[#items+1]={label=group[2],items=expansions} end
   end
  else
   local raids,byRaid={},{}
   for _,spec in ipairs(bossMaps) do
    local raid,boss=spec[1]:match('^([^:]+):%s*(.+)$')
    raid=raid or 'Other';boss=boss or spec[1]
    if not byRaid[raid] then byRaid[raid]={label=raid,items={}};raids[#raids+1]=byRaid[raid] end
    byRaid[raid].items[#byRaid[raid].items+1]={label=(boss:gsub('^%l',string.upper)),boss=spec[6],full=spec[1]}
   end
   if #raids>0 then items[#items+1]={label='Raids',items=raids} end
  end
  return items
 end
 local function DrawBossMenu()
  local list={}
  if #bossStack>0 then list[1]={label='<  Back',back=true} end
  for _,item in ipairs(#bossStack>0 and bossStack[#bossStack].items or bossItems) do list[#list+1]=item end
  bossOffset=math.max(0,math.min(bossOffset,#list-visibleBossRows))
  for index,row in ipairs(bossRows) do
   local item=list[index+bossOffset];row.entry=item
   if item then row.label:SetText(item.label..((item.items or item.load) and '  >' or ''));row:Show() else row:Hide() end
  end
  local path={};for _,item in ipairs(bossStack) do path[#path+1]=item.label end
  ui.bossPath:SetText(table.concat(path,' > '))
 end
 local function ChooseBoss(id,name)
  ui.bossID=id;ui.bossButton.label:SetText('Boss: '..name..'  v');bossMenu:Hide()
 end
 for index=1,visibleBossRows do
  local row;row=Button(bossMenu,'',5,-5-(index-1)*29,410,function()
   local item=row.entry
   if not item then return end
   if item.back then bossStack[#bossStack]=nil;bossOffset=0;DrawBossMenu();return end
   if item.items or item.load then
    if not item.items then
     local loaded,err=item.load()
     if not loaded then ui.bossPath:SetText(err or 'Boss data is unavailable.');return end
     item.items=loaded
    end
    bossStack[#bossStack+1]=item;bossOffset=0;DrawBossMenu();return
   end
   if item.boss then knownNames[item.boss]=item.full end
   ChooseBoss(item.boss,item.boss and (item.full or item.label) or 'No boss')
  end)
  row.label:SetWidth(390);row.label:SetWordWrap(false);bossRows[index]=row;ui.bossRows=bossRows
 end
 bossMenu:SetScript('OnMouseWheel',function(_,delta) bossOffset=bossOffset-delta;DrawBossMenu() end)
 ui.bossButton=Button(editor,'Boss: No boss  v',18,-102,420,function()
  if bossMenu:IsShown() then bossMenu:Hide();return end
  bossItems=RootItems();bossStack={};bossOffset=0;DrawBossMenu();bossMenu:Show()
 end)
 Text(editor,'Note body — click to edit',20,-136,11,'muted',360)
 local bodyPanel=Surface('Frame',editor,'background');bodyPanel:SetPoint('TOPLEFT',18,-186);bodyPanel:SetSize(916,274)
 local scroll=CreateFrame('ScrollFrame',nil,bodyPanel,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',8,-8);scroll:SetPoint('BOTTOMRIGHT',-21,8)
 if addon.StyleScrollBar then addon.StyleScrollBar(scroll) end
 ui.text=CreateFrame('EditBox',nil,scroll,'BackdropTemplate');ui.text:SetSize(887,258);scroll:SetScrollChild(ui.text)
 ui.text:SetMultiLine(true);ui.text:SetAutoFocus(false);ui.text:SetMaxLetters(200000)
 ui.text:SetFont(STANDARD_TEXT_FONT,13,'');ui.text:SetTextColor(.91,.918,.941);ui.text:SetJustifyH('LEFT');ui.text:SetJustifyV('TOP');ui.text:SetTextInsets(4,4,4,4)
 ui.text:EnableMouse(true);scroll:EnableMouse(true)
 scroll:SetScript('OnSizeChanged',function(self) ui.text:SetSize(self:GetSize()) end)
 local emptyFocus=CreateFrame('Button',nil,bodyPanel);ui.emptyTextFocus=emptyFocus
 emptyFocus:SetPoint('TOPLEFT',scroll);emptyFocus:SetPoint('BOTTOMRIGHT',scroll);emptyFocus:SetFrameLevel(scroll:GetFrameLevel()+5)
 local emptyHint=emptyFocus:CreateFontString(nil,'OVERLAY');emptyHint:SetFont(STANDARD_TEXT_FONT,13,'')
 emptyHint:SetTextColor(.541,.561,.612);emptyHint:SetPoint('TOPLEFT',8,-8);emptyHint:SetText('Click anywhere to start typing')
 emptyFocus:SetScript('OnClick',function(self) self:Hide();ui.text:SetFocus();ui.text:SetCursorPosition(0) end)
 ui.text:SetScript('OnEditFocusGained',function() emptyFocus:Hide();bodyPanel:SetBackdropBorderColor(.78,.11,.25,1) end)
 ui.text:SetScript('OnEditFocusLost',function(self) if self:GetText()=='' then emptyFocus:Show() end;bodyPanel:SetBackdropBorderColor(.18,.196,.235,1) end)
 ui.text:SetScript('OnCursorChanged',ScrollingEdit_OnCursorChanged)
 ui.text:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 local function Selection()
  local text=ui.text:GetText();local cursor=ui.text:GetCursorPosition()
  ui.text:Insert('')
  local changed=ui.text:GetText();local first=ui.text:GetCursorPosition()
  local last=#text-(#changed-first)
  ui.text:SetText(text);ui.text:SetCursorPosition(cursor)
  return text,first,last
 end
 local function ReplaceSelection(prefix,suffix,keepSelection)
  local text,first,last=Selection();suffix=suffix or ''
  local selected=text:sub(first+1,last)
  ui.text:SetText(text:sub(1,first)..prefix..selected..suffix..text:sub(last+1))
  if keepSelection and first~=last then
   ui.text:HighlightText(first+#prefix,last+#prefix)
  else
   ui.text:SetCursorPosition(first+#prefix+(first==last and 0 or #selected+#suffix))
  end
  ui.text:SetFocus()
 end
 local function InsertToken(token)
  local text,first,last=Selection()
  ui.text:SetText(text:sub(1,first)..token..text:sub(last+1))
  ui.text:SetCursorPosition(first+#token);ui.text:SetFocus()
 end
 ui.markerButtons={};ui.colourButtons={}
 Text(editor,'Markers',20,-162,10,'muted',50)
 local markerNames={'star','circle','diamond','triangle','moon','square','cross','skull'}
 for index,name in ipairs(markerNames) do
  local button=Surface('Button',editor,'raised');button:SetSize(21,21);button:SetPoint('TOPLEFT',72+(index-1)*24,-155)
  local icon=button:CreateTexture(nil,'ARTWORK');icon:SetAllPoints(button);icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_'..index)
  button:SetScript('OnEnter',function(self) self:SetBackdropBorderColor(.78,.11,.25,1) end)
  button:SetScript('OnLeave',function(self) self:SetBackdropBorderColor(.18,.196,.235,1) end)
  button:SetScript('OnClick',function() InsertToken('{'..name..'}') end)
  ui.markerButtons[index]=button
 end
 Text(editor,'Text colour',278,-162,10,'muted',70)
 local colourOptions={
  {'red',1,.30,.43},{'orange',1,.62,.26},{'yellow',1,.87,.34},{'green',.33,.87,.53},
  {'blue',.40,.67,1},{'purple',.73,.53,1},{'silver',.72,.76,.81},
 }
 for index,choice in ipairs(colourOptions) do
  local button=Surface('Button',editor,'raised');button:SetSize(21,21);button:SetPoint('TOPLEFT',350+(index-1)*24,-155)
  local swatch=button:CreateTexture(nil,'ARTWORK');swatch:SetPoint('TOPLEFT',3,-3);swatch:SetPoint('BOTTOMRIGHT',-3,3);swatch:SetColorTexture(choice[2],choice[3],choice[4],1)
  button:SetScript('OnEnter',function(self) self:SetBackdropBorderColor(.78,.11,.25,1) end)
  button:SetScript('OnLeave',function(self) self:SetBackdropBorderColor(.18,.196,.235,1) end)
  button:SetScript('OnClick',function() ReplaceSelection('{'..choice[1]..'}','{/}',true) end)
  ui.colourButtons[index]=button
 end
 local reset=Button(editor,'Reset colour',530,-155,112,function() ReplaceSelection('{reset}') end);ui.resetColour=reset
 reset:SetHeight(21);reset.label:ClearAllPoints();reset.label:SetPoint('CENTER');reset.label:SetWidth(112);reset.label:SetJustifyH('CENTER')
 ui.editorStatus=Text(editor,'',18,-468,11,'accent',890)
 Button(editor,'Save VRT copy',18,-502,180,function()
  local ok,err,id=N.Save(ui.editing,ui.title:GetText(),ui.text:GetText(),ui.bossID);ui.editorStatus:SetText(err)
  if ok then ui.selected=id;editor:Hide();ui.Refresh();ui.status:SetText(err);if addon.RefreshNativeTextNote then addon.RefreshNativeTextNote() end end
 end)
 Button(editor,'Cancel',754,-502,180,function() bossMenu:Hide();editor:Hide() end)
 function addon.CloseNativeNoteEditor() bossMenu:Hide();editor:Hide() end
 local function Open(entry)
  if not Ready() then ui.status:SetText('Edit outside combat and encounters.');return end
  ui.editing=entry and entry.id or nil;ui.title:SetText(entry and entry.name or 'New text note');ui.text:SetText(entry and entry.text or '')
  ui.bossID=entry and entry.bossID or false;ui.bossButton.label:SetText('Boss: '..BossName(ui.bossID)..'  v')
  ui.editorStatus:SetText('');scroll:SetVerticalScroll(0);ui.title:ClearFocus();ui.text:ClearFocus();emptyFocus:SetShown(ui.text:GetText()=='');editor:Show()
 end
 local function RefreshRows()
  for index,row in ipairs(ui.rows) do
   row.entry=ui.items and ui.items[ui.offset+index]
   if row.entry then
    row.label:SetText((row.entry.id==ui.selected and '> ' or '  ')..row.entry.name..' · '..BossName(row.entry.bossID))
    row:SetBackdropBorderColor(row.entry.id==ui.selected and 0.78 or 0.180,row.entry.id==ui.selected and 0.11 or 0.196,row.entry.id==ui.selected and 0.25 or 0.235,1)
    row:Show()
   else row:Hide() end
  end
 end
 function ui.Refresh()
  local store,err=N.Store();if not store then ui.status:SetText(err);return end
  ui.items=store.items
  local maximum=math.max(0,#store.items-visibleRows)
  ui.maximum=maximum
  ui.offset=math.min(ui.offset,maximum)
  ui.updatingScroll=true;ui.scrollbar:SetMinMaxValues(0,maximum);ui.scrollbar:SetValue(ui.offset);ui.updatingScroll=false
  ui.scrollbar:SetEnabled(maximum>0);ui.scrollbar:SetAlpha(maximum>0 and 1 or .35)
  -- Name non-preset boss assignments from the Adventure Guide (display only).
  local unnamed={}
  for _,entry in ipairs(store.items) do if entry.bossID and not presetNames[entry.bossID] and not knownNames[entry.bossID] then unnamed[#unnamed+1]={bossID=entry.bossID} end end
  if #unnamed>0 and addon.ReminderChoices then addon.ReminderChoices.LibraryCatalogue(unnamed) end
  RefreshRows()
  ui.summary:SetText(string.format('%d VRT notes · scroll to browse · select a row, then View or Edit',#store.items))
  local incoming=addon.TextNoteSharing and addon.TextNoteSharing.pending[1]
  ui.pendingText:SetText(incoming and ('From '..incoming.sender..': '..incoming.pack.note.name) or '')
  if incoming then ui.accept:Show();ui.decline:Show() else ui.accept:Hide();ui.decline:Hide() end
 end
 for index=1,visibleRows do
  local row;row=Button(list,'',8,-8-(index-1)*29,830,function() ui.selected=row.entry and row.entry.id;ui.Refresh() end);row.label:SetWidth(802);row.label:SetWordWrap(false);ui.rows[index]=row
 end
 -- Clicking empty space (in the list or on the page) clears the selection;
 -- rows and buttons handle their own clicks.
 local function Deselect() if ui.selected then ui.selected=nil;ui.confirmDelete=nil;ui.Refresh() end end
 ui.Deselect=Deselect
 list:EnableMouse(true);list:SetScript('OnMouseDown',Deselect)
 page:EnableMouse(true);page:SetScript('OnMouseDown',Deselect)
 ui.scrollbar=Surface('Slider',list,'background');ui.scrollbar:SetPoint('TOPLEFT',846,-8);ui.scrollbar:SetSize(10,listHeight-17)
 ui.scrollbar:SetOrientation('VERTICAL');ui.scrollbar:SetValueStep(1);ui.scrollbar:SetObeyStepOnDrag(true)
 ui.scrollbar:SetThumbTexture('Interface\\Buttons\\WHITE8X8')
 local thumb=ui.scrollbar:GetThumbTexture();thumb:SetSize(8,32);thumb:SetVertexColor(.72,.76,.81,1)
 ui.scrollbar:SetScript('OnEnter',function() thumb:SetVertexColor(.78,.11,.25,1) end)
 ui.scrollbar:SetScript('OnLeave',function() thumb:SetVertexColor(.72,.76,.81,1) end)
 ui.scrollbar:SetScript('OnValueChanged',function(_,value)
  if ui.updatingScroll then return end
  ui.offset=math.floor(value+.5);RefreshRows()
 end)
 list:SetScript('OnMouseWheel',function(_,delta) ui.scrollbar:SetValue(math.max(0,math.min(ui.maximum or 0,ui.offset-delta))) end)
 ui.refreshButton=Button(page,'Refresh library',714,-556,150,ui.Refresh)
 ui.accept=Button(page,'Accept',618,-592,118,function()
  local ok,message=addon.TextNoteSharing.Accept(1);if not ok then ui.status:SetText(message) end;ui.Refresh()
 end)
 ui.decline=Button(page,'Decline',746,-592,118,function() addon.TextNoteSharing.Decline(1);ui.Refresh() end)
 local sendDialog=Surface('Frame',window);ui.sendDialog=sendDialog
 sendDialog:SetSize(460,176);sendDialog:SetPoint('CENTER');sendDialog:SetFrameLevel(window:GetFrameLevel()+50);sendDialog:EnableMouse(true);sendDialog:Hide()
 Text(sendDialog,'Send selected text note',16,-14,16,'text',425)
 Text(sendDialog,'Send to the raid or enter Player-Realm:',16,-44,11,'muted',425)
 ui.sendTarget=Surface('EditBox',sendDialog,'background');ui.sendTarget:SetSize(428,26);ui.sendTarget:SetPoint('TOPLEFT',16,-67)
 ui.sendTarget:SetAutoFocus(false);ui.sendTarget:SetFont(STANDARD_TEXT_FONT,12,'');ui.sendTarget:SetTextColor(.91,.92,.94)
 ui.sendTarget:SetTextInsets(7,7,0,0);ui.sendTarget:SetMaxLetters(100)
 local function Send(target)
  local entry=N.Find(ui.selected)
  if not entry then ui.status:SetText('Select a saved note first.');return end
  local ok,message=addon.TextNoteSharing.Send(entry,target)
  ui.status:SetText(ok and addon.TextNoteSharing.status or message)
  if ok then sendDialog:Hide() end
 end
 Button(sendDialog,'Raid',16,-116,124,function() Send('RAID') end)
 Button(sendDialog,'Player',152,-116,124,function() Send(ui.sendTarget:GetText()) end)
 Button(sendDialog,'Cancel',288,-116,156,function() sendDialog:Hide() end)
 Button(page,'Add',0,-556,115,function() Open() end)
 Button(page,'View',127,-556,115,function()
  local entry=N.Find(ui.selected);if entry and addon.ShowNativeTextNote then addon.ShowNativeTextNote(entry,true) else ui.status:SetText('Select a note first.') end
 end)
 Button(page,'Edit',254,-556,115,function()
  local entry=N.Find(ui.selected);if entry then Open(entry) else ui.status:SetText('Select a note first.') end
 end)
 Button(page,'Delete',381,-556,115,function()
  if not ui.selected then ui.status:SetText('Select a note first.');return end
  if ui.confirmDelete~=ui.selected then ui.confirmDelete=ui.selected;ui.status:SetText('Click Delete again to remove the selected VRT copy.');return end
  local ok,message=N.Delete(ui.selected);ui.confirmDelete=nil;ui.selected=nil;ui.status:SetText(message);ui.Refresh()
  if ok and addon.RefreshNativeTextNote then addon.RefreshNativeTextNote() end
 end)
 Button(page,'Send',554,-556,150,function()
  if not N.Find(ui.selected) then ui.status:SetText('Select a note first.');return end
  ui.sendTarget:SetText('');sendDialog:Show()
 end)
 function addon.RefreshNativeNotesUI() if page:IsShown() then ui.Refresh() end end
 page:SetScript('OnShow',ui.Refresh);page:SetScript('OnHide',function() bossMenu:Hide();sendDialog:Hide();editor:Hide() end);ui.Refresh()
end
