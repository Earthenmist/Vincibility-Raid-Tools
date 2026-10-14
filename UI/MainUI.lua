local addonName, addon = ...
local window
local strataOptions={'BACKGROUND','LOW','MEDIUM','HIGH','DIALOG','FULLSCREEN','FULLSCREEN_DIALOG','TOOLTIP'}
addon.PanelStrataOptions=strataOptions
local function StrataLabel(value) return ((value:sub(1,1)..value:sub(2):lower()):gsub('_',' ')) end
local colours = {
    background={0.078,0.086,0.106,0.97}, panel={0.114,0.125,0.157,1},
    raised={0.145,0.157,0.192,1}, border={0.180,0.196,0.235,1},
    accent={0.72,0.76,0.81,1}, highlight={0.78,0.11,0.25,1}, text={0.910,0.918,0.941,1},
    muted={0.541,0.561,0.612,1},
}
local function Surface(kind,parent,colour)
    local f=CreateFrame(kind,nil,parent,'BackdropTemplate')
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    f:SetBackdropColor(unpack(colours[colour or 'panel']))
    f:SetBackdropBorderColor(unpack(colours.border))
    return f
end
function addon.StyleScrollBar(scroll)
    local bar=scroll.ScrollBar
    if not bar then return end
    bar:ClearAllPoints();bar:SetPoint('TOPLEFT',scroll,'TOPRIGHT',4,0);bar:SetPoint('BOTTOMLEFT',scroll,'BOTTOMRIGHT',4,0)
    bar:SetWidth(10)
    local hidden={}
    for _,button in pairs({bar.ScrollUpButton,bar.ScrollDownButton,bar.Back,bar.Forward}) do
        if button and not hidden[button] then
            hidden[button]=true;button:Hide()
            button:HookScript('OnShow',function(self) self:Hide() end)
        end
    end
    local track=bar:CreateTexture(nil,'BACKGROUND');track:SetAllPoints(bar);track:SetColorTexture(unpack(colours.panel))
    bar:SetThumbTexture('Interface\\Buttons\\WHITE8X8')
    local thumb=bar:GetThumbTexture();thumb:SetSize(8,32);thumb:SetVertexColor(unpack(colours.accent))
    bar:HookScript('OnEnter',function() thumb:SetVertexColor(unpack(colours.highlight)) end)
    bar:HookScript('OnLeave',function() thumb:SetVertexColor(unpack(colours.accent)) end)
end
local function Text(parent,text,x,y,size,colour,width)
    local t=parent:CreateFontString(nil,'OVERLAY')
    t:SetFont(STANDARD_TEXT_FONT,size or 12,'')
    t:SetTextColor(unpack(colours[colour or 'text']))
    t:SetJustifyH('LEFT');t:SetJustifyV('TOP')
    t:SetPoint('TOPLEFT',x,y);t:SetWidth(width or 760);t:SetText(text)
    return t
