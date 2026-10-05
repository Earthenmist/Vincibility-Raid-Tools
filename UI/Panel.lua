local addonName, addon = ...
-- Secure visibility driver hides protected Main Tank buttons during combat.
local panel, launcher, db
-- panelOpen: the user opened the panel from the icon (or /vinc); it starts closed.
local panelOpen, raidKey = false, nil
-- Preview ('party' or 'raid') shows that version of the panel outside a group;
-- its buttons look live but do nothing. Ends when the panel closes or combat starts.
local preview
local function InRaidGroup() if preview then return preview=='raid' end return IsInRaid() end
local function Grouped() if preview then return true end return (IsInGroup and IsInGroup()) or IsInRaid() end
local function IsLeader() if preview then return true end return UnitIsGroupLeader('player') end
local function IsAssist() if preview then return false end return UnitIsGroupAssistant('player') end
local panelModes={always=true,group=true,raid=true}
local strataOptions=addon.PanelStrataOptions
local function CurrentRaid()
    local inside, kind = IsInInstance()
    if not inside or kind ~= 'raid' then return nil end
    local name, _, difficulty, _, _, _, _, mapID = GetInstanceInfo()
    return tostring(mapID)..':'..tostring(difficulty), name
end

local function Text(parent, size, colour)
    local t = parent:CreateFontString(nil, 'OVERLAY')
    t:SetFont(STANDARD_TEXT_FONT, size, '')
    t:SetTextColor(unpack(colour))
    t:SetJustifyH('LEFT')
    return t
end

local accent = {0.72, 0.76, 0.81, 1}
local highlight = {0.78, 0.11, 0.25, 1}
local white = {0.910, 0.918, 0.941, 1}
local muted = {0.541, 0.561, 0.612, 1}
local markerNames={'Star','Circle','Diamond','Triangle','Moon','Square','Cross','Skull'}
local worldMarkerIDs={5,6,3,2,7,1,4,8}
local function Button(parent, label, width, action)
    local b = CreateFrame('Button', nil, parent, 'BackdropTemplate')
    b:SetSize(width, 27)
    b:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8', edgeFile='Interface\\Buttons\\WHITE8X8', edgeSize=1})
    b:SetBackdropColor(0.145,0.157,0.192,1)
    b:SetBackdropBorderColor(0.72,0.76,0.81,0.45)
    b.label=Text(b,12,accent); b.label:SetPoint('CENTER'); b.label:SetText(label)
    b:SetScript('OnEnter',function(self) self:SetBackdropColor(0.114,0.125,0.157,1);self:SetBackdropBorderColor(unpack(highlight)) end)
    b:SetScript('OnLeave',function(self) self:SetBackdropColor(0.145,0.157,0.192,1);self:SetBackdropBorderColor(0.72,0.76,0.81,0.45) end)
    b:SetScript('OnClick',action)
    return b
end

local function CanUseRaidControls()
    local grouped=(IsInGroup and IsInGroup()) or IsInRaid()
    return grouped and (UnitIsGroupLeader('player') or UnitIsGroupAssistant('player'))
end

local function RequireRaidControlAuthority()
    if CanUseRaidControls() then return true end
    print('Vincibility: raid controls require group leader or assistant.')
    return false
end

local function StartReadyCheck()
    if not RequireRaidControlAuthority() then return end
    if DoReadyCheck then DoReadyCheck() end
end

local function StartPull(seconds)
    if not RequireRaidControlAuthority() then return end
    if DBM and type(DBM.CreatePullTimer)=='function' then DBM:CreatePullTimer(seconds)
    elseif C_PartyInfo and C_PartyInfo.DoCountdown then C_PartyInfo.DoCountdown(seconds) end
end

-- Party tools (leader, out of combat, called straight from the click).
local DISBAND_CONFIRM=5
local function PartyLeader()
    return IsInGroup() and not IsInRaid() and UnitIsGroupLeader('player')
