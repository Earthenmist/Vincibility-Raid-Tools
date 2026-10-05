local _,addon=...
-- Assignments page. Timeline view (default): the boss's casts on the left;
-- click one and assign a cooldown from your group on the right. Table view:
-- the plan as rows with a one-row editor and text import/export.
local A=addon.Assignments
local VISIBLE=13
local COLUMNS={{'Time',0,60},{'Ph',64,40},{'Who',108,214},{'Spell',328,228},{'Note',562,290}}
local TIMELINE_ROWS,ROSTER_ROWS,ICONS=23,11,11

function addon.BuildAssignmentsPage(page,window,H)
 local Text,Button,Surface,CheckBox,colours=H.Text,H.Button,H.Surface,H.CheckBox,H.colours
 local ui={rows={},offset=0,timelineOffset=0,rosterOffset=0,category=nil};window.assignments=ui
 Text(page,'Pick a boss, click one of its abilities, then pick who covers it from your group.',0,-27,12,'muted',850)
 local tableView=CreateFrame('Frame',nil,page);tableView:SetAllPoints(page);ui.tableView=tableView
 local timelineView=CreateFrame('Frame',nil,page);timelineView:SetAllPoints(page);ui.timelineView=timelineView
 local function Input(parent,x,y,width,letters)
  local box=Surface('EditBox',parent,'background');box:SetSize(width,26);box:SetPoint('TOPLEFT',x,y)
  box:SetAutoFocus(false);box:SetFont(STANDARD_TEXT_FONT,12,'');box:SetTextColor(.91,.92,.94)
  box:SetTextInsets(7,7,0,0);box:SetMaxLetters(letters or 100)
  box:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
  box:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
  return box
 end
 local function SpellName(entry)
  local info=entry.spellID and A.SpellInfo(entry.spellID)
  return info and info.name or (entry.spellID and ('Spell '..entry.spellID) or '')
 end
 -- What was assigned: the spell's name, or the action text.
 local function Describe(entry)
  if entry.spellID then return SpellName(entry)..((entry.text and entry.text~='') and (' - '..entry.text) or '') end
  return entry.text or ''
 end
 -- Who, with names flagged by the last signup check coloured: red not signed
 -- up, amber tentative, blue-grey standby.
 local signupColours={missing='ffe05a5a',tentative='ffe0b040',standby='ff8fa3bf'}
 local function WhoText(list)
  local out={}
  for _,who in ipairs(list or {}) do
   local label=A.roleLabels[who] or who
   local flag=not A.roleLabels[who] and A.Signups and A.Signups.Flag(who)
   out[#out+1]=flag and ('|c'..signupColours[flag]..label..'|r') or label
  end
  return table.concat(out,', ')
 end
 ui.WhoText=WhoText
 local function AnchorText(entry) return entry.anchor and ('on '..entry.anchor.ability..' ('..entry.anchor.cast..')') or '' end

 -- Boss picker: Raids/Dungeons > expansion > instance > boss.
 ui.bossButton=Button(page,'Boss: choose a boss  v',0,-54,420,function() end)
 ui.bossButton.label:SetWordWrap(false)
 local menu=Surface('Frame',page);ui.bossMenu=menu
 menu:SetSize(420,34+12*29);menu:SetPoint('TOPLEFT',ui.bossButton,'BOTTOMLEFT',0,-2);menu:SetFrameLevel(page:GetFrameLevel()+30)
 menu:EnableMouse(true);menu:EnableMouseWheel(true);menu:Hide()
 ui.bossPath=Text(menu,'',10,-12-12*29,10,'muted',400)
 local menuItems,menuStack,menuRows,menuOffset={},{},{},0
 local function RootItems()
  local items={}
  local catalogue=addon.ReminderChoices
  local instances=catalogue and catalogue.Instances()
  if not instances then return items end
  for _,group in ipairs({{'raid','Raids'},{'party','Dungeons'}}) do
   local expansions,byTier={},{}
   for _,instance in ipairs(instances) do
    if instance.kind==group[1] then
     local expansion=byTier[instance.tier]
     if not expansion then expansion={label=instance.tierName,items={}};byTier[instance.tier]=expansion;expansions[#expansions+1]=expansion end
     expansion.items[#expansion.items+1]={label=instance.name,load=function()
      local bosses,err=catalogue.Bosses(instance);if not bosses then return nil,err end
      local list={}
      for _,boss in ipairs(bosses) do list[#list+1]={label=boss.name,bossID=boss.bossID,full=boss.name} end
      return list
     end}
    end
   end
   if #expansions>0 then items[#items+1]={label=group[2],items=expansions} end
  end
  return items
 end
 local function DrawMenu()
  local list={}
  if #menuStack>0 then list[1]={label='<  Back',back=true} end
  for _,item in ipairs(#menuStack>0 and menuStack[#menuStack].items or menuItems) do list[#list+1]=item end
  menuOffset=math.max(0,math.min(menuOffset,#list-12))
  for index,row in ipairs(menuRows) do
   local item=list[index+menuOffset];row.entry=item
   if item then row.label:SetText(item.label..((item.items or item.load) and '  >' or ''));row:Show() else row:Hide() end
  end
  local path={};for _,item in ipairs(menuStack) do path[#path+1]=item.label end
  ui.bossPath:SetText(#list==0 and 'Adventure Guide data is not ready; open the guide and try again.' or table.concat(path,' > '))
 end
 for index=1,12 do
  local row;row=Button(menu,'',5,-5-(index-1)*29,410,function()
   local item=row.entry;if not item then return end
   if item.back then menuStack[#menuStack]=nil;menuOffset=0;DrawMenu();return end
   if item.items or item.load then
    if not item.items then local loaded,err=item.load();if not loaded then ui.bossPath:SetText(err or 'Boss data is unavailable.');return end;item.items=loaded end
    menuStack[#menuStack+1]=item;menuOffset=0;DrawMenu();return
   end
   menu:Hide();ui.SelectBoss(item.bossID,item.full)
  end)
  row.label:SetWidth(390);row.label:SetWordWrap(false);menuRows[index]=row
 end
 ui.bossRows=menuRows
 menu:SetScript('OnMouseWheel',function(_,delta) menuOffset=menuOffset-delta;DrawMenu() end)
 ui.bossButton:SetScript('OnClick',function()
  if InCombatLockdown() then return end
  if menu:IsShown() then menu:Hide();return end
  menuItems=RootItems();menuStack={};menuOffset=0;DrawMenu();menu:Show()
 end)

 -- Shared header controls.
 ui.difficultyButton=Button(page,'',430,-54,110,function()
  local list=A.TimelineDifficulties(ui.bossID)
  if #list<2 then return end
  local nextValue=list[1]
  for index,value in ipairs(list) do if value==ui.difficulty then nextValue=list[index%#list+1] end end
  ui.difficulty=nextValue;ui.selectedCast=nil;ui.timelineOffset=0;ui.Refresh()
 end)
 ui.onlyMine=CheckBox(page,'Only mine',100,'Show only assignments for you: your name, your role or everyone.')
 ui.onlyMine:SetPoint('TOPLEFT',550,-59)
 ui.onlyMine:SetScript('OnClick',function() ui.offset=0;ui.timelineOffset=0;ui.Refresh() end)
 -- Team roster in the header so it is reachable from both views.
 ui.rosterButton=Button(page,'Team roster',646,-54,92,function() ui.OpenRoster() end)
 ui.rosterButton.label:ClearAllPoints();ui.rosterButton.label:SetPoint('CENTER');ui.rosterButton.label:SetWidth(90);ui.rosterButton.label:SetJustifyH('CENTER')
 ui.viewButton=Button(page,'',744,-54,120,function() ui.SetView(ui.view=='timeline' and 'table' or 'timeline') end)
 ui.count=Text(page,'',2,-87,10,'muted',420)
 ui.status=Text(page,'',0,-586,11,'accent',314)
 -- Plan sharing: button, automatic send with the leader's ready check, and
 -- Accept/Decline for plans shared by others.
 ui.sharePlan=Button(page,'Share plan',430,-582,100,function()
  if not ui.bossID then ui.status:SetText('Choose a boss first.');return end
  local _,message=A.PlanShare.Send(ui.bossID);ui.status:SetText(message)
 end)
 ui.sharePlan:SetHeight(20);ui.sharePlan.label:ClearAllPoints();ui.sharePlan.label:SetPoint('CENTER');ui.sharePlan.label:SetWidth(100);ui.sharePlan.label:SetJustifyH('CENTER')
 ui.autoShare=CheckBox(page,'Send with my ready check',190,'When you are raid leader or assistant and start a ready check, the plan for the current boss is sent to the group.')
 ui.autoShare:SetPoint('TOPLEFT',540,-583)
 ui.autoShare:SetScript('OnClick',function(self) local store=A.Store();if store then store.autoSharePlan=self:GetChecked() and true or false end end)
 -- Test pull: run this boss's plan on its timeline to check reminders.
 ui.testPull=Button(page,'Test pull',324,-582,100,function()
  local Run=A.Runtime
  if Run.test then Run.Stop();ui.status:SetText('Test pull stopped.');ui.Refresh();return end
  if not ui.bossID then ui.status:SetText('Choose a boss first.');return end
  local _,message=Run.StartTest(ui.bossID,ui.difficulty);ui.status:SetText(message);ui.Refresh()
 end)
 ui.testPull:SetHeight(20);ui.testPull.label:ClearAllPoints();ui.testPull.label:SetPoint('CENTER');ui.testPull.label:SetWidth(100);ui.testPull.label:SetJustifyH('CENTER')
 -- Leader view: preview the in-fight overview to place it and set its options.
 ui.leaderView=Button(page,'Leader view',744,-582,120,function()
  if not (A.Overview and A.Overview.ShowPreview()) then ui.status:SetText('The leader view can be placed out of combat.') end
 end)
 -- Signup check: compare named assignments with a calendar event's sign-ups.
 ui.signupEvent=nil
 local eventMenu=Surface('Frame',page);ui.signupMenu=eventMenu
 eventMenu:SetSize(410,10+9*24);eventMenu:SetFrameLevel(page:GetFrameLevel()+30);eventMenu:EnableMouse(true);eventMenu:Hide()
 ui.signupRows={}
 for index=1,9 do
  local row;row=Button(eventMenu,'',5,-5-(index-1)*24,400,function()
   if not row.option then return end
   ui.signupEvent=row.option.event;eventMenu:Hide();ui.RefreshSignupButton()
  end)
  row:SetHeight(22);row.label:ClearAllPoints();row.label:SetPoint('LEFT',10,0);row.label:SetWidth(380);row.label:SetWordWrap(false)
  ui.signupRows[index]=row
 end
 function ui.RefreshSignupButton()
  ui.signupEventButton.label:SetText((ui.signupEvent and ui.signupEvent.label or 'Next raid (automatic)')..'  v')
 end
 ui.signupEventButton=Button(page,'',324,-608,410,function()
  if eventMenu:IsShown() then eventMenu:Hide();return end
  local list,err=A.Signups.Upcoming()
  if not list then ui.status:SetText(err);return end
  local options={{label='Next raid (automatic)'}}
  for _,event in ipairs(list) do if #options<9 then options[#options+1]={label=event.label,event=event} end end
  for index,row in ipairs(ui.signupRows) do
   local option=options[index];row.option=option
   if option then row.label:SetText(option.label);row:Show() else row:Hide() end
  end
  if #list==0 then ui.status:SetText('No guild event in the next 7 days. Has Guilds of WoW added the raid to the calendar?') end
  eventMenu:SetHeight(10+#options*24);eventMenu:ClearAllPoints();eventMenu:SetPoint('BOTTOMLEFT',ui.signupEventButton,'TOPLEFT',0,2);eventMenu:Show()
 end)
 ui.signupEventButton:SetHeight(20);ui.signupEventButton.label:ClearAllPoints();ui.signupEventButton.label:SetPoint('LEFT',10,0);ui.signupEventButton.label:SetWidth(390);ui.signupEventButton.label:SetWordWrap(false)
 ui.RefreshSignupButton()
 ui.checkSignups=Button(page,'Check signups',744,-608,120,function()
  eventMenu:Hide();ui.status:SetText('Checking signups...')
  local ok,message=A.Signups.Check(ui.signupEvent,function(result,err)
   if not result then ui.status:SetText(err);return end
   ui.ShowSignups(result);ui.Refresh()
  end)
  if not ok then ui.status:SetText(message) end
 end)
 ui.checkSignups:SetHeight(20);ui.checkSignups.label:ClearAllPoints();ui.checkSignups.label:SetPoint('CENTER');ui.checkSignups.label:SetWidth(120);ui.checkSignups.label:SetJustifyH('CENTER')
 ui.leaderView:SetHeight(20);ui.leaderView.label:ClearAllPoints();ui.leaderView.label:SetPoint('CENTER');ui.leaderView.label:SetWidth(120);ui.leaderView.label:SetJustifyH('CENTER')
 ui.planAccept=Button(page,'Accept',430,-581,76,function() local _,message=A.PlanShare.Accept();ui.status:SetText(message);ui.Refresh() end)
 ui.planDecline=Button(page,'Decline',514,-581,80,function() local _,message=A.PlanShare.Decline();ui.status:SetText(message);ui.Refresh() end)
 for _,button in ipairs({ui.planAccept,ui.planDecline}) do button:SetHeight(22);button:Hide() end

 ---------------------------------------------------------------- Timeline view
 local tl=Surface('Frame',timelineView,'background');tl:SetPoint('TOPLEFT',0,-104);tl:SetSize(452,TIMELINE_ROWS*20+8);tl:EnableMouseWheel(true);ui.timelineList=tl
 ui.timelineRows={}
 for index=1,TIMELINE_ROWS do
  local row;row=Button(tl,'',4,-4-(index-1)*20,444,function()
   local item=row.item;if not item or item.kind~='cast' then return end
   if ui.CancelEdit then ui.CancelEdit() end
   ui.selectedCast=item;ui.rosterOffset=0;ui.Refresh()
  end)
  row:SetHeight(19);row.label:Hide()
  row.time=Text(row,'',6,-4,10,'accent',36)
  row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(15,15);row.icon:SetPoint('TOPLEFT',44,-2)
  row.name=Text(row,'',64,-4,11,'text',180);row.name:SetWordWrap(false)
  row.assigned=Text(row,'',248,-4,10,'muted',192);row.assigned:SetWordWrap(false)
  -- The game's own spell tooltip explains what the boss ability does.
  row:HookScript('OnEnter',function(self)
   local item=self.item
   if not GameTooltip or not item or item.kind~='cast' then return end
   GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
   if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(item.spellID) else GameTooltip:SetText(item.ability,1,1,1) end
   GameTooltip:AddLine(' ')
   GameTooltip:AddLine(string.format('Cast %d of %d  ·  %s from pull',item.cast,item.total or item.cast,A.FormatTime(item.time)),.72,.76,.81)
   local who={}
   for _,entry in ipairs(A.EntriesForCast(ui.bossID,item.ability,item.cast)) do who[#who+1]=A.FormatWho(entry.who)..': '..Describe(entry) end
   GameTooltip:AddLine(#who>0 and ('Assigned: '..table.concat(who,', ')) or 'Nobody assigned. Click to assign.',.75,.78,.82,true)
   GameTooltip:Show()
  end)
  row:HookScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  ui.timelineRows[index]=row
 end
 tl:SetScript('OnMouseWheel',function(_,delta) ui.timelineOffset=math.max(0,math.min(ui.timelineMaximum or 0,ui.timelineOffset-delta*3));ui.Refresh() end)
 ui.timelineEmpty=Text(tl,'',12,-14,12,'muted',420)

 local side=Surface('Frame',timelineView,'background');side:SetPoint('TOPLEFT',462,-104);side:SetSize(402,TIMELINE_ROWS*20+8);side:EnableMouseWheel(true);ui.side=side
 ui.castTitle=Text(side,'',12,-10,13,'text',270)
 ui.castTitle:SetWordWrap(false)
 -- Pick from the online group or the imported team roster.
 ui.sourceButton=Button(side,'',300,-6,92,function()
  ui.source=ui.source=='team' and 'group' or 'team'
  local store=A.Store();if store then store.source=ui.source end
  ui.rosterOffset=0;ui.Refresh()
 end)
 ui.sourceButton:SetHeight(22);ui.sourceButton.label:ClearAllPoints();ui.sourceButton.label:SetPoint('CENTER');ui.sourceButton.label:SetWidth(90);ui.sourceButton.label:SetJustifyH('CENTER')
 Text(side,'ASSIGNED',12,-34,10,'accent',200)
 ui.assignedRows={}
 for index=1,4 do
  local line=CreateFrame('Frame',nil,side);line:SetSize(380,20);line:SetPoint('TOPLEFT',12,-50-(index-1)*21)
  line.icon=line:CreateTexture(nil,'ARTWORK');line.icon:SetSize(16,16);line.icon:SetPoint('LEFT',0,0)
  line.text=Text(line,'',22,-3,11,'text',284);line.text:SetWordWrap(false)
  line.edit=Button(line,'Edit',310,0,42,function() if line.entry then ui.EditAssignment(line.entry) end end)
  line.edit:SetHeight(20);line.edit.label:ClearAllPoints();line.edit.label:SetPoint('CENTER');line.edit.label:SetWidth(42);line.edit.label:SetJustifyH('CENTER')
  line.remove=Button(line,'x',356,0,24,function() if line.entry then local _,message=A.Delete(ui.bossID,line.entry.id);ui.status:SetText(message);ui.Refresh() end end)
  line.remove:SetHeight(20);line.remove.label:ClearAllPoints();line.remove.label:SetPoint('CENTER');line.remove.label:SetWidth(24);line.remove.label:SetJustifyH('CENTER')
  line:Hide();ui.assignedRows[index]=line
 end
 ui.assignedNone=Text(side,'',12,-52,11,'muted',380)
 ui.categoryButtons={}
 local categories={{nil,'All'}}
 for _,category in ipairs(A.cooldownCategories) do categories[#categories+1]=category end
 categories[#categories+1]={'actions','Actions'}
 for index,category in ipairs(categories) do
  local value=category[1]
  local button=Button(side,category[2],12+(index-1)*63,-140,60,function() ui.category=value;ui.rosterOffset=0;ui.Refresh() end)
  button:SetHeight(24);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(60);button.label:SetJustifyH('CENTER')
  button.value=value;ui.categoryButtons[index]=button
 end
 ui.rosterRows={}
 for index=1,ROSTER_ROWS do
  local row=CreateFrame('Frame',nil,side);row:SetSize(380,26);row:SetPoint('TOPLEFT',12,-172-(index-1)*26)
  row.name=Text(row,'',0,-7,11,'text',96);row.name:SetWordWrap(false)
  -- Signup marker (after Check signups): red not signed up, amber tentative, blue-grey standby.
  row.signupMark=row:CreateTexture(nil,'ARTWORK');row.signupMark:SetSize(3,20);row.signupMark:SetPoint('LEFT',-7,0);row.signupMark:Hide()
  row.icons={}
  for slot=1,ICONS do
   local icon=Surface('Button',row,'raised');icon:SetSize(24,24);icon:SetPoint('TOPLEFT',100+(slot-1)*26,-1)
   icon.texture=icon:CreateTexture(nil,'ARTWORK');icon.texture:SetPoint('TOPLEFT',2,-2);icon.texture:SetPoint('BOTTOMRIGHT',-2,2)
   icon:SetScript('OnEnter',function(self)
    self:SetBackdropBorderColor(unpack(colours.highlight))
    if GameTooltip and self.spell then
     GameTooltip:SetOwner(self,'ANCHOR_TOP')
     if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spell.spellID) else GameTooltip:SetText(self.spell.name,1,1,1) end
     GameTooltip:AddLine(' ')
     GameTooltip:AddLine('Click to assign '..row.member.name..' to this cast.',.75,.78,.82,true)
     if row.signup and row.signup~='ok' then
      local text={missing='Not signed up for ',tentative='Tentative for ',standby='On standby for '}
      local colour=row.signup=='missing' and {.88,.35,.35} or row.signup=='tentative' and {.88,.69,.25} or {.56,.64,.75}
      GameTooltip:AddLine(text[row.signup]..(A.Signups.last.event and A.Signups.last.event.title or 'the raid')..'.',colour[1],colour[2],colour[3],true)
     end
     GameTooltip:Show()
    end
   end)
   icon:SetScript('OnLeave',function(self) self:SetBackdropBorderColor(unpack(colours.border));if GameTooltip then GameTooltip:Hide() end end)
   icon:SetScript('OnClick',function(self) if self.spell and row.member then ui.Assign(row.member,self.spell) end end)
   icon:Hide();row.icons[slot]=icon
  end
  row:Hide();ui.rosterRows[index]=row
 end
 side:SetScript('OnMouseWheel',function(_,delta) ui.rosterOffset=math.max(0,math.min(ui.rosterMaximum or 0,ui.rosterOffset-delta));ui.Refresh() end)
 ui.rosterNone=Text(side,'',12,-176,11,'muted',380)
 -- Actions: role-wide calls such as tank swaps, plus a custom action for anyone.
 local actions=CreateFrame('Frame',nil,side);actions:SetPoint('TOPLEFT',12,-172);actions:SetSize(380,270);actions:Hide();ui.actions=actions
 ui.actionButtons={}
 local actionRows={
  {'ALL','Everyone',{'Stack','Spread','Soak','Dodge','Defensive'}},
  {'TANK','Tanks',{'Tank swap','Taunt','Defensive'}},
  {'HEALER','Healers',{'Healing CD','Dispel'}},
  {'MELEE','Melee',{'Interrupt','Soak','Burst'}},
  {'RANGED','Ranged',{'Interrupt','Soak','Burst','Spread'}},
 }
 for index,spec in ipairs(actionRows) do
  local role,label,list=spec[1],spec[2],spec[3]
  Text(actions,label,0,-6-(index-1)*28,11,'accent',62)
  local x=62
  for _,action in ipairs(list) do
   local width=action:len()>6 and 70 or 56
   local chip=Button(actions,action,x,-(index-1)*28,width,function() ui.AssignAction({role},action) end)
   chip:SetHeight(24);chip.label:ClearAllPoints();chip.label:SetPoint('CENTER');chip.label:SetWidth(width);chip.label:SetJustifyH('CENTER')
   chip.role,chip.action=role,action;ui.actionButtons[#ui.actionButtons+1]=chip
   x=x+width+4
  end
 end
 ui.customLabel=Text(actions,'Custom',0,-152,11,'accent',70)
 ui.customAction=Input(actions,70,-146,150,40)
 -- Who dropdown (multi-select): roles, raid groups, then each person in the
 -- team roster or group. Clicking toggles; the list stays open until closed.
 local whoList=Surface('Frame',actions);ui.customWhoMenu=whoList
 local WHO_ROWS=9
 whoList:SetSize(176,10+WHO_ROWS*22);whoList:SetFrameLevel(side:GetFrameLevel()+30);whoList:EnableMouse(true);whoList:EnableMouseWheel(true);whoList:Hide()
 ui.customWhoRows={};ui.customTargets={ALL=true};local whoOptions,whoOffset={},0
 local function WhoSelection()
  local list={}
  for _,option in ipairs(whoOptions) do if ui.customTargets[option[1]] then list[#list+1]=option[1] end end
  for key in pairs(ui.customTargets) do
   local listed=false;for _,value in ipairs(list) do if value==key then listed=true end end
   if not listed then list[#list+1]=key end
  end
  return list
 end
 function ui.CustomWho() local list=WhoSelection();if #list==0 then list={'ALL'} end;return list end
 function ui.SetCustomWho(list)
  ui.customTargets={}
  for _,key in ipairs(list or {}) do ui.customTargets[key]=true end
  if not next(ui.customTargets) then ui.customTargets={ALL=true} end
 end
 local function WhoLabel()
  local list=ui.CustomWho()
  local first=A.roleLabels[list[1]] or list[1]
  ui.customWho.label:SetText((#list>1 and (first..' +'..(#list-1)) or first)..'  v')
 end
 local bar=Surface('Slider',whoList,'background');ui.customWhoBar=bar
 bar:SetPoint('TOPRIGHT',-5,-5);bar:SetSize(8,WHO_ROWS*22-2);bar:SetOrientation('VERTICAL');bar:SetValueStep(1);bar:SetObeyStepOnDrag(true)
 bar:SetThumbTexture('Interface\\Buttons\\WHITE8X8')
 local thumb=bar:GetThumbTexture();thumb:SetSize(6,24);thumb:SetVertexColor(unpack(colours.accent))
 local function DrawWho()
  local maximum=math.max(0,#whoOptions-WHO_ROWS)
  whoOffset=math.max(0,math.min(whoOffset,maximum))
  for index,row in ipairs(ui.customWhoRows) do
   local option=whoOptions[index+whoOffset];row.option=option
   if option then
    local selected=ui.customTargets[option[1]] and true or false
    row.label:SetText(option[2]);row.mark:SetShown(selected)
    row:SetBackdropBorderColor(unpack(selected and colours.highlight or colours.border));row:Show()
   else row:Hide() end
  end
  ui.updatingWhoBar=true;bar:SetMinMaxValues(0,maximum);bar:SetValue(whoOffset);ui.updatingWhoBar=false
  bar:SetEnabled(maximum>0);bar:SetAlpha(maximum>0 and 1 or .35)
 end
 bar:SetScript('OnValueChanged',function(_,value) if ui.updatingWhoBar then return end;whoOffset=math.floor(value+.5);DrawWho() end)
 for index=1,WHO_ROWS do
  local row;row=Button(whoList,'',5,-5-(index-1)*22,152,function()
   if not row.option then return end
   local key=row.option[1]
   if ui.customTargets[key] then ui.customTargets[key]=nil else ui.customTargets[key]=true end
   if key=='ALL' and ui.customTargets.ALL then ui.customTargets={ALL=true}
   elseif key~='ALL' then ui.customTargets.ALL=nil end
   if not next(ui.customTargets) then ui.customTargets={ALL=true} end
   WhoLabel();DrawWho()
  end)
  -- 20 px rows: lift the text clear of the border and leave room for the check mark.
  row:SetHeight(20);row.label:ClearAllPoints();row.label:SetPoint('LEFT',20,1);row.label:SetWidth(126);row.label:SetWordWrap(false)
  row.mark=row:CreateTexture(nil,'ARTWORK');row.mark:SetSize(8,8);row.mark:SetPoint('LEFT',7,0);row.mark:SetColorTexture(unpack(colours.highlight));row.mark:Hide()
  ui.customWhoRows[index]=row
 end
 whoList:SetScript('OnMouseWheel',function(_,delta) whoOffset=whoOffset-delta;DrawWho() end)
 ui.customWho=Button(actions,'',226,-146,94,function()
  if whoList:IsShown() then whoList:Hide();return end
  whoOptions={{'ALL','Everyone'},{'TANK','Tanks'},{'HEALER','Healers'},{'DAMAGER','DPS'},{'MELEE','Melee DPS'},{'RANGED','Ranged DPS'}}
  for group=1,8 do whoOptions[#whoOptions+1]={'G'..group,'Group '..group} end
  for _,member in ipairs(ui.Members()) do whoOptions[#whoOptions+1]={member.name,member.name} end
  whoOffset=0;DrawWho()
  whoList:ClearAllPoints();whoList:SetPoint('BOTTOMRIGHT',ui.customWho,'TOPRIGHT',0,2);whoList:Show()
 end)
 ui.customWho:SetHeight(26);ui.customWho.label:SetWidth(84);ui.customWho.label:SetWordWrap(false)
 ui.RefreshCustomWho=WhoLabel
 ui.customAdd=Button(actions,'Add',324,-146,56,function()
  local text=ui.customAction:GetText():gsub('^%s+',''):gsub('%s+$','')
  if ui.editingAssignment then ui.SaveEditedAssignment(text);return end
  if text=='' then ui.status:SetText('Type the action first, for example "Use healthstone".');return end
  if ui.AssignAction(ui.CustomWho(),text,ui.customShow) then ui.customAction:SetText('');ui.customWhoMenu:Hide() end
 end)
 ui.customAdd:SetHeight(26)
 -- How this assignment is shown in the fight: bar, text, icon and/or sound.
 Text(actions,'Show as',0,-182,11,'accent',62)
 ui.customShow={bar=true,text=true,icon=false,sound=false};ui.showButtons={}
 local function DrawShow()
  for _,button in ipairs(ui.showButtons) do
   local on=ui.customShow[button.key]
   button:SetBackdropBorderColor(unpack(on and colours.highlight or colours.border))
   button.label:SetTextColor(unpack(on and colours.text or colours.muted))
  end
 end
 ui.DrawShow=DrawShow
 for index,spec in ipairs({{'bar','Bar'},{'text','Text'},{'icon','Icon'},{'sound','Sound'}}) do
  local key=spec[1]
  local toggle=Button(actions,spec[2],62+(index-1)*60,-176,56,function()
   ui.customShow[key]=not ui.customShow[key];DrawShow()
  end)
  toggle:SetHeight(22);toggle.key=key;toggle.label:ClearAllPoints();toggle.label:SetPoint('CENTER');toggle.label:SetWidth(56);toggle.label:SetJustifyH('CENTER')
  ui.showButtons[index]=toggle
 end
 DrawShow()
 ui.customCancel=Button(actions,'Cancel',304,-176,76,function() ui.CancelEdit() end)
 ui.customCancel:SetHeight(22);ui.customCancel.label:ClearAllPoints();ui.customCancel.label:SetPoint('CENTER');ui.customCancel.label:SetWidth(76);ui.customCancel.label:SetJustifyH('CENTER');ui.customCancel:Hide()
 -- Edit an assignment in the custom row: who and text for actions; who and an
 -- optional note for cooldowns (the spell stays).
 function ui.EditAssignment(entry)
  ui.editingAssignment=entry.id;ui.editingSpell=entry.spellID
  ui.category='actions';ui.customWhoMenu:Hide()
  ui.customAction:SetText(entry.text or '');ui.SetCustomWho(entry.who)
  local flags=A.ShowFlags and A.ShowFlags(entry) or {bar=true,text=true}
  ui.customShow={bar=flags.bar,text=flags.text,icon=flags.icon,sound=flags.sound};ui.DrawShow()
  ui.customSound=entry.soundFile;ui.RefreshSound();ui.soundMenu:Hide()
  ui.customLabel:SetText('Editing');ui.customAdd.label:SetText('Save');ui.customCancel:Show()
  ui.status:SetText('Editing '..A.FormatWho(entry.who)..': '..Describe(entry)..(entry.spellID and '. Change who, or add a note.' or '. Change who or the action.'))
  ui.Refresh();ui.RefreshCustomWho()
 end
 function ui.CancelEdit()
  if not ui.editingAssignment then return end
  ui.editingAssignment,ui.editingSpell=nil,nil
  ui.customAction:SetText('');ui.SetCustomWho({'ALL'})
  ui.customShow={bar=true,text=true,icon=false,sound=false};ui.DrawShow()
  ui.customSound=nil;ui.RefreshSound();ui.soundMenu:Hide()
  -- Drop the "Editing ..." prompt; keep messages such as "Updated: ...".
  if (ui.status:GetText() or ''):find('^Editing ') then ui.status:SetText('') end
  ui.customLabel:SetText('Custom');ui.customAdd.label:SetText('Add');ui.customCancel:Hide();ui.customWhoMenu:Hide()
  ui.RefreshCustomWho()
 end
 function ui.SaveEditedAssignment(text)
  local plan=A.Plan(ui.bossID);local original
  for _,entry in ipairs(plan and plan.entries or {}) do if entry.id==ui.editingAssignment then original=entry end end
  if not original then ui.status:SetText('That assignment no longer exists.');ui.CancelEdit();ui.Refresh();return end
  if not original.spellID and text=='' then ui.status:SetText('Type the action, or Cancel.');return end
  local updated={time=original.time,phase=original.phase,who=ui.CustomWho(),spellID=original.spellID,text=text~='' and text or nil,anchor=original.anchor,
   show={bar=ui.customShow.bar==true,text=ui.customShow.text==true,icon=ui.customShow.icon==true,sound=ui.customShow.sound==true},
   soundFile=ui.customShow.sound and ui.customSound or nil}
  local ok,message=A.Save(ui.bossID,ui.bossName,updated,original.id)
  ui.status:SetText(ok and ('Updated: '..A.FormatWho(updated.who)..': '..Describe(updated)..'.') or message)
  if ok then ui.CancelEdit() end
  ui.Refresh()
 end
 -- Sound: raid warning by default, or any bundled sound (played on choosing).
 Text(actions,'Sound',0,-214,11,'accent',62)
 ui.customSound=nil
 local function SoundPath(relative) return 'Interface\\AddOns\\VincRaidTools\\Media\\Sounds\\'..relative:gsub('/','\\') end
 local SoundName,PlayChoice=A.SoundName,A.PlayAssignmentSound
 local soundMenu=Surface('Frame',actions);ui.soundMenu=soundMenu
 local SOUND_ROWS=10
 soundMenu:SetSize(256,10+SOUND_ROWS*22);soundMenu:SetFrameLevel(side:GetFrameLevel()+30);soundMenu:EnableMouse(true);soundMenu:EnableMouseWheel(true);soundMenu:Hide()
 ui.soundRows={};local soundOptions,soundOffset={},0
 local soundBar=Surface('Slider',soundMenu,'background');ui.soundBar=soundBar
 soundBar:SetPoint('TOPRIGHT',-5,-5);soundBar:SetSize(8,SOUND_ROWS*22-2);soundBar:SetOrientation('VERTICAL');soundBar:SetValueStep(1);soundBar:SetObeyStepOnDrag(true)
 local soundThumb=soundBar:CreateTexture(nil,'OVERLAY');soundThumb:SetColorTexture(1,1,1,1);soundThumb:SetSize(6,24);soundThumb:SetVertexColor(unpack(colours.accent));soundBar:SetThumbTexture(soundThumb)
 local function DrawSounds()
  local maximum=math.max(0,#soundOptions-SOUND_ROWS)
  soundOffset=math.max(0,math.min(soundOffset,maximum))
  for index,row in ipairs(ui.soundRows) do
   local option=soundOptions[index+soundOffset];row.option=option
   if option then
    local selected=option.file==ui.customSound
    row.label:SetText(option.label);row.mark:SetShown(selected)
    row:SetBackdropBorderColor(unpack(selected and colours.highlight or colours.border));row:Show()
   else row:Hide() end
  end
  ui.updatingSoundBar=true;soundBar:SetMinMaxValues(0,maximum);soundBar:SetValue(soundOffset);ui.updatingSoundBar=false
  soundBar:SetEnabled(maximum>0);soundBar:SetAlpha(maximum>0 and 1 or .35)
 end
 soundBar:SetScript('OnValueChanged',function(_,value) if ui.updatingSoundBar then return end;soundOffset=math.floor(value+.5);DrawSounds() end)
 soundMenu:SetScript('OnMouseWheel',function(_,delta) soundOffset=soundOffset-delta*3;DrawSounds() end)
 function ui.RefreshSound() ui.soundButton.label:SetText(SoundName(ui.customSound)..'  v') end
 -- Choosing a sound plays it and turns Sound on for this assignment.
 function ui.ChooseSound(file)
  ui.customSound=file;ui.customShow.sound=true;ui.DrawShow();ui.RefreshSound();PlayChoice(file)
 end
 for index=1,SOUND_ROWS do
  local row;row=Button(soundMenu,'',5,-5-(index-1)*22,232,function()
   if not row.option then return end
   ui.ChooseSound(row.option.file);DrawSounds()
  end)
  row:SetHeight(20);row.label:ClearAllPoints();row.label:SetPoint('LEFT',20,1);row.label:SetWidth(206);row.label:SetWordWrap(false)
  row.mark=row:CreateTexture(nil,'ARTWORK');row.mark:SetSize(8,8);row.mark:SetPoint('LEFT',7,0);row.mark:SetColorTexture(unpack(colours.highlight));row.mark:Hide()
  ui.soundRows[index]=row
 end
 ui.soundButton=Button(actions,'',62,-208,236,function()
  if soundMenu:IsShown() then soundMenu:Hide();return end
  soundOptions={{label='Raid warning (default)'}}
  -- DBM voice lines first: each player hears them in their own DBM voice pack.
  for _,voice in ipairs(A.DBMVoices) do soundOptions[#soundOptions+1]={label='DBM voice: '..voice[2],file='DBM:'..voice[1]} end
  local list={}
  for _,relative in ipairs(addon.Reminders and addon.Reminders.SoundPaths and addon.Reminders.SoundPaths() or {}) do list[#list+1]={label=relative:gsub('%.ogg$',''):gsub('/',' / '),file=SoundPath(relative)} end
  table.sort(list,function(a,b) return a.label:lower()<b.label:lower() end)
  for _,option in ipairs(list) do soundOptions[#soundOptions+1]=option end
  soundOffset=0
  for index,option in ipairs(soundOptions) do if option.file==ui.customSound then soundOffset=index-1 end end
  DrawSounds()
  soundMenu:ClearAllPoints();soundMenu:SetPoint('BOTTOMLEFT',ui.soundButton,'TOPLEFT',0,2);soundMenu:Show()
 end)
 ui.soundButton:SetHeight(22);ui.soundButton.label:ClearAllPoints();ui.soundButton.label:SetPoint('LEFT',10,0);ui.soundButton.label:SetWidth(216);ui.soundButton.label:SetWordWrap(false)
 ui.soundPlay=Button(actions,'Play',304,-208,76,function() PlayChoice(ui.customSound) end)
 ui.soundPlay:SetHeight(22);ui.soundPlay.label:ClearAllPoints();ui.soundPlay.label:SetPoint('CENTER');ui.soundPlay.label:SetWidth(76);ui.soundPlay.label:SetJustifyH('CENTER')
 ui.RefreshSound()
 Text(actions,'Bar and icon appear 10 s before the cast; text and sound 3 s before.',0,-242,10,'muted',380)

 -- Group members with class and role; the player always appears.
 function ui.Members()
  local roster=A.Roster and A.Roster()
  if ui.source=='team' and roster then
   local members={}
   for _,member in ipairs(roster.members) do members[#members+1]={name=member.name,class=member.class,role=member.role,spec=member.spec} end
   table.sort(members,function(a,b) if a.class~=b.class then return a.class<b.class end;return a.name<b.name end)
   return members
  end
  local units={}
  if IsInRaid() then for index=1,GetNumGroupMembers() do units[#units+1]='raid'..index end
  else units[1]='player';for index=1,4 do if UnitExists('party'..index) then units[#units+1]='party'..index end end end
  local members,seen={},{}
  for _,unit in ipairs(units) do
   local name=UnitName(unit);local _,class=UnitClass(unit)
   if name and class and not seen[name] then
    seen[name]=true
    local role=UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if (not role or role=='NONE') and UnitIsUnit and UnitIsUnit(unit,'player') and addon.Reminders and addon.Reminders.PlayerRole then role=addon.Reminders.PlayerRole() end
    members[#members+1]={name=name,class=class,role=role}
   end
  end
  table.sort(members,function(a,b) if a.class~=b.class then return a.class<b.class end;return a.name<b.name end)
  return members
 end
 function ui.Assign(member,spell)
  local cast=ui.selectedCast;if not cast or not ui.bossID then return end
  for _,entry in ipairs(A.EntriesForCast(ui.bossID,cast.ability,cast.cast)) do
   if entry.spellID==spell.spellID and entry.who[1]==member.name then ui.status:SetText(member.name..' already has '..spell.name..' here.');return end
  end
  local ok,message=A.Save(ui.bossID,ui.bossName,{time=cast.time,who={member.name},spellID=spell.spellID,anchor={ability=cast.ability,cast=cast.cast}})
  ui.status:SetText(ok and (member.name..': '..spell.name..' on '..cast.ability..' ('..cast.cast..') at '..A.FormatTime(cast.time)..'.') or message)
  ui.Refresh()
 end
 function ui.AssignAction(who,text,show)
  local cast=ui.selectedCast;if not cast or not ui.bossID then return false end
  for _,entry in ipairs(A.EntriesForCast(ui.bossID,cast.ability,cast.cast)) do
   if not entry.spellID and entry.text==text and table.concat(entry.who,',')==table.concat(who,',') then ui.status:SetText(A.FormatWho(who)..' already has "'..text..'" here.');return false end
  end
  local entry={time=cast.time,who=who,text=text,anchor={ability=cast.ability,cast=cast.cast}}
  if show then entry.show={bar=show.bar==true,text=show.text==true,icon=show.icon==true,sound=show.sound==true} end
  if show and show.sound and ui.customSound then entry.soundFile=ui.customSound end
  local ok,message=A.Save(ui.bossID,ui.bossName,entry)
  ui.status:SetText(ok and (A.FormatWho(who)..': '..text..' on '..cast.ability..' ('..cast.cast..') at '..A.FormatTime(cast.time)..'.') or message)
  ui.Refresh();return ok
 end
 function ui.RefreshTimeline()
  local timeline=ui.bossID and ui.difficulty and A.Timeline(ui.bossID,ui.difficulty)
  local rows={}
  local mine=ui.onlyMine:GetChecked()
  for _,item in ipairs(timeline and A.TimelineRows(ui.bossID,ui.difficulty) or {}) do
   if item.kind=='phase' or not mine then rows[#rows+1]=item
   else
    for _,entry in ipairs(A.EntriesForCast(ui.bossID,item.ability,item.cast)) do if A.IsMine(entry) then rows[#rows+1]=item;break end end
   end
  end
  ui.timelineMaximum=math.max(0,#rows-TIMELINE_ROWS);ui.timelineOffset=math.min(ui.timelineOffset,ui.timelineMaximum)
  for index,row in ipairs(ui.timelineRows) do
   local item=rows[index+ui.timelineOffset];row.item=item
   if not item then row:Hide()
   elseif item.kind=='phase' then
    row.time:SetText(A.FormatTime(item.time));row.name:SetText((item.intermission and 'Intermission: ' or '')..item.name:gsub('^Intermission: ',''))
    row.name:SetTextColor(unpack(colours.accent));row.icon:Hide();row.assigned:SetText('')
    row:SetBackdropColor(0,0,0,0);row:SetBackdropBorderColor(0,0,0,0);row:Show()
   else
    local info=A.SpellInfo(item.spellID)
    row.time:SetText(A.FormatTime(item.time));row.name:SetText(item.ability..' ('..item.cast..')');row.name:SetTextColor(unpack(colours.text))
    row.icon:SetTexture(info and info.iconID or nil);row.icon:SetShown(info~=nil)
    local who={}
    for _,entry in ipairs(A.EntriesForCast(ui.bossID,item.ability,item.cast)) do who[#who+1]=WhoText(entry.who) end
    row.assigned:SetText(table.concat(who,', '))
    local selected=ui.selectedCast and ui.selectedCast.ability==item.ability and ui.selectedCast.cast==item.cast
    row:SetBackdropColor(unpack(colours.raised));row:SetBackdropBorderColor(unpack(selected and colours.highlight or colours.border))
    row:Show()
   end
  end
  ui.timelineEmpty:SetText(not ui.bossID and 'Choose a boss to see its abilities.' or
   (not timeline and 'No preloaded timeline for this boss yet. Use Table view to plan by time.' or (#rows==0 and 'Nothing assigned to you for this boss.' or '')))
  -- Right side: the selected cast.
  local cast=ui.selectedCast
  ui.castTitle:SetText(cast and (cast.ability..' ('..cast.cast..')  ·  '..A.FormatTime(cast.time)) or 'Click an ability on the left.')
  local assigned=cast and A.EntriesForCast(ui.bossID,cast.ability,cast.cast) or {}
  for index,line in ipairs(ui.assignedRows) do
   local entry=assigned[index];line.entry=entry
   if entry then
    local info=entry.spellID and A.SpellInfo(entry.spellID)
    line.icon:SetTexture(info and info.iconID or nil);line.icon:SetShown(info~=nil);line.text:SetText(WhoText(entry.who)..': '..Describe(entry));line:Show()
   else line:Hide() end
  end
  ui.assignedNone:SetText(cast and #assigned==0 and 'Nobody yet: pick a cooldown or an action below.' or (#assigned>4 and ('+'..(#assigned-4)..' more in Table view') or ''))
  for _,button in ipairs(ui.categoryButtons) do
   button:SetBackdropBorderColor(unpack(button.value==ui.category and colours.highlight or colours.border))
   button:SetShown(cast~=nil)
  end
  local roster=A.Roster and A.Roster()
  if ui.source=='team' and not roster then ui.source='group' end
  ui.sourceButton:SetShown(roster~=nil)
  ui.sourceButton.label:SetText(ui.source=='team' and 'Show: Team' or 'Show: Group')
  local showActions=cast~=nil and ui.category=='actions'
  ui.actions:SetShown(showActions)
  if showActions and ui.customWho.label:GetText()=='' then ui.customWho.label:SetText('Everyone  v') end
  if not showActions then ui.customWhoMenu:Hide() end
  local members=(cast and not showActions) and ui.Members() or {}
  local rosterRows={}
  for _,member in ipairs(members) do
   local spells=A.CooldownsFor(member.class,member.role,ui.category~='actions' and ui.category or nil)
   if #spells>0 then rosterRows[#rosterRows+1]={member=member,spells=spells} end
  end
  ui.rosterMaximum=math.max(0,#rosterRows-ROSTER_ROWS);ui.rosterOffset=math.min(ui.rosterOffset,ui.rosterMaximum)
  for index,row in ipairs(ui.rosterRows) do
   local data=rosterRows[index+ui.rosterOffset]
   if data then
    row.member=data.member
    local colour=RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.member.class]
    row.name:SetText(data.member.name)
    if colour then row.name:SetTextColor(colour.r,colour.g,colour.b) else row.name:SetTextColor(unpack(colours.text)) end
    -- After Check signups: not signed up is greyed out (still clickable);
    -- tentative and standby keep their colour; all three get a marker.
    local signup=A.Signups and A.Signups.StatusOf(data.member.name);row.signup=signup
    local missing=signup=='missing'
    if missing then row.name:SetTextColor(.42,.44,.48) end
    local marks={missing={.88,.35,.35},tentative={.88,.69,.25},standby={.56,.64,.75}}
    if marks[signup] then row.signupMark:SetColorTexture(unpack(marks[signup]));row.signupMark:Show() else row.signupMark:Hide() end
    for slot,icon in ipairs(row.icons) do
     local spell=data.spells[slot];icon.spell=spell
     if spell then icon.texture:SetTexture(spell.icon);icon.texture:SetDesaturated(missing);icon:SetAlpha(missing and .45 or 1);icon:Show() else icon:Hide() end
    end
    row:Show()
   else row.member=nil;row:Hide() end
  end
  ui.rosterNone:SetText(cast and not showActions and #rosterRows==0 and (ui.source=='team' and 'No matching cooldowns in the team roster.' or 'No matching cooldowns in your group.') or '')
 end

 ---------------------------------------------------------------- Table view
 for _,column in ipairs(COLUMNS) do Text(tableView,column[1]:upper(),column[2]+8,-98,10,'accent',column[3]) end
 local list=Surface('Frame',tableView,'background');list:SetPoint('TOPLEFT',0,-112);list:SetSize(864,VISIBLE*26+8);list:EnableMouseWheel(true);ui.list=list
 for index=1,VISIBLE do
  local row;row=Button(list,'',4,-4-(index-1)*26,856,function() if row.entry then ui.Edit(row.entry) end end)
  row:SetHeight(24);row.label:Hide();row.cells={}
  for c,column in ipairs(COLUMNS) do
   local cell=Text(row,'',column[2]+4+(c==4 and 22 or 0),-5,11,c==1 and 'accent' or 'text',column[3]-(c==4 and 26 or 8))
   cell:SetWordWrap(false);row.cells[c]=cell
  end
  row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(18,18);row.icon:SetPoint('TOPLEFT',COLUMNS[4][2]+2,-3)
  ui.rows[index]=row
 end
 list:SetScript('OnMouseWheel',function(_,delta) ui.offset=math.max(0,math.min(ui.maximum or 0,ui.offset-delta));ui.Refresh() end)
 ui.empty=Text(list,'',12,-14,12,'muted',800)
 local editY=-468
 for _,label in ipairs({{'TIME',0},{'PH',66},{'WHO',112},{'SPELL (NAME OR ID)',360},{'NOTE',572}}) do Text(tableView,label[1],label[2],editY,10,'muted',200) end
 ui.time=Input(tableView,0,editY-14,60,6)
 ui.phase=Input(tableView,66,editY-14,40,1)
 ui.who=Input(tableView,112,editY-14,210,200)
 ui.whoButton=Button(tableView,'v',326,editY-14,28,function() end)
 ui.spell=Input(tableView,360,editY-14,180,60)
 ui.spellIcon=tableView:CreateTexture(nil,'ARTWORK');ui.spellIcon:SetSize(24,24);ui.spellIcon:SetPoint('TOPLEFT',544,editY-15)
 ui.note=Input(tableView,572,editY-14,292,200)
 local function UpdateSpellPreview()
  local info=A.SpellInfo(ui.spell:GetText())
  ui.spellIcon:SetTexture(info and info.iconID or nil);ui.spellIcon:SetShown(info~=nil)
 end
 ui.spell:SetScript('OnTextChanged',UpdateSpellPreview)
 local whoMenu=Surface('Frame',tableView);ui.whoMenu=whoMenu
 whoMenu:SetSize(220,10+14*24);whoMenu:SetPoint('BOTTOMLEFT',ui.whoButton,'TOPLEFT',-214,2);whoMenu:SetFrameLevel(page:GetFrameLevel()+30)
 whoMenu:EnableMouse(true);whoMenu:Hide()
 local whoRows={}
 for index=1,14 do
  local row;row=Button(whoMenu,'',5,-5-(index-1)*24,210,function()
   if not row.value then return end
   local current=A.ParseWho(ui.who:GetText())
   current[#current+1]=row.value
   ui.who:SetText(A.FormatWho(A.ParseWho(A.FormatWho(current))));whoMenu:Hide()
  end)
  row:SetHeight(22);row.label:SetWordWrap(false);whoRows[index]=row
 end
 ui.whoRows=whoRows
 ui.whoButton:SetScript('OnClick',function()
  if whoMenu:IsShown() then whoMenu:Hide();return end
  local entries={{'Everyone','ALL'},{'Tanks','TANK'},{'Healers','HEALER'},{'DPS','DAMAGER'},{'Melee DPS','MELEE'},{'Ranged DPS','RANGED'}}
  local names={};for _,member in ipairs(ui.Members()) do names[#names+1]=member.name end;table.sort(names)
  for _,name in ipairs(names) do entries[#entries+1]={name,name} end
  for index,row in ipairs(whoRows) do
   local entry=entries[index]
   if entry then row.label:SetText(entry[1]);row.value=entry[2];row:Show() else row.value=nil;row:Hide() end
  end
  whoMenu:Show()
 end)
 local function Draft()
  local time=A.ParseTime(ui.time:GetText())
  if not time then return nil,'Enter a time such as 1:30 or 90.' end
  local phaseText=ui.phase:GetText():gsub('%s','')
  local phase=phaseText~='' and tonumber(phaseText) or nil
  if phaseText~='' and not phase then return nil,'Phase must be a number.' end
  local spellText=ui.spell:GetText():gsub('^%s+',''):gsub('%s+$','')
  local spellID
  if spellText~='' then
   local info=A.SpellInfo(spellText)
   spellID=info and info.spellID or tonumber(spellText)
   if not spellID then return nil,'Spell not found; use its exact name or ID.' end
  end
  local note=ui.note:GetText():gsub('^%s+',''):gsub('%s+$','')
  return {time=time,phase=phase,who=A.ParseWho(ui.who:GetText()),spellID=spellID,text=note~='' and note or nil}
 end
 function ui.ClearEditor()
  ui.editing=nil
  for _,box in ipairs({ui.time,ui.phase,ui.who,ui.spell,ui.note}) do box:SetText('');box:ClearFocus() end
  UpdateSpellPreview()
  ui.save.label:SetText('Add assignment');ui.delete:Hide()
 end
 function ui.Edit(entry)
  ui.editing=entry.id;ui.editingAnchor=entry.anchor
  ui.time:SetText(A.FormatTime(entry.time));ui.phase:SetText(entry.phase and tostring(entry.phase) or '')
  ui.who:SetText(A.FormatWho(entry.who));ui.spell:SetText(entry.spellID and tostring(entry.spellID) or '')
  ui.note:SetText(entry.text or '');UpdateSpellPreview()
  ui.save.label:SetText('Save changes');ui.delete:Show();ui.Refresh()
 end
 ui.save=Button(tableView,'Add assignment',0,-520,160,function()
  if not ui.bossID then ui.status:SetText('Choose a boss first.');return end
  local draft,err=Draft();if not draft then ui.status:SetText(err);return end
  if ui.editing then draft.anchor=ui.editingAnchor end
  local ok,message=A.Save(ui.bossID,ui.bossName,draft,ui.editing)
  ui.status:SetText(message or err)
  if ok then ui.ClearEditor();ui.Refresh() end
 end)
 ui.delete=Button(tableView,'Delete',170,-520,110,function()
  if not ui.editing then return end
  local _,message=A.Delete(ui.bossID,ui.editing);ui.status:SetText(message);ui.ClearEditor();ui.Refresh()
 end)
 ui.clearButton=Button(tableView,'New',290,-520,110,function() ui.ClearEditor();ui.Refresh() end)
 ui.importButton=Button(tableView,'Import text',614,-520,120,function() ui.OpenDialog(false) end)
 ui.exportButton=Button(tableView,'Export',744,-520,120,function() ui.OpenDialog(true) end)

 -- Import / export dialog.
 local dialog=Surface('Frame',window);ui.dialog=dialog
 dialog:SetSize(640,400);dialog:SetPoint('CENTER');dialog:SetFrameLevel(window:GetFrameLevel()+50);dialog:EnableMouse(true);dialog:Hide()
 dialog.title=Text(dialog,'',16,-14,16,'text',600)
 dialog.hint=Text(dialog,'',16,-40,11,'muted',600)
 local scroll=CreateFrame('ScrollFrame',nil,dialog,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',16,-64);scroll:SetPoint('BOTTOMRIGHT',-30,60)
 if addon.StyleScrollBar then addon.StyleScrollBar(scroll) end
 local box=CreateFrame('EditBox',nil,scroll);box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFont(STANDARD_TEXT_FONT,12,'')
 box:SetTextColor(.91,.92,.94);box:SetWidth(590);box:SetMaxLetters(60000);scroll:SetScrollChild(box)
 box:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 ui.dialogText=box
 ui.append=Button(dialog,'Add to plan',16,-352,150,function()
  local ok,message=A.Import(ui.bossID,ui.bossName,box:GetText(),false);ui.status:SetText(message)
  if ok then dialog:Hide();ui.Refresh() else dialog.hint:SetText(message) end
 end)
 ui.replace=Button(dialog,'Replace plan',176,-352,150,function()
  local ok,message=A.Import(ui.bossID,ui.bossName,box:GetText(),true);ui.status:SetText(message)
  if ok then dialog:Hide();ui.Refresh() else dialog.hint:SetText(message) end
 end)
 Button(dialog,'Close',474,-352,150,function() dialog:Hide() end)
 function ui.OpenDialog(export)
  if not ui.bossID then ui.status:SetText('Choose a boss first.');return end
  whoMenu:Hide();menu:Hide()
  if export then
   dialog.title:SetText('Export: '..(ui.bossName or 'boss'))
   dialog.hint:SetText('MRT note format. Copy with Ctrl+C; paste into MRT, websites or another VRT.')
   box:SetText(A.Export(ui.bossID));box:HighlightText();box:SetFocus()
   ui.append:Hide();ui.replace:Hide()
  else
   dialog.title:SetText('Import: '..(ui.bossName or 'boss'))
   dialog.hint:SetText('Paste MRT note lines ({time:1:30} Name {spell:31821}) or NSRT lines (time:90;tag:Name;spellid:31821).')
   box:SetText('');box:SetFocus()
   ui.append:Show();ui.replace:Show()
  end
  dialog:Show()
 end
 -- Signup results: grouped by category, then boss.
 local signupDialog=Surface('Frame',window);ui.signupDialog=signupDialog
 signupDialog:SetSize(640,400);signupDialog:SetPoint('CENTER');signupDialog:SetFrameLevel(window:GetFrameLevel()+50);signupDialog:EnableMouse(true);signupDialog:Hide()
 signupDialog.title=Text(signupDialog,'',16,-14,16,'text',600)
 signupDialog.summary=Text(signupDialog,'',16,-40,11,'muted',600)
 local signupScroll=CreateFrame('ScrollFrame',nil,signupDialog,'UIPanelScrollFrameTemplate');signupScroll:SetPoint('TOPLEFT',16,-64);signupScroll:SetPoint('BOTTOMRIGHT',-30,60)
 if addon.StyleScrollBar then addon.StyleScrollBar(signupScroll) end
 local signupText=CreateFrame('EditBox',nil,signupScroll);signupText:SetMultiLine(true);signupText:SetAutoFocus(false);signupText:SetFont(STANDARD_TEXT_FONT,12,'')
 signupText:SetTextColor(.91,.92,.94);signupText:SetWidth(590);signupText:SetMaxLetters(60000);signupScroll:SetScrollChild(signupText)
 signupText:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 -- Read-only: typing restores the report.
 signupText:SetScript('OnTextChanged',function(self,userInput) if userInput and ui.signupReport then self:SetText(ui.signupReport) end end)
 ui.signupText=signupText
 Button(signupDialog,'Close',474,-352,150,function() signupDialog:Hide() end)
 function ui.ShowSignups(result)
  local lines={}
  local headings={missing='|cffe05a5aNOT SIGNED UP|r (no reply, declined, out or not invited)',tentative='|cffe0b040TENTATIVE|r',standby='|cff8fa3bfSTANDBY|r (benched; may still be wanted)'}
  local counts={}
  for _,category in ipairs({'missing','tentative','standby'}) do
   local list=result[category];counts[category]=#list
   if #list>0 then
    lines[#lines+1]=headings[category]
    for _,item in ipairs(list) do
     local entry=item.entry
     local anchor=entry.anchor and (' on '..entry.anchor.ability..' ('..entry.anchor.cast..')') or (' at '..A.FormatTime(entry.time))
     lines[#lines+1]='   '..item.name..'  -  '..item.boss..': '..Describe(entry)..anchor
    end
    lines[#lines+1]=''
   end
  end
  if #lines==0 then lines[1]='Everyone assigned by name is signed up.' end
  ui.signupReport=table.concat(lines,'\n')
  signupDialog.title:SetText('Signups: '..result.event.label)
  signupDialog.summary:SetText(string.format('%d not signed up, %d tentative, %d standby. %d named assignments checked against %d calendar invites.',
   counts.missing,counts.tentative,counts.standby,result.checked,result.invites))
  signupText:SetText(ui.signupReport);signupDialog:Show()
  ui.status:SetText(string.format('Signups for %s: %d not signed up, %d tentative, %d standby.',result.event.title,counts.missing,counts.tentative,counts.standby))
 end
 -- Team roster dialog: paste, share, accept a share, clear.
 local rosterDialog=Surface('Frame',window);ui.rosterDialog=rosterDialog
 rosterDialog:SetSize(560,300);rosterDialog:SetPoint('CENTER');rosterDialog:SetFrameLevel(window:GetFrameLevel()+50);rosterDialog:EnableMouse(true);rosterDialog:Hide()
 Text(rosterDialog,'Team roster',16,-14,16,'text',520)
 rosterDialog.info=Text(rosterDialog,'',16,-40,11,'muted',520)
 rosterDialog.pending=Text(rosterDialog,'',16,-64,11,'accent',360)
 ui.rosterAccept=Button(rosterDialog,'Accept',380,-58,80,function() local _,message=A.RosterShare.Accept();ui.status:SetText(message);ui.RefreshRoster() end)
 ui.rosterDecline=Button(rosterDialog,'Decline',466,-58,80,function() local _,message=A.RosterShare.Decline();ui.status:SetText(message);ui.RefreshRoster() end)
 Text(rosterDialog,'Paste a roster string (from tools/gow_roster.py or another officer):',16,-98,11,'text',520)
 ui.rosterText=Input(rosterDialog,16,-116,528,8000)
 ui.rosterImport=Button(rosterDialog,'Import',16,-150,120,function()
  local ok,message=A.ImportRoster(ui.rosterText:GetText());rosterDialog.result:SetText(message)
  if ok then ui.rosterText:SetText('');ui.source='team';ui.Refresh() end
  ui.RefreshRoster()
 end)
 rosterDialog.result=Text(rosterDialog,'',146,-157,11,'accent',400)
 Text(rosterDialog,'Send it to everyone with VRT so only one person needs the tool.',16,-196,11,'muted',520)
 ui.rosterShareGroup=Button(rosterDialog,'Share with group',16,-216,170,function() local _,message=A.RosterShare.Send('GROUP');rosterDialog.result:SetText(message) end)
 ui.rosterShareGuild=Button(rosterDialog,'Share with guild',196,-216,170,function() local _,message=A.RosterShare.Send('GUILD');rosterDialog.result:SetText(message) end)
 ui.rosterClear=Button(rosterDialog,'Clear roster',376,-216,168,function()
  if not ui.confirmClear then ui.confirmClear=true;rosterDialog.result:SetText('Click Clear roster again to remove the team roster.');return end
  ui.confirmClear=nil;local _,message=A.ClearRoster();rosterDialog.result:SetText(message);ui.RefreshRoster()
 end)
 Button(rosterDialog,'Close',424,-258,120,function() rosterDialog:Hide() end)
 function ui.RefreshRoster()
  local roster=A.Roster and A.Roster()
  rosterDialog.info:SetText(roster and string.format('%s: %d members%s.',roster.team,#roster.members,
   roster.source and roster.source~='import' and (', shared by '..roster.source) or ', imported') or 'No team roster yet. The planner uses your online group until you import one.')
  local pending=A.RosterShare and A.RosterShare.pending
  rosterDialog.pending:SetText(pending and string.format('%s shared %s (%d members).',pending.sender,pending.roster.team,#pending.roster.members) or '')
  ui.rosterAccept:SetShown(pending~=nil);ui.rosterDecline:SetShown(pending~=nil)
  ui.rosterShareGroup:SetEnabled(roster~=nil);ui.rosterShareGuild:SetEnabled(roster~=nil);ui.rosterClear:SetEnabled(roster~=nil)
 end
 function ui.OpenRoster()
  whoMenu:Hide();menu:Hide();dialog:Hide();ui.confirmClear=nil;rosterDialog.result:SetText('')
  ui.RefreshRoster();rosterDialog:Show()
 end
 function addon.RefreshAssignmentsPage()
  if rosterDialog:IsShown() then ui.RefreshRoster() end
  if page:IsShown() then ui.Refresh() end
 end
 function ui.RefreshTable()
  local plan=ui.bossID and A.Plan(ui.bossID)
  local visible={}
  for _,entry in ipairs(plan and plan.entries or {}) do
   if not ui.onlyMine:GetChecked() or A.IsMine(entry) then visible[#visible+1]=entry end
  end
  ui.maximum=math.max(0,#visible-VISIBLE);ui.offset=math.min(ui.offset,ui.maximum)
  for index,row in ipairs(ui.rows) do
   local entry=visible[index+ui.offset];row.entry=entry
   if entry then
    local info=entry.spellID and A.SpellInfo(entry.spellID)
    row.cells[1]:SetText(A.FormatTime(entry.time))
    row.cells[2]:SetText(entry.phase and ('P'..entry.phase) or '')
    row.cells[3]:SetText(WhoText(entry.who))
    row.cells[4]:SetText(SpellName(entry))
    row.cells[5]:SetText(entry.text or AnchorText(entry))
    row.icon:SetTexture(info and info.iconID or nil);row.icon:SetShown(info~=nil)
    row:SetBackdropBorderColor(unpack(entry.id==ui.editing and colours.highlight or colours.border))
    row:Show()
   else row:Hide() end
  end
  ui.empty:SetText(not ui.bossID and 'Choose a boss to start a plan.' or (#visible==0 and (ui.onlyMine:GetChecked() and 'Nothing assigned to you for this boss.' or 'No assignments yet. Add one below or import text.') or ''))
  return visible,plan
 end

 ---------------------------------------------------------------- Shared
 function ui.SetView(view)
  ui.view=view=='table' and 'table' or 'timeline'
  local store=A.Store();if store then store.view=ui.view end
  whoMenu:Hide();menu:Hide()
  ui.Refresh()
 end
 function ui.SelectBoss(bossID,name)
  ui.bossID,ui.bossName=bossID,name;ui.offset=0;ui.timelineOffset=0;ui.selectedCast=nil;ui.ClearEditor()
  local list=A.TimelineDifficulties(bossID)
  local _,_,current=GetInstanceInfo()
  ui.difficulty=nil
  for _,value in ipairs(list) do if value==current then ui.difficulty=value end end
  if not ui.difficulty then for _,value in ipairs(list) do if value==15 then ui.difficulty=15 end end end
  ui.difficulty=ui.difficulty or list[1]
  local store=A.Store();if store then store.lastBoss=bossID;store.lastBossName=name end
  ui.Refresh()
 end
 function ui.Refresh()
  ui.bossButton.label:SetText('Boss: '..(ui.bossName or 'choose a boss')..'  v')
  local timelineMode=ui.view~='table'
  timelineView:SetShown(timelineMode);tableView:SetShown(not timelineMode)
  ui.viewButton.label:SetText(timelineMode and 'Table view' or 'Timeline view')
  local difficulties=ui.bossID and A.TimelineDifficulties(ui.bossID) or {}
  ui.difficultyButton.label:SetText((A.difficultyNames[ui.difficulty] or 'No timeline')..(#difficulties>1 and '  >' or ''))
  ui.difficultyButton:SetShown(timelineMode and ui.bossID~=nil)
  local visible,plan=ui.RefreshTable()
  if timelineMode then ui.RefreshTimeline() end
  local total=plan and #plan.entries or 0
  ui.count:SetText(ui.bossID and string.format('%d assignment%s in this plan%s',total,total==1 and '' or 's',ui.onlyMine:GetChecked() and (' · '..#visible..' mine') or '') or '')
  local store=A.Store()
  ui.autoShare:SetChecked(not store or store.autoSharePlan~=false)
  ui.sharePlan:SetEnabled(total>0)
  ui.testPull.label:SetText(A.Runtime and A.Runtime.test and 'Stop test' or 'Test pull')
  local pending=A.PlanShare and A.PlanShare.pending
  local ask=pending and not pending.trusted
  ui.planAccept:SetShown(ask and true or false);ui.planDecline:SetShown(ask and true or false)
  ui.sharePlan:SetShown(not ask);ui.autoShare:SetShown(not ask)
  if ask then ui.status:SetText(string.format('%s shared %s (%d assignments). Accept to replace yours.',pending.sender,pending.pack.name or 'boss',#pending.pack.entries)) end
 end
 page:SetScript('OnShow',function()
  -- Ask for calendar data now so Check signups has the event list ready.
  if A.Signups then A.Signups.Prepare() end
  local store=A.Store()
  if not ui.view then ui.view=store and store.view=='table' and 'table' or 'timeline' end
  if not ui.bossID and store and store.lastBoss then ui.SelectBoss(store.lastBoss,store.lastBossName) else ui.Refresh() end
 end)
 page:SetScript('OnHide',function() menu:Hide();whoMenu:Hide();dialog:Hide();rosterDialog:Hide() end)
 local store=A.Store();ui.view=store and store.view=='table' and 'table' or 'timeline'
 ui.source=store and store.source or ((A.Roster and A.Roster()) and 'team' or 'group')
 ui.ClearEditor();ui.Refresh()
end