end
local function Button(parent,label,x,y,width,action)
    local b=Surface('Button',parent,'raised')
    b:SetSize(width,28);b:SetPoint('TOPLEFT',x,y)
    b:SetBackdropBorderColor(0.72,0.76,0.81,0.45)
    b.label=Text(b,label,10,-7,12,'accent',width-20)
    local hover=CreateFrame('Frame',nil,b,'BackdropTemplate')
    hover:SetAllPoints(b)
    hover:SetBackdrop({edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    hover:SetBackdropBorderColor(unpack(colours.highlight))
    hover:Hide();b.hoverOutline=hover
    b:SetScript('OnEnter',function(self) self.hoverOutline:Show() end)
    b:SetScript('OnLeave',function(self) self.hoverOutline:Hide() end)
    b:SetScript('OnClick',function() if not InCombatLockdown() then action() end end)
    return b
end
-- Themed checkbox: charcoal box, silver border, red fill and hover outline.
-- Callers position it; the label sits to its right. tooltip is optional.
local function CheckBox(parent,label,width,tooltip)
    local check=Surface('CheckButton',parent,'background');check:SetSize(18,18)
    check:SetBackdropBorderColor(0.72,0.76,0.81,0.5)
    local mark=check:CreateTexture(nil,'ARTWORK');mark:SetSize(10,10);mark:SetPoint('CENTER')
    mark:SetColorTexture(unpack(colours.highlight));check:SetCheckedTexture(mark)
    check.label=Text(check,label,0,0,11,'text',width or 300)
    check.label:ClearAllPoints();check.label:SetPoint('LEFT',check,'RIGHT',7,0)
    check:SetScript('OnEnter',function(self)
        self:SetBackdropBorderColor(unpack(colours.highlight))
        if tooltip and GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText(tooltip,1,1,1,1,true);GameTooltip:Show() end
    end)
    check:SetScript('OnLeave',function(self)
        self:SetBackdropBorderColor(0.72,0.76,0.81,0.5)
        if tooltip and GameTooltip then GameTooltip:Hide() end
    end)
    return check
end
addon.ThemedCheckBox=CheckBox
local function Card(parent,title,x,y,width,height)
    local c=Surface('Frame',parent)
    c:SetPoint('TOPLEFT',x,y);c:SetSize(width,height)
    Text(c,title,16,-14,13,'text',width-32)
    return c
end
local function Count(tableValue)
    local count=0
    for _ in pairs(tableValue or {}) do count=count+1 end
    return count
end
local function Incoming(sharing)
    local count,received,total=0,0,0
    for _,item in pairs(sharing and sharing.incoming or {}) do
        count=count+1;received=received+(item.count or 0);total=total+(item.total or 0)
    end
    return count==0 and 'None' or (count..(count==1 and ' pack, ' or ' packs, ')..received..'/'..total)
end
local function TransferStatus(sharing)
    if not sharing then return 'Unavailable' end
    if sharing.latest then
        local item=sharing.latest
        if item.failed then return 'Failed at '..(item.sentCount or 0)..'/'..item.total end
        if item.pending>0 then return (item.sentCount or 0)..'/'..item.total..' sent'..(item.throttled and ' (slowed)' or '') end
        if item.channel=='WHISPER' and item.result then return 'Sent · '..item.result end
        local acknowledgements=Count(item.ack)
        if acknowledgements>0 then return 'Sent · '..acknowledgements..' replied' end
        if GetTime and GetTime()-item.when>180 then return 'Sent · no reply' end
        return 'Sent · waiting for reply'
    end
    local queued=Count(sharing.outgoing)
    return queued>0 and (queued..' queued') or 'None'
end
local function Refresh()
    if not window or not window:IsShown() or InCombatLockdown() then return end
    local db=VincibilityRaidToolsDB or {}
    window.autoAssist:SetChecked(db.autoTankAssist)
    window.lock:SetChecked(db.locked)
    window.autoVisual:SetChecked(db.autoVisualNotes)
    window.notesLeaderOnly:SetChecked(db.notesLeaderOnly~=false)
    window.minimapVisible:SetChecked(addon.GetMinimapButtonShown())
    window.reminderTTS:SetChecked(db.reminderTTS==true)
    if window.panelMode then
        local mode=window.panelModeLabels[db.panelMode] and db.panelMode or 'group'
        window.panelMode.label:SetText(window.panelModeLabels[mode]..'  v')
        window.panelAutoOpen:SetChecked(db.panelAutoOpen==true)
    end
    window.strataButton.label:SetText(StrataLabel(db.frameStrata)..'  v')
    window.noteButton.label:SetText(addon.GetStartingNoteName()..'  v')
    window.visualStatus:SetText(addon.GetVisualNoteStatus())
    -- Transfers table: single sends from each page, one row per kind.
    local A=addon.Assignments
    local sources={notes=addon.TextNoteSharing,visual=addon.VisualNoteSharing,reminders=addon.ReminderSharing,plans=A and A.PlanShare,roster=A and A.RosterShare}
    for key,row in pairs(window.transferRows or {}) do
        local sharing=sources[key]
        if sharing then
            local pending=sharing.pending
            local waiting=type(pending)=='table' and (pending.sender and 1 or #pending) or 0
            row.send:SetText(TransferStatus(sharing));row.incoming:SetText(Incoming(sharing));row.waiting:SetText(tostring(waiting))
        else row.send:SetText('Sync only');row.incoming:SetText('—');row.waiting:SetText('—') end
    end
    window.groupStatus:SetText(addon.GetGroupStatus())
    if window.RefreshLayoutButtons then window.RefreshLayoutButtons() end
    if window.settingsSync and window.settingsSync:IsShown() and window.RefreshSync then window.RefreshSync() end
    if addon.RefreshRemindersPage then addon.RefreshRemindersPage() end
end
-- Sidebar: hide pages whose module is disabled and close the gaps.
local function RefreshNavigation()
    local order={'Notes','Visual Notes','Reminders','Assignments','Groups','Ready Check','Auras','Settings'}
    local slot=0
    for _,name in ipairs(order) do
        local b=window.navigation[name]
        local key=addon.ModuleForPage and addon.ModuleForPage(name)
        local shown=not key or addon.ModuleEnabled(key)
        b:SetShown(shown)
        if shown then b:ClearAllPoints();b:SetPoint('TOPLEFT',1,-40-slot*34);slot=slot+1 end
    end
    if window.raidPanelButton then window.raidPanelButton:SetShown(addon.ModuleEnabled('panel')) end
end
addon.RefreshNavigation=function() if window then RefreshNavigation() end end
local function SelectPage(name)
    if not window.pages[name] then name='Notes' end
    local key=addon.ModuleForPage and addon.ModuleForPage(name)
    if key and not addon.ModuleEnabled(key) then name='Settings' end
    if window.strataMenu then window.strataMenu:Hide();window.noteMenu:Hide() end
    window.selectedPage=name
    for key,page in pairs(window.pages) do
        if key==name then page:Show() else page:Hide() end
        local b=window.navigation[key]
        b.selected=key==name
        b:SetBackdropColor(unpack(b.selected and colours.raised or {0,0,0,0}))
        if b.selected then b.marker:Show() else b.marker:Hide() end
    end
    Refresh()
end
local function Build()
    if window then return end
    window=CreateFrame('Frame','VincibilityMainUI',UIParent,'BackdropTemplate')
    window:Hide();window:SetSize(1060,700);window:SetPoint('CENTER')
    window:SetFrameStrata('DIALOG');window:SetClampedToScreen(true)
    window:SetMovable(true);window:EnableMouse(true)
    window:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    window:SetBackdropColor(unpack(colours.background));window:SetBackdropBorderColor(unpack(colours.border))
    local header=Surface('Frame',window,'raised')
    header:SetPoint('TOPLEFT');header:SetSize(1060,30)
    Text(header,'Vincibility Raid Tools',18,-7,15,'text',600)
    header:EnableMouse(true);header:RegisterForDrag('LeftButton')
    header:SetScript('OnDragStart',function() if not InCombatLockdown() then window:StartMoving() end end)
    header:SetScript('OnDragStop',function() window:StopMovingOrSizing() end)
    local close=Button(header,'X',1028,-4,24,function() window:Hide() end)
    close:SetHeight(22);close.label:ClearAllPoints();close.label:SetPoint('CENTER');close.label:SetWidth(24);close.label:SetJustifyH('CENTER')
    -- Window scale: 70-130 %, applied when the slider is released (so the
    -- slider does not move under the cursor); right-click resets to 100 %.
    local function SavedScale()
        local value=VincibilityRaidToolsDB and tonumber(VincibilityRaidToolsDB.uiScale)
        return value and math.max(.7,math.min(1.3,value)) or 1
    end
    local function ApplyScale(value)
        value=math.floor(value*20+.5)/20
        VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
        VincibilityRaidToolsDB.uiScale=value~=1 and value or nil
        window:SetScale(value)
    end
    Text(header,'Scale',836,-9,11,'muted',40)
    local scale=Surface('Slider',header,'background');window.scaleSlider=scale
    scale:SetPoint('TOPLEFT',874,-10);scale:SetSize(90,10);scale:SetOrientation('HORIZONTAL')
    scale:SetMinMaxValues(.7,1.3);scale:SetValueStep(.05);scale:SetObeyStepOnDrag(true)
    -- Solid thumb and a fill up to it, so the current scale is always visible.
    local thumb=scale:CreateTexture(nil,'OVERLAY');thumb:SetColorTexture(1,1,1,1);thumb:SetSize(8,14);thumb:SetVertexColor(unpack(colours.accent));scale:SetThumbTexture(thumb)
    local fill=scale:CreateTexture(nil,'ARTWORK');fill:SetColorTexture(unpack(colours.highlight));fill:SetPoint('TOPLEFT',1,-1);fill:SetPoint('BOTTOMLEFT',1,1);scale.fill=fill
    scale.valueText=Text(header,'',970,-9,11,'accent',44);scale.valueText:SetJustifyH('RIGHT')
    scale:SetScript('OnValueChanged',function(self,value)
        self.valueText:SetText(math.floor(value*100+.5)..'%')
        self.fill:SetWidth(math.max(1,(value-.7)/.6*88))
    end)
    scale:SetScript('OnMouseDown',function(self,button) if button=='LeftButton' then self.dragging=true end end)
    scale:SetScript('OnMouseUp',function(self,button)
        if InCombatLockdown() then return end
        if button=='RightButton' then self:SetValue(1);ApplyScale(1)
        else self.dragging=false;ApplyScale(self:GetValue()) end
    end)
    scale:EnableMouseWheel(true)
    scale:SetScript('OnMouseWheel',function(self,delta)
        if InCombatLockdown() then return end
        local value=math.max(.7,math.min(1.3,self:GetValue()+delta*.05));self:SetValue(value);ApplyScale(value)
    end)
    scale:SetScript('OnEnter',function(self)
        thumb:SetVertexColor(unpack(colours.highlight))
        if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_BOTTOM');GameTooltip:SetText('Window scale. Right-click to reset to 100%.',1,1,1,1,true);GameTooltip:Show() end
    end)
    scale:SetScript('OnLeave',function() thumb:SetVertexColor(unpack(colours.accent));if GameTooltip then GameTooltip:Hide() end end)
    scale:SetValue(SavedScale());window:SetScale(SavedScale())
    window:SetScript('OnHide',function()
        window:StopMovingOrSizing()
        if window.strataMenu then window.strataMenu:Hide();window.noteMenu:Hide() end
        if addon.CloseReminderEditor then addon.CloseReminderEditor() end
        if addon.CloseNativeNoteEditor then addon.CloseNativeNoteEditor() end
        if addon.CloseNativeVisualNotes then addon.CloseNativeVisualNotes() end
    end)
    UISpecialFrames=UISpecialFrames or {};table.insert(UISpecialFrames,'VincibilityMainUI')
    local sidebar=Surface('Frame',window)
    sidebar:SetPoint('TOPLEFT',0,-30);sidebar:SetSize(160,670)
    Text(sidebar,'RAID TOOLS',12,-18,10,'muted',136)
    local crest=addon.CreateGuildCrest(sidebar,124)
    crest:SetPoint('TOP',sidebar,'TOP',0,-460)
    crest.image:SetVertexColor(.78,.78,.78,1)
    window.guildCrest=crest
    window.pages={};window.navigation={}
    for i,name in ipairs({'Notes','Visual Notes','Reminders','Assignments','Groups','Ready Check','Auras','Settings'}) do
        local pageName=name
        local page=CreateFrame('Frame',nil,window)
        page:SetPoint('TOPLEFT',178,-48);page:SetSize(864,622);page:Hide()
        window.pages[name]=page
        Text(page,name,0,0,17,'text',800)
        local b=Surface('Button',sidebar)
        b:SetPoint('TOPLEFT',1,-40-(i-1)*34);b:SetSize(158,32)
        b:SetBackdropColor(0,0,0,0);b:SetBackdropBorderColor(0,0,0,0)
        b.label=Text(b,name,12,-9,12,'text',130)
        b.marker=b:CreateTexture(nil,'ARTWORK');b.marker:SetColorTexture(unpack(colours.highlight))
        b.marker:SetPoint('TOPLEFT');b.marker:SetSize(2,32);b.marker:Hide()
        b:SetScript('OnClick',function() if not InCombatLockdown() then SelectPage(pageName) end end)
        b:SetScript('OnEnter',function(self) if not self.selected then self:SetBackdropColor(unpack(colours.raised)) end end)
        b:SetScript('OnLeave',function(self) if not self.selected then self:SetBackdropColor(0,0,0,0) end end)
        window.navigation[name]=b
    end
    window.raidPanelButton=Button(sidebar,'Raid panel',12,-618,136,function() SlashCmdList.VINCIBILITYRAIDTOOLS('') end)
    RefreshNavigation()

    local notes=window.pages.Notes
    addon.BuildNativeNotesPage(notes,window,{Text=Text,Button=Button,Surface=Surface})

    addon.BuildNativeVisualNotesPage(window.pages['Visual Notes'],window,{Text=Text,Button=Button,Surface=Surface,colours=colours})

    local reminders=window.pages.Reminders
    addon.BuildRemindersPage(reminders,window,{Text=Text,Button=Button,Surface=Surface,colours=colours})

    local groups=window.pages.Groups
    Text(groups,'Pick a layout and apply it. Groups 7–8 (bench) are never touched.',0,-27,12,'muted')
    local descriptions={
        soak3='DPS evenly across groups 1-3; tanks and healers in groups 4-6. Up to 15 DPS.',
        odd20='Two balanced teams across groups 1-4. Up to 20 active players.',
        odd30='Two balanced teams across groups 1-6. Up to 30 active players.',
        healers='Healers and tanks spread one per group, then DPS balanced by class.',
        rolesort='Tanks first, then healers, then DPS, filling groups 1-6 in order.',
        meleeranged='Tanks and melee in groups 1-3, ranged in 4-6; healers fill the smaller side. Specs from the team roster or by inspecting.',
    }
    -- Two cards per row.
    for i,entry in ipairs(addon.GetGroupPresets()) do
        local preset=entry.preset
        local column,row=(i-1)%2,math.floor((i-1)/2)
        local card=Card(groups,entry.name,column*440,-58-row*132,424,120)
        Text(card,descriptions[preset.id] or '',16,-38,12,'muted',392)
        -- Same place on every card, whatever the description length.
        local apply=Button(card,'Apply layout',0,0,150,function()
            local _,message=addon.ApplyGroupPreset(preset)
            window.groupStatus:SetText(message)
        end)
        apply:ClearAllPoints();apply:SetPoint('BOTTOMLEFT',card,'BOTTOMLEFT',16,12)
        apply.label:ClearAllPoints();apply.label:SetPoint('CENTER');apply.label:SetWidth(150);apply.label:SetJustifyH('CENTER')
        apply:HookScript('OnEnter',function(self)
            if self.blocked and GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText(self.blocked,1,0.82,0.3,1,true);GameTooltip:Show() end
        end)
        apply:HookScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        window.layoutButtons=window.layoutButtons or {};window.layoutButtons[#window.layoutButtons+1]=apply
    end
    -- Greyed (with the reason on hover) when you are not leader/assistant or anyone is in combat.
    function window.RefreshLayoutButtons()
        local blocked=addon.GroupLayoutBlocked and addon.GroupLayoutBlocked() or nil
        for _,apply in ipairs(window.layoutButtons or {}) do apply.blocked=blocked;apply:SetAlpha(blocked and 0.45 or 1) end
    end
    -- Raid invites from the next calendar raid's sign-ups, in their own card.
    local invites=Card(groups,'Raid invites',0,-454,864,116)
    Text(invites,'Invites the next raid in the calendar: signed up first; tentative and standby once everyone signed up is in.',16,-36,12,'muted',832)
    local function InviteButton(label,x,action)
        local button=Button(invites,label,x,-58,250,function() local _,message=action();if message then window.inviteStatus:SetText(message) end end)
        button:SetHeight(26);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(250);button.label:SetJustifyH('CENTER')
        return button
    end
    window.inviteStart=InviteButton('Invite signed up',16,function() return addon.Invites.Start() end)
    window.inviteLater=InviteButton('Invite tentative and standby now',276,function() return addon.Invites.InviteLater(true) end)
    window.inviteStop=InviteButton('Stop',536,function() return addon.Invites.Stop() end)
    window.inviteStatus=Text(invites,addon.Invites and addon.Invites.status or '',16,-92,11,'accent',832)
    addon.RefreshInvites=function() if window and window.inviteStatus then window.inviteStatus:SetText(addon.Invites.status) end end
    -- Status and help at the bottom, as on the other pages.
    window.groupStatus=Text(groups,'',0,0,12,'accent',864);window.groupStatus:ClearAllPoints();window.groupStatus:SetPoint('BOTTOMLEFT',groups,'BOTTOMLEFT',0,-4)
    local groupHelp=Text(groups,'Needs raid leader or assistant, out of combat. Opening this page never moves anyone.',0,0,10,'muted',864)
    groupHelp:ClearAllPoints();groupHelp:SetPoint('BOTTOMLEFT',groups,'BOTTOMLEFT',0,-20)
    VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
    local db=VincibilityRaidToolsDB
    addon.BuildAssignmentsPage(window.pages.Assignments,window,{Text=Text,Button=Button,Surface=Surface,CheckBox=CheckBox,colours=colours})
    addon.BuildReadyCheckPage(window.pages['Ready Check'],window,{Text=Text,Button=Button,Surface=Surface,CheckBox=CheckBox,colours=colours})
    if addon.BuildAurasPage then addon.BuildAurasPage(window.pages.Auras,window,{Text=Text,Button=Button,Surface=Surface,CheckBox=CheckBox,colours=colours}) end
    local settingsPage=window.pages.Settings
    local settings=CreateFrame('Frame',nil,settingsPage);settings:SetAllPoints(settingsPage);window.settingsGeneral=settings
    local syncTab=CreateFrame('Frame',nil,settingsPage);syncTab:SetAllPoints(settingsPage);syncTab:Hide();window.settingsSync=syncTab
    local tabButtons={}
    local function SelectSettingsTab(name)
        window.settingsTab=name
        settings:SetShown(name=='General');syncTab:SetShown(name=='Sync');window.settingsVersions:SetShown(name=='Versions');window.settingsModules:SetShown(name=='Modules');window.settingsBackups:SetShown(name=='Backup & Restore')
        for key,button in pairs(tabButtons) do
            button:SetBackdropBorderColor(unpack(key==name and colours.highlight or {0.72,0.76,0.81,0.45}))
            button.label:SetTextColor(unpack(key==name and colours.text or colours.accent))
        end
        if name=='Sync' and window.RefreshSync then window.RefreshSync() end
        if name=='Versions' and window.RefreshVersions then window.RefreshVersions() end
        if name=='Modules' and window.RefreshModules then window.RefreshModules() end
        if name=='Backup & Restore' and window.RefreshBackups then window.RefreshBackups() end
    end
    window.SelectSettingsTab=SelectSettingsTab
    local versionsTab=CreateFrame('Frame',nil,settingsPage);versionsTab:SetAllPoints(settingsPage);versionsTab:Hide();window.settingsVersions=versionsTab
    local modulesTab=CreateFrame('Frame',nil,settingsPage);modulesTab:SetAllPoints(settingsPage);modulesTab:Hide();window.settingsModules=modulesTab
    -- Modules tab: a card per module, green when enabled, red when disabled.
    Text(modulesTab,'Switch off what you do not use. A disabled module leaves the sidebar and stops working in the background; its data is kept.',0,-60,11,'muted',864)
    window.moduleCards={}
    local enabledColour,disabledColour={0.30,0.75,0.40,1},colours.highlight
    for index,module in ipairs(addon.modules) do
        local column,row=(index-1)%2,math.floor((index-1)/2)
        local card=Card(modulesTab,module.name,column*440,-84-row*112,424,100)
        card.module=module
        Text(card,module.text,16,-38,11,'muted',392)
        card.state=Text(card,'',300,-14,11,'text',108);card.state:SetJustifyH('RIGHT')
        card.toggle=Button(card,'',16,-64,120,function()
            local _,message=addon.SetModuleEnabled(module.key,not addon.ModuleEnabled(module.key))
            if message then window.moduleStatus:SetText(message) end
            window.RefreshModules()
        end)
        card.toggle:SetHeight(26);card.toggle.label:ClearAllPoints();card.toggle.label:SetPoint('CENTER');card.toggle.label:SetWidth(120);card.toggle.label:SetJustifyH('CENTER')
        window.moduleCards[module.key]=card
    end
    window.moduleStatus=Text(modulesTab,'',0,-540,11,'accent',864)
    function window.RefreshModules()
        for key,card in pairs(window.moduleCards) do
            local on=addon.ModuleEnabled(key)
            local colour=on and enabledColour or disabledColour
            card:SetBackdropBorderColor(unpack(colour))
            card.state:SetText(on and 'Enabled' or 'Disabled');card.state:SetTextColor(unpack(colour))
            card.toggle.label:SetText(on and 'Disable' or 'Enable')
        end
        RefreshNavigation()
    end
    local tabX=0
    for _,name in ipairs({'General','Modules','Sync','Versions','Backup & Restore'}) do
        local width=name=='Backup & Restore' and 140 or 100
        local tab=Button(settingsPage,name,tabX,-26,width,function() SelectSettingsTab(name) end)
        tab:SetHeight(22);tab.label:ClearAllPoints();tab.label:SetPoint('CENTER');tab.label:SetWidth(width);tab.label:SetJustifyH('CENTER')
        tabButtons[name]=tab;tabX=tabX+width+6
    end
    window.settingsTabs=tabButtons
    local accent=colours.accent
    local metadata=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version
    if metadata then local ok,value=pcall(metadata,addonName,'Version');if ok and type(value)=='string' then version=value end end
    -- Beside the Settings heading.
    window.version=Text(settingsPage,'Version '..(version or 'unavailable'),88,-5,11,'muted',300)
    -- Versions tab: who has VRT, which version, and whether their data matches ours.
    Text(versionsTab,'Check which VRT version people have and whether their notes, reminders, assignments and roster match yours.',16,-60,11,'muted',820)
    window.versionStatus=Text(versionsTab,'',16,-112,11,'accent',820)
    local function Check(target) local _,message=addon.Sync.CheckVersions(target);window.versionStatus:SetText(message or '');window.RefreshVersions() end
    window.versionRaid=Button(versionsTab,'Check raid',16,-80,140,function() Check('RAID') end)
    window.versionGuild=Button(versionsTab,'Check guild',166,-80,140,function() Check('GUILD') end)
    for _,button in ipairs({window.versionRaid,window.versionGuild}) do button:SetHeight(24);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(140);button.label:SetJustifyH('CENTER') end
    local columns={{'PLAYER',16,150},{'VERSION',170,120}}
    for index,kind in ipairs(addon.Sync.kinds) do columns[#columns+1]={kind.label:upper(),290+(index-1)*94,90,kind.key} end
    for _,column in ipairs(columns) do Text(versionsTab,column[1],column[2],-140,10,'accent',column[3]) end
    local list=Surface('Frame',versionsTab,'background');list:SetPoint('TOPLEFT',8,-156);list:SetSize(856,16*26+8);list:EnableMouseWheel(true)
    window.versionRows={};window.versionOffset=0
    for index=1,16 do
        local row=CreateFrame('Frame',nil,list);row:SetSize(848,24);row:SetPoint('TOPLEFT',4,-4-(index-1)*26)
        row.cells={}
        for c,column in ipairs(columns) do local cell=Text(row,'',column[2]-8,-6,11,'text',column[3]);cell:SetWordWrap(false);row.cells[c]=cell end
        row:Hide();window.versionRows[index]=row
    end
    window.versionEmpty=Text(list,'',12,-38,11,'muted',820)
    Text(versionsTab,'Same: their copy matches yours. Differs: one of you has changes the other has not synced yet (Settings > Sync).',16,-588,10,'muted',820)
    function window.RefreshVersions()
        local answers=addon.Sync.VersionRows()
        -- You first, as the row everyone else is compared with.
        local rows={{name=((UnitName and UnitName('player')) or 'You')..' (you)',ver=addon.Sync.Version(),installed=true,you=true,same={}}}
        for _,data in ipairs(answers) do rows[#rows+1]=data end
        window.versionOffset=math.max(0,math.min(window.versionOffset,#rows-16))
        local green,red,amber,muted={.45,.8,.45},{.88,.35,.35},{.88,.69,.25},colours.muted
        for index,row in ipairs(window.versionRows) do
            local data=rows[index+window.versionOffset]
            if data then
                row.cells[1]:SetText(data.name);row.cells[1]:SetTextColor(unpack(colours.text))
                if data.you then
                    row.cells[1]:SetTextColor(unpack(colours.accent))
                    row.cells[2]:SetText(data.ver);row.cells[2]:SetTextColor(unpack(colours.text))
                    for c=3,#columns do row.cells[c]:SetText('Yours');row.cells[c]:SetTextColor(unpack(muted)) end
                elseif data.installed then
                    row.cells[2]:SetText(data.ver..(data.older and ' (older)' or data.newer and ' (newer)' or ''))
                    row.cells[2]:SetTextColor(unpack(data.older and red or data.newer and amber or green))
                    for c=3,#columns do
                        local same=data.same[columns[c][4]]
                        row.cells[c]:SetText(same and 'Same' or 'Differs');row.cells[c]:SetTextColor(unpack(same and green or amber))
                    end
                else
                    row.cells[2]:SetText('Not installed');row.cells[2]:SetTextColor(unpack(muted))
                    for c=3,#columns do row.cells[c]:SetText('') end
                end
                row:Show()
            else row:Hide() end
        end
        local installed,older=0,0
        for _,data in ipairs(answers) do if data.installed then installed=installed+1;if data.older then older=older+1 end end end
        window.versionEmpty:SetText(#answers==0 and 'No answers yet. Use Check raid or Check guild.' or '')
        if #answers>0 then window.versionStatus:SetText(string.format('Your version: %s. %d with VRT%s%s.',addon.Sync.Version(),installed,older>0 and (', '..older..' out of date') or '',#answers>installed and (', '..(#answers-installed)..' without VRT') or '')) end
    end
    list:SetScript('OnMouseWheel',function(_,delta) window.versionOffset=math.max(0,window.versionOffset-delta);window.RefreshVersions() end)
    addon.RefreshVersionsTab=function() if window and window:IsShown() and versionsTab:IsShown() then window.RefreshVersions() end end
    -- Backup & Restore tab: backups on the left, restore on the right.
    local backupsTab=CreateFrame('Frame',nil,settingsPage);backupsTab:SetAllPoints(settingsPage);backupsTab:Hide();window.settingsBackups=backupsTab
    local backupList=Card(backupsTab,'Backups',0,-56,540,534)
    local restoreCard=Card(backupsTab,'Restore',548,-56,316,534)
    window.backupCards={list=backupList,restore=restoreCard}
    local short={notes='notes',visual='visual',reminders='reminders',plans='plans',roster='roster',auras='auras'}
    local function Summary(backup)
        local parts={}
        for _,kind in ipairs(addon.Sync.kinds) do parts[#parts+1]=(backup.counts[kind.key] or 0)..' '..short[kind.key] end
        if backup.settings then parts[#parts+1]='your settings' end
        return table.concat(parts,' · ')
    end
    local function When(backup) return date and date('%a %d %b, %H:%M',backup.at) or tostring(backup.at) end
    window.backupRows={}
    for index=1,10 do
        local row=Button(backupList,'',16,-40-(index-1)*48,508,function()
            window.backupPick=addon.Backup.List()[index];window.backupConfirm=nil;window.RefreshBackups()
        end)
        row:SetHeight(44);row.label:ClearAllPoints();row.label:SetPoint('TOPLEFT',10,-8);row.label:SetWidth(488);row.label:SetJustifyH('LEFT');row.label:SetWordWrap(false)
        row.detail=Text(row,'',10,-25,10,'muted',488);row.detail:SetWordWrap(false)
        row:Hide();window.backupRows[index]=row
    end
    window.backupEmpty=Text(backupList,'No backups yet. One is made before changes from someone else are applied, or use Back up now.',16,-44,11,'muted',508)
    window.backupNow=Button(restoreCard,'Back up now',16,-40,284,function()
        local ok,message=addon.Backup.Create('Manual backup');if ok then window.backupPick=addon.Backup.List()[1] end;window.backupConfirm=nil
        window.backupStatus:SetText(message or '');window.RefreshBackups()
    end)
    window.backupNow:SetHeight(26);window.backupNow.label:ClearAllPoints();window.backupNow.label:SetPoint('CENTER');window.backupNow.label:SetWidth(284);window.backupNow.label:SetJustifyH('CENTER')
    Text(restoreCard,'Made automatically before changes from someone else are applied (at most every 5 minutes), and when you click Back up now. The newest 10 are kept.',16,-74,10,'muted',284)
    Text(restoreCard,'SELECTED BACKUP',16,-130,10,'muted',284)
    window.backupInfo=Text(restoreCard,'',16,-146,11,'text',284)
    Text(restoreCard,'RESTORE',16,-214,10,'muted',284)
    window.backupKind=nil
    local kindMenu=Surface('Frame',backupsTab);window.backupKindMenu=kindMenu
    kindMenu:SetSize(284,10+(#addon.Sync.kinds+2)*26);kindMenu:SetFrameLevel(window:GetFrameLevel()+20);kindMenu:EnableMouse(true);kindMenu:Hide()
    local function KindLabel(key)
        if not key then return 'Everything' end
        if key=='settings' then return 'Your settings only' end
        for _,kind in ipairs(addon.Sync.kinds) do if kind.key==key then return kind.label..' only' end end
    end
    local kindChoices={false}
    for _,kind in ipairs(addon.Sync.kinds) do kindChoices[#kindChoices+1]=kind.key end
    kindChoices[#kindChoices+1]='settings'
    for index,key in ipairs(kindChoices) do
        local option=Button(kindMenu,KindLabel(key or nil),5,-5-(index-1)*26,274,function()
            window.backupKind=key or nil;window.backupConfirm=nil;kindMenu:Hide();window.RefreshBackups()
        end)
        option:SetHeight(24)
    end
    window.backupKindButton=Button(restoreCard,'',16,-230,284,function()
        if kindMenu:IsShown() then kindMenu:Hide();return end
        kindMenu:ClearAllPoints();kindMenu:SetPoint('TOPLEFT',window.backupKindButton,'BOTTOMLEFT',0,-2);kindMenu:Show()
    end)
    window.backupKindButton:SetHeight(26)
    window.backupRestore=Button(restoreCard,'Restore',16,-264,284,function()
        local index=window.SelectedBackup()
        if not index then window.backupStatus:SetText('Choose a backup on the left first.');return end
        if not window.backupConfirm then
            window.backupConfirm=true
            window.backupStatus:SetText('Click Restore again to restore '..KindLabel(window.backupKind):lower()..' from this backup.');return
        end
        window.backupConfirm=nil
        local _,message=addon.Backup.Restore(index,window.backupKind)
        window.backupStatus:SetText(message or '');window.RefreshBackups()
    end)
    window.backupRestore:SetHeight(26);window.backupRestore.label:ClearAllPoints();window.backupRestore.label:SetPoint('CENTER');window.backupRestore.label:SetWidth(284);window.backupRestore.label:SetJustifyH('CENTER')
    Text(restoreCard,'A restore counts as a fresh edit: sync sends it to everyone (trusted senders apply it automatically) and removes items the backup did not have. Your settings are restored on this computer only. Your current state is backed up first, so a restore can be undone.',16,-300,10,'muted',284)
    window.backupStatus=Text(restoreCard,'',16,-400,11,'accent',284)
    -- The chosen backup is remembered by itself, so new backups do not move the selection.
    function window.SelectedBackup()
        for index,backup in ipairs(addon.Backup.List()) do if backup==window.backupPick then return index end end
    end
    function window.RefreshBackups()
        local list=addon.Backup.List()
        window.backupSelected=window.SelectedBackup()
        for index,row in ipairs(window.backupRows) do
            local backup=list[index]
            if backup then
                row.label:SetText(When(backup)..'  —  '..backup.reason);row.detail:SetText(Summary(backup))
                row:SetBackdropBorderColor(unpack(index==window.backupSelected and colours.highlight or colours.border));row:Show()
            else row:Hide() end
        end
        window.backupEmpty:SetShown(#list==0)
        local selected=window.backupSelected and list[window.backupSelected]
        window.backupInfo:SetText(selected and (When(selected)..'\n'..selected.reason..'\n'..Summary(selected)) or 'None. Click a backup on the left.')
        window.backupKindButton.label:SetText('Restore: '..KindLabel(window.backupKind)..'  v')
        window.backupRestore:SetAlpha(selected and 1 or 0.45)
    end
    addon.RefreshBackupsTab=function() if window and window:IsShown() and backupsTab:IsShown() then window.RefreshBackups() end end
    backupsTab:HookScript('OnHide',function() kindMenu:Hide();window.backupConfirm=nil end)
    -- Sync tab: Offer changes and Auto-accept on top; Transfers and Incoming below.
    local offer=Card(syncTab,'Offer changes',0,-56,540,290)
    local trust=Card(syncTab,'Auto-accept sends from',548,-56,316,290)
    local transfers=Card(syncTab,'Transfers',0,-354,540,236)
    local incoming=Card(syncTab,'Incoming',548,-354,316,236)
    window.syncCards={offer=offer,trust=trust,transfers=transfers,incoming=incoming}
    -- Incoming sync offers to accept.
    window.syncNone=Text(incoming,'Nothing waiting.',16,-40,11,'muted',284)
    window.syncRows={}
    for index=1,3 do
        local row=CreateFrame('Frame',nil,incoming);row:SetSize(284,30);row:SetPoint('TOPLEFT',16,-36-(index-1)*34)
        row.text=Text(row,'',0,-8,11,'text',128);row.text:SetWordWrap(false)
        row.accept=Button(row,'Accept',132,-2,70,function() local _,message=addon.Sync.Accept(index);window.syncStatus:SetText(message or '');window.RefreshSync() end)
        row.decline=Button(row,'Decline',208,-2,72,function() local _,message=addon.Sync.Decline(index);window.syncStatus:SetText(message or '');window.RefreshSync() end)
        for _,button in ipairs({row.accept,row.decline}) do button:SetHeight(24);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetJustifyH('CENTER') end
        row:Hide();window.syncRows[index]=row
    end
    -- Transfers: single sends from each page, one row per kind.
    for _,header in ipairs({{'KIND',16},{'SENDING',140},{'INCOMING',330},{'WAITING',460}}) do Text(transfers,header[1],header[2],-40,10,'accent',120) end
    window.transferRows={}
    for index,kind in ipairs(addon.Sync.kinds) do
        local y=-58-(index-1)*22
        local row={name=Text(transfers,kind.label,16,y,11,'text',120),send=Text(transfers,'',140,y,11,'muted',186),incoming=Text(transfers,'',330,y,11,'muted',126),waiting=Text(transfers,'',460,y,11,'muted',64)}
        for _,cell in pairs(row) do cell:SetWordWrap(false) end
        window.transferRows[kind.key]=row
    end
    Text(transfers,'Single sends from each page. Trusted senders apply automatically; others wait on that page.',16,-196,10,'muted',508)
    -- Offer changes: send everything of a kind to a player, the group or the guild.
    local nameBox=Surface('EditBox',offer,'background');window.syncName=nameBox
    nameBox:SetPoint('TOPLEFT',16,-40);nameBox:SetSize(220,26);nameBox:SetAutoFocus(false);nameBox:SetMaxLetters(60)
    nameBox:SetFont(STANDARD_TEXT_FONT,12,'');nameBox:SetTextColor(unpack(colours.text));nameBox:SetTextInsets(8,8,0,0)
    nameBox:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    nameBox:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
    Text(offer,'Player name (or Name-Realm) for the Player buttons.',246,-48,10,'muted',280)
    window.syncCounts={}
    window.syncButtons={}
    for index,kind in ipairs(addon.Sync.kinds) do
        local y=-76-(index-1)*30
        Text(offer,kind.label,16,y-7,12,'text',140)
        window.syncCounts[kind.key]=Text(offer,'',160,y-8,11,'muted',130)
        local function Send(target)
            if target=='PLAYER' then target=(nameBox:GetText() or ''):gsub('^%s+',''):gsub('%s+$','') end
            local _,message=addon.Sync.Send(kind.key,target);window.syncStatus:SetText(message or '')
        end
        for column,spec in ipairs({{'Player','PLAYER'},{'Raid','RAID'},{'Guild','GUILD'}}) do
            local button=Button(offer,spec[1],300+(column-1)*76,y,70,function() Send(spec[2]) end)
            button:SetHeight(26);button.label:ClearAllPoints();button.label:SetPoint('CENTER');button.label:SetWidth(70);button.label:SetJustifyH('CENTER')
            window.syncButtons[kind.key..':'..spec[2]]=button
        end
    end
    -- Player buttons are greyed until a name is typed.
    function window.RefreshPlayerButtons()
        local empty=((nameBox:GetText() or ''):gsub('%s',''))==''
        for _,kind in ipairs(addon.Sync.kinds) do
            local button=window.syncButtons[kind.key..':PLAYER'];button.blocked=empty;button:SetAlpha(empty and 0.45 or 1)
        end
    end
    nameBox:SetScript('OnTextChanged',function() window.RefreshPlayerButtons() end)
    window.RefreshPlayerButtons()
    window.syncStatus=Text(offer,'',16,-260,11,'accent',508)
    Text(offer,'Receivers compare and fetch only what changed. Raid reaches your raid or party.',16,-276,10,'muted',508)
    -- Trust for guild sends.
    local rankMenu=Surface('Frame',syncTab);window.syncRankMenu=rankMenu
    rankMenu:SetSize(284,10);rankMenu:SetFrameLevel(window:GetFrameLevel()+20);rankMenu:EnableMouse(true);rankMenu:Hide()
    local rankRows={}
    for index=1,10 do
        local row;row=Button(rankMenu,'',5,-5-(index-1)*26,274,function()
            if row.rank==nil then return end
            addon.Sync.Settings().guildRank=row.rank;rankMenu:Hide();window.RefreshSync()
        end)
        row:SetHeight(24);row:Hide();rankRows[index]=row
    end
    local function RankName(index)
        local name=GuildControlGetRankName and GuildControlGetRankName(index+1)
        return type(name)=='string' and name~='' and name or ('Rank '..(index+1))
    end
    window.syncRank=Button(trust,'',16,-40,284,function()
        if rankMenu:IsShown() then rankMenu:Hide();return end
        local count=IsInGuild() and GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        if count==0 then window.syncStatus:SetText('Join a guild to choose trusted ranks.');return end
        for index,row in ipairs(rankRows) do
            if index<=count then row.rank=index-1;row.label:SetText(RankName(index-1)..(index==1 and '' or ' and above'));row:Show() else row.rank=nil;row:Hide() end
        end
        rankMenu:SetHeight(10+math.min(count,10)*26);rankMenu:ClearAllPoints();rankMenu:SetPoint('TOPLEFT',window.syncRank,'BOTTOMLEFT',0,-2);rankMenu:Show()
    end)
    Text(trust,'Trusted: guild members at this rank or higher, plus your raid leader and assistants. Their sends apply automatically, from Sync and every page; others need Accept.',16,-76,10,'muted',284)
    window.syncAuto=CheckBox(trust,'Auto-sync with trusted guild members',284,'After login and shortly after you edit something, compare with trusted guild members and fetch only what changed.')
    window.syncAuto:SetPoint('TOPLEFT',16,-140)
    window.syncAuto:SetScript('OnClick',function(self) addon.Sync.Settings().auto=self:GetChecked() and true or false end)
    Text(trust,'Newest edit wins. Deleting something removes it for everyone who syncs.',16,-168,10,'muted',284)
    function window.RefreshSync()
        if not window.syncCounts then return end
        local S=addon.Sync
        for _,kind in ipairs(S.kinds) do
            local count=S.Count(kind.key)
            window.syncCounts[kind.key]:SetText(count..' '..kind.noun..(count==1 and '' or 's'))
        end
        local _,progress=S.Progress()
        window.syncStatus:SetText(progress or S.status or '')
        local rank=S.Settings().guildRank
        window.syncRank.label:SetText((IsInGuild() and (RankName(rank)..(rank==0 and '' or ' and above')) or 'Not in a guild')..'  v')
        for index,row in ipairs(window.syncRows) do
            local session=S.pending[index]
            if session then
                local kind;for _,k in ipairs(S.kinds) do if k.key==session.key then kind=k end end
                row.text:SetText((session.sender:gsub('%-.*$',''))..': '..kind.label:lower()..' ('..(session.count or 0)..')');row:Show()
            else row:Hide() end
        end
        window.syncNone:SetShown(#S.pending==0)
        window.syncAuto:SetChecked(S.Settings().auto)
    end
    addon.RefreshSyncTab=function() if window and window:IsShown() and syncTab:IsShown() then window.RefreshSync() end end
    local function SettingsButton(parent,label,width,action)
        local b=Button(parent,label,0,0,width,function() end)
        b:SetScript('OnClick',function(self) if not InCombatLockdown() then action(self) end end)
        return b
    end
    local function SettingsText(...)
        local t=Text(...);t:ClearAllPoints();return t
    end
    -- General tab: Window and Raid on top; Notes and Minimap & raid panel below.
    local windowCard=Card(settings,'Window',0,-56,424,160)
    local raidCard=Card(settings,'Raid',440,-56,424,160)
    local notesCard=Card(settings,'Notes',0,-224,424,194)
    local panelCard=Card(settings,'Minimap and raid panel',440,-224,424,194)
    window.generalCards={window=windowCard,raid=raidCard,notes=notesCard,panel=panelCard}
    -- Raid panel preview: the party and raid versions without being in a group.
    local previewCard=Card(settings,'Raid panel preview',0,-428,424,128)
    window.generalCards.preview=previewCard
    local previewHint=SettingsText(previewCard,'',0,0,10,'muted',392);previewHint:SetPoint('TOPLEFT',16,-40);previewHint:SetWidth(392)
    previewHint:SetText('See the party or raid version of the raid panel (the raid one inside a raid, with sample tanks). Its buttons do nothing.')
    window.panelPreviewStatus=SettingsText(previewCard,'',0,0,10,'accent',392);window.panelPreviewStatus:SetPoint('TOPLEFT',16,-108);window.panelPreviewStatus:SetWidth(392)
    local function PreviewButton(label,x,width,kind)
        local b=SettingsButton(previewCard,label,width,function()
            local _,message=addon.PreviewRaidPanel(kind);window.panelPreviewStatus:SetText(message or '')
        end)
        b:SetPoint('TOPLEFT',x,-70);b:SetHeight(26);b.label:ClearAllPoints();b.label:SetPoint('CENTER');b.label:SetWidth(width);b.label:SetJustifyH('CENTER')
        return b
    end
    window.previewParty=PreviewButton('Preview party',16,120,'party')
    window.previewRaid=PreviewButton('Preview raid',144,120,'raid')
    window.previewStop=PreviewButton('Stop preview',272,136,nil)
    -- Raid
    window.autoAssist=CheckBox(raidCard,'Auto raid assist for tanks (leader only)',392)
    window.autoAssist:SetPoint('TOPLEFT',16,-40)
    window.autoAssist:SetScript('OnClick',function(self)
        if InCombatLockdown() then return end
        db.autoTankAssist=self:GetChecked() and true or false
        addon.ResetTankAssistAttempts();addon.UpdateTankAssist();Refresh()
    end)
    local assistHint=SettingsText(raidCard,'',0,0,10,'muted',392);assistHint:SetPoint('TOPLEFT',16,-66);assistHint:SetText('When you lead, tank-role players get raid assist.')
    -- Reminder text-to-speech is a per-client opt-in.
    local reminderTTS=CheckBox(raidCard,'Allow reminder text-to-speech on this client',392);window.reminderTTS=reminderTTS
    reminderTTS:SetPoint('TOPLEFT',16,-92)
    reminderTTS:SetScript('OnClick',function(self)
        if InCombatLockdown() then self:SetChecked(db.reminderTTS==true);return end
        db.reminderTTS=self:GetChecked() and true or false
    end)
    local ttsHint=SettingsText(raidCard,'',0,0,10,'muted',392);ttsHint:SetPoint('TOPLEFT',16,-118);ttsHint:SetText('Reminders set to speak are read aloud on this computer only.')
    -- Window
    local strataTitle=SettingsText(windowCard,'',0,0,10,'muted',392);strataTitle:SetPoint('TOPLEFT',16,-40);strataTitle:SetText('FRAME STRATA')
    local strataButton=SettingsButton(windowCard,StrataLabel(db.frameStrata)..'  v',322,function() end)
    strataButton:SetPoint('TOPLEFT',16,-56);window.strataButton=strataButton
    local hint=SettingsText(windowCard,'',0,0,10,'muted',392);hint:SetPoint('TOPLEFT',16,-90);hint:SetText('Higher layers appear above other addon windows.')
    local lock=CheckBox(windowCard,'Lock frame position',300);window.lock=lock
    lock:SetPoint('TOPLEFT',16,-108);lock:SetChecked(db.locked)
    lock:SetScript('OnClick',function(self)
        if InCombatLockdown() then return end
        db.locked=self:GetChecked() and true or false;addon.UpdateCompactPanelSettings()
    end)
    local moveHint=SettingsText(windowCard,'',0,0,10,'muted',392);moveHint:SetPoint('TOPLEFT',16,-134);moveHint:SetText('Uncheck to move the panel by dragging its title.')
    local strataMenu=CreateFrame('Frame',nil,settings,'BackdropTemplate');window.strataMenu=strataMenu
    strataMenu:Hide();strataMenu:SetSize(322,248);strataMenu:SetPoint('TOPLEFT',strataButton,'BOTTOMLEFT',0,-2)
    strataMenu:SetFrameLevel(window:GetFrameLevel()+20);strataMenu:EnableMouse(true)
    strataMenu:SetClampedToScreen(true)
    strataMenu:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    strataMenu:SetBackdropColor(0.078,0.086,0.106,1);strataMenu:SetBackdropBorderColor(unpack(accent))
    for i,value in ipairs(strataOptions) do
        local choice=value
        local option=SettingsButton(strataMenu,StrataLabel(choice),302,function()
            if InCombatLockdown() then return end
            db.frameStrata=choice;addon.UpdateCompactPanelSettings();strataButton.label:SetText(StrataLabel(choice)..'  v');strataMenu:Hide()
        end)
        option:SetPoint('TOPLEFT',10,-8-(i-1)*29)
    end
    strataButton:SetScript('OnClick',function()
        if InCombatLockdown() then return end
        window.noteMenu:Hide()
        if strataMenu:IsShown() then strataMenu:Hide() else strataMenu:Show() end
    end)
    -- Notes
    local noteTitle=SettingsText(notesCard,'',0,0,10,'muted',392);noteTitle:SetPoint('TOPLEFT',16,-40);noteTitle:SetText('STARTING TEXT NOTE')
    local noteButton=SettingsButton(notesCard,addon.GetStartingNoteName()..'  v',322,function() end)
    window.noteButton=noteButton;noteButton:SetPoint('TOPLEFT',16,-56)
    noteButton.label:SetWidth(300);noteButton.label:SetWordWrap(false)
    local noteHint=SettingsText(notesCard,'',0,0,10,'muted',392);noteHint:SetPoint('TOPLEFT',16,-90);noteHint:SetWidth(392)
    noteHint:SetText('Shows at raid entry until a boss-assigned note takes over.')
    local noteMenu=CreateFrame('Frame',nil,settings,'BackdropTemplate');window.noteMenu=noteMenu
    noteMenu:Hide();noteMenu:SetSize(322,242);noteMenu:SetPoint('BOTTOMLEFT',noteButton,'TOPLEFT',0,2)
    noteMenu:SetFrameLevel(window:GetFrameLevel()+20);noteMenu:EnableMouse(true);noteMenu:EnableMouseWheel(true)
    noteMenu:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    noteMenu:SetBackdropColor(0.078,0.086,0.106,1);noteMenu:SetBackdropBorderColor(unpack(accent))
    local noteEntries,noteOffset,noteRows={},0,{}
    local noteRange=SettingsText(noteMenu,'',0,0,10,'muted',300);noteRange:SetPoint('BOTTOMLEFT',10,10)
    local function DrawNotes()
        for i,row in ipairs(noteRows) do
            row.entry=noteEntries[noteOffset+i]
            row.label:SetText(row.entry and row.entry.name or '')
            if row.entry then row:Show() else row:Hide() end
        end
        noteRange:SetText(string.format('%d–%d of %d · scroll for more',noteOffset+1,math.min(noteOffset+7,#noteEntries),#noteEntries))
    end
    for i=1,7 do
        local row=SettingsButton(noteMenu,'',302,function(self)
            if InCombatLockdown() or not self.entry then return end
            db.nativeStartingNoteID=self.entry.value;db.startingNote=nil;db.startingNoteChosen=true
            noteButton.label:SetText(self.entry.name..'  v');noteMenu:Hide()
            addon.UpdateNativeTextNote()
        end)
        row:SetPoint('TOPLEFT',10,-8-(i-1)*29);row.label:SetWidth(282);row.label:SetWordWrap(false);noteRows[i]=row
    end
    noteMenu:SetScript('OnMouseWheel',function(_,delta)
        if InCombatLockdown() then return end
        noteOffset=math.max(0,math.min(math.max(0,#noteEntries-7),noteOffset-delta));DrawNotes()
    end)
    noteButton:SetScript('OnClick',function()
        if InCombatLockdown() then return end
        strataMenu:Hide()
        if noteMenu:IsShown() then noteMenu:Hide();return end
        noteEntries=addon.GetStartingNotes();noteOffset=0;DrawNotes();noteMenu:Show()
    end)
    local leaderOnly=CheckBox(notesCard,'Auto-show notes only when I am raid leader',392,'On: text notes open by themselves only for the raid leader. Anyone can still open them from Notes.');window.notesLeaderOnly=leaderOnly
    leaderOnly:SetPoint('TOPLEFT',16,-110);leaderOnly:SetChecked(db.notesLeaderOnly~=false)
    leaderOnly:SetScript('OnClick',function(self)
        if InCombatLockdown() then self:SetChecked(db.notesLeaderOnly~=false);return end
        db.notesLeaderOnly=self:GetChecked() and true or false;addon.UpdateNativeTextNote()
    end)
    local visual=CheckBox(notesCard,'Auto-show boss visual notes',300);window.autoVisual=visual
    visual:SetPoint('TOPLEFT',16,-136);visual:SetChecked(db.autoVisualNotes)
    visual:SetScript('OnClick',function(self)
        if InCombatLockdown() then return end
        addon.SetAutoVisualNotes(self:GetChecked());Refresh()
    end)
    window.visualStatus=SettingsText(notesCard,'',0,0,10,'muted',392);window.visualStatus:SetPoint('TOPLEFT',16,-162);window.visualStatus:SetWidth(392)
    -- Minimap and raid panel
    local minimapVisible=CheckBox(panelCard,'Show minimap button',300);window.minimapVisible=minimapVisible
    minimapVisible:SetPoint('TOPLEFT',16,-40)
    minimapVisible:SetScript('OnClick',function(self)
        if not InCombatLockdown() then addon.SetMinimapButtonShown(self:GetChecked()) end
    end)
    -- Raid panel: when its icon is available, and whether it opens itself in raids.
    local panelModes={{'always','Always'},{'group','In a party or raid'},{'raid','In a raid group only'}}
    window.panelModeLabels={}
    for _,mode in ipairs(panelModes) do window.panelModeLabels[mode[1]]=mode[2] end
    local panelTitle=SettingsText(panelCard,'',0,0,10,'muted',392);panelTitle:SetPoint('TOPLEFT',16,-70);panelTitle:SetText('RAID PANEL ICON')
    local panelModeButton=SettingsButton(panelCard,'',322,function() end)
    panelModeButton:SetPoint('TOPLEFT',16,-86);window.panelMode=panelModeButton
    local panelMenu=CreateFrame('Frame',nil,settings,'BackdropTemplate');window.panelModeMenu=panelMenu
    panelMenu:Hide();panelMenu:SetSize(322,10+#panelModes*29);panelMenu:SetPoint('TOPLEFT',panelModeButton,'BOTTOMLEFT',0,-2)
    panelMenu:SetFrameLevel(window:GetFrameLevel()+20);panelMenu:EnableMouse(true);panelMenu:SetClampedToScreen(true)
    panelMenu:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    panelMenu:SetBackdropColor(0.078,0.086,0.106,1);panelMenu:SetBackdropBorderColor(unpack(accent))
    for index,mode in ipairs(panelModes) do
        local value=mode[1]
        local option=SettingsButton(panelMenu,mode[2],302,function()
            if InCombatLockdown() then return end
            db.panelMode=value;panelMenu:Hide()
            if addon.UpdateRaidPanelVisibility then addon.UpdateRaidPanelVisibility() end
            Refresh()
        end)
        option:SetPoint('TOPLEFT',10,-5-(index-1)*29)
    end
    panelModeButton:SetScript('OnClick',function()
        if InCombatLockdown() then return end
        strataMenu:Hide();window.noteMenu:Hide()
        if panelMenu:IsShown() then panelMenu:Hide() else panelMenu:Show() end
    end)
    local panelHint=SettingsText(panelCard,'',0,0,10,'muted',392);panelHint:SetPoint('TOPLEFT',16,-120);panelHint:SetWidth(392)
    panelHint:SetText('Click the crest icon to open the raid panel; Hide returns it to the icon.')
    local panelAutoOpen=CheckBox(panelCard,'Open automatically in raid instances',340);window.panelAutoOpen=panelAutoOpen
    panelAutoOpen:SetPoint('TOPLEFT',16,-140)
    panelAutoOpen:SetScript('OnClick',function(self)
        if InCombatLockdown() then self:SetChecked(db.panelAutoOpen);return end
        db.panelAutoOpen=self:GetChecked() and true or false
    end)
    settings:HookScript('OnHide',function() panelMenu:Hide() end)
    local elapsed=0
    window:SetScript('OnUpdate',function(_,dt) elapsed=elapsed+dt;if elapsed>=1 then elapsed=0;Refresh() end end)
end
function addon.OpenMainUI(page)
    if InCombatLockdown() then print('Vincibility: main UI available after combat.');return false end
    Build();window:Show();SelectPage(page or window.selectedPage or 'Notes');return true
end
SLASH_VINCUI1='/vincui'
SlashCmdList.VINCUI=function(message)
    local name=(message or ''):lower():match('^%s*(.-)%s*$')
    if name=='hide' then if window then window:Hide() end;return end
    local pages={notes='Notes',visual='Visual Notes',visualnotes='Visual Notes',reminders='Reminders',assignments='Assignments',groups='Groups',readycheck='Ready Check',ready='Ready Check',auras='Auras',settings='Settings'}
    addon.OpenMainUI(pages[name])
end
local events=CreateFrame('Frame')
events:RegisterEvent('PLAYER_REGEN_DISABLED')
events:SetScript('OnEvent',function()
    if window then window.strataMenu:Hide();window.noteMenu:Hide();window:Hide() end
end)
