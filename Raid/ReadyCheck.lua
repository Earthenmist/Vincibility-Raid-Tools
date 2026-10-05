local _,addon=...
-- Ready-check options: a raid-wide overview plus personal gear/buff warnings
-- and a consumables bar. Only public, non-secret data may be read when it runs.
local RC={};addon.ReadyCheck=RC
local defaults={
 enabled=true,raidOnly=true,skipLFR=true,tts=false,
 chatReport=false,chatSelfOnly=true,flaskWarn=10,
 overview=true,overviewLeaderOnly=true,
 columns={food=true,flask=true,rune=true,vantus=false,oil=true,buffs=true,soulstone=true,durability=true,itemLevel=true,latency=true},
 personal={rebuff=true,classUtility=true,enchants=true,gems=true,embellishments=false,tier=false,itemLevel=false,missingItems=true,repair=true,group=false},
 consumables=true,consumablesClick=true,consumablesSkipStarter=false,
}
RC.defaults=defaults
RC.flaskWarnChoices={0,5,10,15,20}
local function Fill(target,source)
 for key,value in pairs(source) do
  if type(value)=='table' then
   if type(target[key])~='table' then target[key]={} end
   Fill(target[key],value)
  elseif type(target[key])~=type(value) then target[key]=value end
 end
end
function RC.Settings()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.readyCheck)~='table' then db.readyCheck={} end
 Fill(db.readyCheck,defaults)
 local valid=false
 for _,minutes in ipairs(RC.flaskWarnChoices) do if db.readyCheck.flaskWarn==minutes then valid=true end end
 if not valid then db.readyCheck.flaskWarn=defaults.flaskWarn end
 return db.readyCheck
end
function RC.Reset()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 VincibilityRaidToolsDB.readyCheck={}
 return RC.Settings()
end

-- Options page between Groups and Settings in the main window.
local sections={
 {key='when',title='WHEN TO RUN',column=1,items={
  {'enabled','Ready check tools','Master switch for everything on this page.'},
  {'raidOnly','Raid instances only','Skip ready checks outside raid instances.'},
  {'skipLFR','Skip Raid Finder','Do nothing in LFR groups.'},
  {'tts','Speak warnings','Read your personal warnings aloud with text-to-speech.'},
 }},
 {key='chat',title='CHAT REPORT',column=1,items={
  {'chatReport','Report missing food/flask','After the ready check, list players missing food or a flask.'},
  {'chatSelfOnly','Only print it to me','Show the report in your own chat instead of raid chat.'},
 }},
 {key='overview',title='RAID OVERVIEW',column=2,items={
  {'overview','Show raid overview','A window listing every raid member while the check runs.'},
  {'overviewLeaderOnly','Only as leader/assist','Show the overview only when you are raid leader or an assistant.'},
  {heading='COLUMNS'},
  {'columns.food','Food','Well Fed buff.'},
  {'columns.flask','Flask','Flask or phial, flagged when it expires soon.'},
  {'columns.rune','Augment rune','Augment rune buff.'},
  {'columns.vantus','Vantus rune','Vantus rune for the current boss.'},
  {'columns.oil','Weapon oil','Temporary weapon enchant. Needs VRT on that player.'},
  {'columns.buffs','Raid buffs','Intellect, Attack Power, Stamina, Versatility, Mastery and movement buffs.'},
  {'columns.soulstone','Soulstone','Who currently has a Soulstone.'},
  {'columns.durability','Durability','Gear durability. Needs VRT, or any addon with LibDurability, on that player.'},
  {'columns.itemLevel','Item level','Equipped item level. Needs VRT on that player.'},
  {'columns.latency','Latency','World latency in ms, with home latency in the tooltip. Works for anyone running VRT, DBM or BigWigs.'},
 }},
 {key='personal',title='PERSONAL CHECKS',column=3,items={
  {'personal.rebuff','Rebuff my raid buff','Warn when someone is missing the raid buff your class provides.'},
  {'personal.classUtility','Class utility buffs','Soulstone, Source of Magic, Blistering Scales and similar.'},
  {'personal.enchants','Missing enchants','Enchantable slots without an enchant.'},
  {'personal.gems','Missing gems','Empty sockets.'},
  {'personal.embellishments','Embellishments','Warn with fewer than two embellished items.'},
  {'personal.tier','Tier set bonus','Warn without the 4-piece set bonus.'},
  {'personal.itemLevel','Low item level','Slots well below your equipped average.'},
  {'personal.missingItems','Missing or wrong armour','Empty slots or the wrong armour type.'},
  {'personal.repair','Needs repair','Any item at 20% durability or less.'},
  {'personal.group','Show my raid group','Tell you which group you are in.'},
 }},
 {key='consumables',title='CONSUMABLES',column=4,items={
  {'consumables','Show consumables bar','Your food, flask, weapon oil and rune with time left.'},
  {'consumablesClick','Click to use','Clicking an icon uses the matching item from your bags (out of combat).'},
  {'consumablesSkipStarter','Hide when I start the check','Do not show the bar on ready checks you start.'},
 }},
}
RC.optionSections=sections
local function Path(settings,key)
 local group,field=key:match('^(%w+)%.(%w+)$')
 if group then return settings[group],field end
 return settings,key
