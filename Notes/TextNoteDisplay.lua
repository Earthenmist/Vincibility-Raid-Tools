local _,addon=...
local N=addon.NativeNotes
local frame,body,heading,scroll,fontSlider,fontLabel
local currentID,currentBoss,manual,suppressed
local status='Waiting for a raid.'
local raidMarkers={star=1,circle=2,diamond=3,triangle=4,moon=5,square=6,cross=7,skull=8}
local textColours={
 red='ffff4d6d',orange='ffff9f43',yellow='ffffdd57',green='ff55dd88',
 blue='ff66aaff',purple='ffbb88ff',silver='ffb8c2cf',white='fff0f0f0',
}

local function Reflow(value)
 value=value:gsub('\r\n','\n'):gsub('\r','\n')
 local result,current={}
 local function Flush() if current then result[#result+1]=current;current=nil end end
 local function ListStart(line)
  if line:match('^%s*[•%-%*]') or line:match('^%s*%d+[%.%)]%s+') or line:match('^%s*{[Rr][Tt][1-8]}') then return true end
  local token=line:match('^%s*{([%a]+)}')
  return token and raidMarkers[token:lower()]~=nil
 end
 local function Heading(line)
  local plain=line:gsub('{[%a/]+}',''):gsub('[%p%d%s]','')
  return plain~='' and not plain:find('%l')
 end
 for line in (value..'\n'):gmatch('(.-)\n') do
  line=line:match('^%s*(.-)%s*$')
  if line=='' then Flush();if #result>0 and result[#result]~='' then result[#result+1]='' end
  elseif Heading(line) then Flush();result[#result+1]=line
  elseif ListStart(line) then Flush();current=line
  elseif current then current=current..' '..line
  else current=line end
 end
 Flush()
 while result[#result]=='' do table.remove(result) end
 return table.concat(result,'\n')
end
addon.ReflowNativeTextNote=Reflow
local function Render(value)
 value=Reflow(value)
 value=value:gsub('{[Rr][Tt]([1-8])}',function(index)
  return '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_'..index..':16:16|t'
 end)
 value=value:gsub('{([%a]+)}',function(name)
  local key=name:lower();local marker=raidMarkers[key]
  if marker then return '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_'..marker..':16:16|t' end
  local colour=textColours[key]
  if colour then return '|c'..colour end
  if key=='reset' then return '|r' end
  return '{'..name..'}'
 end)
 value=value:gsub('{/}','|r')
 value=value:gsub('{[Ss][Pp][Ee][Ll][Ll]:(%d+)}',function(id)
  local name=C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(tonumber(id))
  return name or '{spell:'..id..'}'
 end)
 return value
end
addon.RenderNativeTextNote=Render
local function DisplaySettings()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local settings=VincibilityRaidToolsDB.textNoteDisplay
 if type(settings)~='table' then settings={};VincibilityRaidToolsDB.textNoteDisplay=settings end
 local width=tonumber(settings.width);local height=tonumber(settings.height);local fontSize=tonumber(settings.fontSize)
 settings.width=width and math.max(360,math.min(1100,width)) or 520
 settings.height=height and math.max(260,math.min(900,height)) or 460
 settings.fontSize=fontSize and math.floor(math.max(10,math.min(24,fontSize))+.5) or 13
 if settings.defaultsVersion~=1 then
  settings.controlsShown=false;settings.sizeLocked=true;settings.defaultsVersion=1
 end
 if type(settings.controlsShown)~='boolean' then settings.controlsShown=false end
 if type(settings.sizeLocked)~='boolean' then settings.sizeLocked=true end
 return settings
end
addon.GetNativeTextNoteDisplaySettings=DisplaySettings
local function SavePosition()
 local x,y=frame:GetCenter();local ux,uy=UIParent:GetCenter()
 if x and ux then
  local scale=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
  local db=VincibilityRaidToolsDB;db.textNotePosition={x=x*scale-ux,y=y*scale-uy}
  frame:ClearAllPoints();frame:SetPoint('CENTER',UIParent,'CENTER',db.textNotePosition.x,db.textNotePosition.y)
 end
end
local function LayoutText()
 if not frame or not body or not scroll then return end
 local settings=DisplaySettings()
 body:SetFont(STANDARD_TEXT_FONT,settings.fontSize,'')
 local width=math.max(300,frame:GetWidth()-54)
 body:SetWidth(width);frame.noteChild:SetWidth(width)
 if fontLabel then
  fontLabel:SetText('Text size: '..settings.fontSize)
  fontLabel:SetShown(settings.controlsShown);fontSlider:SetShown(settings.controlsShown)
  scroll:ClearAllPoints();scroll:SetPoint('TOPLEFT',12,-38)
  scroll:SetPoint('BOTTOMRIGHT',-30,settings.controlsShown and 42 or 32)
 end
 frame.noteChild:SetHeight(math.max(scroll:GetHeight() or 0,body:GetStringHeight()+20))
end
local function Build()
 if frame then return end
 local settings=DisplaySettings()
 frame=CreateFrame('Frame','VincibilityTextNote',UIParent,'BackdropTemplate')
 frame:SetSize(settings.width,settings.height);frame:SetPoint('CENTER');frame:SetFrameStrata('MEDIUM')
 frame:SetClampedToScreen(true);frame:SetMovable(true);frame:EnableMouse(true)
 frame:SetResizable(true)
 if frame.SetResizeBounds then frame:SetResizeBounds(360,260,1100,900)
 else frame:SetMinResize(360,260);frame:SetMaxResize(1100,900) end
 frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 frame:SetBackdropColor(.078,.086,.106,.96);frame:SetBackdropBorderColor(.72,.76,.81,.8)
 local header=CreateFrame('Frame',nil,frame,'BackdropTemplate')
 header:SetPoint('TOPLEFT');header:SetPoint('TOPRIGHT');header:SetHeight(28)
 header:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'})
 header:SetBackdropColor(.145,.157,.192,1)
 header:EnableMouse(true);header:RegisterForDrag('LeftButton')
 header:SetScript('OnDragStart',function() frame:StartMoving() end)
 header:SetScript('OnDragStop',function()
  frame:StopMovingOrSizing()
  SavePosition()
 end)
 local function ToggleFontControls(_,button)
  if button~='RightButton' then return end
  local current=DisplaySettings();current.controlsShown=not current.controlsShown;LayoutText()
 end
 header:SetScript('OnMouseUp',ToggleFontControls)
 heading=header:CreateFontString(nil,'OVERLAY')
 heading:SetFont(STANDARD_TEXT_FONT,13,'');heading:SetTextColor(.91,.918,.941)
 heading:SetPoint('LEFT',12,0);heading:SetWidth(455);heading:SetJustifyH('LEFT')
 local close=CreateFrame('Button',nil,header,'BackdropTemplate')
 close:SetSize(24,20);close:SetPoint('RIGHT',-4,0)
 close:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 close:SetBackdropColor(.114,.125,.157,1);close:SetBackdropBorderColor(.72,.76,.81,.4)
 local cross=close:CreateFontString(nil,'OVERLAY');cross:SetFont(STANDARD_TEXT_FONT,12,'');cross:SetPoint('CENTER');cross:SetText('X');cross:SetTextColor(.72,.76,.81)
 close:SetScript('OnClick',function() if not manual then suppressed=currentBoss or 'start' end;manual=false;frame:Hide() end)
 scroll=CreateFrame('ScrollFrame',nil,frame,'UIPanelScrollFrameTemplate')
 scroll:SetPoint('TOPLEFT',12,-38);scroll:SetPoint('BOTTOMRIGHT',-30,42)
 if addon.StyleScrollBar then addon.StyleScrollBar(scroll) end
 local child=CreateFrame('Frame',nil,scroll);child:SetSize(466,400);scroll:SetScrollChild(child)
 body=child:CreateFontString(nil,'ARTWORK');body:SetFont(STANDARD_TEXT_FONT,13,'')
 body:SetTextColor(.91,.918,.941);body:SetJustifyH('LEFT');body:SetJustifyV('TOP')
 body:SetPoint('TOPLEFT');body:SetWidth(466)
 frame.noteChild=child;frame.noteScroll=scroll
 frame:EnableMouseWheel(true)
 frame:SetScript('OnMouseWheel',function(_,delta) scroll:SetVerticalScroll(math.max(0,scroll:GetVerticalScroll()-delta*35)) end)
 frame:SetScript('OnMouseUp',ToggleFontControls);scroll:SetScript('OnMouseUp',ToggleFontControls)
 fontLabel=frame:CreateFontString(nil,'OVERLAY');fontLabel:SetFont(STANDARD_TEXT_FONT,11,'')
 fontLabel:SetTextColor(.72,.76,.81);fontLabel:SetPoint('BOTTOMLEFT',12,15);fontLabel:SetWidth(82);fontLabel:SetJustifyH('LEFT')
 fontSlider=CreateFrame('Slider',nil,frame,'BackdropTemplate');frame.fontSlider=fontSlider
 fontSlider:SetSize(150,12);fontSlider:SetPoint('LEFT',fontLabel,'RIGHT',5,0)
 fontSlider:SetOrientation('HORIZONTAL');fontSlider:SetMinMaxValues(10,24)
 fontSlider:SetValueStep(1);fontSlider:SetObeyStepOnDrag(true)
 fontSlider:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 fontSlider:SetBackdropColor(.055,.06,.075,1);fontSlider:SetBackdropBorderColor(.72,.76,.81,.45)
 fontSlider:SetThumbTexture('Interface\\Buttons\\WHITE8X8');fontSlider:GetThumbTexture():SetSize(9,18)
 fontSlider:GetThumbTexture():SetVertexColor(.72,.76,.81)
 fontSlider:SetScript('OnValueChanged',function(_,value)
  value=math.floor(value+.5);DisplaySettings().fontSize=value;LayoutText()
 end)
 fontSlider:SetValue(settings.fontSize)
 local grip=CreateFrame('Button',nil,frame,'BackdropTemplate');frame.resizeGrip=grip
 grip:SetSize(22,22);grip:SetPoint('BOTTOMRIGHT',-3,3)
 grip:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 grip:SetBackdropColor(.114,.125,.157,1);grip:SetBackdropBorderColor(.72,.76,.81,.45)
 local marks={}
 for i=0,2 do
  local mark=grip:CreateTexture(nil,'ARTWORK');mark:SetColorTexture(.72,.76,.81,.85)
  mark:SetSize(3+i*3,2);mark:SetPoint('BOTTOMRIGHT',-4,4+i*4);marks[#marks+1]=mark
 end
 local lockLabel=grip:CreateFontString(nil,'OVERLAY');lockLabel:SetFont(STANDARD_TEXT_FONT,12,'OUTLINE')
 lockLabel:SetPoint('CENTER');lockLabel:SetText('L');lockLabel:SetTextColor(1,.35,.42)
 local function UpdateGrip()
  local locked=DisplaySettings().sizeLocked
  lockLabel:SetShown(locked);for _,mark in ipairs(marks) do mark:SetShown(not locked) end
  grip:SetBackdropBorderColor(locked and .76 or .72,locked and 0 or .76,locked and .18 or .81,locked and 1 or .45)
 end
 grip:SetScript('OnEnter',function()
  grip:SetBackdropBorderColor(.76,0,.18,1)
  if GameTooltip then
   GameTooltip:SetOwner(grip,'ANCHOR_TOPRIGHT')
   GameTooltip:SetText(DisplaySettings().sizeLocked and 'Size locked — right-click to unlock' or 'Drag to resize — right-click to lock')
   GameTooltip:Show()
  end
 end)
 grip:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end;UpdateGrip() end)
 grip:SetScript('OnMouseDown',function(_,button)
  if button=='LeftButton' and not DisplaySettings().sizeLocked then frame:StartSizing('BOTTOMRIGHT') end
 end)
 grip:SetScript('OnMouseUp',function(_,button)
  if button=='RightButton' then
   local current=DisplaySettings();current.sizeLocked=not current.sizeLocked;UpdateGrip()
   if GameTooltip and GameTooltip:IsOwned(grip) then
    GameTooltip:SetText(current.sizeLocked and 'Size locked — right-click to unlock' or 'Drag to resize — right-click to lock')
   end
   return
  end
  if button~='LeftButton' or DisplaySettings().sizeLocked then return end
  frame:StopMovingOrSizing();local current=DisplaySettings()
  current.width=math.floor(frame:GetWidth()+.5);current.height=math.floor(frame:GetHeight()+.5)
  SavePosition();LayoutText()
 end)
 UpdateGrip()
 frame:SetScript('OnSizeChanged',LayoutText)
 local db=VincibilityRaidToolsDB
 if db and type(db.textNotePosition)=='table' then
  local p=db.textNotePosition
  if type(p.x)=='number' and type(p.y)=='number' and math.abs(p.x)<5000 and math.abs(p.y)<5000 then
   frame:ClearAllPoints();frame:SetPoint('CENTER',UIParent,'CENTER',p.x,p.y)
  end
 end
 LayoutText()
 frame:Hide()
end
function addon.ShowNativeTextNote(entry,isManual)
 if not entry or type(entry.text)~='string' then return false end
 Build();heading:SetText(entry.name);body:SetText(Render(entry.text))
 LayoutText()
 frame.noteScroll:SetVerticalScroll(0)
 currentID=entry.id;manual=isManual and true or false
 frame:Show();return true
end
function addon.RefreshNativeTextNote()
 if currentID and frame and frame:IsShown() then
  local entry=N.Find(currentID)
  if entry then addon.ShowNativeTextNote(entry,manual)
  else frame:Hide();manual=false;currentID=nil end
 end
 addon.UpdateNativeTextNote()
end
function addon.GetNativeTextNoteStatus() return status end
function addon.GetStartingNotes()
 local entries={{name='Disabled'}}
 local store=N.Store();if not store then return entries end
 for _,entry in ipairs(store.items) do
  if type(entry.name)=='string' and type(entry.text)=='string' and entry.text~='' then
   entries[#entries+1]={name=entry.name,value=entry.id}
  end
 end
 return entries
end
local function MigrateStartingNote()
 local db=VincibilityRaidToolsDB or {}
 if db.nativeStartingNoteID or type(db.startingNote)~='string' then return end
 local store=N.Store();if not store then return end
 local found
 for _,entry in ipairs(store.items) do
  if entry.name==db.startingNote and entry.origin and entry.origin.addon=='MRT' and entry.origin.kind=='saved' then
   if found then return end
   found=entry
  end
 end
 if found then db.nativeStartingNoteID=found.id;db.startingNote=nil;db.startingNoteChosen=true end
end
-- The starting note is Disabled until chosen in Settings (startingNoteChosen).
local function StartingNote()
 local db=VincibilityRaidToolsDB or {}
 return db.startingNoteChosen and N.Find(db.nativeStartingNoteID) or nil
end
function addon.GetStartingNoteName()
 MigrateStartingNote()
 local entry=StartingNote()
 return entry and entry.name or 'Disabled'
end
function addon.UpdateNativeTextNote()
 local db=VincibilityRaidToolsDB
 if not db then return end
 MigrateStartingNote()
 -- Notes module switched off: nothing shows automatically.
 if addon.ModuleEnabled and not addon.ModuleEnabled('notes') then
  if frame and not manual then frame:Hide() end
  currentBoss=nil;currentID=nil;status='Notes module is disabled.';return
 end
 -- Default: notes only open by themselves for the raid leader.
 if db.notesLeaderOnly~=false and not UnitIsGroupLeader('player') then
  if frame and not manual then frame:Hide() end
  currentBoss=nil;currentID=nil;status='Notes open by themselves for the raid leader only.';return
 end
 local inside,kind=IsInInstance()
 local boss=addon.GetNativeBossID and addon.GetNativeBossID() or nil
 if not inside or kind~='raid' then
  if frame and not manual then frame:Hide() end
  currentBoss=nil;currentID=nil;suppressed=nil;status='Waiting for a raid.';return
 end
 if boss~=currentBoss then
  currentBoss=boss;suppressed=nil
  if frame and not manual then frame:Hide() end
  currentID=nil
 end
 if manual then return end
 if suppressed==(boss or 'start') then status='Closed for this area.';return end
 local store=N.Store();if not store then return end
 local selected,duplicates,ignoredSnapshots= nil,false,0
 if boss then
  local candidates,durable={},{}
  for _,entry in ipairs(store.items) do if entry.bossID==boss then
   candidates[#candidates+1]=entry
   local origin=entry.origin
   if not (origin and origin.addon=='MRT' and (origin.kind=='shared' or origin.kind=='personal')) then durable[#durable+1]=entry end
  end end
  if #durable>0 then ignoredSnapshots=#candidates-#durable;candidates=durable end
  local unique={}
  for _,entry in ipairs(candidates) do
   local repeated=false
   for _,other in ipairs(unique) do if entry.text==other.text then repeated=true;break end end
   if not repeated then unique[#unique+1]=entry end
  end
  selected=unique[1];duplicates=#unique>1
  if duplicates then if frame then frame:Hide() end;status='Several notes assigned to this boss; choose one in Notes.';return end
 else selected=StartingNote() end
 if not selected then if frame then frame:Hide() end;status=boss and 'No VRT text note for this boss.' or 'No starting VRT text note selected.';return end
 if currentID~=selected.id or not frame or not frame:IsShown() then addon.ShowNativeTextNote(selected,false) end
 status='Showing VRT: '..selected.name..(ignoredSnapshots>0 and ' · ignored imported current-note snapshot' or '')
end
local eventFrame=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_ENTERING_WORLD','ZONE_CHANGED','ZONE_CHANGED_INDOORS','ZONE_CHANGED_NEW_AREA','PARTY_LEADER_CHANGED'}) do eventFrame:RegisterEvent(event) end
local generation=0
eventFrame:SetScript('OnEvent',function()
 generation=generation+1;local request=generation
 C_Timer.After(1,function() if request==generation then addon.UpdateNativeTextNote() end end)
end)
