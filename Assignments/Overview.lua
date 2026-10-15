local _,addon=...
-- Leader overview: during a fight, the raid leader (optionally assistants)
-- sees the next assignments for everyone, with countdowns, so they can call
-- them. A preview places the window and sets its options before a pull; the
-- position is saved and the window is locked outside the preview.
local A=addon.Assignments
local Run=A.Runtime
local O={rows={}};A.Overview=O
local ROWS,ROW=8,20
local colours={background={0.078,0.086,0.106,0.95},raised={0.145,0.157,0.192,1},border={0.180,0.196,0.235,1},
 accent={0.72,0.76,0.81,1},highlight={0.78,0.11,0.25,1},text={0.910,0.918,0.941,1},muted={0.541,0.561,0.612,1}}

function O.Settings()
 local store=A.Store();if not store then return {enabled=true,assistants=false} end
 if type(store.overview)~='table' then store.overview={} end
 local settings=store.overview
 if settings.enabled==nil then settings.enabled=true end
 settings.assistants=settings.assistants==true
 return settings
end
function O.Allowed()
 local settings=O.Settings()
 if not settings.enabled then return false end
 -- A test pull shows it to whoever runs the test.
 if Run.test then return true end
 if not IsInGroup() then return false end
 return UnitIsGroupLeader('player') or (settings.assistants and UnitIsGroupAssistant('player')) or false
end
local function Paint(frame,colour)
 frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 frame:SetBackdropColor(unpack(colours[colour or 'background']));frame:SetBackdropBorderColor(unpack(colours.border))
end
local function Label(parent,size,colour,width)
 local t=parent:CreateFontString(nil,'OVERLAY');t:SetFont(STANDARD_TEXT_FONT,size,'');t:SetTextColor(unpack(colours[colour or 'text']))
 t:SetJustifyH('LEFT');if width then t:SetWidth(width);t:SetWordWrap(false) end
 return t
end
local function Toggle(parent,text,x,y,get,set)
 local box=CreateFrame('CheckButton',nil,parent,'BackdropTemplate');Paint(box,'background');box:SetSize(14,14);box:SetPoint('TOPLEFT',x,y)
 local mark=box:CreateTexture(nil,'ARTWORK');mark:SetSize(8,8);mark:SetPoint('CENTER');mark:SetColorTexture(unpack(colours.highlight));box:SetCheckedTexture(mark)
 box.label=Label(box,10,'text',160);box.label:SetPoint('LEFT',box,'RIGHT',5,0);box.label:SetText(text)
 box:SetScript('OnClick',function(self) set(self:GetChecked() and true or false) end)
 box.Sync=function(self) self:SetChecked(get()) end
 return box
end
function O.Build()
 if O.frame then return O.frame end
 local frame=CreateFrame('Frame','VincibilityAssignmentOverview',UIParent,'BackdropTemplate');O.frame=frame
 Paint(frame);frame:SetSize(420,30+ROWS*ROW+8);frame:SetFrameStrata('HIGH');frame:SetClampedToScreen(true);frame:SetMovable(true)
 frame:EnableMouse(true);frame:RegisterForDrag('LeftButton');frame:Hide()
 frame:SetScript('OnDragStart',function(self) if O.preview and not InCombatLockdown() then self:StartMoving() end end)
 frame:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local x,y=self:GetCenter();local px,py=UIParent:GetCenter()
  if x and px then O.Settings().position={x=math.floor(x-px+.5),y=math.floor(y-py+.5)} end
 end)
 frame.title=Label(frame,12,'text',240);frame.title:SetPoint('TOPLEFT',8,-8)
 local shared=addon.ReadyCheck and addon.ReadyCheck.Overview
 if shared and shared.CloseButton then frame.close=shared.CloseButton(frame,function() O.Hide() end)
 else
  frame.close=CreateFrame('Button',nil,frame,'BackdropTemplate');Paint(frame.close,'raised');frame.close:SetSize(20,20);frame.close:SetPoint('TOPRIGHT',-6,-5)
  frame.close.label=Label(frame.close,11,'accent');frame.close.label:SetPoint('CENTER');frame.close.label:SetText('X')
  frame.close:SetScript('OnClick',function() O.Hide() end)
 end
 for index=1,ROWS do
  local row=CreateFrame('Frame',nil,frame);row:SetSize(404,ROW);row:SetPoint('TOPLEFT',8,-28-(index-1)*ROW)
  row.time=Label(row,11,'accent',36);row.time:SetPoint('LEFT',0,0)
  row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(16,16);row.icon:SetPoint('LEFT',38,0)
  row.who=Label(row,11,'text',96);row.who:SetPoint('LEFT',58,0)
  row.what=Label(row,11,'text',246);row.what:SetPoint('LEFT',158,0)
  row:Hide();O.rows[index]=row
 end
 -- Preview footer: options and how to finish.
 frame.footer=CreateFrame('Frame',nil,frame,'BackdropTemplate');frame.footer:SetSize(420,52);frame.footer:SetPoint('TOPLEFT',frame,'BOTTOMLEFT',0,0)
 Paint(frame.footer,'raised')
 frame.enabled=Toggle(frame.footer,'Show during fights',8,-6,function() return O.Settings().enabled end,function(v) O.Settings().enabled=v end)
 frame.assistants=Toggle(frame.footer,'Include assistants',170,-6,function() return O.Settings().assistants end,function(v) O.Settings().assistants=v end)
 frame.hint=Label(frame.footer,10,'muted',400);frame.hint:SetPoint('TOPLEFT',8,-30);frame.hint:SetText('Drag to place it, then close. It stays here during fights.')
 frame.footer:Hide()
 frame:SetScript('OnUpdate',function(_,elapsed)
  O.elapsed=(O.elapsed or 0)+elapsed
  if O.elapsed<.2 then return end
  O.elapsed=0;O.Refresh()
 end)
 return frame