end
local function ConvertPartyToRaid()
    if InCombatLockdown() or not PartyLeader() then print('Vincibility: converting to a raid requires the party leader, out of combat.');return end
    if C_PartyInfo and C_PartyInfo.ConvertToRaid then C_PartyInfo.ConvertToRaid() elseif ConvertToRaid then ConvertToRaid() end
end
-- Retail has no disband call: uninvite every member; a party of one dissolves.
local function DisbandParty()
    if InCombatLockdown() or not PartyLeader() then print('Vincibility: disbanding requires the party leader, out of combat.');return 0 end
    local removed=0
    for index=1,4 do
        local unit='party'..index
        if UnitExists(unit) then
            local name=GetUnitName(unit,true)
            if name then
                if C_PartyInfo and C_PartyInfo.UninviteUnit then C_PartyInfo.UninviteUnit(name) elseif UninviteUnit then UninviteUnit(name) end
                removed=removed+1
            end
        end
    end
    print('Vincibility: disbanding the party ('..removed..' member'..(removed==1 and '' or 's')..' removed).')
    return removed
end

local function StartBreak()
    if not RequireRaidControlAuthority() then return end
    -- DBM, then BigWigs (/break), then VRT's own break bar for groups with neither.
    if DBM and type(DBM.CreateBreakTimer)=='function' then DBM:CreateBreakTimer(5)
    elseif SlashCmdList and SlashCmdList['break'] then SlashCmdList['break']('5')
    elseif addon.Break then
        local ok,message=addon.Break.Start(5)
        if not ok then print('Vincibility: '..message) end
    end
end

-- Tanks and raid layouts only make sense in a raid group inside a raid instance.
local function RaidSections()
    if preview then return preview=='raid' end
    return IsInRaid() and raidKey~=nil
