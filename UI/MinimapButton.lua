local _,addon=...
local button

local function Settings()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.minimapButton)~='table' then db.minimapButton={} end
 local settings=db.minimapButton
 if type(settings.angle)~='number' or settings.angle~=settings.angle or settings.angle<0 or settings.angle>=360 then settings.angle=225 end
 return settings
end

local function Position()
 if not button or not Minimap then return end
 local angle=math.rad(Settings().angle)
 local radiusX=Minimap:GetWidth()/2+9
 local radiusY=Minimap:GetHeight()/2+9
 button:ClearAllPoints()
 button:SetPoint('CENTER',Minimap,'CENTER',math.cos(angle)*radiusX,math.sin(angle)*radiusY)
end

local function CursorAngle()
 local x,y=GetCursorPosition()
 local scale=Minimap:GetEffectiveScale()
 local centerX,centerY=Minimap:GetCenter()
 if not x or not centerX or not scale or scale==0 then return end
 x=x/scale-centerX;y=y/scale-centerY
 local angle
 if x==0 then angle=y>=0 and 90 or 270
 else
  angle=math.deg(math.atan(y/x))
  if x<0 then angle=angle+180 elseif y<0 then angle=angle+360 end
 end
 return angle%360
end

function addon.SetMinimapButtonShown(shown)
 local settings=Settings();settings.hide=not shown
 if button then if shown then button:Show() else button:Hide() end end
end
function addon.GetMinimapButtonShown() return not Settings().hide end

local function Build()
 if button or not Minimap then return end
 button=CreateFrame('Button','VincibilityMinimapButton',Minimap)
 button:SetSize(32,32);button:SetFrameStrata('MEDIUM')
 button:SetFrameLevel(Minimap:GetFrameLevel()+5)
 button:RegisterForClicks('LeftButtonUp','RightButtonUp')
 button:RegisterForDrag('LeftButton')
 local background=button:CreateTexture(nil,'BACKGROUND')
 background:SetSize(29,29);background:SetPoint('CENTER')
 background:SetTexture('Interface\\Minimap\\UI-Minimap-Background')
 local crest=addon.CreateSmallGuildCrest(button,22)
 crest:SetPoint('CENTER')
 -- The coloured square is a Texture collectors can move without altering the
 -- atlas coordinates of the separate small tabard emblem.
 button.crest=crest
 button.icon=crest.background
 local border=button:CreateTexture(nil,'OVERLAY')
 border:SetSize(53,53);border:SetPoint('CENTER')
 border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
 local highlight=button:CreateTexture(nil,'HIGHLIGHT')
 highlight:SetSize(28,28);highlight:SetPoint('CENTER')
 highlight:SetTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
 highlight:SetBlendMode('ADD')
 button:SetScript('OnClick',function(_,mouseButton)
  if mouseButton=='RightButton' then SlashCmdList.VINCIBILITYRAIDTOOLS('')
  else addon.OpenMainUI() end
 end)
 button:SetScript('OnEnter',function(self)
  GameTooltip:SetOwner(self,'ANCHOR_LEFT')
  GameTooltip:AddLine('Vincibility Raid Tools',.72,.76,.81)
  GameTooltip:AddLine('Left click: Main window',1,1,1)
  GameTooltip:AddLine('Right click: Raid panel',1,1,1)
  GameTooltip:AddLine('Drag: Move around minimap',.7,.7,.7)
  GameTooltip:Show()
 end)
 button:SetScript('OnLeave',function() GameTooltip:Hide() end)
 button:SetScript('OnDragStart',function(self)
  self:SetScript('OnUpdate',function()
   local angle=CursorAngle()
   if angle then Settings().angle=angle;Position() end
  end)
 end)
 button:SetScript('OnDragStop',function(self)
  self:SetScript('OnUpdate',nil)
  local angle=CursorAngle()
  if angle then Settings().angle=angle;Position() end
 end)
 Position()
 if Settings().hide then button:Hide() end
 addon.MinimapButton=button
end

local events=CreateFrame('Frame')
events:RegisterEvent('PLAYER_LOGIN')
events:RegisterEvent('PLAYER_ENTERING_WORLD')
events:SetScript('OnEvent',Build)
