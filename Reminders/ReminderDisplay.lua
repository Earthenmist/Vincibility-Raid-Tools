local addonName,addon=...
local R=addon.Reminders
local D={roots={},items={},preview=false}
addon.ReminderDisplay=D
local kinds={'Texts','Icons','Bars','Circles','Debuff Overview'}
D.kinds=kinds
local defaults={Texts={0,-20},Icons={-300,100},Bars={-300,-170},Circles={300,-170},['Debuff Overview']={-600,-170}}
local accent={0.72,0.76,0.81,1}
local function Label(parent,size)
 local t=parent:CreateFontString(nil,'OVERLAY')
 t:SetFont(STANDARD_TEXT_FONT,size,'OUTLINE');t:SetTextColor(0.91,0.92,0.94,1);return t
end
local function Box(kind,parent)
 local f=CreateFrame(kind,nil,parent,'BackdropTemplate')
 f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 f:SetBackdropColor(0.078,0.086,0.106,0.9);f:SetBackdropBorderColor(unpack(accent));return f
end
local function Positions()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.reminderPositions)~='table' then db.reminderPositions={} end
 for _,kind in ipairs(kinds) do
  local pos=db.reminderPositions[kind]
  if type(pos)~='table' or type(pos.x)~='number' or type(pos.y)~='number' or pos.x~=pos.x or pos.y~=pos.y then
   db.reminderPositions[kind]={x=defaults[kind][1],y=defaults[kind][2],scale=1}
  end
 end
 return db.reminderPositions
end
local function Place(root)
 local pos=Positions()[root.kind]
 pos.scale=math.max(0.5,math.min(2,tonumber(pos.scale) or 1))
 root:ClearAllPoints();root:SetScale(pos.scale)
 -- Offsets are in UIParent units, independent of each display's chosen scale.
 root:SetPoint('CENTER',UIParent,'CENTER',pos.x/pos.scale,pos.y/pos.scale)
end
-- Display preferences are local; reminder definitions/transfer packs never contain these.
local common={growth='Up',width=300,height=40,spacing=4,sticky=0,font='Default',outline='OUTLINE',fontSize=22,timerFontSize=22,
 decimals=3,textFormat='%icon%text (%p)',hiddenFormat='%icon%text',textX=0,textY=0,timerX=0,timerY=0,
 textColor={1,1,1,1},borderColor={0,0,0,1},fillColor={1,0.1,0.1,1},backgroundColor={0.05,0.05,0.05,0.85},
 ringColor={1,1,1,1},center=false,hideTimer=false,hideSwipe=false,rightAligned=false,zoom=0,glow=0,
 size=80,thickness=4,textPosition='Top',backgroundRing=false,iconPosition='Left',texture='Solid',
 iconX=0,iconY=0,iconSize=0,leftFormat='%text',rightFormat='%p',hiddenLeft='%text',hiddenRight='',leftX=2,leftY=0,rightX=-2,rightY=0}
local bounds={width={80,600},height={16,160},spacing={-10,60},sticky={0,30},fontSize={8,80},timerFontSize={8,80},
 decimals={0,10},textX={-200,200},textY={-200,200},timerX={-200,200},timerY={-200,200},zoom={0,40},glow={0,30},
 size={20,200},thickness={1,16},iconSize={0,200},iconX={-200,200},iconY={-200,200},leftX={-200,200},leftY={-200,200},rightX={-200,200},rightY={-200,200}}
local enums={growth={'Up','Down','Left','Right'},outline={'NONE','OUTLINE','THICKOUTLINE'},textPosition={'Top','Bottom','Left','Right','Center'},iconPosition={'Left','Right','Hidden'}}
local formats={textFormat=true,hiddenFormat=true,leftFormat=true,rightFormat=true,hiddenLeft=true,hiddenRight=true}
local baselines={}
local function Baseline(kind)
 if baselines[kind] then return baselines[kind] end
 local o=R.Copy(common)
 if kind=='Texts' then o.fontSize=50;o.spacing=1;o.textFormat='%text (%p)';o.hiddenFormat='%text'
 elseif kind=='Icons' then o.width=80;o.height=80;o.fontSize=30;o.timerFontSize=40;o.sticky=5
 elseif kind=='Circles' then o.fontSize=18
 else o.sticky=5 end
 baselines[kind]=o;return o
end
local function ValidSetting(key,value)
 local base=common[key];if base==nil then return false end
 if bounds[key] then return type(value)=='number' and value==value and value>=bounds[key][1] and value<=bounds[key][2] end
 if enums[key] then for _,v in ipairs(enums[key]) do if value==v then return true end end;return false end
 if type(base)=='boolean' then return type(value)=='boolean' end
 if type(base)=='table' then
  if type(value)~='table' then return false end
  for i=1,4 do if type(value[i])~='number' or value[i]~=value[i] or value[i]<0 or value[i]>1 then return false end end
  return true
 end
 return type(value)=='string' and #value<=240