end
function addon.BuildReadyCheckPage(page,window,H)
 local Text,Button,Surface,CheckBox=H.Text,H.Button,H.Surface,H.CheckBox
 local ui={checks={},cards={}};window.readyCheck=ui
 Text(page,'Ready check tools: a raid overview for leaders, personal warnings for everyone, and a consumables bar.',0,-27,12,'muted',850)
 -- One card per section in four columns; column 1 stacks When to run over Chat report.
 local WIDTH,GAP,TOP,BOTTOM,FIRST=210,8,-54,-540,196
 local function SmallButton(parent,label,action)
  local button=Button(parent,label,0,0,WIDTH-24,action)
  button:SetHeight(26);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(WIDTH-24);button.label:SetJustifyH('CENTER')
  button:ClearAllPoints();button:SetPoint('BOTTOMLEFT',parent,'BOTTOMLEFT',12,12)
  return button
 end
 for _,section in ipairs(sections) do
  local top,height=TOP,TOP-BOTTOM
  if section.column==1 then
   if section.key=='when' then height=FIRST else top=TOP-FIRST-GAP;height=top-BOTTOM end
  end
  local card=Surface('Frame',page);card:SetPoint('TOPLEFT',(section.column-1)*(WIDTH+GAP),top);card:SetSize(WIDTH,height)
  ui.cards[section.key]=card
  Text(card,section.title,12,-12,11,'accent',WIDTH-24)
  local y=-34
  for _,item in ipairs(section.items) do
   if item.heading then
    y=y-6;Text(card,item.heading,16,y-4,10,'muted',WIDTH-32);y=y-20
   else
    local key=item[1]
    local check=CheckBox(card,item[2],WIDTH-30,item[3])
    check:SetPoint('TOPLEFT',12,y-2)
    check.key=key
    check:SetScript('OnClick',function(self)
     if InCombatLockdown() then self:SetChecked(not self:GetChecked());return end
     local target,field=Path(RC.Settings(),key);target[field]=self:GetChecked() and true or false
     ui.Refresh()
    end)
    ui.checks[key]=check
    y=y-24
   end
  end
  section.bottom=y
 end
 -- Flask expiry threshold: shared by the overview, chat report and consumables bar.
 local when=ui.cards.when
 Text(when,'FLASK EXPIRY WARNING',16,sections[1].bottom-6,10,'muted',WIDTH-32)
 local function FlaskLabel(minutes) return minutes==0 and 'Off' or ('Under '..minutes..' minutes') end
 ui.flaskWarn=Button(when,'',12,sections[1].bottom-24,WIDTH-24,function() end)
 local menu=Surface('Frame',page);ui.flaskMenu=menu
 menu:SetSize(WIDTH-24,10+#RC.flaskWarnChoices*29);menu:SetPoint('TOPLEFT',ui.flaskWarn,'BOTTOMLEFT',0,-2)
 menu:SetFrameLevel(page:GetFrameLevel()+20);menu:EnableMouse(true);menu:Hide()
 ui.flaskOptions={}
 for index,minutes in ipairs(RC.flaskWarnChoices) do
  local option=Button(menu,FlaskLabel(minutes),5,-5-(index-1)*29,WIDTH-34,function()
   if InCombatLockdown() then return end
   RC.Settings().flaskWarn=minutes;menu:Hide();ui.Refresh()
  end)
  ui.flaskOptions[index]=option
 end
 ui.flaskWarn:SetScript('OnClick',function()
  if InCombatLockdown() or not RC.Settings().enabled then return end
  if menu:IsShown() then menu:Hide() else menu:Show() end
 end)
 -- Each preview sits in the card it shows.
 ui.preview=SmallButton(ui.cards.overview,'Preview overview',function()
  if InCombatLockdown() or not RC.Overview then return end
  RC.Overview.Show(nil,true)
 end)
 ui.previewWarnings=SmallButton(ui.cards.personal,'Preview warnings',function()
  if InCombatLockdown() or not RC.Personal then return end
  RC.Personal.Run(true)
 end)
 ui.previewReport=SmallButton(ui.cards.chat,'Preview report',function()
  if InCombatLockdown() or not RC.Report then return end
  RC.Report.Preview()
 end)
 ui.previewConsumables=SmallButton(ui.cards.consumables,'Preview consumables',function()
  if InCombatLockdown() or not RC.Consumables then return end
  RC.Consumables.Show(true)
 end)
 -- Reset on its own, bottom right; status at the page bottom like the other pages.
 ui.status=Text(page,'',0,0,11,'accent',680);ui.status:ClearAllPoints();ui.status:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-4)
 ui.reset=Button(page,'Reset to defaults',0,0,160,function()
  if InCombatLockdown() then return end
  if not ui.confirmReset then ui.confirmReset=true;ui.status:SetText('Click Reset to defaults again to restore every ready-check option.');return end
  ui.confirmReset=nil;RC.Reset();ui.Refresh();ui.status:SetText('Ready-check options restored to defaults.')
 end)
 ui.reset:ClearAllPoints();ui.reset:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',0,-14)
 ui.reset.label:ClearAllPoints();ui.reset.label:SetPoint('CENTER');ui.reset.label:SetWidth(160);ui.reset.label:SetJustifyH('CENTER')
 function ui.Refresh()
  local settings=RC.Settings()
  for key,check in pairs(ui.checks) do
   local target,field=Path(settings,key);check:SetChecked(target[field])
   -- Everything follows the master switch; columns follow the overview.
   local active=key=='enabled' or settings.enabled
   if key:match('^columns%.') or key=='overviewLeaderOnly' then active=active and settings.overview end
   if key=='chatSelfOnly' then active=active and settings.chatReport end
   if key=='consumablesClick' or key=='consumablesSkipStarter' then active=active and settings.consumables end
   check:SetEnabled(active);check:SetAlpha(active and 1 or .4)
  end
  ui.flaskWarn.label:SetText(FlaskLabel(settings.flaskWarn)..'  v')
  for index,option in ipairs(ui.flaskOptions) do option:SetBackdropBorderColor(unpack(RC.flaskWarnChoices[index]==settings.flaskWarn and H.colours.highlight or H.colours.border)) end
  ui.flaskWarn:SetEnabled(settings.enabled);ui.flaskWarn:SetAlpha(settings.enabled and 1 or .4)
  if not settings.enabled then menu:Hide() end
  if not ui.confirmReset then ui.status:SetText('') end
 end
 page:SetScript('OnShow',function() ui.confirmReset=nil;ui.Refresh() end)
 page:SetScript('OnHide',function() menu:Hide() end)
 ui.Refresh()
end