end
addon.RaidPanelShowsRaidSections=RaidSections
local raidSectionKeys={'tankTitle','empty','presetTitle','presetButton','presetStatus'}
local partySectionKeys={'partyTitle','convertButton','disbandButton'}
local function Refresh()
    if not panel or not panel:IsShown() or InCombatLockdown() then return end
    local _, name = CurrentRaid()
    if preview then name=preview=='raid' and 'Raid preview' or nil end
    local grouped=Grouped() and true or false
    panel.raid:SetText(name or (InRaidGroup() and 'Raid group' or (grouped and 'Party' or 'Not in a group')))
    local leader,assist=IsLeader(),IsAssist()
    local suffix=preview and ' (preview)' or ''
    if InRaidGroup() then panel.role:SetText((leader and 'Raid leader' or (assist and 'Raid assistant' or 'Raid member'))..suffix)
    elseif grouped then panel.role:SetText((leader and 'Party leader' or 'Party member')..suffix)
    else panel.role:SetText('Solo') end
    -- In a preview every control looks live but cannot be clicked.
    local canControl=preview and true or CanUseRaidControls()
    if panel.raidActionButtons then
        for _,button in ipairs(panel.raidActionButtons) do
            button:SetEnabled(canControl and not preview)
            if button.label then button.label:SetTextColor(unpack(canControl and accent or muted)) end
            if button.icon then button.icon:SetAlpha(canControl and 1 or .35) end
        end
    end
    local showRaid=RaidSections()
    local showParty=not showRaid and grouped and not InRaidGroup()
    panel.compact=not showRaid
    for _,key in ipairs(raidSectionKeys) do panel[key]:SetShown(showRaid) end
    for _,key in ipairs(partySectionKeys) do panel[key]:SetShown(showParty) end
    if showParty then
        local canManage=leader and true or false
        for _,button in ipairs({panel.convertButton,panel.disbandButton}) do
            button:SetEnabled(canManage and not preview);button.label:SetTextColor(unpack(canManage and accent or muted))
        end
        if panel.disbandConfirm and GetTime()>panel.disbandConfirm then panel.disbandConfirm=nil end
        panel.disbandButton.label:SetText(panel.disbandConfirm and 'Click again to disband' or 'Disband party')
        if panel.disbandConfirm then panel.disbandButton.label:SetTextColor(unpack(highlight)) end
    else panel.disbandConfirm=nil end
    if not showRaid then
        panel.presetMenu:Hide()
        for _,row in ipairs(panel.tankRows) do row.assign:SetAttribute('unit',nil);row:Hide() end
        panel:SetHeight(showParty and 268 or 206)
        return
    end
    local tanks=preview and {
        {name='Tank One (sample)',assistant=true,mainTank=true},
        {name='Tank Two (sample)'},
    } or addon.GetTanks()
    panel.presetButton:SetEnabled(not preview)
    local shownTanks=math.min(#tanks,4)
    local noticeHeight=(#tanks==0 or #tanks>4) and 16 or 0
    local contentEnd=91+shownTanks*37
    local presetTop=contentEnd+noticeHeight+8
    if panel.layoutTop~=presetTop then
        panel.layoutTop=presetTop
        panel.empty:ClearAllPoints();panel.empty:SetPoint('TOPLEFT',16,-contentEnd)
        panel.presetTitle:ClearAllPoints();panel.presetTitle:SetPoint('TOPLEFT',16,-presetTop)
        panel.presetButton:ClearAllPoints();panel.presetButton:SetPoint('TOPLEFT',16,-presetTop-18)
        panel.presetStatus:ClearAllPoints();panel.presetStatus:SetPoint('TOPLEFT',16,-presetTop-49)
    end
    -- The layout status line only takes space when it has something to say.
    local layoutStatus=addon.GetGroupStatus and addon.GetGroupStatus() or ''
    panel.presetStatus:SetText(layoutStatus)
    panel:SetHeight(presetTop+223-(layoutStatus=='' and 24 or 0))
    local canAssign=InRaidGroup() and (leader or assist)
    panel.empty:SetText(#tanks==0 and 'No tank roles assigned' or (#tanks>4 and (#tanks-4)..' more tanks — use the raid roster' or ''))
    for i,row in ipairs(panel.tankRows) do
        local tank=tanks[i]
        if tank then
            row.name:SetText(tank.name)
            row.status:SetText(tank.leader and 'Raid leader' or (tank.assistant and 'Raid assist' or 'No raid assist'))
            row.assign:SetAttribute('unit',not preview and tank.unit or nil)
            row.assign.label:SetText(tank.mainTank and 'Remove Main Tank' or 'Set Main Tank')
            row.assign:SetEnabled(canAssign and not preview)
            row.assign.label:SetTextColor(unpack(canAssign and accent or muted))
            row:Show()
        else
            row.assign:SetAttribute('unit',nil)
            row:Hide()
        end
    end
end

-- Settings > Raid panel icon: always, in a party or raid (default), or raid group only.
local function PanelMode()
    local mode=db and db.panelMode
    return panelModes[mode] and mode or 'group'
end
local function Available()
    if addon.ModuleEnabled and not addon.ModuleEnabled('panel') then return false end
    if preview then return true end
    local mode=PanelMode()
    if mode=='always' then return true end
    if mode=='raid' then return IsInRaid() or raidKey~=nil end
    return (IsInGroup and IsInGroup()) or IsInRaid() or raidKey~=nil
end
addon.RaidPanelAvailable=Available

local function SetVisible(show)
    if not panel or InCombatLockdown() then return end
    panel:SetAttribute('wanted',show and true or false)
    if show then
        if launcher then launcher:Hide() end
        panel:Show();Refresh()
    else
        preview=nil
        panel:Hide()
        if launcher then launcher:SetShown(Available()) end
    end
end

local function Visibility()
    if not panel then return end
    if InCombatLockdown() then return end
    if not Available() then panelOpen=false end
    SetVisible(panelOpen)
end
addon.UpdateRaidPanelVisibility=Visibility

local function Build()
    if panel then return end
    VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
    db=VincibilityRaidToolsDB
    if db.autoTankAssist==nil then db.autoTankAssist=true end
    if not db.autoVisualNotesChosen then db.autoVisualNotes=false end
    if not panelModes[db.panelMode] then db.panelMode='group' end
    db.panelAutoOpen=db.panelAutoOpen==true
    local validStrata=false
    for _,value in ipairs(strataOptions) do if value==db.frameStrata then validStrata=true end end
    if not validStrata then db.frameStrata='MEDIUM' end
    db.locked=db.locked==true
    if type(db.raidPanelLauncher)~='table' then db.raidPanelLauncher={} end
    local launcherSettings=db.raidPanelLauncher
    if launcherSettings.locked==nil then launcherSettings.locked=true
    else launcherSettings.locked=launcherSettings.locked==true end
    if type(launcherSettings.x)~='number' or launcherSettings.x~=launcherSettings.x or math.abs(launcherSettings.x)>5000 then launcherSettings.x=nil end
    if type(launcherSettings.y)~='number' or launcherSettings.y~=launcherSettings.y or math.abs(launcherSettings.y)>5000 then launcherSettings.y=nil end
    panel=CreateFrame('Frame','VincibilityRaidPanel',UIParent,'SecureHandlerStateTemplate,BackdropTemplate')
    panel:Hide()
    panel:SetAttribute('wanted',false)
    panel:SetAttribute('_onstate-combat', [[
        if newstate == 'combat' then
            -- All controls inherit visibility from this protected parent.
            -- Ordinary dropdown frames cannot be used as restricted frame handles.
            self:Hide()
        elseif self:GetAttribute('wanted') then self:Show() end
    ]])
    RegisterStateDriver(panel,'combat','[combat] combat; peace')
    panel:SetSize(354,522)
    panel:SetFrameStrata(db.frameStrata)
    panel:SetClampedToScreen(true)
    panel:SetMovable(not db.locked)
    panel:EnableMouse(true)
    panel:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    panel:SetBackdropColor(0.078,0.086,0.106,0.97)
    panel:SetBackdropBorderColor(0.180,0.196,0.235,1)
    panel:SetPoint('CENTER',UIParent,'CENTER',tonumber(db.x) or 380,tonumber(db.y) or 100)

    launcher=CreateFrame('Button','VincibilityRaidPanelLauncher',UIParent,'BackdropTemplate')
    launcher:SetSize(44,44)
    launcher:SetFrameStrata(db.frameStrata)
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(not launcherSettings.locked)
    launcher:EnableMouse(true)
    launcher:RegisterForClicks('LeftButtonUp','RightButtonUp')
    launcher:RegisterForDrag('LeftButton')
    launcher:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    launcher:SetBackdropColor(0.078,0.086,0.106,0.97)
    if launcherSettings.x and launcherSettings.y then
        launcher:SetPoint('CENTER',UIParent,'CENTER',launcherSettings.x,launcherSettings.y)
    else
        launcher:SetPoint('LEFT',UIParent,'LEFT',10,0)
    end
    local launcherCrest=addon.CreateGuildCrest(launcher,36)
    launcherCrest:SetPoint('CENTER')
    launcher.crest=launcherCrest
    local launcherLock=Text(launcher,10,highlight)
    launcherLock:SetPoint('BOTTOMRIGHT',-3,2)
    launcherLock:SetText('L')
    launcher.lockIndicator=launcherLock
    local function UpdateLauncherLock()
        launcher:SetMovable(not launcherSettings.locked)
        launcherLock:SetShown(launcherSettings.locked)
        if launcherSettings.locked then launcher:SetBackdropBorderColor(0.72,0.76,0.81,0.45)
        else launcher:SetBackdropBorderColor(unpack(highlight)) end
    end
    local function SaveLauncherPosition()
        if InCombatLockdown() then return end
        launcher:StopMovingOrSizing()
        local x,y=launcher:GetCenter();local cx,cy=UIParent:GetCenter()
        if x and y and cx and cy then
            launcherSettings.x=x-cx;launcherSettings.y=y-cy
            launcher:ClearAllPoints()
            launcher:SetPoint('CENTER',UIParent,'CENTER',launcherSettings.x,launcherSettings.y)
        end
    end
    launcher:SetScript('OnClick',function(_,mouseButton)
        if mouseButton=='RightButton' then
            launcherSettings.locked=not launcherSettings.locked
            if launcherSettings.locked then SaveLauncherPosition() end
            UpdateLauncherLock()
        elseif mouseButton=='LeftButton' and not launcher.suppressClick then
            panelOpen=true
            SetVisible(true)
        end
    end)
    launcher:SetScript('OnDragStart',function(self)
        if InCombatLockdown() or launcherSettings.locked then return end
        self.suppressClick=true
        self:StartMoving()
    end)
    launcher:SetScript('OnDragStop',function(self)
        if launcherSettings.locked then return end
        SaveLauncherPosition()
        C_Timer.After(0,function() self.suppressClick=false end)
    end)
    launcher:SetScript('OnEnter',function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
        GameTooltip:AddLine('Vincibility Raid Tools',.72,.76,.81)
        GameTooltip:AddLine('Left click: Open raid panel',1,1,1)
        GameTooltip:AddLine(launcherSettings.locked and 'Right click: Unlock position' or 'Right click: Lock position',1,1,1)
        if not launcherSettings.locked then GameTooltip:AddLine('Left drag: Move',.7,.7,.7) end
        GameTooltip:Show()
    end)
    launcher:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    UpdateLauncherLock()
    launcher:Hide()
    panel.launcher=launcher

    local top=panel:CreateTexture(nil,'ARTWORK');top:SetColorTexture(unpack(highlight));top:SetPoint('TOPLEFT',1,-1);top:SetPoint('TOPRIGHT',-1,-1);top:SetHeight(3)
    local hide=Button(panel,'Hide',54,function() panelOpen=false;SetVisible(false) end);hide:SetPoint('TOPRIGHT',-12,-15)
    local content=CreateFrame('Frame',nil,panel);content:SetAllPoints(panel);panel.content=content
    local mainUIButton=Button(panel,'Main UI',72,function() addon.OpenMainUI() end);mainUIButton:SetPoint('TOPRIGHT',-74,-15)
    panel.mainUIButton=mainUIButton
    local drag=CreateFrame('Frame',nil,panel);drag:SetPoint('TOPLEFT',0,0);drag:SetSize(198,55);drag:EnableMouse(true);drag:RegisterForDrag('LeftButton')
    drag:SetScript('OnDragStart',function() if not InCombatLockdown() and not db.locked then panel:StartMoving() end end)
    local function SavePosition()
        if InCombatLockdown() then return end
        if panel.presetMenu then panel.presetMenu:Hide() end
        panel:StopMovingOrSizing()
        local x,y=panel:GetCenter();local cx,cy=UIParent:GetCenter()
        if x and y and cx and cy then db.x=x-cx;db.y=y-cy end
    end
    drag:SetScript('OnDragStop',SavePosition)
    panel:SetScript('OnHide',SavePosition)
    panel:SetScript('OnShow',function()
        if InCombatLockdown() then return end
        if panel.presetMenu then panel.presetMenu:Hide() end
    end)
    panel.raid=Text(content,14,white);panel.raid:SetPoint('TOPLEFT',16,-20);panel.raid:SetWidth(176)
    panel.role=Text(content,11,muted);panel.role:SetPoint('TOPLEFT',16,-41)
    local tankTitle=Text(content,11,accent);tankTitle:SetPoint('TOPLEFT',16,-70);tankTitle:SetText('TANKS');panel.tankTitle=tankTitle
    panel.tankRows={}
    for i=1,4 do
        local row=CreateFrame('Frame',nil,content)
        row:SetSize(322,36);row:SetPoint('TOPLEFT',16,-91-(i-1)*37)
        row.name=Text(row,12,white);row.name:SetPoint('TOPLEFT');row.name:SetSize(192,16);row.name:SetWordWrap(false)
        row.status=Text(row,10,muted);row.status:SetPoint('TOPLEFT',0,-17)
        local b=CreateFrame('Button',nil,row,'SecureActionButtonTemplate,BackdropTemplate')
        b:SetSize(122,28);b:SetPoint('TOPRIGHT',0,0)
        b:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
        b:SetBackdropColor(0.145,0.157,0.192,1);b:SetBackdropBorderColor(0.72,0.76,0.81,0.45)
        b.label=Text(b,11,accent);b.label:SetPoint('CENTER');b.label:SetText('Set Main Tank')
        b:RegisterForClicks('AnyUp','AnyDown')
        b:SetAttribute('useOnKeyDown',false)
        b:SetAttribute('type','maintank');b:SetAttribute('action','toggle')
        b:HookScript('PostClick',function() C_Timer.After(0.2,Refresh) end)
        row.assign=b;panel.tankRows[i]=row
    end
    -- Party section: shown in place of Tanks/layouts while in a party.
    panel.partyTitle=Text(content,11,accent);panel.partyTitle:SetPoint('TOPLEFT',16,-70);panel.partyTitle:SetText('GROUP')
    panel.convertButton=Button(content,'Convert to raid',156,function()
        if InCombatLockdown() then return end
        ConvertPartyToRaid();C_Timer.After(0.5,Refresh)
    end)
    panel.convertButton:SetPoint('TOPLEFT',16,-88)
    panel.disbandButton=Button(content,'Disband party',156,function()
        if InCombatLockdown() then return end
        if not panel.disbandConfirm or GetTime()>panel.disbandConfirm then
            panel.disbandConfirm=GetTime()+DISBAND_CONFIRM;Refresh();return
        end
        panel.disbandConfirm=nil;DisbandParty();C_Timer.After(0.5,Refresh)
    end)
    panel.disbandButton:SetPoint('TOPLEFT',182,-88)
    for _,key in ipairs({'partyTitle','convertButton','disbandButton'}) do panel[key]:Hide() end
    panel.empty=Text(content,10,muted);panel.empty:SetPoint('TOPLEFT',16,-363)
    panel.presetTitle=Text(content,11,accent);panel.presetTitle:SetPoint('TOPLEFT',16,-386);panel.presetTitle:SetText('APPLY RAID LAYOUT')
    panel.presetButton=Button(content,'Select group layout  v',322,function() end)
    panel.presetButton:SetPoint('TOPLEFT',16,-404)
    panel.presetButton.label:SetWidth(296);panel.presetButton.label:SetWordWrap(false)
    panel.presetStatus=Text(content,10,muted);panel.presetStatus:SetPoint('TOPLEFT',16,-435);panel.presetStatus:SetWidth(322)
    panel.presetStatus:SetHeight(28)
    panel.presetStatus:SetText('Selection applies now. Groups 7–8 stay untouched.')
    local menu=CreateFrame('Frame',nil,content,'BackdropTemplate')
    panel.presetMenu=menu;menu:Hide();menu:SetSize(322,212)
    menu:SetPoint('BOTTOMLEFT',panel.presetButton,'TOPLEFT',0,2)
    menu:SetFrameLevel(panel:GetFrameLevel()+20)
    menu:EnableMouse(true);menu:EnableMouseWheel(true)
    menu:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    menu:SetBackdropColor(0.078,0.086,0.106,1);menu:SetBackdropBorderColor(unpack(accent))
    local entries,offset={},0
    local rows={}
    local range=Text(menu,10,muted);range:SetPoint('BOTTOMLEFT',10,10)
    local function DrawMenu()
        for i,row in ipairs(rows) do
            local entry=entries[offset+i]
            row.entry=entry
            row.label:SetText(entry and entry.name or '')
            if entry then row:Show() else row:Hide() end
        end
        range:SetText('Live roster · groups 7–8 excluded')
    end
    for i=1,6 do
        local row=Button(menu,'',302,function(self)
            if InCombatLockdown() or not self.entry then return end
            local entry=self.entry
            menu:Hide()
            local ok,message=addon.ApplyGroupPreset(entry.preset)
            panel.presetStatus:SetText(message)
            if ok then panel.presetButton.label:SetText(entry.name..'  v') end
            print('Vincibility: '..(ok and ('Applying '..entry.name..'. ') or '')..message)
        end)
        row:SetPoint('TOPLEFT',10,-8-(i-1)*29)
        row.label:SetWidth(282);row.label:SetWordWrap(false)
        rows[i]=row
    end
    menu:SetScript('OnMouseWheel',function(_,delta)
        if InCombatLockdown() then return end
        offset=math.max(0,math.min(math.max(0,#entries-#rows),offset-delta));DrawMenu()
    end)
    local function OpenGroupMenu()
        if InCombatLockdown() then return end
        if menu:IsShown() then menu:Hide();return end
        entries=addon.GetGroupPresets();offset=0;DrawMenu();menu:Show()
    end
    panel.presetButton:SetScript('OnClick',OpenGroupMenu)
    local controls=CreateFrame('Frame',nil,content)
    controls:SetSize(322,130);controls:SetPoint('BOTTOMLEFT',16,14)
    panel.raidControls=controls
    local controlsTitle=Text(controls,11,accent);controlsTitle:SetPoint('TOPLEFT',0,0);controlsTitle:SetText('CHECKS AND TIMERS');panel.controlsTitle=controlsTitle
    panel.raidActionButtons={}
    local ready=Button(controls,'Ready Check',156,StartReadyCheck);ready:SetPoint('TOPLEFT',0,-16)
    local breakButton=Button(controls,'Break 5',156,StartBreak);breakButton:SetPoint('TOPRIGHT',0,-16)
    panel.raidActionButtons[#panel.raidActionButtons+1]=ready
    panel.raidActionButtons[#panel.raidActionButtons+1]=breakButton
    panel.readyCheckButton=ready;panel.breakButton=breakButton;panel.pullButtons={}
    local pullLabel=Text(controls,10,muted);pullLabel:SetPoint('TOPLEFT',0,-56);pullLabel:SetText('Pull')
    for i,value in ipairs({5,10,15,0}) do
        local seconds=value
        local label=seconds==0 and 'Stop' or tostring(seconds)
        local pull=Button(controls,label,i==4 and 67 or 65,function() StartPull(seconds) end)
        pull:SetPoint('TOPLEFT',42+(i-1)*71,-48)
        panel.pullButtons[i]=pull
        panel.raidActionButtons[#panel.raidActionButtons+1]=pull
    end
    local separator=controls:CreateTexture(nil,'ARTWORK')
    separator:SetColorTexture(unpack(highlight));separator:SetPoint('TOPLEFT',0,-88);separator:SetPoint('TOPRIGHT',0,-88);separator:SetHeight(2)
    controls.separator=separator
    local worldLabel=Text(controls,10,muted);worldLabel:SetPoint('TOPLEFT',0,-111);worldLabel:SetText('World')
    panel.worldMarkerButtons={}
    for i=1,9 do
        local markerIndex=i
        local worldMarkerID=worldMarkerIDs[markerIndex]
        local marker=CreateFrame('Button',nil,controls,'SecureActionButtonTemplate,BackdropTemplate')
        marker:SetSize(25,25);marker:SetPoint('TOPLEFT',42+(markerIndex-1)*31,-104)
        marker:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
        marker:SetBackdropColor(0.078,0.086,0.106,1);marker:SetBackdropBorderColor(0.72,0.76,0.81,0.35)
        marker:RegisterForClicks('AnyDown')
        marker:SetAttribute('useOnKeyDown',true)
        if markerIndex<=8 then
            marker:SetAttribute('type1','worldmarker')
            marker:SetAttribute('marker1',tostring(worldMarkerID))
            marker:SetAttribute('action1','set')
            marker:SetAttribute('type2','worldmarker')
            marker:SetAttribute('marker2',tostring(worldMarkerID))
            marker:SetAttribute('action2','clear')
        else
            marker:SetAttribute('type','macro')
            marker:SetAttribute('macrotext',(SLASH_CLEAR_WORLD_MARKER1 or '/cwm')..' '..(ALL or 'All'))
        end
        local icon=marker:CreateTexture(nil,'ARTWORK')
        icon:SetSize(20,20);icon:SetPoint('CENTER')
        icon:SetTexture(markerIndex<=8 and ('Interface\\TargetingFrame\\UI-RaidTargetingIcon_'..markerIndex) or 'Interface\\Buttons\\UI-GroupLoot-Pass-Up')
        marker.icon=icon
        marker:SetScript('OnEnter',function(self)
            self:SetBackdropBorderColor(unpack(highlight))
            if not GameTooltip then return end
            GameTooltip:SetOwner(self,'ANCHOR_TOP')
            if markerIndex<=8 then
                GameTooltip:AddLine(markerNames[markerIndex]..' world marker',.72,.76,.81)
                GameTooltip:AddLine('Left click: Place',1,1,1)
                GameTooltip:AddLine('Right click: Clear',1,1,1)
            else GameTooltip:AddLine('Clear all world markers',.72,.76,.81) end
            GameTooltip:Show()
        end)
        marker:SetScript('OnLeave',function(self)
            self:SetBackdropBorderColor(0.72,0.76,0.81,0.35)
            if GameTooltip then GameTooltip:Hide() end
        end)
        panel.worldMarkerButtons[markerIndex]=marker
        panel.raidActionButtons[#panel.raidActionButtons+1]=marker
    end
    local elapsed=0
    panel:SetScript('OnUpdate',function(_,dt) elapsed=elapsed+dt;if elapsed>=1 then elapsed=0;Refresh() end end)
end

function addon.UpdateCompactPanelSettings()
    if InCombatLockdown() then return end
    Build()
    panel:SetFrameStrata(db.frameStrata)
    panel:SetMovable(not db.locked)
    if launcher then launcher:SetFrameStrata(db.frameStrata) end
    Refresh()
end

local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_ENTERING_WORLD','ZONE_CHANGED_NEW_AREA','PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED','GROUP_ROSTER_UPDATE','GROUP_JOINED','GROUP_LEFT','PLAYER_ROLES_ASSIGNED','ROLE_CHANGED_INFORM','PARTY_LEADER_CHANGED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event)
    if event=='PLAYER_LOGIN' then Build() end
    if not panel then return end
    if event=='GROUP_ROSTER_UPDATE' and not IsInRaid() then addon.ResetTankAssistAttempts() end
    addon.UpdateTankAssist()
    if event=='PLAYER_ENTERING_WORLD' or event=='ZONE_CHANGED_NEW_AREA' or event=='PLAYER_LOGIN' then
        local key=CurrentRaid()
        if key~=raidKey then
            raidKey=key
            -- Optional: open on entering a raid instance (off by default).
            if key and db.panelAutoOpen then panelOpen=true end
        end
        Visibility()
    elseif event=='PLAYER_REGEN_DISABLED' then
        if preview then preview=nil;panelOpen=false;panel:Hide() end
        if launcher then launcher:Hide() end
    elseif event=='PLAYER_REGEN_ENABLED' or event=='GROUP_ROSTER_UPDATE' or event=='GROUP_JOINED' or event=='GROUP_LEFT' then
        Visibility();Refresh()
    else Refresh() end
end)

-- Settings: show the party or raid version of the panel (nil ends the preview).
function addon.PreviewRaidPanel(kind)
    if InCombatLockdown() then return false,'Preview the raid panel out of combat.' end
    if not panel then Build() end
    if kind~='party' and kind~='raid' then
        if preview then preview=nil;panelOpen=false;SetVisible(false) end
        return true,'Raid panel preview ended.'
    end
    preview=kind;panelOpen=true;SetVisible(true);Refresh()
    return true,(kind=='raid' and 'Raid' or 'Party')..' panel preview: buttons do nothing. Close the panel to end it.'
end
function addon.RaidPanelPreview() return preview end
SLASH_VINCIBILITYRAIDTOOLS1='/vinc'
SlashCmdList.VINCIBILITYRAIDTOOLS=function(message)
    if not panel then Build() end
    if InCombatLockdown() then print('Vincibility: panel available after combat.');return end
    if message and message:lower():match('^hide%s*$') then panelOpen=false;SetVisible(false);return end
    panelOpen=true;SetVisible(true)
end