end
function D.GetSettings(kind)
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.reminderDisplaySettings)~='table' then db.reminderDisplaySettings={} end
 local data=db.reminderDisplaySettings[kind]
 if type(data)~='table' then data={};db.reminderDisplaySettings[kind]=data end
 -- Update only the previous automatic text defaults once; retain custom formats,
 -- including an icon explicitly added after this correction.
 if kind=='Texts' and data.defaultsVersion~=2 then
  if data.textFormat=='%icon%text (%p)' then data.textFormat='%text (%p)' end
  if data.hiddenFormat=='%icon%text' then data.hiddenFormat='%text' end
  data.defaultsVersion=2
 end
 for key,value in pairs(Baseline(kind)) do if not ValidSetting(key,data[key]) then data[key]=R.Copy(value) end end
 return data
end
local fonts={Default=STANDARD_TEXT_FONT,['Friz Quadrata']='Fonts\\FRIZQT__.TTF',['Arial Narrow']='Fonts\\ARIALN.TTF',Morpheus='Fonts\\MORPHEUS.TTF',Skurri='Fonts\\SKURRI.TTF'}
local textures={Solid='Interface\\Buttons\\WHITE8X8'}
local function Media(kind)
 local list=kind=='font' and fonts or textures
 if LibStub then
  local media=LibStub('LibSharedMedia-3.0',true)
  if media and media.HashTable then for name,path in pairs(media:HashTable(kind=='font' and 'font' or 'statusbar') or {}) do list[name]=path end end
 end
 return list
end
local function Font(label,o,size)
 label:SetFont(Media('font')[o.font] or STANDARD_TEXT_FONT,size,o.outline=='NONE' and '' or o.outline)
 label:SetTextColor(unpack(o.textColor))
end
-- Original ring textures from scripts/make_ring_textures.py; widths are in
-- 256 px texture units. Pick the closest to the configured screen thickness.
local RING_WIDTHS={3,4,6,8,10,13,16,20,26,32,40,52,64,80,100,127}
local function RingTexture(o)
 local wanted,best=o.thickness*256/o.size,RING_WIDTHS[1]
 for _,width in ipairs(RING_WIDTHS) do if math.abs(width-wanted)<math.abs(best-wanted) then best=width end end
 return string.format('Interface\\AddOns\\%s\\Media\\Ring%03d.png',addonName,best)
end
-- Inline %icon size: 0 follows the font size.
local function InlineIconSize(o) return o.iconSize>0 and o.iconSize or o.fontSize end
local function Layout(root)
 local o=D.GetSettings(root.kind)
 local icon=root.kind=='Icons';local circle=root.kind=='Circles'
 local width=icon and math.max(300,o.width+220) or circle and math.max(300,o.size+180) or o.width
 local lineHeight=o.fontSize
 if (o.textFormat..o.hiddenFormat):find('%icon',1,true) then lineHeight=math.max(lineHeight,InlineIconSize(o)) end
 local height=circle and o.size or root.kind=='Texts' and math.max(o.height,lineHeight+4) or o.height
 root:SetSize(width,30);root.mover:SetWidth(width)
 for i,card in ipairs(root.cards) do
  card:SetSize(circle and o.size or width,height);card:ClearAllPoints()
  local step=(o.growth=='Left' or o.growth=='Right') and (circle and o.size or width)+o.spacing or height+o.spacing
  if o.growth=='Up' then card:SetPoint('BOTTOM',root,'TOP',0,4+(i-1)*step)
  elseif o.growth=='Down' then card:SetPoint('TOP',root,'BOTTOM',0,-4-(i-1)*step)
  elseif o.growth=='Left' then card:SetPoint('RIGHT',root,'LEFT',-4-(i-1)*step,0)
  else card:SetPoint('LEFT',root,'RIGHT',4+(i-1)*step,0) end
  Font(card.text,o,o.fontSize);card.text:ClearAllPoints();card.text:SetWidth(width);card.text:SetJustifyH(o.center and 'CENTER' or o.rightAligned and 'RIGHT' or 'LEFT')
  card.text:SetPoint('CENTER',o.textX,o.textY)
  if card.icon then
   card.icon:ClearAllPoints();card.icon:SetSize(icon and o.width or height, height)
   card.icon:SetPoint(o.iconPosition=='Right' and 'RIGHT' or 'LEFT',o.iconX,o.iconY)
   local zoom=o.zoom/100;card.icon:SetTexCoord(zoom,1-zoom,zoom,1-zoom)
   card.number:ClearAllPoints();card.number:SetPoint('CENTER',card.icon,'CENTER',o.timerX,o.timerY);Font(card.number,o,o.timerFontSize)
   if icon then
    card.text:ClearAllPoints();card.text:SetPoint('LEFT',card.icon,'RIGHT',8+o.textX,o.textY);card.text:SetWidth(width-o.width-8)
    card.glow:SetBackdropBorderColor(unpack(o.ringColor))
   end
  end
  if card.fill then
   card.fill:SetHeight(height);card.fill:SetTexture(Media('texture')[o.texture] or textures.Solid);card.fill:SetVertexColor(unpack(o.fillColor))
   card.background:SetColorTexture(unpack(o.backgroundColor));card:SetBackdropBorderColor(unpack(o.borderColor))
   card.text:ClearAllPoints();card.text:SetPoint('LEFT',(o.iconPosition=='Left' and height+4 or 0)+o.leftX,o.leftY)
   -- One line inside the bar; long text ends in an ellipsis instead of spilling out.
   card.text:SetWidth(math.max(40,width-height-65));card.text:SetJustifyH('LEFT');card.text:SetWordWrap(false)
   card.number:ClearAllPoints();card.number:SetPoint('RIGHT',card,'RIGHT',o.rightX-(o.iconPosition=='Right' and height+4 or 0),o.rightY);card.number:SetJustifyH('RIGHT')
  end
  if circle then
   card.text:ClearAllPoints();card.text:SetPoint(o.textPosition:upper(),card,o.textPosition:upper(),o.textX,o.textY)
   -- Anti-aliased ring texture; the cooldown sweep draws the remaining time.
   local ring=RingTexture(o)
   card.ringBack:SetTexture(ring,'CLAMP','CLAMP','TRILINEAR');card.ringBack:SetVertexColor(unpack(o.backgroundColor))
   card.sweep:SetSwipeTexture(ring);card.sweep:SetSwipeColor(unpack(o.ringColor))
  end
 end
