local _,addon=...
-- Auras page: per boss (or Every boss), the aura sounds, the raid debuff
-- overview list and the co-tank debuff list; display toggles and positioning.
function addon.BuildAurasPage(page,window,helpers)
 local Text,Button,Surface,CheckBox,colours=helpers.Text,helpers.Button,helpers.Surface,helpers.CheckBox,helpers.colours
 local U,A=addon.Auras,addon.Assignments
 local ui={bossID=0,bossName='Every boss'};addon.AurasUI=ui
 local function Small(button,width) button:SetHeight(24);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(width);button.label:SetJustifyH('CENTER');return button end
 ui.inputs={}
 local function Hint(box) box.hint:SetShown(box:GetText()=='' and not (box.HasFocus and box:HasFocus())) end
 local function Input(parent,x,y,width)
  local box=Surface('EditBox',parent,'background');box:SetPoint('TOPLEFT',x,y);box:SetSize(width,24)
  box:SetAutoFocus(false);box:SetMaxLetters(10);box:SetFont(STANDARD_TEXT_FONT,12,'');box:SetTextColor(unpack(colours.text));box:SetTextInsets(6,6,0,0)
  box:SetScript('OnEscapePressed',function(self) self:ClearFocus() end);box:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
  -- Greyed "Spell ID" until something is typed.
  box.hint=Text(box,'Spell ID',7,-6,11,'muted',width-12)
  box:SetScript('OnTextChanged',Hint);box:SetScript('OnEditFocusGained',Hint);box:SetScript('OnEditFocusLost',Hint)
  ui.inputs[#ui.inputs+1]=box
  return box
 end
 -- A titled card, like the other pages.
 local function Card(title,x,y,width,height)
  local card=Surface('Frame',page);card:SetPoint('TOPLEFT',x,y);card:SetSize(width,height)
  Text(card,title,12,-12,11,'accent',width-24)
  return card
 end
 local function SpellText(id)
  local info=A.SpellInfo and A.SpellInfo(id)
  return (info and info.name or ('Spell '..id))..' ('..id..')',info and info.iconID
 end
 -- Shared scrolling option menu.
 local menu=Surface('Frame',page);menu:SetFrameLevel(page:GetFrameLevel()+40);menu:EnableMouse(true);menu:EnableMouseWheel(true);menu:Hide();ui.menu=menu
 local MENU_ROWS=10;local menuOptions,menuOffset,menuChoose={},0
 local menuRows={}
 local function DrawMenu()
  menuOffset=math.max(0,math.min(menuOffset,#menuOptions-MENU_ROWS))
  for index,row in ipairs(menuRows) do
   local option=menuOptions[index+menuOffset];row.option=option
   if option then row.label:SetText(option.label);row:Show() else row:Hide() end
  end
 end
 for index=1,MENU_ROWS do
  local row;row=Button(menu,'',5,-5-(index-1)*24,290,function()
   if not row.option then return end
   if row.option.children then
    -- Drill down (and back) without closing the menu.
    menuOptions,menuOffset=row.option.children,0
    menu:SetHeight(10+math.min(MENU_ROWS,math.max(1,#menuOptions))*24);DrawMenu();return
   end
   menu:Hide();menuChoose(row.option)
  end)
  row:SetHeight(22);row.label:ClearAllPoints();row.label:SetPoint('LEFT',10,0);row.label:SetWidth(270);row.label:SetWordWrap(false)
  menuRows[index]=row
 end
 menu:SetScript('OnMouseWheel',function(_,delta) menuOffset=menuOffset-delta*3;DrawMenu() end)
 function ui.OpenMenu(anchor,options,choose)
  if menu:IsShown() and ui.menuAnchor==anchor then menu:Hide();return end
  menuOptions,menuOffset,menuChoose,ui.menuAnchor=options,0,choose,anchor
  menu:SetSize(300,10+math.min(MENU_ROWS,math.max(1,#options))*24)
  menu:ClearAllPoints();menu:SetPoint('TOPLEFT',anchor,'BOTTOMLEFT',0,-2);DrawMenu();menu:Show()
 end
 -- Abilities of the selected boss (from its preloaded timeline).
 local function Abilities()
  local options,seen={},{}
  local boss=addon.AssignmentTimelines and addon.AssignmentTimelines[ui.bossID]
  for key,timeline in pairs(boss or {}) do
   if type(key)=='number' and type(timeline)=='table' then
    for _,ability in ipairs(timeline.abilities or {}) do
     if ability.spellID and not seen[ability.spellID] then seen[ability.spellID]=true;options[#options+1]={label=ability.name..' ('..ability.spellID..')',value=ability.spellID} end
    end
   end
  end
  table.sort(options,function(a,b) return a.label<b.label end)
  return options
 end

 Text(page,'Blizzard tracks and draws these auras; VRT chooses which. Sounds and spell lists sync to your raid; ticks, sizes and positions are yours.',0,-27,12,'muted',864)
 -- Boss choice.
 ui.bossButton=Button(page,'',0,-54,420,function()
  local options={{label='Every boss (any fight)',value=0}}
  -- Raid  >  boss, with a way back.
  for _,raid in ipairs(U.RaidList()) do
   local children={{label='< Back',children=options}}
   for _,boss in ipairs(raid.bosses) do children[#children+1]={label=boss.name,value=boss.id} end
   options[#options+1]={label=raid.name..'  >',children=children}
  end
  ui.OpenMenu(ui.bossButton,options,function(option) ui.bossID,ui.bossName=option.value,option.value==0 and 'Every boss' or option.label;ui.soundOffset=0;ui.Refresh() end)
 end)
 -- Status at the page bottom, like the other pages.
 ui.status=Text(page,'',0,0,11,'accent',864);ui.status:ClearAllPoints();ui.status:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-4)
 -- How it works: on hover (or click) of the ? beside the boss.
 ui.helpLines={
  '1. Pick a raid and boss (Every boss: sounds for any fight).',
  '2. Sounds: when that debuff lands on you (or your co-tank, or anyone), you hear the voice line. Defaults are loaded for the current raids; Play previews them.',
  '3. Lists: leave them empty to show all boss and dispellable debuffs, or add spell IDs to show only those.',
  '4. Turn the displays on in Your settings and use Position displays to place them.',
 }
 local function ShowHelp(owner)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');GameTooltip:SetText('How it works',1,1,1)
  for _,line in ipairs(ui.helpLines) do GameTooltip:AddLine(line,0.8,0.82,0.86,true) end
  GameTooltip:Show()
 end
 ui.help=Small(Button(page,'?',426,-54,28,function() ShowHelp(ui.help) end),28)
 ui.help:SetHeight(28)
 ui.help:HookScript('OnEnter',function(self) ShowHelp(self) end)
 ui.help:HookScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
 ui.restore=Small(Button(page,'Restore defaults',462,-54,160,function()
  local added,name=U.RestoreDefaults(ui.bossID)
  if not added then ui.status:SetText(name) else ui.status:SetText(added>0 and ('Added '..added..' default sound'..(added==1 and '' or 's')..' for '..name..'.') or ('All defaults for '..name..' are already here.')) end
  ui.Refresh()
 end),160)
 ui.restore:SetHeight(28)
 -- Dropdowns: a list of {key,label} choices, shown under the button.
 local function Choices(list) local options={};for _,item in ipairs(list) do options[#options+1]={label=item[2],value=item[1]} end;return options end
 local function Dropdown(parent,x,y,width,options,choose)
  local button;button=Button(parent,'',x,y,width,function() ui.OpenMenu(button,options(),choose) end)
  button:SetHeight(24);button.label:ClearAllPoints();button.label:SetPoint('LEFT',8,0);button.label:SetWidth(width-14);button.label:SetWordWrap(false)
  return button
 end
 local function Numbers(list,suffix) local options={};for _,n in ipairs(list) do options[#options+1]={label=suffix(n),value=n} end;return options end
 local function Apply() addon.AuraDisplays.Refresh();ui.Refresh() end
 -- Two columns of cards: Sounds over Your settings; overview over co-tank.
 local LEFT,RIGHT,WIDTH,TOP=0,436,428,-92
 ui.cards={
  sounds=Card('SOUNDS',LEFT,TOP,WIDTH,346),
  settings=Card('YOUR SETTINGS (not synced)',LEFT,TOP-354,WIDTH,150),
  overview=Card('RAID DEBUFF OVERVIEW',RIGHT,TOP,WIDTH,234),
  cotank=Card('CO-TANK DEBUFFS',RIGHT,TOP-242,WIDTH,262),
 }

 ---------------------------------------------------------------- Sounds
 local sounds=ui.cards.sounds
 ui.soundRows={}
 for index=1,7 do
  local row=CreateFrame('Frame',nil,sounds);row:SetSize(404,26);row:SetPoint('TOPLEFT',12,-32-(index-1)*28)
  row.enabled=CheckBox(row,'',20,'Play this sound for you. Your choice only; the sound stays in the shared setup.')
  row.enabled:SetPoint('LEFT',0,0)
  row.enabled:SetScript('OnClick',function(self) if row.sound then U.SetSoundEnabled(ui.bossID,row.sound,self:GetChecked());ui.Refresh() end end)
  row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(20,20);row.icon:SetPoint('LEFT',26,0)
  row.text=Text(row,'',52,-2,11,'text',262);row.text:SetWordWrap(false)
  row.detail=Text(row,'',52,-15,10,'muted',262);row.detail:SetWordWrap(false)
  row.play=Small(Button(row,'Play',318,-1,48,function() if row.sound then A.PlayAssignmentSound(row.sound.sound) end end),48)
  row.remove=Small(Button(row,'x',372,-1,30,function() local _,message=U.RemoveSound(ui.bossID,row.index);ui.status:SetText(message);ui.Refresh() end),30)
  row:Hide();ui.soundRows[index]=row
 end
 ui.soundNone=Text(sounds,'No sounds for this boss yet.',12,-36,11,'muted',404)
 -- Scroll the sound list with the mouse wheel.
 ui.soundOffset=0
 local soundWheel=CreateFrame('Frame',nil,sounds);soundWheel:SetPoint('TOPLEFT',12,-30);soundWheel:SetSize(310,7*28);soundWheel:EnableMouseWheel(true)
 soundWheel:SetScript('OnMouseWheel',function(_,delta)
  local config=U.Boss(ui.bossID);local count=config and #config.sounds or 0
  ui.soundOffset=math.max(0,math.min(count-7,ui.soundOffset-delta));ui.Refresh()
 end)
 ui.soundMore=Text(sounds,'',200,-234,10,'muted',216)
 Text(sounds,'Add: spell ID, who, when and sound',12,-234,10,'muted',190)
 ui.soundSpell=Input(sounds,12,-250,96)
 ui.soundAbilities=Small(Button(sounds,'v',112,-250,28,function()
  local options=Abilities();if #options==0 then ui.status:SetText('Pick a boss to list its abilities, or type a spell ID.');return end
  ui.OpenMenu(ui.soundAbilities,options,function(option) ui.soundSpell:SetText(tostring(option.value)) end)
 end),28)
 ui.draft={unit='player',when='applied'}
 local function Label(list,key) for _,item in ipairs(list) do if item[1]==key then return item[2] end end;return key end
 ui.soundUnit=Dropdown(sounds,146,-250,116,function() return Choices(U.units) end,function(option) ui.draft.unit=option.value;ui.RefreshDraft() end)
 ui.soundWhen=Dropdown(sounds,268,-250,148,function() return Choices(U.triggers) end,function(option) ui.draft.when=option.value;ui.RefreshDraft() end)
 ui.soundChoice=Button(sounds,'',12,-282,290,function()
  local options={}
  for _,voice in ipairs(A.DBMVoices or {}) do options[#options+1]={label='DBM voice: '..voice[2],value='DBM:'..voice[1]} end
  local R=addon.Reminders
  local paths=R and R.SoundPaths and R.SoundPaths() or {}
  table.sort(paths,function(a,b) return a:lower()<b:lower() end)
  for _,relative in ipairs(paths) do options[#options+1]={label=relative:gsub('%.ogg$',''):gsub('/',' / '),value='Interface\\AddOns\\VincRaidTools\\Media\\Sounds\\'..relative:gsub('/','\\')} end
  ui.OpenMenu(ui.soundChoice,options,function(option) ui.draft.sound=option.value;A.PlayAssignmentSound(option.value);ui.RefreshDraft() end)
 end)
 ui.soundChoice:SetHeight(24);ui.soundChoice.label:ClearAllPoints();ui.soundChoice.label:SetPoint('LEFT',10,0);ui.soundChoice.label:SetWidth(270);ui.soundChoice.label:SetWordWrap(false)
 ui.soundAdd=Small(Button(sounds,'Add sound',308,-282,108,function()
  local ok,message=U.AddSound(ui.bossID,ui.bossID~=0 and ui.bossName or nil,{spell=tonumber(ui.soundSpell:GetText()),unit=ui.draft.unit,when=ui.draft.when,sound=ui.draft.sound})
  ui.status:SetText(message);if ok then ui.soundSpell:SetText('') end;ui.Refresh()
 end),108)
 function ui.RefreshDraft()
  ui.soundUnit.label:SetText('Who: '..Label(U.units,ui.draft.unit)..'  v')
  ui.soundWhen.label:SetText('When: '..Label(U.triggers,ui.draft.when)..'  v')
  ui.soundChoice.label:SetText((ui.draft.sound and A.SoundName(ui.draft.sound) or 'Choose a sound')..'  v')
 end

 ---------------------------------------------------------------- Spell lists
 local lists={}
 local function SpellList(key,card)
  local list={key=key,rows={}};lists[#lists+1]=list
  for index=1,6 do
   local row=CreateFrame('Frame',nil,card);row:SetSize(404,22);row:SetPoint('TOPLEFT',12,-30-(index-1)*22)
   row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(18,18);row.icon:SetPoint('LEFT',0,0)
   row.text=Text(row,'',24,-4,11,'text',336);row.text:SetWordWrap(false)
   row.remove=Small(Button(row,'x',372,0,30,function() local _,message=U.RemoveSpell(ui.bossID,key,row.index);ui.status:SetText(message);ui.Refresh() end),30)
   row:SetScript('OnMouseWheel',nil);row:Hide();list.rows[index]=row
  end
  list.none=Text(card,'Empty: all boss and dispellable debuffs.',12,-34,11,'muted',404)
  list.input=Input(card,12,-168,96)
  list.abilities=Small(Button(card,'v',112,-168,28,function()
   local options=Abilities();if #options==0 then ui.status:SetText('Pick a boss to list its abilities, or type a spell ID.');return end
   ui.OpenMenu(list.abilities,options,function(option) list.input:SetText(tostring(option.value)) end)
  end),28)
  list.add=Small(Button(card,'Add spell',146,-168,100,function()
   local ok,message=U.AddSpell(ui.bossID,ui.bossID~=0 and ui.bossName or nil,key,list.input:GetText())
   ui.status:SetText(message);if ok then list.input:SetText('') end;ui.Refresh()
  end),100)
  list.offset=0
  return list
 end
 ui.overviewList=SpellList('overview',ui.cards.overview)
 ui.cotankList=SpellList('cotank',ui.cards.cotank)
 -- Each display's own look sits in its card (personal, not synced).
 local function Overview() return addon.AuraDisplays.OverviewSettings() end
 local overviewCard=ui.cards.overview
 ui.overviewSize=Dropdown(overviewCard,12,-198,96,function() return Numbers({16,20,22,24,28,32},function(n) return 'Size '..n end) end,function(option) Overview().size=option.value;Apply() end)
 ui.overviewMax=Dropdown(overviewCard,114,-198,84,function() return Numbers({2,3,4,5,6},function(n) return n..' icons' end) end,function(option) Overview().max=option.value;Apply() end)
 ui.overviewColumns=Dropdown(overviewCard,204,-198,110,function() return Numbers({1,2,3},function(n) return n..(n==1 and ' column' or ' columns') end) end,function(option) Overview().columns=option.value;Apply() end)
 -- Co-tank options: when to show, icon size and count, growth, second tank.
 local function Cotank() return addon.AuraDisplays.CotankSettings() end
 local cotankCard=ui.cards.cotank
 ui.cotankWhen=Dropdown(cotankCard,12,-198,150,function() return {{label='Show: when tanking',value='tank'},{label='Show: always',value='always'}} end,function(option) Cotank().when=option.value;Apply() end)
 ui.cotankSize=Dropdown(cotankCard,168,-198,82,function() return Numbers({32,40,48,56,64},function(n) return 'Size '..n end) end,function(option) Cotank().size=option.value;Apply() end)
 ui.cotankMax=Dropdown(cotankCard,256,-198,74,function() return Numbers({3,4,5,6,7,8},function(n) return n..' icons' end) end,function(option) Cotank().max=option.value;Apply() end)
 ui.cotankGrow=Dropdown(cotankCard,336,-198,80,function() return {{label='Right',value='RIGHT'},{label='Left',value='LEFT'}} end,function(option) Cotank().grow=option.value;Apply() end)
 ui.cotankSecond=CheckBox(cotankCard,'Also show the second tank',300,'Show icons for a second tank-role player that is not you.')
 ui.cotankSecond:SetPoint('TOPLEFT',12,-228)
 ui.cotankSecond:SetScript('OnClick',function(self) Cotank().second=self:GetChecked() and true or false;Apply() end)

 ---------------------------------------------------------------- Your settings
 local mine=ui.cards.settings
 ui.playSounds=CheckBox(mine,'Play aura sounds',140,'Your choice only. Off: no aura sounds play for you; the shared setup is unchanged.')
 ui.playSounds:SetPoint('TOPLEFT',12,-32)
 ui.playSounds:SetScript('OnClick',function(self) U.SetSoundsEnabled(self:GetChecked());U.RegisterSounds();ui.Refresh() end)
 ui.soundCount=Text(mine,'',170,-38,10,'muted',246)
 ui.showOverview=CheckBox(mine,'Show raid debuff overview',260,'A row per group member with their boss or listed debuffs.')
 ui.showOverview:SetPoint('TOPLEFT',12,-56)
 ui.showOverview:SetScript('OnClick',function(self) U.Store().display.overview.enabled=self:GetChecked() and true or false;addon.AuraDisplays.Refresh() end)
 ui.showCotank=CheckBox(mine,'Show co-tank debuffs',260,'The other tank\'s boss or listed debuffs, with larger icons.')
 ui.showCotank:SetPoint('TOPLEFT',12,-80)
 ui.showCotank:SetScript('OnClick',function(self) U.Store().display.cotank.enabled=self:GetChecked() and true or false;addon.AuraDisplays.Refresh() end)
 ui.showParties=CheckBox(mine,'Show displays in 5-player parties',260,'Off: the debuff overview and co-tank displays only appear in raids, not in dungeons or Mythic+.')
 ui.showParties:SetPoint('TOPLEFT',12,-104)
 ui.showParties:SetScript('OnClick',function(self) U.Store().display.parties=self:GetChecked() and true or false;addon.AuraDisplays.Refresh() end)
 ui.position=Small(Button(mine,'Position displays',0,0,140,function()
  local _,message=addon.AuraDisplays.SetPreview(not addon.AuraDisplays.preview);ui.status:SetText(message or '');ui.Refresh()
 end),140)
 ui.position:ClearAllPoints();ui.position:SetPoint('BOTTOMRIGHT',mine,'BOTTOMRIGHT',-12,12)

 function ui.Refresh()
  if not page:IsShown() then return end
  local raid=U.raidOf and U.raidOf[ui.bossID]
  ui.bossButton.label:SetText('Boss: '..ui.bossName..(raid and ('  ('..raid..')') or '')..'  v')
  ui.restore:SetShown(U.DefaultsFor(ui.bossID)~=nil)
  local config=U.Boss(ui.bossID) or {sounds={},overview={},cotank={}}
  for index,row in ipairs(ui.soundRows) do
   local sound=config.sounds[index+ui.soundOffset];row.sound,row.index=sound,index+ui.soundOffset
   if sound then
    local text,icon=SpellText(sound.spell)
    local who,when;for _,item in ipairs(U.units) do if item[1]==sound.unit then who=item[2] end end
    for _,item in ipairs(U.triggers) do if item[1]==sound.when then when=item[2] end end
    local on=U.SoundEnabled(ui.bossID,sound)
    row.text:SetText(text);row.detail:SetText(who..', '..when:lower()..': '..A.SoundName(sound.sound)..(on and '' or '  (off for you)'))
    row.text:SetTextColor(unpack(on and colours.text or colours.muted))
    row.enabled:SetChecked(not U.Personal().muted[U.SoundKey(ui.bossID,sound)])
    row.icon:SetTexture(icon);row.icon:SetShown(icon~=nil);if row.icon.SetDesaturated then row.icon:SetDesaturated(not on) end;row:Show()
   else row:Hide() end
  end
  ui.soundOffset=math.max(0,math.min(ui.soundOffset,#config.sounds-7))
  ui.soundNone:SetShown(#config.sounds==0)
  if ui.bossID==0 then
   -- Every boss is its own list; per-boss sounds (and the defaults) live on each boss.
   local bosses,total=0,0
   for id,boss in pairs(U.Store().bosses) do if id~=0 and #(boss.sounds or {})>0 then bosses=bosses+1;total=total+#boss.sounds end end
   ui.soundNone:SetText(string.format('Sounds here play in every fight (for debuffs seen on several bosses).\n%d boss%s have %d sound%s set up: pick a raid and boss from the Boss list to see them.',bosses,bosses==1 and '' or 'es',total,total==1 and '' or 's'))
  else ui.soundNone:SetText('No sounds for this boss yet.') end
  ui.soundMore:SetText(#config.sounds>7 and string.format('Showing %d-%d of %d (scroll for more)',ui.soundOffset+1,math.min(#config.sounds,ui.soundOffset+7),#config.sounds) or '')
  for _,list in ipairs(lists) do
   local spells=config[list.key] or {}
   for index,row in ipairs(list.rows) do
    local id=spells[index];row.index=index
    if id then local text,icon=SpellText(id);row.text:SetText(text);row.icon:SetTexture(icon);row.icon:SetShown(icon~=nil);row:Show() else row:Hide() end
   end
   list.none:SetShown(#spells==0)
   list.none:SetText(ui.bossID==0 and 'Empty: all boss and dispellable debuffs.' or 'Empty: uses Every boss, or all boss and dispellable debuffs.')
  end
  local display=U.Store().display
  ui.showOverview:SetChecked(display.overview.enabled~=false);ui.showCotank:SetChecked(display.cotank.enabled~=false)
  ui.playSounds:SetChecked(U.Personal().sounds~=false);ui.showParties:SetChecked(display.parties==true)
  ui.position.label:SetText(addon.AuraDisplays.preview and 'Done' or 'Position displays')
  ui.soundCount:SetText(string.format('%d aura sound%s registered with the game.',U.RegisteredCount(),U.RegisteredCount()==1 and '' or 's'))
  local overviewSettings=addon.AuraDisplays.OverviewSettings()
  ui.overviewSize.label:SetText('Size '..overviewSettings.size..'  v');ui.overviewMax.label:SetText(overviewSettings.max..' icons  v')
  ui.overviewColumns.label:SetText(overviewSettings.columns..(overviewSettings.columns==1 and ' column' or ' columns')..'  v')
  local cotank=addon.AuraDisplays.CotankSettings()
  ui.cotankWhen.label:SetText((cotank.when=='tank' and 'Show: when tanking' or 'Show: always')..'  v')
  ui.cotankSize.label:SetText('Size '..cotank.size..'  v');ui.cotankMax.label:SetText(cotank.max..' icons  v')
  ui.cotankGrow.label:SetText((cotank.grow=='RIGHT' and 'Right' or 'Left')..'  v');ui.cotankSecond:SetChecked(cotank.second)
  ui.RefreshDraft()
  for _,box in ipairs(ui.inputs) do Hint(box) end
 end
 addon.RefreshAurasPage=function() ui.Refresh() end
 page:SetScript('OnShow',function() ui.Refresh() end)
 page:SetScript('OnHide',function() menu:Hide();if addon.AuraDisplays.preview then addon.AuraDisplays.SetPreview(false) end end)
end