end
local function Place(frame)
 local position=O.Settings().position
 frame:ClearAllPoints()
 if type(position)=='table' and type(position.x)=='number' and type(position.y)=='number' then frame:SetPoint('CENTER',UIParent,'CENTER',position.x,position.y)
 else frame:SetPoint('LEFT',UIParent,'LEFT',40,120) end
end
-- Rows: upcoming assignments (all of them) in time order.
function O.Upcoming(now)
 local list={}
 for _,item in ipairs(Run.items or {}) do
  local left=item.expected-now
  if left>-2 then list[#list+1]={left=left,item=item} end
 end
 table.sort(list,function(a,b) return a.left<b.left end)
 return list
end
local function Draw(rows,title)
 local frame=O.frame
 frame.title:SetText(title)
 for index,row in ipairs(O.rows) do
  local data=rows[index]
  if data then
   -- Seconds until it happens; m:ss from a minute out.
   local left=math.ceil(data.left)
   row.time:SetText(data.left<=0 and 'now' or left>=60 and string.format('%d:%02d',math.floor(left/60),left%60) or tostring(left))
   row.time:SetTextColor(unpack(data.left<=(Run.alertLead or 3) and colours.highlight or colours.accent))
   row.icon:SetTexture(data.icon);row.icon:SetShown(data.icon~=nil)
   row.who:SetText(data.who);row.what:SetText(data.what)
   row:Show()
  else row:Hide() end
 end
end
function O.Refresh()
 local frame=O.frame;if not frame or not frame:IsShown() then return end
 if O.preview then
  Draw(O.SampleRows(),'Leader overview (preview)')
  return
 end
 if not Run.running or not O.Allowed() then frame:Hide();return end
 local now=GetTime()-Run.started
 local rows={}
 for _,entry in ipairs(O.Upcoming(now)) do
  if #rows>=ROWS then break end
  local item=entry.item
  rows[#rows+1]={left=entry.left,icon=item.icon,who=A.FormatWho(item.entry.who),what=item.label..(item.ability and (' > '..item.ability..' ('..(item.cast or '')..')') or '')}
 end
 Draw(rows,'Upcoming assignments')
end
-- Preview rows: the current boss's plan if it has one, otherwise examples.
function O.SampleRows()
 local rows={}
 local store=A.Store()
 local plan=store and store.lastBoss and A.Plan(store.lastBoss)
 for index,entry in ipairs(plan and plan.entries or {}) do
  if index>ROWS then break end
  local info=entry.spellID and A.SpellInfo and A.SpellInfo(entry.spellID)
  rows[#rows+1]={left=index*7,icon=info and info.iconID,who=A.FormatWho(entry.who),what=A.AssignmentLabel(entry)..(entry.anchor and (' > '..entry.anchor.ability..' ('..entry.anchor.cast..')') or '')}
 end
 if #rows==0 then
  rows={{left=2,who='Tanks',what='Tank swap > Slam (2)'},{left=9,who='Healer',what='Aura Mastery > Raid Burst (1)'},{left=16,who='Group 1, Group 3',what='Soak the left pool'}}
 end
 return rows
end
function O.ShowPreview()
 if InCombatLockdown() then return false end
 local frame=O.Build();O.preview=true
 Place(frame);frame:EnableMouse(true);frame.footer:Show();frame.enabled:Sync();frame.assistants:Sync()
 frame:Show();O.Refresh()
 return true
end
function O.Hide()
 O.preview=false
 if O.frame then O.frame.footer:Hide();O.frame:Hide() end
end
function O.OnStart()
 if addon.ModuleEnabled and not addon.ModuleEnabled('assignments') then return end
 if not Run.running or not O.Allowed() then return end
 -- Locked during fights: clicks pass through except on the close button.
 local frame=O.Build();O.preview=false;frame.footer:Hide();frame:EnableMouse(false);Place(frame);frame:Show();O.Refresh()
end
-- Test pull bar: while a test runs the main window is hidden and this bar
-- (styled like the reminder preview bar) shows the clock and Stop test.
function O.ShowTestBar()
 if not O.testBar then
  local bar=CreateFrame('Frame','VincibilityAssignmentTestBar',UIParent,'BackdropTemplate');O.testBar=bar
  bar:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
  bar:SetBackdropColor(0.078,0.086,0.106,0.9);bar:SetBackdropBorderColor(unpack(colours.accent))
  bar:SetSize(620,34);bar:SetPoint('TOP',0,-60);bar:SetFrameStrata('DIALOG');bar:Hide()
  bar.text=bar:CreateFontString(nil,'OVERLAY');bar.text:SetFont(STANDARD_TEXT_FONT,12,'OUTLINE');bar.text:SetTextColor(unpack(colours.text))
  bar.text:SetPoint('LEFT',10,0);bar.text:SetWidth(500);bar.text:SetJustifyH('LEFT');bar.text:SetWordWrap(false)
  local stop=CreateFrame('Button',nil,bar,'BackdropTemplate');bar.stop=stop
  stop:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
  stop:SetBackdropColor(0.078,0.086,0.106,0.9);stop:SetBackdropBorderColor(unpack(colours.accent))
  stop:SetSize(96,28);stop:SetPoint('RIGHT',-3,0)
  stop.label=stop:CreateFontString(nil,'OVERLAY');stop.label:SetFont(STANDARD_TEXT_FONT,12,'OUTLINE');stop.label:SetTextColor(unpack(colours.text))
  stop.label:SetPoint('CENTER');stop.label:SetText('Stop test')
  stop:SetScript('OnEnter',function(self) self:SetBackdropBorderColor(unpack(colours.highlight)) end)
  stop:SetScript('OnLeave',function(self) self:SetBackdropBorderColor(unpack(colours.accent)) end)
  stop:SetScript('OnClick',function() if Run.test then Run.Stop() end end)
  bar:SetScript('OnUpdate',function(self)
   if not Run.test then return end
   local now=GetTime()-Run.started
   local left=0;for _,item in ipairs(Run.Mine()) do if item.expected>now then left=left+1 end end
   self.text:SetText(string.format('Test pull %s - %d of yours to come. Reminders fire as in a real fight.',A.FormatTime(now),left))
  end)
 end
 if VincibilityMainUI then VincibilityMainUI:Hide() end
 O.testBar:Show()
end
function O.HideTestBar(reopen)
 if not (O.testBar and O.testBar:IsShown()) then return end
 O.testBar:Hide()
 if reopen and not InCombatLockdown() and addon.OpenMainUI then addon.OpenMainUI('Assignments') end
end
local events=CreateFrame('Frame')
for _,event in ipairs({'ENCOUNTER_START','ENCOUNTER_END'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event)
 if event=='ENCOUNTER_START' then
  -- The runtime builds its list on the same event; show on the next frame.
  if C_Timer and C_Timer.After then C_Timer.After(0,O.OnStart) else O.OnStart() end
 elseif O.frame and not O.preview then O.frame:Hide() end
end)