end
function D.SetSetting(kind,key,value)
 if InCombatLockdown() or R.encounter then return false end
 if not ValidSetting(key,value) then return false end
 D.GetSettings(kind)[key]=R.Copy(value)
 if D.roots[kind] then Layout(D.roots[kind]) end
 return true
end
local function OptionLabel(parent,text,x,y,size)
 local label=Label(parent,size or 12);label:SetPoint('TOPLEFT',x,y);label:SetText(text);return label
end
local function Action(parent,text,x,y,width,fn)
 local b=Box('Button',parent);b:SetSize(width,24);b:SetPoint('TOPLEFT',x,y)
 b.label=Label(b,11);b.label:SetPoint('CENTER');b.label:SetText(text)
 b:SetScript('OnClick',function() if D.preview and not InCombatLockdown() then fn() end end);return b
end
local function NumberControl(parent,label,x,y,lo,hi,value,changed)
 OptionLabel(parent,label,x,y-4)
 local entry=CreateFrame('EditBox',nil,parent,'InputBoxTemplate');entry:SetAutoFocus(false);entry:SetSize(46,24);entry:SetPoint('TOPLEFT',x+294,y)
 local slider=CreateFrame('Slider',nil,parent,'BackdropTemplate');slider:SetSize(124,16);slider:SetPoint('TOPLEFT',x+155,y-4)
 slider:SetOrientation('HORIZONTAL');slider:SetMinMaxValues(lo,hi);slider:SetValueStep(1);slider:SetObeyStepOnDrag(true)
 slider:SetThumbTexture('Interface\\Buttons\\WHITE8X8');slider:GetThumbTexture():SetSize(8,18);slider:GetThumbTexture():SetVertexColor(unpack(accent))
 slider:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});slider:SetBackdropColor(0.15,0.16,0.18,1)
 local updating=false
 local function Set(v)
  if updating then return end
  v=tonumber(v);if not v or v~=v then entry:SetText(tostring(slider:GetValue()));return end
  v=math.floor(math.max(lo,math.min(hi,v))+0.5)
  updating=true;entry:SetText(tostring(v));slider:SetValue(v);updating=false
  if D.preview and not InCombatLockdown() then changed(v) end
 end
 slider:SetValue(value);entry:SetText(tostring(value))
 slider:SetScript('OnValueChanged',function(_,v) Set(v) end)
 entry:SetScript('OnEnterPressed',function(self) Set(self:GetText());self:ClearFocus() end)
 entry:SetScript('OnEditFocusLost',function(self) Set(self:GetText()) end)
 entry:SetScript('OnEscapePressed',function(self) self:SetText(tostring(slider:GetValue()));self:ClearFocus() end)
 return {slider=slider,entry=entry,set=Set}
end
-- Skin the shared native picker only during a VRT session, restoring every
-- native region afterward so other addons keep their own picker appearance.
local function RestorePickerTheme()
 local state=D.pickerTheme;if not state then return end
 D.pickerTheme=nil
 for _,entry in ipairs(state.hidden) do entry.region[entry.shown and 'Show' or 'Hide'](entry.region) end
 local hex=state.picker.Content.HexBox
 if state.font then hex:SetFont(unpack(state.font)) end
 if state.color then hex:SetTextColor(unpack(state.color)) end
 state.skin.background:Hide();state.skin.header:Hide();state.skin.okay:Hide();state.skin.cancel:Hide();state.skin.hex:Hide()
