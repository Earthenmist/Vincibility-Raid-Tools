local _,addon=...
local smallCrests={}

local function Layer(parent,size,layer,sublevel,width,height)
 local texture=parent:CreateTexture(nil,layer,nil,sublevel)
 texture:SetSize(width or size,height or size)
 texture:SetPoint('CENTER')
 return texture
end

function addon.CreateGuildCrest(parent,size)
 local crest=CreateFrame('Frame',nil,parent)
 crest:SetSize(size,size)
 crest.image=Layer(crest,size,'ARTWORK',0)
 crest.image:SetTexture('Interface\\AddOns\\VincRaidTools\\Media\\VincibilityCrest')
 return crest
end

local function UpdateSmall(crest)
 local guild=GetGuildInfo and GetGuildInfo('player')
 local info=C_GuildInfo and C_GuildInfo.GetGuildTabardInfo and C_GuildInfo.GetGuildTabardInfo('player')
 if guild=='Vincibility' and info and info.emblemFileID and info.backgroundColor and SetSmallGuildTabardTextures then
  local ok=pcall(function()
   local r,g,b=info.backgroundColor:GetRGB()
   crest.background:SetColorTexture(r,g,b)
   SetSmallGuildTabardTextures('player',crest.emblem,nil,nil,info)
  end)
  if ok then crest.emblem:Show();crest.fallback:Hide();return true end
 end
 crest.background:SetColorTexture(.12,.16,.19)
 crest.emblem:Hide();crest.fallback:Show()
 return false
end

function addon.CreateSmallGuildCrest(parent,size)
 local crest=CreateFrame('Frame',nil,parent)
 crest:SetSize(size,size)
 -- Keep a real Texture on the button for minimap collectors to resize.
 crest.background=parent:CreateTexture(nil,'BACKGROUND',nil,1)
 crest.background:SetSize(size,size)
 crest.background:SetPoint('CENTER')
 crest.emblem=Layer(crest,size,'ARTWORK',0,16,16)
 crest.fallback=crest:CreateFontString(nil,'OVERLAY')
 crest.fallback:SetPoint('CENTER')
 crest.fallback:SetFont(STANDARD_TEXT_FONT,13,'OUTLINE')
 crest.fallback:SetTextColor(.72,.76,.81)
 crest.fallback:SetText('V')
 crest:SetScript('OnShow',function(self) UpdateSmall(self) end)
 smallCrests[#smallCrests+1]=crest
 UpdateSmall(crest)
 return crest
end

function addon.UpdateGuildCrests()
 for _,crest in ipairs(smallCrests) do UpdateSmall(crest) end
end

local events=CreateFrame('Frame')
events:RegisterEvent('PLAYER_LOGIN')
events:RegisterEvent('PLAYER_ENTERING_WORLD')
events:RegisterEvent('PLAYER_GUILD_UPDATE')
events:SetScript('OnEvent',function(_,event)
 addon.UpdateGuildCrests()
 if event=='PLAYER_ENTERING_WORLD' and C_Timer then C_Timer.After(2,addon.UpdateGuildCrests) end
end)