end
local function ThemePicker(picker,session,kind)
 if not picker.Border or not picker.Header or not picker.Footer or not picker.Content or not picker.Content.HexBox then return end
 RestorePickerTheme()
 local skin=D.pickerSkin
 if not skin then
  skin={};D.pickerSkin=skin
  skin.background=Box('Frame',picker);skin.background:SetAllPoints();skin.background:SetBackdropColor(0.078,0.086,0.106,0.97)
  skin.header=CreateFrame('Frame',nil,picker);skin.header:SetPoint('TOPLEFT',10,-2);skin.header:SetSize(360,25);skin.header:EnableMouse(true);skin.header:RegisterForDrag('LeftButton')
  skin.header:SetScript('OnDragStart',function() if D.colorSession and not InCombatLockdown() then picker:StartMoving() end end)
  skin.header:SetScript('OnDragStop',function() picker:StopMovingOrSizing() end)
  skin.title=OptionLabel(skin.header,'',4,-6,13);skin.title:SetTextColor(unpack(accent))
  local function NativeClick(button)
   local fn=button:GetScript('OnClick');if fn then fn(button) end
  end
  skin.okay=Action(picker,'Okay',0,0,170,function() NativeClick(picker.Footer.OkayButton) end)
  skin.cancel=Action(picker,'Cancel',0,0,170,function() NativeClick(picker.Footer.CancelButton) end)
  skin.okay:ClearAllPoints();skin.okay:SetPoint('BOTTOMLEFT',16,12)
  skin.cancel:ClearAllPoints();skin.cancel:SetPoint('BOTTOMRIGHT',-16,12)
  skin.hex=Box('Frame',picker.Content);skin.hex:SetPoint('TOPLEFT',picker.Content.HexBox,'TOPLEFT',-3,1);skin.hex:SetPoint('BOTTOMRIGHT',picker.Content.HexBox,'BOTTOMRIGHT',3,-1)
  picker:HookScript('OnHide',function() picker:StopMovingOrSizing();RestorePickerTheme() end)
  hooksecurefunc(picker,'SetupColorPickerAndShow',function()
   if D.pickerTheme and picker:GetExtraInfo()~=D.pickerTheme.session then RestorePickerTheme() end
  end)
 end
 local hex=picker.Content.HexBox
 local state={picker=picker,skin=skin,session=session,hidden={},font={hex:GetFont()},color={hex:GetTextColor()}}
 local function Hide(region)
  if region then state.hidden[#state.hidden+1]={region=region,shown=region:IsShown()};region:Hide() end
 end
 Hide(picker.Border);Hide(picker.Header);Hide(picker.DragBar);Hide(picker.Footer)
 for _,region in ipairs({hex:GetRegions()}) do if region:GetObjectType()=='Texture' then Hide(region) end end
 D.pickerTheme=state
 skin.background:SetFrameLevel(picker:GetFrameLevel());skin.hex:SetFrameLevel(math.max(0,hex:GetFrameLevel()-1))
 hex:SetFont(STANDARD_TEXT_FONT,12,'');hex:SetTextColor(0.91,0.92,0.94,1)
 skin.title:SetText(kind..' colour')
 skin.background:Show();skin.header:Show();skin.okay:Show();skin.cancel:Show();skin.hex:Show()
end
local function CloseColors()
 local session=D.colorSession;D.colorSession=nil
 -- The picker is shared with Blizzard/other addons. Close only our own session.
 if session and ColorPickerFrame and ColorPickerFrame.GetExtraInfo and ColorPickerFrame:GetExtraInfo()==session then ColorPickerFrame:Hide() end
end
local function HideSettings()
 if D.settings then D.settings:Hide() end
 if D.optionMenu then D.optionMenu:Hide() end
 CloseColors()
end
local function OpenColors(kind,key,button)
 if not D.preview or InCombatLockdown() or R.encounter then return end
 CloseColors()
 if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn('Blizzard_ColorPickerFrame') end
 local picker=ColorPickerFrame
 if not picker or not picker.SetupColorPickerAndShow or not picker.GetExtraInfo then
  D.settings.title:SetText(kind..' settings — colour picker unavailable');return
 end
 local original=R.Copy(D.GetSettings(kind)[key])
 local session={};D.colorSession=session
 local ready=false
 local function Apply(color)
  if not ready or D.colorSession~=session or picker:GetExtraInfo()~=session or not D.preview then return end
  if D.SetSetting(kind,key,color) then button:SetBackdropColor(unpack(color)) end
 end
 local function Changed()
  if not ready or D.colorSession~=session or picker:GetExtraInfo()~=session then return end
  local r,g,b=picker:GetColorRGB()
  Apply({r,g,b,picker:GetColorAlpha()})
 end
 picker:SetupColorPickerAndShow({r=original[1],g=original[2],b=original[3],opacity=original[4],hasOpacity=true,
  swatchFunc=Changed,opacityFunc=Changed,cancelFunc=function() Apply(original) end,extraInfo=session})
 ready=true;ThemePicker(picker,session,kind)
end
function D.OpenSettings(kind)
 if not D.preview or InCombatLockdown() or R.encounter then return false end
 HideSettings()
 local panel=D.settings
 if not panel then
  panel=Box('Frame',UIParent);D.settings=panel;panel:SetSize(390,510);panel:SetFrameStrata('DIALOG');panel:SetClampedToScreen(true);panel:EnableMouse(true);panel:SetMovable(true)
  -- Only the title strip drags: slider drags must not bubble into moving settings.
  local header=CreateFrame('Frame',nil,panel);panel.header=header;header:SetPoint('TOPLEFT',10,-2);header:SetSize(330,30)
  header:EnableMouse(true);header:RegisterForDrag('LeftButton')
  header:SetScript('OnDragStart',function() if D.preview and not InCombatLockdown() then panel:StartMoving() end end)
  header:SetScript('OnDragStop',function() panel:StopMovingOrSizing() end)
  panel.title=OptionLabel(panel,'',14,-12)
  Action(panel,'X',350,-6,26,HideSettings)
  local scroll=CreateFrame('ScrollFrame',nil,panel,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',12,-40);scroll:SetSize(352,408)
  if addon.StyleScrollBar then addon.StyleScrollBar(scroll) end
  panel.content=CreateFrame('Frame',nil,scroll);panel.content:SetSize(350,500);scroll:SetScrollChild(panel.content)
  panel.controls={};panel.widgets={};panel.cache={}
  panel:SetScript('OnHide',function() panel:StopMovingOrSizing();if D.optionMenu then D.optionMenu:Hide() end;CloseColors() end)
  Action(panel,'Reset appearance',14,-470,170,function()
   VincibilityRaidToolsDB.reminderDisplaySettings[panel.kind]=nil;panel.cache[panel.kind]=nil;Layout(D.roots[panel.kind]);D.OpenSettings(panel.kind)
  end)
  Action(panel,'Reset position',200,-470,175,function()
   local p=Positions()[panel.kind];p.x=defaults[panel.kind][1];p.y=defaults[panel.kind][2];p.scale=1;Place(D.roots[panel.kind])
  end)
 end
 for _,widget in ipairs(panel.widgets) do widget:Hide() end
 panel.widgets={};panel.controls={};panel.kind=kind;panel.title:SetText(kind..' settings')
 -- Snapshot the anchor's screen position when opening. Keeping the panel attached
 -- to the mover makes its left edge jump whenever a width slider resizes it.
 local mover=D.roots[kind].mover
 local left,bottom=mover:GetLeft(),mover:GetBottom()
 panel:ClearAllPoints()
 if left and bottom then
  local scale=mover:GetEffectiveScale()/UIParent:GetEffectiveScale()
  panel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',left*scale,bottom*scale-4)
 else panel:SetPoint('CENTER',UIParent,'CENTER') end
 local o=D.GetSettings(kind)
 local cached=panel.cache[kind]
 if cached then
  panel.widgets=cached.widgets;panel.controls=cached.controls
  for _,row in ipairs(panel.widgets) do row:Show() end
  for key,control in pairs(panel.controls) do
   if control.slider then control.set(o[key])
   elseif type(o[key])=='boolean' then control:SetChecked(o[key])
   elseif type(o[key])=='table' then control:SetBackdropColor(unpack(o[key]))
   elseif control.label then control.label:SetText(tostring(o[key])..'  v')
   else control:SetText(o[key]) end
  end
  panel.content:SetHeight(cached.height);panel:Show();return true
 end
 local y=0
 local function Row(key,label,mode,choices)
  local row=CreateFrame('Frame',nil,panel.content);row:SetSize(348,30);row:SetPoint('TOPLEFT',0,y);y=y-32;panel.widgets[#panel.widgets+1]=row
  if mode=='number' then
   panel.controls[key]=NumberControl(row,label,0,0,bounds[key][1],bounds[key][2],o[key],function(v) D.SetSetting(kind,key,v) end)
  elseif mode=='bool' then
   local check=CreateFrame('CheckButton',nil,row,'UICheckButtonTemplate');check:SetSize(24,24);check:SetPoint('LEFT');check:SetChecked(o[key]);OptionLabel(row,label,30,-5)
   check:SetScript('OnClick',function(self) if not D.SetSetting(kind,key,self:GetChecked() and true or false) then self:SetChecked(D.GetSettings(kind)[key]) end end);panel.controls[key]=check
  elseif mode=='text' then
   OptionLabel(row,label,0,-5);local entry=CreateFrame('EditBox',nil,row,'InputBoxTemplate');entry:SetSize(186,24);entry:SetPoint('TOPLEFT',154,0);entry:SetAutoFocus(false);entry:SetMaxLetters(240);entry:SetText(o[key])
   local function Save(self) if not D.SetSetting(kind,key,self:GetText()) then self:SetText(D.GetSettings(kind)[key]) end end
   entry:SetScript('OnEnterPressed',function(self) Save(self);self:ClearFocus() end);entry:SetScript('OnEditFocusLost',Save);panel.controls[key]=entry
  elseif mode=='color' then
   OptionLabel(row,label,0,-5);local b=Action(row,'',294,0,46,function() OpenColors(kind,key,panel.controls[key]) end);b:SetBackdropColor(unpack(o[key]));panel.controls[key]=b
  else
   OptionLabel(row,label,0,-5)
   local button
   button=Action(row,tostring(o[key])..'  v',148,0,192,function()
    if not D.optionMenu then
     D.optionMenu=Box('Frame',UIParent);D.optionMenu:SetSize(270,300);D.optionMenu:SetFrameStrata('FULLSCREEN_DIALOG');D.optionMenu:SetClampedToScreen(true);D.optionMenu:EnableMouseWheel(true);D.optionMenu:EnableMouse(true);D.optionMenu.rows={}
     for i=1,8 do
      D.optionMenu.rows[i]=Action(D.optionMenu,'',8,-8-(i-1)*30,252,function()
       local menu=D.optionMenu;local value=menu.options[(menu.offset or 0)+i]
       if value then D.SetSetting(menu.kind,menu.key,value);menu.button.label:SetText(value..'  v');menu:Hide() end
      end)
     end
     Action(D.optionMenu,'Close',8,-268,252,function() D.optionMenu:Hide() end)
     D.optionMenu.Draw=function(menu)
      for i,row in ipairs(menu.rows) do local value=menu.options[menu.offset+i];if value then row.label:SetText(value);row:Show() else row:Hide() end end
     end
     D.optionMenu:SetScript('OnMouseWheel',function(menu,delta) menu.offset=math.max(0,math.min(math.max(0,#menu.options-8),menu.offset-delta));menu:Draw() end)
    end
    local menu=D.optionMenu;menu.options=choices or enums[key] or {};menu.kind=kind;menu.key=key;menu.button=button;menu.offset=0
    menu:ClearAllPoints();menu:SetPoint('CENTER',panel,'CENTER');menu:Draw();menu:Show()
   end);panel.controls[key]=button
  end
 end
 local function Num(key,label) Row(key,label,'number') end
 local function Select(key,label) Row(key,label,'select') end
 local function Color(key,label) Row(key,label,'color') end
 local function Check(key,label) Row(key,label,'bool') end
 local function Text(key,label) Row(key,label,'text') end
 Select('growth','Grow direction')
 if kind=='Circles' then Num('size','Size');Num('thickness','Ring thickness') else Num('width','Width');Num('height','Height') end
 Num('spacing','Spacing');Num('sticky','Sticky duration')
 local names={};for name in pairs(Media('font')) do names[#names+1]=name end;table.sort(names);Row('font','Font','select',names)
 Select('outline','Font outline');Num('fontSize','Font size');if kind=='Icons' or kind=='Bars' or kind=='Debuff Overview' then Num('timerFontSize','Timer font size') end;Num('decimals','Decimals threshold')
 if kind=='Icons' then
  Num('glow','Glow threshold');Num('zoom','Zoom');Num('textX','Text X offset');Num('textY','Text Y offset');Num('timerX','Timer X offset');Num('timerY','Timer Y offset')
  Color('textColor','Text colour');Color('ringColor','Glow colour');Color('borderColor','Border colour');Check('rightAligned','Right-aligned text');Check('hideTimer','Hide timer text');Check('hideSwipe','Hide swipe')
 elseif kind=='Bars' or kind=='Debuff Overview' then
  local names={};for name in pairs(Media('texture')) do names[#names+1]=name end;table.sort(names);Row('texture','Texture','select',names)
  Select('iconPosition','Icon position');Text('leftFormat','Left text format');Text('rightFormat','Right text format');Text('hiddenLeft','Hidden left text');Text('hiddenRight','Hidden right text')
  Color('fillColor','Bar fill colour');Color('backgroundColor','Background colour');Color('textColor','Text colour');Color('borderColor','Border colour')
  Num('iconX','Icon X offset');Num('iconY','Icon Y offset');Num('leftX','Left text X offset');Num('leftY','Left text Y offset');Num('rightX','Right text X offset');Num('rightY','Right text Y offset')
 else
  Text('textFormat','Text format');Text('hiddenFormat','Hidden timer format');Num('iconSize','Icon size (0 = font)');Num('textX','Text X offset');Num('textY','Text Y offset');Color('textColor','Text colour')
  if kind=='Circles' then Select('textPosition','Text position');Color('ringColor','Ring colour');Color('backgroundColor','Background ring colour');Check('backgroundRing','Show background ring')
  else Check('center','Center aligned') end
 end
 local help=CreateFrame('Frame',nil,panel.content);help:SetSize(348,30);help:SetPoint('TOPLEFT',0,y);panel.widgets[#panel.widgets+1]=help
 OptionLabel(help,'Formats: %text message · %p timer · %icon icon',0,-4,10);y=y-32
 panel.cache[kind]={widgets=panel.widgets,controls=panel.controls,height=-y}
 panel.content:SetHeight(-y);panel:Show();return true
end
local function Build()
 if D.built then return end
 D.built=true
 for _,kind in ipairs(kinds) do
  local root=CreateFrame('Frame',nil,UIParent);D.roots[kind]=root;root.kind=kind
  root:SetSize(300,30);root:SetFrameStrata('HIGH');root:SetClampedToScreen(true)
  root:SetMovable(true);root:EnableMouse(false);root:Hide();Place(root)
  local mover=Box('Frame',root);root.mover=mover
  mover:SetSize(300,30);mover:SetPoint('CENTER');mover:EnableMouse(true);mover:RegisterForDrag('LeftButton');mover:Hide()
  mover.title=Label(mover,12);mover.title:SetPoint('CENTER');mover.title:SetText(kind)
  mover:SetScript('OnDragStart',function() if D.preview and not InCombatLockdown() then root:StartMoving() end end)
  mover:SetScript('OnDragStop',function()
   root:StopMovingOrSizing()
   if not D.preview or InCombatLockdown() then Place(root);return end
   local x,y=root:GetCenter();local cx,cy=UIParent:GetCenter()
   if x and y and cx and cy then
    local pos=Positions()[kind];pos.x=x*root:GetEffectiveScale()/UIParent:GetEffectiveScale()-cx
    pos.y=y*root:GetEffectiveScale()/UIParent:GetEffectiveScale()-cy;Place(root)
   end
  end)
  local gear=Box('Button',mover);gear:SetPoint('RIGHT',-2,0);gear:SetSize(26,26)
  gear.icon=gear:CreateTexture(nil,'ARTWORK');gear.icon:SetSize(18,18);gear.icon:SetPoint('CENTER');gear.icon:SetTexture('Interface\\Buttons\\UI-OptionsButton')
  gear:SetScript('OnClick',function() D.OpenSettings(kind) end);root.gear=gear
  root.cards={}
  for i=1,5 do
   local card=Box('Frame',root);card:SetBackdropColor(0,0,0,0);card:SetBackdropBorderColor(0,0,0,0);root.cards[i]=card;card:Hide()
   card:SetSize(300,kind=='Icons' and 48 or kind=='Circles' and 100 or 36)
   card:SetPoint('TOP',root,'BOTTOM',0,-4-(i-1)*(kind=='Icons' and 52 or kind=='Circles' and 104 or 40))
   card.text=Label(card,kind=='Texts' and 26 or 18)
   card.text:SetPoint('LEFT',kind=='Icons' and 54 or 4,0);card.text:SetWidth(kind=='Icons' and 245 or 290);card.text:SetJustifyH('LEFT')
   if kind=='Icons' or kind=='Bars' or kind=='Debuff Overview' then
    card.icon=card:CreateTexture(nil,'ARTWORK');card.icon:SetSize(48,48);card.icon:SetPoint('LEFT')
    card.numberFrame=CreateFrame('Frame',nil,card);card.numberFrame:SetAllPoints();card.numberFrame:SetFrameLevel(card:GetFrameLevel()+4)
    card.number=Label(card.numberFrame,22);card.number:SetPoint('CENTER',card.icon,'CENTER')
   end
   if kind=='Icons' then
    card.cooldown=CreateFrame('Cooldown',nil,card,'CooldownFrameTemplate');card.cooldown:SetAllPoints(card.icon);card.cooldown:SetHideCountdownNumbers(true);card.cooldown:SetDrawEdge(false)
    card.glow=Box('Frame',card);card.glow:SetPoint('TOPLEFT',card.icon,'TOPLEFT',-3,3);card.glow:SetPoint('BOTTOMRIGHT',card.icon,'BOTTOMRIGHT',3,-3);card.glow:SetBackdropColor(0,0,0,0);card.glow:Hide()
   elseif kind=='Bars' or kind=='Debuff Overview' then
    card.background=card:CreateTexture(nil,'BACKGROUND');card.background:SetAllPoints();card.background:SetColorTexture(0.08,0.09,0.11,0.95)
    card.fill=card:CreateTexture(nil,'BORDER');card.fill:SetPoint('TOPLEFT');card.fill:SetHeight(36);card.fill:SetColorTexture(unpack(accent))
   elseif kind=='Circles' then
    card.text:ClearAllPoints();card.text:SetPoint('LEFT',105,0);card.text:SetWidth(195)
    card.ringBack=card:CreateTexture(nil,'BACKGROUND');card.ringBack:SetAllPoints()
    card.sweep=CreateFrame('Cooldown',nil,card,'CooldownFrameTemplate');card.sweep:SetAllPoints()
    card.sweep:SetDrawEdge(false);card.sweep:SetDrawBling(false);card.sweep:SetHideCountdownNumbers(true);card.sweep:SetReverse(false)
   end
  end
  Layout(root)
 end
 local bar=Box('Frame',UIParent);D.previewBar=bar;bar:SetSize(620,34);bar:SetPoint('TOP',0,-60);bar:SetFrameStrata('DIALOG');bar:Hide()
 bar.text=Label(bar,12);bar.text:SetPoint('LEFT',10,0);bar.text:SetText('Preview: drag anchors. Use the gear to customise each display.')
 local exit=Box('Button',bar);exit:SetSize(96,28);exit:SetPoint('RIGHT',-3,0)
 exit.label=Label(exit,12);exit.label:SetPoint('CENTER');exit.label:SetText('Exit preview')
 exit:SetScript('OnClick',function() D.StopPreview(true) end)
 D.exit=exit
end
function D.Clear()
 D.items={}
 if D.built then
  for _,root in pairs(D.roots) do for _,card in ipairs(root.cards) do card:Hide() end;if not D.preview then root:Hide() end end
 end
end
-- Remove a shown item (for example a cancelled break bar).
function D.Remove(uid)
 for i=#D.items,1,-1 do if D.items[i].data.uid==uid then table.remove(D.items,i) end end
end
function D.Prune()
 for i=#D.items,1,-1 do
  if not D.items[i].test and not R.CanOutput(D.items[i].data) then table.remove(D.items,i) end
 end
end
local function Format(message,p,spoken)
 return R.FormatMessage(message,p,spoken)
end
function D.Show(data,params,test)
 Build()
 if D.preview and not test then return end
 for i=#D.items,1,-1 do if D.items[i].data.uid==data.uid then table.remove(D.items,i) end end
 D.items[#D.items+1]={data=R.Copy(data),message=Format(data.message,params),started=GetTime(),expires=GetTime()+data.duration,test=test}
 if #D.items>20 then table.remove(D.items,1) end
 if not test then
  if data.sound then
   local audio=R.ResolveSoundFile(data.soundFile) or data.soundFileID
   if audio and R.SoundSource(audio) and PlaySoundFile then
    local ok,played=pcall(PlaySoundFile,audio,'Master')
    if not ok or not played then R.lastError='Reminder sound file unavailable. Check its path and owning addon.' end
   elseif not audio and PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,'Master') end
  end
  -- Voice is a local preference, never supplied by a sender.
  local db=VincibilityRaidToolsDB or {}
  if data.tts and db.reminderTTS and C_VoiceChat and C_VoiceChat.SpeakText then
   local voice=db.reminderVoice
   if not voice and C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then
    voice=C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard)
   end
   if type(voice)=='number' and R.Public(voice) then pcall(C_VoiceChat.SpeakText,voice,Format(data.message,params,true),0,100,false) end
  end
 end
end
local function Samples()
 D.Clear()
 local messages={Texts={'Personals','Stack on marker'},Icons={'Fortifying Brew','Give Ironbark'},Bars={'Breath','Dodge'},Circles={'Spread','Dispel'},['Debuff Overview']={'Player two','Player one'}}
 for i,kind in ipairs(kinds) do
  for n=1,2 do
   D.Show({uid='VRT-preview-'..i..'-'..n,message=messages[kind][n],duration=8,display=kind,icon=136085,countdown=true},{},true)
  end
 end
end
function D.StartPreview()
 if InCombatLockdown() or R.encounter then return false,'Preview is available outside combat and encounters.' end
 Build();D.preview=true;D.nextSample=GetTime()+8;Samples()
 if VincibilityMainUI then VincibilityMainUI:Hide() end
 D.previewBar:Show()
 for _,root in pairs(D.roots) do root:Show();root.mover:Show() end
 return true
end
function D.StopPreview(reopen)
 if not D.preview then return end
 D.preview=false;D.previewBar:Hide();HideSettings()
 for _,root in pairs(D.roots) do root:StopMovingOrSizing();root.mover:Hide();root:Hide() end
 D.Clear()
 if reopen and not InCombatLockdown() then addon.OpenMainUI('Reminders') end
end
local driver=CreateFrame('Frame')
driver:RegisterEvent('PLAYER_REGEN_DISABLED');driver:RegisterEvent('ENCOUNTER_START')
driver:RegisterEvent('GROUP_ROSTER_UPDATE');driver:RegisterEvent('PARTY_LEADER_CHANGED')
driver:SetScript('OnEvent',function(_,event)
 if event=='PLAYER_REGEN_DISABLED' or event=='ENCOUNTER_START' then D.StopPreview(false) else D.Prune() end
end)
local function Update()
 if not D.built then return end
 local now=GetTime()
 if D.preview and now>=D.nextSample then Samples();D.nextSample=now+8 end
 D.Prune()
 -- An item can override the display's sticky time (assignment countdowns end at zero).
 for i=#D.items,1,-1 do
  local item=D.items[i];local sticky=type(item.data.sticky)=='number' and item.data.sticky or D.GetSettings(item.data.display).sticky
  if now>=item.expires+sticky then table.remove(D.items,i) end
 end
 for kind,root in pairs(D.roots) do
  local index=0
  for i=#D.items,1,-1 do
   local item=D.items[i]
   if item.data.display==kind and index<5 then
    index=index+1;local card=root.cards[index];local left=math.max(0,item.expires-now);local o=D.GetSettings(kind)
    local timer=left<o.decimals and string.format('%.1f',left) or tostring(math.ceil(left))
    local visible=item.data.countdown and not o.hideTimer and left>0
    local size=InlineIconSize(o)
    local icon='|T'..(item.data.icon or 134400)..':'..size..':'..size..'|t'
    local function Render(pattern) return pattern:gsub('%%(%a+)',function(key) return key=='text' and item.message or key=='p' and (visible and timer or '') or key=='icon' and icon or '%'..key end) end
    card:Show();card.text:SetText(Render(visible and o.textFormat or o.hiddenFormat))
    if card.icon then
     card.icon:SetTexture(item.data.icon or 134400);card.icon[o.iconPosition=='Hidden' and 'Hide' or 'Show'](card.icon)
     card.number:SetText(visible and timer or '')
    end
    if card.cooldown then
     card.text:SetText(item.message);card:SetBackdropBorderColor(unpack(o.borderColor))
     if not o.hideSwipe and left>0 then
      if card.item~=item then card.cooldown:SetCooldown(item.started,item.data.duration);card.item=item end
      card.cooldown:Show()
     else card.cooldown:Hide() end
     if o.glow>0 and left>0 and left<=o.glow then card.glow:Show();card.glow:SetAlpha(0.6+0.4*math.sin(now*8)) else card.glow:Hide() end
    end
    if card.fill then
     card.text:SetText(Render(visible and o.leftFormat or o.hiddenLeft));card.number:SetText(Render(visible and o.rightFormat or o.hiddenRight))
     card.fill:SetWidth(math.max(0.1,o.width*left/item.data.duration))
    end
    if card.sweep then
     card.ringBack[o.backgroundRing and 'Show' or 'Hide'](card.ringBack)
     if left>0 then
      if card.item~=item then card.sweep:SetCooldown(item.started,item.data.duration);card.item=item end
      card.sweep:Show()
     else card.sweep:Hide();card.item=nil end
    end
   end
  end
  for i=index+1,5 do root.cards[i]:Hide() end
  if index>0 or D.preview then root:Show() else root:Hide() end
 end
end
D.Update=Update
driver:SetScript('OnUpdate',Update)
