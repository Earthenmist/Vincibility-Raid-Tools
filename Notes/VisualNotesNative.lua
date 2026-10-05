local _,addon=...
local function Now() return addon.Now and addon.Now() or (time and time() or 0) end
local V={width=700,height=430}
addon.NativeVisualNotes=V
local mrtCanvasHeight=535

local palette={
 {0.95,0.96,0.98},{0.24,0.85,0.75},{1,0.30,0.36},{1,0.76,0.30},
 {0.35,0.65,1},{0.72,0.48,1},{0.32,0.86,0.42},{0.15,0.16,0.19},
 {1,.88,.25},{1,.48,.70},{.36,.84,1},{.97,.43,.17},
 {.56,.58,.64},{.55,.30,.88},{.62,.38,.19},{0,0,0},
}
local colorNames={'white','teal','red','orange','blue','violet','green','charcoal',
 'yellow','pink','cyan','amber','grey','purple','brown','black'}
local roleArt='Interface\\LFGFrame\\UI-LFG-ICON-ROLES'
local classArt='Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES'
local filledCircleArt='Interface\\AddOns\\VincRaidTools\\Media\\circle256'
local markerOptions={}
for _,name in ipairs({'Star','Circle','Diamond','Triangle','Moon','Square','Cross','Skull'}) do
 markerOptions[#markerOptions+1]={name=name,art='Interface\\TargetingFrame\\UI-RaidTargetingIcon_'..(#markerOptions+1)}
end
local function Atlas(name,art,left,right,top,bottom)
 markerOptions[#markerOptions+1]={name=name,art=art,coords={left,right,top,bottom}}
end
Atlas('Tank',roleArt,0,.26171875,.26171875,.5234375)
Atlas('Healer',roleArt,.26171875,.5234375,0,.26171875)
Atlas('Damage',roleArt,.26171875,.5234375,.26171875,.5234375)
markerOptions[#markerOptions+1]={name='Faction',art=UnitFactionGroup and UnitFactionGroup('player')=='Alliance' and
 'Interface\\FriendsFrame\\PlusManz-Alliance' or 'Interface\\FriendsFrame\\PlusManz-Horde'}
Atlas('Warrior',classArt,0,.25,0,.25)
Atlas('Mage',classArt,0,.25,.5,.75)
Atlas('Rogue',classArt,0,.25,.25,.5)
Atlas('Druid',classArt,.49609375,.7421875,0,.25)
Atlas('Hunter',classArt,.49609375,.7421875,.25,.5)
Atlas('Shaman',classArt,.25,.5,.5,.75)
Atlas('Priest',classArt,.25,.49609375,.25,.5)
Atlas('Warlock',classArt,.25,.49609375,0,.25)
Atlas('Paladin',classArt,.7421875,.98828125,.25,.5)
Atlas('Death knight',classArt,.5,.73828125,.5,.75)
Atlas('Monk',classArt,.7421875,.98828125,0,.25)
Atlas('Demon hunter',classArt,.7421875,.98828125,.5,.75)
markerOptions[#markerOptions+1]={name='Evoker',art='Interface\\Icons\\ClassIcon_Evoker'}
-- Saved drawings store the symbol's position in this list: add new symbols at the end.
markerOptions[#markerOptions+1]={name='Boss',atlas='worldquest-icon-boss',art='Interface\\TargetingFrame\\UI-TargetingFrame-Skull'}
local function SetMarkerArt(texture,id)
 local option=markerOptions[id]
 -- Atlas symbols (the boss icon) fall back to a plain texture if the client lacks the atlas.
 local atlas=option.atlas and texture.SetAtlas and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(option.atlas))
 if atlas then texture:SetAtlas(option.atlas);texture:SetVertexColor(1,1,1,1);return end
 texture:SetTexture(option.art)
 texture:SetVertexColor(1,1,1,1)
 if option.coords then texture:SetTexCoord(unpack(option.coords)) else texture:SetTexCoord(0,1,0,1) end
end
V.markerOptions=markerOptions
-- UI map IDs are client map-art IDs, not encounter or instance IDs.
local bossMaps={
 {"Kith'ix: boss arena",2669,.48,.27,2,3513},
 {'Tidebound Grotto: boss arena',2632,.51,.54,2,3379},
 {'Venomous Abyss: Nek\'zali',2606,.5,.5,4,3470},
 {'Venomous Abyss: Twin Fangs',2607,.5,.58,2,3421},
 {'Venomous Abyss: Entombed Sentinels',2608,.53,.3,3,3445},
 {'Venomous Abyss: Vashnik',2608,.43,.70,2.5,3455},
 {'Venomous Abyss: Lost Explorers',2609,.48,.32,3,3497},
 {'Venomous Abyss: Sszorak',2609,.55,.72,3,3420},
 {'Venomous Abyss: Coiled Altar',2610,.5,.77,3,3429},
 {'Venomous Abyss: Ula\'tek',2610,.5,.26,3.5,3492},
}
V.bossMaps=bossMaps
local function Plain(value,kind)
 return (not addon.Reminders or addon.Reminders.Public(value)) and type(value)==kind
end
local function Number(value,minimum,maximum)
 return Plain(value,'number') and value==value and value>=minimum and value<=maximum
end
local function Copy(value)
 if type(value)~='table' then return value end
 local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end
V.Copy=Copy
local function Ready()
 return not InCombatLockdown() and not (addon.Reminders and addon.Reminders.encounter)
end
function V.Store()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if db.visualNotes==nil then db.visualNotes={schema=1,serial=0,items={}} end
 local store=db.visualNotes
 if type(store)~='table' or store.schema~=1 or type(store.items)~='table' or
  #store.items>100 or not Number(store.serial,0,1000000000) or store.serial%1~=0 then
  return nil,'VRT visual-note storage needs review.'
 end
 local ids={}
 -- Sync identity: give older visual notes a global uid and a version time once.
 for _,item in ipairs(store.items) do
  if type(item)=='table' then
   if item.uid==nil and addon.NewUID then item.uid=addon.NewUID('visual') end
   if item.updated==nil then item.updated=0 end
  end
 end
 for _,item in ipairs(store.items) do
  local valid=V.Validate(item)
  if not valid or not item.id or ids[item.id] then return nil,'VRT visual-note storage needs review.' end
  ids[item.id]=true
 end
 return store
end
function V.New()
 return {name='New visual note',objects={}}
end
local function Coord(value,limit) return Number(value,0,limit) end
function V.Validate(note)
 if not Plain(note,'table') or getmetatable(note) or
  not Plain(note.name,'string') or note.name=='' or #note.name>120 or
  (note.id~=nil and (not Plain(note.id,'string') or not note.id:match('^VRT%-visual%-%d+$'))) or
  not Plain(note.objects,'table') or getmetatable(note.objects) or #note.objects>400 then
  return false,'Visual note title or object list is invalid.'
 end
 if note.map~=nil then
  local map=note.map
  if not Plain(map,'table') or getmetatable(map) or not Number(map.id,1,100000) or map.id%1~=0 or
   not Number(map.zoom,.5,8) or not Number(map.cx,0,1) or not Number(map.cy,0,1) then
   return false,'Visual-note map is invalid.'
  end
  if map.label~=nil and (not Plain(map.label,'string') or map.label=='' or #map.label>120) then return false,'Visual-note map label is invalid.' end
  if map.mode~=nil and map.mode~='absolute' then return false,'Visual-note map scale is invalid.' end
  for key in pairs(map) do if key~='id' and key~='zoom' and key~='cx' and key~='cy' and key~='label' and key~='mode' then return false,'Unexpected map field.' end end
 end
 if note.bossID~=nil and (not Number(note.bossID,1,1000000) or note.bossID%1~=0) then return false,'Invalid boss assignment.' end
 if note.origin~=nil then
  local origin=note.origin
  if not Plain(origin,'table') or getmetatable(origin) or not Plain(origin.sender,'string') or
   #origin.sender>160 or origin.sender=='' or not Plain(origin.id,'string') or
   not origin.id:match('^VRT%-visual%-%d+$') then return false,'Invalid visual-note source.' end
  for key in pairs(origin) do if key~='sender' and key~='id' then return false,'Unexpected visual-note source field.' end end
 end
 if note.uid~=nil and not (addon.ValidUID and addon.ValidUID(note.uid)) then return false,'Invalid visual-note identity.' end
 if note.updated~=nil and not Number(note.updated,0,1e10) then return false,'Invalid visual-note version.' end
 for key in pairs(note) do if key~='id' and key~='name' and key~='objects' and key~='map' and
  key~='bossID' and key~='origin' and key~='uid' and key~='updated' then return false,'Unexpected visual-note field.' end end
 for key in pairs(note.objects) do
  if type(key)~='number' or key%1~=0 or key<1 or key>#note.objects then return false,'Invalid object index.' end
 end
 local total,circles=0,0
 for index,object in ipairs(note.objects) do
  if not Plain(object,'table') or getmetatable(object) or not Plain(object.kind,'string') or
   not ({stroke=true,line=true,rect=true,circle=true,filledCircle=true,text=true,marker=true})[object.kind] or
   not Coord(object.x,V.width) or not Coord(object.y,V.height) or
   not Number(object.color,1,#palette) or object.color%1~=0 or
   not Number(object.size,1,48) then return false,'Invalid drawing object '..index..'.' end
  local allowed={kind=true,x=true,y=true,color=true,size=true}
  if object.kind=='stroke' then
   allowed.points=true
   if not Plain(object.points,'table') or getmetatable(object.points) or #object.points<1 or #object.points>400 then return false,'Invalid stroke.' end
   total=total+#object.points
   for _,point in ipairs(object.points) do
    if not Plain(point,'table') or getmetatable(point) or not Coord(point[1],V.width) or not Coord(point[2],V.height) or
     next(point,2)~=nil then return false,'Invalid stroke point.' end
    for key in pairs(point) do if key~=1 and key~=2 then return false,'Invalid stroke point.' end end
   end
   for key in pairs(object.points) do
    if type(key)~='number' or key%1~=0 or key<1 or key>#object.points then return false,'Invalid stroke index.' end
   end
  elseif object.kind=='line' or object.kind=='rect' or object.kind=='circle' or object.kind=='filledCircle' then
   allowed.x2=true;allowed.y2=true
   if not Coord(object.x2,V.width) or not Coord(object.y2,V.height) then return false,'Invalid shape.' end
   if object.kind=='circle' or object.kind=='filledCircle' then circles=circles+1 end
  elseif object.kind=='text' then
   allowed.text=true
   allowed.anchor=true
   if object.anchor~=nil and object.anchor~='center' then return false,'Invalid drawing anchor.' end
   if not Plain(object.text,'string') or object.text=='' or #object.text>120 then return false,'Invalid drawing text.' end
  else
   allowed.marker=true
   allowed.anchor=true
   if object.anchor~=nil and object.anchor~='center' then return false,'Invalid drawing anchor.' end
   if not Number(object.marker,1,#markerOptions) or object.marker%1~=0 then return false,'Invalid drawing symbol.' end
  end
  for key in pairs(object) do if not allowed[key] then return false,'Unexpected drawing field.' end end
 end
 if total>5000 then return false,'Visual note has too many stroke points.' end
 if circles>100 then return false,'Visual note has too many circles.' end
 return true
end

local function MapArt(id)
 if not C_Map or not C_Map.GetMapArtLayers or not C_Map.GetMapArtLayerTextures then return end
 local ok,layers=pcall(C_Map.GetMapArtLayers,id)
 if not ok or type(layers)~='table' or type(layers[1])~='table' then return end
 local layer=layers[1]
 local w,h,tw,th=layer.layerWidth,layer.layerHeight,layer.tileWidth,layer.tileHeight
 if not Number(w,1,16384) or not Number(h,1,16384) or not Number(tw,1,2048) or not Number(th,1,2048) then return end
 local cols,rows=math.ceil(w/tw),math.ceil(h/th)
 if cols*rows>256 then return end
 local got,files=pcall(C_Map.GetMapArtLayerTextures,id,1)
 if not got or type(files)~='table' then return end
 for i=1,cols*rows do if not (Plain(files[i],'number') or Plain(files[i],'string')) then return end end
 return layer,files,cols,rows
end
function V.MapName(map)
 if not map then return 'Blank canvas' end
 if Plain(map.label,'string') then return map.label end
 for _,preset in ipairs(bossMaps) do
  if map.id==preset[2] and map.cx==preset[3] and map.cy==preset[4] then return preset[1] end
 end
 if C_Map and C_Map.GetMapInfo then
  local ok,info=pcall(C_Map.GetMapInfo,map.id)
  if ok and type(info)=='table' and Plain(info.name,'string') then return info.name end
 end
 return 'Map '..map.id
end
-- The Adventure Guide reports a map for only some instances (and may report 0
-- before its data is ready). Index dungeon-type UI maps by the journal
-- instance of the bosses pinned on them, as the world map's boss pins do.
local instanceMapIndex
function V.InstanceMapIndex(worldMaps)
 if instanceMapIndex then return instanceMapIndex end
 local index,found={},false
 if not (C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap and EJ_GetEncounterInfo) then return index end
 local dungeonType=Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
 for _,info in ipairs(worldMaps or {}) do
  if type(info)=='table' and info.mapType==dungeonType and Number(info.mapID,1,100000) then
   local ok,pins=pcall(C_EncounterJournal.GetEncountersOnMap,info.mapID)
   local first=ok and type(pins)=='table' and pins[1]
   if type(first)=='table' and Number(first.encounterID,1,10000000) then
    local got,_,_,_,_,_,journalInstance=pcall(EJ_GetEncounterInfo,first.encounterID)
    if got and Number(journalInstance,1,10000000) then
     local maps=index[journalInstance] or {};index[journalInstance]=maps
     maps[#maps+1]=info.mapID;found=true
    end
   end
  end
 end
 -- Keep retrying until the client's journal data produces a usable index.
 if found then instanceMapIndex=index end
 return index
end
function V.ResolveInstanceMap(instance,index)
 if type(instance)~='table' then return end
 if not Number(instance.uiMapID,1,100000) and EJ_GetInstanceInfo and Number(instance.journalID,1,10000000) then
  local ok,_,_,_,_,_,_,uiMapID=pcall(EJ_GetInstanceInfo,instance.journalID)
  if ok and Number(uiMapID,1,100000) then instance.uiMapID=uiMapID end
 end
 local pinned=index and index[instance.journalID]
 if pinned then
  if not Number(instance.uiMapID,1,100000) then instance.uiMapID=pinned[1] end
  instance.pinnedMaps=pinned
 end
 return Number(instance.uiMapID,1,100000) and instance.uiMapID or nil
end
-- Map choices for one Adventure Guide instance: each boss on the floor where
-- the journal pins it (centred on that pin), then each floor in full.
-- Hand-tuned arena presets win for their bosses so saved labels still match.
function V.InstanceMaps(instance)
 local catalogue=addon.ReminderChoices
 if not catalogue or type(instance)~='table' or not Number(instance.uiMapID,1,100000) then return nil,'No map is available for this instance.' end
 local root=instance.uiMapID
 local floors,seen={root},{[root]=true}
 for _,mapID in ipairs(instance.pinnedMaps or {}) do
  if not seen[mapID] and #floors<20 then seen[mapID]=true;floors[#floors+1]=mapID end
 end
 if C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupMembersInfo then
  local ok,group=pcall(C_Map.GetMapGroupID,root)
  if ok and Number(group,1,10000000) then
   local got,members=pcall(C_Map.GetMapGroupMembersInfo,group)
   if got and type(members)=='table' then
    for _,member in ipairs(members) do
     if type(member)=='table' and Number(member.mapID,1,100000) and not seen[member.mapID] and #floors<20 then
      seen[member.mapID]=true;floors[#floors+1]=member.mapID
     end
    end
   end
  end
 end
 local pins={}
 if C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap then
  for _,floor in ipairs(floors) do
   local ok,list=pcall(C_EncounterJournal.GetEncountersOnMap,floor)
   if ok and type(list)=='table' then
    for _,pin in ipairs(list) do
     if type(pin)=='table' and Number(pin.encounterID,1,10000000) and Number(pin.mapX,0,1) and Number(pin.mapY,0,1) and not pins[pin.encounterID] then
      pins[pin.encounterID]={floor,pin.mapX,pin.mapY}
     end
    end
   end
  end
 end
 local presets={};for _,spec in ipairs(bossMaps) do presets[spec[6]]=spec end
 local bosses,err=catalogue.Bosses(instance)
 local result={}
 for _,boss in ipairs(bosses or {}) do
  local preset=presets[boss.bossID]
  if preset then
   result[#result+1]={label=preset[1],display=boss.name,id=preset[2],cx=preset[3],cy=preset[4],
    zoom=preset[5]*V.height/mrtCanvasHeight,absolute=true,bossID=boss.bossID}
  else
   local pin=pins[boss.journalEncounterID]
   result[#result+1]={label=(instance.name..': '..boss.name):sub(1,120),display=boss.name,
    id=pin and pin[1] or root,cx=pin and pin[2] or .5,cy=pin and pin[3] or .5,zoom=pin and 2 or 1,bossID=boss.bossID}
  end
 end
 for _,floor in ipairs(floors) do
  local name=V.MapName({id=floor})
  result[#result+1]={label=(instance.name..': '..name):sub(1,120),display='Full map: '..name,id=floor,cx=.5,cy=.5,zoom=1}
 end
 if #result==0 then return nil,err or 'No map is available for this instance.' end
 return result
end
local function MapScale(map,layer)
 local fit=math.min(V.width/layer.layerWidth,V.height/layer.layerHeight)
 return (map.mode=='absolute' and 1 or fit)*map.zoom
end
local function RenderMap(canvas,map)
 canvas.mapTiles=canvas.mapTiles or {}
 for _,tile in ipairs(canvas.mapTiles) do tile:Hide() end
 if not map then return true end
 local layer,files,cols,rows=MapArt(map.id)
 if not layer then return false end
 local scale=MapScale(map,layer)
 local left=V.width/2-map.cx*layer.layerWidth*scale
 local top=V.height/2-map.cy*layer.layerHeight*scale
 for row=1,rows do for col=1,cols do
  local index=(row-1)*cols+col
  local tile=canvas.mapTiles[index]
  -- BackdropTemplate paints at BACKGROUND; use a lower ARTWORK sublevel so
  -- the map sits above that backdrop and below all drawing objects.
  if not tile then tile=canvas:CreateTexture(nil,'ARTWORK',nil,-8);canvas.mapTiles[index]=tile end
  tile:ClearAllPoints();tile:SetTexture(files[index]);tile:SetSize(layer.tileWidth*scale,layer.tileHeight*scale)
  tile:SetPoint('TOPLEFT',canvas,'TOPLEFT',left+(col-1)*layer.tileWidth*scale,-top-(row-1)*layer.tileHeight*scale)
  tile:Show()
 end end
 return true
end
V.RenderMap=RenderMap
function V.Save(note)
 if not Ready() then return false,'Save outside combat and encounters.' end
 local valid,err=V.Validate(note);if not valid then return false,err end
 local store;store,err=V.Store();if not store then return false,err end
 local at
 if note.id then for index,item in ipairs(store.items) do if item.id==note.id then at=index;break end end
  if not at then return false,'Saved visual note was not found.' end
 elseif #store.items>=100 then return false,'Visual-note library is full (100).' end
 local copy=Copy(note)
 if not at then
  store.serial=store.serial+1;copy.id='VRT-visual-'..store.serial;at=#store.items+1
 end
 copy.uid=at and store.items[at] and store.items[at].uid or copy.uid
 if not (addon.ValidUID and addon.ValidUID(copy.uid)) and addon.NewUID then copy.uid=addon.NewUID('visual') end
 copy.updated=math.max(Now(),((store.items[at] and store.items[at].updated) or 0)+1)
 store.items[at]=copy
 if addon.UpdateVisualNote then addon.UpdateVisualNote() end
 if addon.SyncChanged then addon.SyncChanged('visual') end
 return true,copy.id
end
function V.Remove(id)
 if not Ready() then return false,'Delete outside combat and encounters.' end
 local store,err=V.Store();if not store then return false,err end
 for index,item in ipairs(store.items) do if item.id==id then
  table.remove(store.items,index);if addon.MarkDeleted then addon.MarkDeleted('visual',item.uid) end
  if addon.UpdateVisualNote then addon.UpdateVisualNote() end
  if addon.SyncChanged then addon.SyncChanged('visual') end;return true
 end end
 return false,'Visual note not found.'
end

-- Render the same native objects in both the read-only viewer and the editor.
local function Render(canvas,note)
 canvas.drawn={};canvas.cache=canvas.cache or {line={},text={},texture={}}
 for _,pool in pairs(canvas.cache) do for _,region in ipairs(pool) do region:Hide() end end
 local mapReady=RenderMap(canvas,note.map)
 local count=0
 local used={line=0,text=0,texture=0}
 local function Region(kind)
  count=count+1
  used[kind]=used[kind]+1
  local pool=canvas.cache[kind]
  local region=pool[used[kind]]
  if not region then
   region=kind=='line' and canvas:CreateLine(nil,'ARTWORK') or
    kind=='text' and canvas:CreateFontString(nil,'OVERLAY') or canvas:CreateTexture(nil,'ARTWORK')
   region.vrtKind=kind;pool[used[kind]]=region
  end
  canvas.drawn[count]=region;region:Show();return region
 end
 local function Segment(x,y,x2,y2,color,size)
  local line=Region('line');line:SetColorTexture(unpack(palette[color]))
  line:ClearAllPoints()
  line:SetThickness(size);line:SetStartPoint('TOPLEFT',canvas,x,-y);line:SetEndPoint('TOPLEFT',canvas,x2,-y2)
 end
 for _,object in ipairs(note.objects) do
  if object.kind=='stroke' then
   local last={object.x,object.y}
   for _,point in ipairs(object.points) do Segment(last[1],last[2],point[1],point[2],object.color,object.size);last=point end
  elseif object.kind=='line' then Segment(object.x,object.y,object.x2,object.y2,object.color,object.size)
  elseif object.kind=='rect' then
   Segment(object.x,object.y,object.x2,object.y,object.color,object.size)
   Segment(object.x2,object.y,object.x2,object.y2,object.color,object.size)
   Segment(object.x2,object.y2,object.x,object.y2,object.color,object.size)
   Segment(object.x,object.y2,object.x,object.y,object.color,object.size)
  elseif object.kind=='circle' then
   local cx,cy=(object.x+object.x2)/2,(object.y+object.y2)/2
   local rx,ry=math.abs(object.x2-object.x)/2,math.abs(object.y2-object.y)/2
   for index=0,23 do
    local a,b=index*math.pi/12,(index+1)*math.pi/12
    Segment(cx+rx*math.cos(a),cy+ry*math.sin(a),cx+rx*math.cos(b),cy+ry*math.sin(b),object.color,object.size)
   end
  elseif object.kind=='filledCircle' then
   local circle=Region('texture');circle:SetTexture(filledCircleArt)
   circle:SetTexCoord(0,1,0,1)
   circle:SetVertexColor(unpack(palette[object.color]));circle:ClearAllPoints()
   circle:SetSize(math.max(1,math.abs(object.x2-object.x)),math.max(1,math.abs(object.y2-object.y)))
   circle:SetPoint('TOPLEFT',canvas,'TOPLEFT',math.min(object.x,object.x2),-math.min(object.y,object.y2))
  elseif object.kind=='text' then
   local label=Region('text');label:SetFont(STANDARD_TEXT_FONT,object.size,'OUTLINE')
   label:ClearAllPoints()
   label:SetTextColor(unpack(palette[object.color]))
   label:SetPoint(object.anchor=='center' and 'CENTER' or 'TOPLEFT',canvas,'TOPLEFT',object.x,-object.y)
   label:SetJustifyH(object.anchor=='center' and 'CENTER' or 'LEFT')
   label:SetWidth(object.anchor=='center' and V.width or math.max(1,V.width-object.x));label:SetText(object.text)
  else
   local marker=Region('texture');SetMarkerArt(marker,object.marker)
   marker:ClearAllPoints()
   marker:SetSize(object.size,object.size)
   marker:SetPoint(object.anchor=='center' and 'CENTER' or 'TOPLEFT',canvas,'TOPLEFT',object.x,-object.y)
  end
 end
 canvas.used=used
 return mapReady
end
V.Render=Render
local popup
local function PopupSettings()
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local position=VincibilityRaidToolsDB.visualPopup
 if type(position)~='table' then position={x=0,y=0,scale=.65};VincibilityRaidToolsDB.visualPopup=position end
 if not Number(position.x,-10000,10000) then position.x=0 end
 if not Number(position.y,-10000,10000) then position.y=0 end
 if not Number(position.scale,.35,1.2) then position.scale=.65 end
 return position
end
V.PopupSettings=PopupSettings
local function PlacePopup()
 local position=PopupSettings()
 popup:SetScale(position.scale);popup:ClearAllPoints()
 -- Saved offsets are in UIParent units; SetPoint offsets on this scaled frame
 -- are scaled again. Convert them back so dragging/resizing preserves its centre.
 popup:SetPoint('CENTER',UIParent,'CENTER',position.x/position.scale,position.y/position.scale)
end
local function BuildPopup()
 if popup then return end
 popup=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');V.popup=popup
 popup:SetSize(724,474);popup:SetFrameStrata('DIALOG');popup:SetClampedToScreen(true)
 popup:SetMovable(true);popup:EnableMouse(true);popup:Hide()
 popup:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 popup:SetBackdropColor(.078,.086,.106,.97);popup:SetBackdropBorderColor(.72,.76,.81,.8)
 local header=CreateFrame('Frame',nil,popup);popup.header=header;header:SetSize(724,28);header:SetPoint('TOPLEFT')
 header:EnableMouse(true);header:RegisterForDrag('LeftButton')
 popup.title=header:CreateFontString(nil,'OVERLAY');popup.title:SetFont(STANDARD_TEXT_FONT,15,'OUTLINE')
 popup.title:SetPoint('LEFT',header,'LEFT',10,0);popup.title:SetWidth(600);popup.title:SetJustifyH('LEFT')
 header:SetScript('OnDragStart',function()
  if InCombatLockdown() then return end
  header.dragX,header.dragY=GetCursorPosition()
  local position=PopupSettings();header.startX,header.startY=position.x,position.y
 end)
 header:SetScript('OnUpdate',function()
  if not header.dragX then return end
  if InCombatLockdown() then header.dragX=nil;return end
  local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale()
  local position=PopupSettings()
  position.x=math.max(-10000,math.min(10000,header.startX+(x-header.dragX)/scale))
  position.y=math.max(-10000,math.min(10000,header.startY+(y-header.dragY)/scale))
  PlacePopup()
 end)
 header:SetScript('OnDragStop',function() header.dragX=nil end)
 local function Control(label,x,action)
  local button=CreateFrame('Button',nil,header,'BackdropTemplate');button:SetSize(28,23)
  button:SetPoint('TOPRIGHT',header,'TOPRIGHT',x,-2)
  button:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
  button:SetBackdropColor(.145,.157,.192,1);button:SetBackdropBorderColor(.72,.76,.81,.6)
  local title=button:CreateFontString(nil,'OVERLAY');title:SetFont(STANDARD_TEXT_FONT,14,'OUTLINE')
  title:SetPoint('CENTER');title:SetText(label);button:SetScript('OnClick',action)
  return button
 end
 popup.close=Control('X',-4,function()
  popup:Hide()
  if not popup.manual and addon.OnNativeVisualPopupClosed then addon.OnNativeVisualPopupClosed() end
 end)
 local function ChangeScale(delta)
  local position=PopupSettings();position.scale=math.max(.35,math.min(1.2,position.scale+delta));PlacePopup()
 end
 popup.grow=Control('+',-36,function() ChangeScale(.1) end)
 popup.shrink=Control('-',-68,function() ChangeScale(-.1) end)
 popup.canvas=CreateFrame('Frame',nil,popup,'BackdropTemplate');popup.canvas:SetSize(V.width,V.height)
 popup.canvas:SetPoint('TOPLEFT',popup,'TOPLEFT',12,-32)
 popup.canvas:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 popup.canvas:SetBackdropColor(.078,.086,.106,1);popup.canvas:SetBackdropBorderColor(.72,.76,.81,.5)
 if popup.canvas.SetClipsChildren then popup.canvas:SetClipsChildren(true) end
 local grip=CreateFrame('Button',nil,popup,'BackdropTemplate');popup.grip=grip
 grip:SetSize(20,20);grip:SetPoint('BOTTOMRIGHT',popup,'BOTTOMRIGHT',0,0)
 grip:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 grip:SetBackdropColor(.145,.157,.192,1);grip:SetBackdropBorderColor(.72,.76,.81,.6)
 grip:SetScript('OnMouseDown',function(_,button)
  if button~='LeftButton' or InCombatLockdown() then return end
  local x=GetCursorPosition();grip.startX=x;grip.startScale=PopupSettings().scale
 end)
 grip:SetScript('OnUpdate',function()
  if not grip.startX then return end
  local x=GetCursorPosition();local parentScale=UIParent:GetEffectiveScale()
  local scale=math.max(.35,math.min(1.2,grip.startScale+(x-grip.startX)/(parentScale*724)))
  PopupSettings().scale=scale;PlacePopup()
 end)
 grip:SetScript('OnMouseUp',function() grip.startX=nil end)
 grip:SetScript('OnHide',function() grip.startX=nil end)
 popup:SetScript('OnHide',function() header.dragX=nil;grip.startX=nil end)
 PlacePopup()
end
function V.ShowPopup(note,manual)
 local valid,err=V.Validate(note);if not valid then return false,err end
 BuildPopup();popup.manual=manual and true or false
 popup.title:SetText(note.name);Render(popup.canvas,note);popup:Show()
 return true
end
function V.HidePopup() if popup and not popup.manual then popup:Hide() end end
function V.IsManualPopup() return popup and popup:IsShown() and popup.manual end
local function AppendStroke(canvas,x,y,x2,y2,color,size)
 local pool=canvas.cache.line
 canvas.used.line=canvas.used.line+1
 local line=pool[canvas.used.line]
 if not line then line=canvas:CreateLine(nil,'ARTWORK');line.vrtKind='line';pool[canvas.used.line]=line end
 line:ClearAllPoints();line:SetColorTexture(unpack(palette[color]));line:SetThickness(size)
 line:SetStartPoint('TOPLEFT',canvas,x,-y);line:SetEndPoint('TOPLEFT',canvas,x2,-y2);line:Show()
 canvas.drawn[#canvas.drawn+1]=line
end

function addon.BuildNativeVisualNotesPage(page,window,H)
 local Text,Button,Surface=H.Text,H.Button,H.Surface
 local ui={rows={},offset=0,tool='stroke',color=2,size=4,marker=1}
 window.nativeVisualNotes=ui
 Text(page,'Choose a boss map to auto-show a drawing in that room; select one to pop out or send.',0,-27,12,'muted',850)
 -- Status and summary sit at the bottom, under the buttons (as on Notes).
 ui.status=Text(page,'',0,0,11,'accent',600);ui.status:ClearAllPoints();ui.status:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-4)
 ui.summary=Text(page,'',0,0,10,'muted',850);ui.summary:ClearAllPoints();ui.summary:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,-20)
 ui.pendingText=Text(page,'',0,-598,11,'accent',580)
 local list=Surface('Frame',page);list:SetSize(864,480);list:SetPoint('TOPLEFT',0,-60);list:EnableMouseWheel(true);ui.list=list
 -- Clicking empty space (in the list or on the page) clears the selection;
 -- cards and buttons handle their own clicks.
 local function Deselect() if ui.viewNote then ui.viewNote=nil;ui.Refresh() end end
 ui.Deselect=Deselect
 list:EnableMouse(true);list:SetScript('OnMouseDown',Deselect)
 page:EnableMouse(true);page:SetScript('OnMouseDown',Deselect)
 local viewer=Surface('Frame',window);ui.viewer=viewer;viewer:SetSize(990,640);viewer:SetPoint('CENTER',window,'CENTER',0,-15)
 viewer:SetFrameLevel(window:GetFrameLevel()+30);viewer:EnableMouse(true);viewer:Hide()
 ui.viewTitle=Text(viewer,'',18,-14,16,'text',930)
 local editor=Surface('Frame',window);ui.editor=editor;editor:SetSize(990,620);editor:SetPoint('CENTER')
 editor:SetFrameLevel(window:GetFrameLevel()+40);editor:EnableMouse(true);editor:Hide()
 function V.IsEditing() return editor:IsShown() end
 Text(editor,'Visual-note editor',18,-12,17,'text',920)
 ui.title=Surface('EditBox',editor,'background');ui.title:SetSize(700,25);ui.title:SetPoint('TOPLEFT',18,-38)
 ui.title:SetAutoFocus(false);ui.title:SetFont(STANDARD_TEXT_FONT,13,'');ui.title:SetTextColor(0.91,0.92,0.94)
 ui.title:SetTextInsets(7,7,0,0);ui.title:SetMaxLetters(120)
 local function Canvas(parent,y)
  local canvas=Surface('Frame',parent,'background');canvas:SetSize(V.width,V.height);canvas:SetPoint('TOPLEFT',18,y)
  canvas:SetBackdropBorderColor(0.72,0.76,0.81,0.55);canvas:EnableMouse(true)
  if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
  return canvas
 end
 ui.viewCanvas=Canvas(viewer,-46);ui.canvas=Canvas(editor,-70)
 -- The read-only viewer shows the drawing larger and centred; its coordinates
 -- stay in canvas units, so only the frame's scale changes.
 local VIEW_SCALE=1.25
 ui.viewCanvas:SetScale(VIEW_SCALE);ui.viewCanvas:ClearAllPoints();ui.viewCanvas:SetPoint('TOP',viewer,'TOP',0,-46/VIEW_SCALE)
 local function Cursor(canvas)
  if not GetCursorPosition or not canvas:GetLeft() or not canvas:GetTop() then return end
  local x,y=GetCursorPosition();local scale=canvas:GetEffectiveScale()
  x=math.floor(x/scale-canvas:GetLeft()+0.5);y=math.floor(canvas:GetTop()-y/scale+0.5)
  return math.max(0,math.min(V.width,x)),math.max(0,math.min(V.height,y))
 end
 local function Draw()
  if not ui.draft then return end
  local ready=Render(ui.canvas,ui.draft)
  ui.mapButton.label:SetText('Map: '..V.MapName(ui.draft.map)..'  v')
  if not ready then ui.editStatus:SetText('Map art is unavailable on this client; drawing is preserved.') end
 end
 local picker=Surface('Frame',editor);ui.mapPicker=picker;picker:SetSize(650,500);picker:SetPoint('CENTER')
 picker:SetFrameLevel(editor:GetFrameLevel()+10);picker:EnableMouse(true);picker:Hide()
 Text(picker,'Choose a map',16,-14,16,'text',600)
 Text(picker,'Browse Nearby, Raids or Dungeons, or search. Blank keeps drawings.',16,-40,11,'muted',600)
 ui.mapSearch=Surface('EditBox',picker,'background');ui.mapSearch:SetSize(610,26);ui.mapSearch:SetPoint('TOPLEFT',16,-62)
 ui.mapSearch:SetAutoFocus(false);ui.mapSearch:SetFont(STANDARD_TEXT_FONT,12,'')
 ui.mapSearch:SetTextColor(.91,.92,.94);ui.mapSearch:SetTextInsets(7,7,0,0);ui.mapSearch:SetMaxLetters(80)
 -- Top level: Blank, Current, Parent, then Nearby, Raids and Dungeons submenus.
 -- allChoices is the flat list used by search; labels there stay fully qualified.
 local choices,allChoices,filtered,worldMaps,stack={},{},{},{},{}
 local offset=0
 local function AddChoice(label,id,cx,cy,zoom,absolute,bossID,list,display)
  if id and not MapArt(id) then return end
  local choice={label=label,display=display,map=id and {id=id,cx=cx or .5,cy=cy or .5,zoom=zoom or 1,label=label,
   mode=absolute and 'absolute' or nil} or nil,bossID=bossID}
  local target=list or choices;target[#target+1]=choice;allChoices[#allChoices+1]=choice
 end
 local function Choices()
  choices={};allChoices={};stack={};AddChoice('Blank canvas')
  local nearby={}
  worldMaps={}
  if C_Map and C_Map.GetFallbackWorldMapID and C_Map.GetMapChildrenInfo then
   local rootOK,root=pcall(C_Map.GetFallbackWorldMapID)
   if rootOK and Number(root,1,100000) then
    -- Start above Azeroth so Outland, Draenor and the Shadowlands are included.
    for _=1,5 do
     local ok,info=C_Map.GetMapInfo and pcall(C_Map.GetMapInfo,root)
     if not ok or type(info)~='table' or not Number(info.parentMapID,1,100000) then break end
     root=info.parentMapID
    end
    local allOK,all=pcall(C_Map.GetMapChildrenInfo,root,nil,true)
    if allOK and type(all)=='table' and #all<=10000 then worldMaps=all end
   end
  end
  if C_Map and C_Map.GetBestMapForUnit then
   local ok,id=pcall(C_Map.GetBestMapForUnit,'player')
   if ok and Number(id,1,100000) then
    AddChoice('Current area: '..V.MapName({id=id,cx=.5,cy=.5,zoom=1}),id)
    if C_Map.GetMapInfo and C_Map.GetMapChildrenInfo then
     local got,info=pcall(C_Map.GetMapInfo,id)
     if got and type(info)=='table' and Number(info.parentMapID,1,100000) then
      local seen={[id]=true}
      local parent=info.parentMapID
      AddChoice('Parent area: '..V.MapName({id=parent,cx=.5,cy=.5,zoom=1}),parent)
      seen[parent]=true
      local found,children=pcall(C_Map.GetMapChildrenInfo,parent)
      if found and type(children)=='table' then
       for _,child in ipairs(children) do
        if type(child)=='table' and Number(child.mapID,1,100000) and not seen[child.mapID] then
         seen[child.mapID]=true
         local name=V.MapName({id=child.mapID,cx=.5,cy=.5,zoom=1})
         AddChoice('Nearby: '..name,child.mapID,nil,nil,nil,nil,nil,nearby,name)
        end
       end
      end
     end
    end
   end
  end
  if #nearby>0 then choices[#choices+1]={label='Nearby',submenu=nearby} end
  local raids,byRaid={},{}
  local presetStart=#allChoices
  -- Boss presets are drawn for a taller canvas; show the same vertical map area here.
  -- They are the fallback Raids menu when Adventure Guide data is unavailable.
  for _,spec in ipairs(bossMaps) do
   local raid,boss=spec[1]:match('^(.-):%s*(.+)$')
   raid=raid or spec[1];boss=boss or spec[1]
   if not byRaid[raid] then byRaid[raid]={label=raid,submenu={}};raids[#raids+1]=byRaid[raid] end
   -- Keep the full preset label on the saved map: boss-room matching compares it.
   AddChoice(spec[1],spec[2],spec[3],spec[4],spec[5]*V.height/mrtCanvasHeight,true,spec[6],byRaid[raid].submenu,(boss:gsub('^%l',string.upper)))
  end
  local instances=addon.ReminderChoices and addon.ReminderChoices.Instances()
  local guideRaids=false
  if instances then
   local mapIndex=V.InstanceMapIndex(worldMaps)
   for _,group in ipairs({{'raid','Raids'},{'party','Dungeons'}}) do
    local expansions,byTier={},{}
    for _,instance in ipairs(instances) do
     if instance.kind==group[1] and V.ResolveInstanceMap(instance,mapIndex) then
      local expansion=byTier[instance.tier]
      if not expansion then expansion={label=instance.tierName,submenu={}};byTier[instance.tier]=expansion;expansions[#expansions+1]=expansion end
      -- Bosses and floors load on demand; the label carries tier/type for search results.
      local node={label=instance.label or instance.name,display=instance.name,load=function()
       local maps,err=V.InstanceMaps(instance);if not maps then return nil,err end
       local list={}
       for _,m in ipairs(maps) do AddChoice(m.label,m.id,m.cx,m.cy,m.zoom,m.absolute,m.bossID,list,m.display) end
       if #list==0 then return nil,'No map art is available for '..instance.name..'.' end
       return list
      end}
      expansion.submenu[#expansion.submenu+1]=node;allChoices[#allChoices+1]=node
     end
    end
    if #expansions>0 then
     choices[#choices+1]={label=group[2],submenu=expansions}
     if group[1]=='raid' then guideRaids=true end
    end
   end
  end
  if guideRaids then
   -- Guide-built boss entries replace the preset leaves in search results.
   local kept={};for index,choice in ipairs(allChoices) do if index<=presetStart or choice.load then kept[#kept+1]=choice end end
   allChoices=kept
  elseif #raids>0 then table.insert(choices,#choices+1-(choices[#choices] and choices[#choices].label=='Dungeons' and 1 or 0),{label='Raids',submenu=raids}) end
 end
 local rows={};ui.mapRows=rows
 local function RefreshChoices()
  filtered={};local query=ui.mapSearch:GetText():lower()
  local level=#stack>0 and stack[#stack].submenu or choices
  if query=='' then
   if #stack>0 then filtered[1]={label='<  Back',back=true} end
   for _,choice in ipairs(level) do filtered[#filtered+1]=choice end
  else
   for _,choice in ipairs(allChoices) do if choice.label:lower():find(query,1,true) then filtered[#filtered+1]=choice end end
  end
  if #query>=3 then
   local seen={}
   for _,choice in ipairs(filtered) do if choice.map then seen[choice.map.id]=true end end
   local added=0
   for _,info in ipairs(worldMaps) do
    if added>=100 then break end
    if type(info)=='table' and Plain(info.name,'string') and Number(info.mapID,1,100000) and
     not seen[info.mapID] and info.name:lower():find(query,1,true) and MapArt(info.mapID) then
     filtered[#filtered+1]={label='World map: '..info.name,map={id=info.mapID,cx=.5,cy=.5,zoom=1,label=info.name}}
     seen[info.mapID]=true;added=added+1
    end
   end
  end
  offset=math.min(offset,math.max(0,#filtered-11))
  for index,row in ipairs(rows) do
   row.choice=filtered[index+offset]
   local choice=row.choice
   if choice then
    local text=query=='' and choice.display or choice.label
    row.label:SetText(text..((choice.submenu or choice.load) and '  >' or ''));row:Show()
   else row:Hide() end
  end
  local path={};for _,entry in ipairs(stack) do path[#path+1]=entry.label end
  local count=0;for _,choice in ipairs(filtered) do if not choice.back then count=count+1 end end
  ui.mapCount:SetText((query=='' and #path>0 and table.concat(path,' > ')..' · ' or '')..count..' choice(s)')
 end
 for index=1,11 do
  local row;row=Button(picker,'',16,-99-(index-1)*32,610,function()
   local choice=row.choice
   if not choice then return end
   if choice.back then stack[#stack]=nil;offset=0;RefreshChoices();return end
   if choice.submenu or choice.load then
    if not choice.submenu then
     local list,err=choice.load()
     if not list then ui.mapCount:SetText(err or 'This map list is unavailable.');return end
     choice.submenu=list
    end
    -- A submenu picked from search results opens on its own and clears the search.
    if ui.mapSearch:GetText()~='' then stack={choice};ui.mapSearch:SetText('') else stack[#stack+1]=choice end
    offset=0;RefreshChoices();return
   end
   ui.draft.map=Copy(choice.map);ui.draft.bossID=choice.bossID;picker:Hide();Draw()
  end)
  row.label:SetWidth(580);row.label:SetWordWrap(false);rows[index]=row
 end
 ui.mapCount=Text(picker,'',16,-457,11,'muted',300)
 Button(picker,'Close',508,-456,118,function() picker:Hide() end)
 ui.mapSearch:SetScript('OnTextChanged',function() offset=0;RefreshChoices() end)
 picker:EnableMouseWheel(true)
 picker:SetScript('OnMouseWheel',function(_,delta)
  offset=math.max(0,math.min(math.max(0,#filtered-11),offset-delta));RefreshChoices()
 end)
 ui.mapButton=Button(editor,'Map: Blank canvas  v',738,-38,225,function()
  if ui.markerPicker then ui.markerPicker:Hide() end
  Choices();offset=0;ui.mapSearch:SetText('');RefreshChoices();picker:Show()
 end)
 ui.mapButton.label:SetWordWrap(false)
 local toolButtons={}
 local function ToolGlyph(button,kind)
  local function Line(x,y,x2,y2)
   local line=button:CreateLine(nil,'ARTWORK');line:SetColorTexture(.91,.92,.94)
   line:SetThickness(2);line:SetStartPoint('CENTER',button,-23+x,y)
   line:SetEndPoint('CENTER',button,-23+x2,y2)
   return line
  end
  if kind=='marker' or kind=='move' then
   local icon=button:CreateTexture(nil,'ARTWORK');icon:SetSize(17,17)
   icon:SetPoint('CENTER',button,'CENTER',-23,0)
   icon:SetTexture(kind=='marker' and 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_1' or
    'Interface\\Cursor\\UI-Cursor-Move')
   button.icon=icon
  elseif kind=='text' then
   local glyph=button:CreateFontString(nil,'ARTWORK');glyph:SetFont(STANDARD_TEXT_FONT,16,'OUTLINE')
   glyph:SetTextColor(.91,.92,.94);glyph:SetPoint('CENTER',button,'CENTER',-23,0);glyph:SetText('T')
  elseif kind=='stroke' then
   local dot=button:CreateTexture(nil,'ARTWORK');dot:SetSize(9,9)
   dot:SetPoint('CENTER',button,'CENTER',-23,0);dot:SetColorTexture(.91,.92,.94)
  elseif kind=='erase' then Line(-6,-6,6,6);Line(-6,6,6,-6)
  elseif kind=='line' then Line(-7,-6,7,6)
  elseif kind=='rect' then
   Line(-7,-6,7,-6);Line(7,-6,7,6);Line(7,6,-7,6);Line(-7,6,-7,-6)
  elseif kind=='filledCircle' then
   local disc=button:CreateTexture(nil,'ARTWORK');disc:SetSize(15,15)
   disc:SetPoint('CENTER',button,'CENTER',-23,0)
   disc:SetTexture(filledCircleArt);disc:SetVertexColor(.91,.92,.94)
   button.icon=disc
  elseif kind=='circle' then
   button.glyphLines={}
   for i=0,11 do
    local a,b=i*math.pi/6,(i+1)*math.pi/6
    button.glyphLines[#button.glyphLines+1]=Line(7*math.cos(a),7*math.sin(a),7*math.cos(b),7*math.sin(b))
   end
  end
 end
 local function Tool(name)
  ui.tool=name;ui.toolLabel:SetText('Tool: '..(name=='filledCircle' and 'filled circle' or name))
  for key,button in pairs(toolButtons) do
   if key==name then button:SetBackdropBorderColor(.78,.11,.25,1)
   else button:SetBackdropBorderColor(.72,.76,.81,.35) end
  end
 end
 ui.toolLabel=Text(editor,'Tool: stroke',738,-68,12,'accent',225)
 for index,spec in ipairs({{'stroke','Brush'},{'erase','Erase'},{'text','Text'},
  {'circle','Circle'},{'marker','Marker'},{'line','Line'},
  {'rect','Rect'},{'move','Move'},{'filledCircle','Filled'}}) do
  local x=738+((index-1)%3)*76
  local y=-94-math.floor((index-1)/3)*36
  local button=Button(editor,spec[2],x,y,72,function() Tool(spec[1]) end)
  button.label:SetFont(STANDARD_TEXT_FONT,11,'')
  button.label:ClearAllPoints();button.label:SetPoint('LEFT',button,'LEFT',31,0)
  button.label:SetWidth(39);button.label:SetJustifyH('LEFT')
  ToolGlyph(button,spec[1])
  toolButtons[spec[1]]=button
 end
 ui.toolButtons=toolButtons;Tool('stroke')
 Text(editor,'Colour',738,-208,11,'muted',220)
 ui.paletteSwatches={}
 for index,color in ipairs(palette) do
  local swatch=Surface('Button',editor,'raised');swatch:SetSize(23,23)
  swatch:SetPoint('TOPLEFT',738+((index-1)%8)*28,-229-math.floor((index-1)/8)*27)
  local fill=swatch:CreateTexture(nil,'ARTWORK');fill:SetPoint('CENTER');fill:SetSize(17,17);fill:SetColorTexture(unpack(color))
  swatch:SetScript('OnClick',function() ui.color=index;ui.colourLabel:SetText('Colour: '..colorNames[index]) end)
  ui.paletteSwatches[index]=swatch
 end
 ui.colourLabel=Text(editor,'Colour: teal',738,-289,11,'accent',220)
 ui.sizeLabel=Text(editor,'Size: 4',738,-310,11,'text',220)
 ui.sizeSlider=Surface('Slider',editor,'raised');ui.sizeSlider:SetSize(225,15);ui.sizeSlider:SetPoint('TOPLEFT',738,-332)
 ui.sizeSlider:SetOrientation('HORIZONTAL');ui.sizeSlider:SetMinMaxValues(1,48)
 ui.sizeSlider:SetValueStep(1);ui.sizeSlider:SetObeyStepOnDrag(true)
 ui.sizeSlider:SetThumbTexture('Interface\\Buttons\\WHITE8X8')
 ui.sizeSlider:GetThumbTexture():SetSize(9,19)
 ui.sizeSlider:GetThumbTexture():SetVertexColor(.72,.76,.81)
 ui.sizeSlider:SetScript('OnValueChanged',function(_,value)
  ui.size=math.floor(math.max(1,math.min(48,value))+.5);ui.sizeLabel:SetText('Size: '..ui.size)
 end)
 ui.sizeSlider:SetValue(ui.size)
 ui.text=Surface('EditBox',editor,'background');ui.text:SetSize(225,26);ui.text:SetPoint('TOPLEFT',738,-372)
 ui.text:SetAutoFocus(false);ui.text:SetFont(STANDARD_TEXT_FONT,12,'');ui.text:SetTextColor(0.91,0.92,0.94)
 ui.text:SetTextInsets(7,7,0,0);ui.text:SetMaxLetters(120)
 Text(editor,'Text to place (Text tool)',738,-402,10,'muted',225)
 Text(editor,'Symbol',738,-441,11,'muted',225)
 local markerPicker=Surface('Frame',editor);ui.markerPicker=markerPicker
 markerPicker:SetSize(225,42+math.ceil(#markerOptions/5)*42);markerPicker:SetPoint('TOPLEFT',738,-176)
 markerPicker:SetFrameLevel(editor:GetFrameLevel()+10);markerPicker:EnableMouse(true);markerPicker:Hide()
 Text(markerPicker,'Choose symbol',9,-9,11,'text',170)
 Button(markerPicker,'X',192,-5,25,function() markerPicker:Hide() end)
 ui.markerChoices={}
 local function MarkerIcon(parent,id,size)
  local icon=parent:CreateTexture(nil,'ARTWORK');icon:SetSize(size,size)
  SetMarkerArt(icon,id)
  return icon
 end
 local function RefreshMarker()
  ui.markerButton.label:SetText(markerOptions[ui.marker].name..'  v')
  SetMarkerArt(ui.markerButton.icon,ui.marker)
  for index,choice in ipairs(ui.markerChoices) do
   if index==ui.marker then choice:SetBackdropBorderColor(.78,.11,.25,1)
   else choice:SetBackdropBorderColor(.72,.76,.81,.35) end
  end
 end
 for index,option in ipairs(markerOptions) do
  local x=9+((index-1)%5)*42
  local y=-36-math.floor((index-1)/5)*42
  local choice=Button(markerPicker,'',x,y,38,function()
   ui.marker=index;RefreshMarker();markerPicker:Hide()
  end)
  choice:SetHeight(38)
  choice.icon=MarkerIcon(choice,index,27);choice.icon:SetPoint('CENTER')
  choice:HookScript('OnEnter',function()
   if GameTooltip then GameTooltip:SetOwner(choice,'ANCHOR_RIGHT');GameTooltip:SetText(option.name);GameTooltip:Show() end
  end)
  choice:HookScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  ui.markerChoices[index]=choice
 end
 ui.markerButton=Button(editor,'Star  v',738,-459,225,function()
  if markerPicker:IsShown() then markerPicker:Hide() else picker:Hide();RefreshMarker();markerPicker:Show() end
 end)
 ui.markerButton.icon=MarkerIcon(ui.markerButton,ui.marker,21)
 ui.markerButton.icon:SetPoint('LEFT',8,0)
 ui.markerButton.label:ClearAllPoints();ui.markerButton.label:SetPoint('LEFT',ui.markerButton.icon,'RIGHT',7,0)
 ui.markerButton.label:SetWidth(178)
 RefreshMarker()
 ui.editStatus=Text(editor,'Drag to draw or size; Move drags objects. Right-click removes; right-drag empty map pans.',18,-527,11,'accent',940)
 local function Add(object)
  if #ui.draft.objects>=400 then ui.editStatus:SetText('Maximum 400 drawing objects.');return false end
  ui.draft.objects[#ui.draft.objects+1]=object;Draw();return true
 end
 local function Near(object,x,y)
  if object.kind=='stroke' then
   for _,point in ipairs(object.points) do if math.abs(point[1]-x)<12 and math.abs(point[2]-y)<12 then return true end end
   return math.abs(object.x-x)<12 and math.abs(object.y-y)<12
  end
  if object.x2 then return x>=math.min(object.x,object.x2)-8 and x<=math.max(object.x,object.x2)+8 and
   y>=math.min(object.y,object.y2)-8 and y<=math.max(object.y,object.y2)+8 end
  if object.kind=='marker' then
   local half=math.max(7,object.size/2)
   if object.anchor=='center' then return math.abs(object.x-x)<=half and math.abs(object.y-y)<=half end
   return x>=object.x-4 and x<=object.x+object.size+4 and y>=object.y-4 and y<=object.y+object.size+4
  end
  if object.kind=='text' then
   local width=math.min(V.width,#object.text*object.size*.6)
   if object.anchor=='center' then return math.abs(object.x-x)<=width/2+4 and math.abs(object.y-y)<=object.size/2+4 end
   return x>=object.x-4 and x<=object.x+width+4 and y>=object.y-4 and y<=object.y+object.size+4
  end
  return math.abs(object.x-x)<math.max(14,object.size) and math.abs(object.y-y)<math.max(14,object.size)
 end
 local function Shift(source,dx,dy)
  local object=Copy(source)
  local function Move(x,y)
   x,y=x+dx,y+dy
   if not Coord(x,V.width) or not Coord(y,V.height) then return end
   return x,y
  end
  object.x,object.y=Move(source.x,source.y)
  if not object.x then return end
  if source.x2 then
   object.x2,object.y2=Move(source.x2,source.y2)
   if not object.x2 then return end
  end
  if source.points then
   for index,point in ipairs(source.points) do
    local x,y=Move(point[1],point[2]);if not x then return end
    object.points[index]={x,y}
   end
  end
  return object
 end
 ui.canvas:SetScript('OnMouseDown',function(_,button)
  if not Ready() or not ui.draft then return end
  local x,y=Cursor(ui.canvas);if not x then return end
  if button=='RightButton' then
   for index=#ui.draft.objects,1,-1 do
    if Near(ui.draft.objects[index],x,y) then table.remove(ui.draft.objects,index);Draw();return end
   end
   if ui.draft.map then ui.panX,ui.panY=x,y end
   return
  end
  if button~='LeftButton' then return end
  if ui.tool=='move' then
   for index=#ui.draft.objects,1,-1 do
    if Near(ui.draft.objects[index],x,y) then
     ui.moving={index=index,x=x,y=y,source=Copy(ui.draft.objects[index])};break
    end
   end
  elseif ui.tool=='erase' then
   for index=#ui.draft.objects,1,-1 do
    if Near(ui.draft.objects[index],x,y) then table.remove(ui.draft.objects,index);Draw();break end
   end
  elseif ui.tool=='text' then
   local text=ui.text:GetText()
   if text=='' then ui.editStatus:SetText('Enter text in the field before placing it.');return end
   local object={kind='text',x=x,y=y,text=text,color=ui.color,size=math.min(48,math.max(10,ui.size*4)),anchor='center'}
   if Add(object) then ui.sizing={object=object,initial=object.size} end
  elseif ui.tool=='marker' then
   local object={kind='marker',x=x,y=y,marker=ui.marker,color=ui.color,size=math.min(48,math.max(16,ui.size*6)),anchor='center'}
   if Add(object) then ui.sizing={object=object,initial=object.size} end
  else
   local object={kind=ui.tool,x=x,y=y,color=ui.color,size=ui.size}
   if ui.tool=='stroke' then object.points={{x,y}} else object.x2=x;object.y2=y end
   if Add(object) then ui.drawing=object end
  end
 end)
 local function UpdateSizing()
  if not ui.sizing or not Ready() then return end
  local x,y=Cursor(ui.canvas);if not x then return end
  local object=ui.sizing.object
  local size=math.min(48,math.max(ui.sizing.initial,
   2*math.max(math.abs(x-object.x),math.abs(y-object.y))))
  if size~=object.size then object.size=size;Draw() end
 end
 ui.canvas:SetScript('OnUpdate',function()
  if ui.sizing then UpdateSizing();return end
  if ui.moving and Ready() then
   local x,y=Cursor(ui.canvas)
   if x then
    local object=Shift(ui.moving.source,x-ui.moving.x,y-ui.moving.y)
    if object then ui.draft.objects[ui.moving.index]=object;Draw() end
   end
   return
  end
  if ui.panX and ui.draft and ui.draft.map then
   local x,y=Cursor(ui.canvas)
   if x then
    local layer=MapArt(ui.draft.map.id)
    if layer then
     local scale=MapScale(ui.draft.map,layer)
     ui.draft.map.cx=math.max(0,math.min(1,ui.draft.map.cx-(x-ui.panX)/(layer.layerWidth*scale)))
     ui.draft.map.cy=math.max(0,math.min(1,ui.draft.map.cy-(y-ui.panY)/(layer.layerHeight*scale)))
     RenderMap(ui.canvas,ui.draft.map)
    end
    ui.panX,ui.panY=x,y
   end
   return
  end
  if not ui.drawing or not Ready() then return end
  local x,y=Cursor(ui.canvas);if not x then return end
  local object=ui.drawing
  if object.kind=='stroke' then
   local last=object.points[#object.points]
   if #object.points<400 and (x-last[1])^2+(y-last[2])^2>=9 then
    object.points[#object.points+1]={x,y}
    AppendStroke(ui.canvas,last[1],last[2],x,y,object.color,object.size)
   end
  elseif x~=object.x2 or y~=object.y2 then object.x2=x;object.y2=y;Draw() end
 end)
 ui.canvas:SetScript('OnMouseUp',function(_,button)
  if button=='RightButton' then ui.panX=nil;ui.panY=nil else UpdateSizing();ui.drawing=nil;ui.moving=nil;ui.sizing=nil end
 end)
 ui.canvas:SetScript('OnMouseWheel',function(_,delta)
  if not Ready() or not ui.draft or not ui.draft.map then return end
  ui.draft.map.zoom=math.max(.5,math.min(8,ui.draft.map.zoom*(delta>0 and 1.2 or 1/1.2)))
  RenderMap(ui.canvas,ui.draft.map)
 end)
 ui.canvas:EnableMouseWheel(true)
 ui.canvas:SetScript('OnHide',function() ui.drawing=nil;ui.moving=nil;ui.sizing=nil;ui.panX=nil;ui.panY=nil end)
 Button(editor,'Undo',18,-566,125,function()
  if ui.draft and #ui.draft.objects>0 then table.remove(ui.draft.objects);Draw() end
 end)
 Button(editor,'Clear canvas',156,-566,140,function()
  if ui.draft then ui.draft.objects={};Draw() end
 end)
 Button(editor,'Save visual note',310,-566,180,function()
  if not ui.draft then return end
  ui.drawing=nil;ui.sizing=nil;ui.panX=nil;ui.panY=nil;picker:Hide();markerPicker:Hide();ui.draft.name=ui.title:GetText()
  local ok,result=V.Save(ui.draft);ui.editStatus:SetText(ok and 'Saved in VRT.' or result)
  if ok then
   local store=V.Store()
   for _,item in ipairs(store.items) do if item.id==result then ui.viewNote=Copy(item);break end end
   editor:Hide();ui.Refresh();if addon.UpdateVisualNote then addon.UpdateVisualNote() end
  end
 end)
 Button(editor,'Cancel',802,-566,170,function() picker:Hide();markerPicker:Hide();editor:Hide() end)
 local function OpenEditor(note)
  if not Ready() then ui.status:SetText('Edit outside combat and encounters.');return end
  picker:Hide();markerPicker:Hide()
  ui.draft=Copy(note);ui.drawing=nil;ui.title:SetText(note.name);ui.text:SetText('');Tool('stroke')
  ui.editStatus:SetText('Drag to draw or size; Move drags objects. Right-click removes; right-drag empty map pans.')
  Draw();viewer:Hide();editor:Show()
 end
 Button(viewer,'Edit',18,-596,150,function()
  if ui.viewNote then OpenEditor(ui.viewNote) end
 end)
 Button(viewer,'Pop out',184,-596,150,function()
  if ui.viewNote then V.ShowPopup(ui.viewNote,true);window:Hide() end
 end)
 Button(viewer,'Close',802,-596,170,function() viewer:Hide() end)
 local function OpenView(note)
  local ok,err=V.Validate(note);if not ok then ui.status:SetText(err);return end
  ui.viewNote=Copy(note);ui.viewTitle:SetText(note.name..'  ·  '..V.MapName(note.map))
  if not Render(ui.viewCanvas,note) then ui.status:SetText('Map art is unavailable on this client; drawing is preserved.') end
  viewer:Show()
 end
 function ui.Refresh()
  local store,err=V.Store();if not store then ui.status:SetText(err);return end
  ui.offset=math.min(ui.offset,math.max(0,math.ceil(#store.items/2)-13))
  for index,row in ipairs(ui.rows) do
   row.note=store.items[ui.offset*2+index]
   if row.note then
    row.label:SetText(row.note.name..'  ·  '..V.MapName(row.note.map))
    row.selected=ui.viewNote and row.note.id==ui.viewNote.id
    row:SetBackdropColor(unpack(row.selected and H.colours.raised or H.colours.panel))
    if row.selected then row:SetBackdropBorderColor(.78,.11,.25,1)
    else row:SetBackdropBorderColor(.72,.76,.81,.35) end
    row:Show()
   else row:Hide() end
  end
  ui.summary:SetText(#store.items..' VRT visual note(s) · select a card, then Send selected, Edit or Pop out; View opens the drawing')
  local incoming=addon.VisualNoteSharing and addon.VisualNoteSharing.pending[1]
  ui.pendingText:SetText(incoming and ('From '..incoming.sender..': '..incoming.pack.note.name) or '')
  if incoming then ui.accept:Show();ui.decline:Show() else ui.accept:Hide();ui.decline:Hide() end
 end
 for index=1,13 do
  for column=1,2 do
   local slot=(index-1)*2+column
   local row;row=Button(list,'',8+(column-1)*428,-8-(index-1)*35,420,function()
    if row.note then ui.viewNote=Copy(row.note);ui.Refresh() end
   end)
   row.label:SetWidth(328);row.label:SetWordWrap(false);ui.rows[slot]=row
   row.view=Button(row,'View',350,0,62,function() if row.note then OpenView(row.note);ui.Refresh() end end)
  end
 end
 list:SetScript('OnMouseWheel',function(_,delta)
  local store=V.Store();if not store then return end
  ui.offset=math.max(0,math.min(math.max(0,math.ceil(#store.items/2)-13),ui.offset-delta));ui.Refresh()
 end)
 ui.accept=Button(page,'Accept',618,-592,118,function()
  local ok,err=addon.VisualNoteSharing.Accept(1);if not ok then ui.status:SetText(err) end;ui.Refresh()
 end)
 ui.decline=Button(page,'Decline',746,-592,118,function()
  addon.VisualNoteSharing.Decline(1);ui.Refresh()
 end)
 local sendDialog=Surface('Frame',window);ui.sendDialog=sendDialog
 sendDialog:SetSize(460,176);sendDialog:SetPoint('CENTER');sendDialog:SetFrameLevel(window:GetFrameLevel()+50)
 sendDialog:EnableMouse(true);sendDialog:Hide()
 Text(sendDialog,'Send selected visual note',16,-14,16,'text',425)
 Text(sendDialog,'Send to the raid or enter Player-Realm:',16,-44,11,'muted',425)
 ui.sendTarget=Surface('EditBox',sendDialog,'background');ui.sendTarget:SetSize(428,26)
 ui.sendTarget:SetPoint('TOPLEFT',16,-67);ui.sendTarget:SetAutoFocus(false)
 ui.sendTarget:SetFont(STANDARD_TEXT_FONT,12,'');ui.sendTarget:SetTextColor(.91,.92,.94)
 ui.sendTarget:SetTextInsets(7,7,0,0);ui.sendTarget:SetMaxLetters(100)
 local function Send(target)
  local store,err=V.Store();if not store then ui.status:SetText(err);return end
  local selected
  for _,note in ipairs(store.items) do if ui.viewNote and note.id==ui.viewNote.id then selected=note;break end end
  if not selected then ui.status:SetText('Select a saved visual note first.');return end
  local ok,message=addon.VisualNoteSharing.Send(selected,target)
  ui.status:SetText(ok and addon.VisualNoteSharing.status or message)
  if ok then sendDialog:Hide() end
 end
 Button(sendDialog,'Raid',16,-116,124,function() Send('RAID') end)
 Button(sendDialog,'Player',152,-116,124,function() Send(ui.sendTarget:GetText()) end)
 Button(sendDialog,'Cancel',288,-116,156,function() sendDialog:Hide() end)
 Button(page,'New visual note',0,-556,180,function() OpenEditor(V.New()) end)
 Button(page,'Edit selected',194,-556,180,function() if ui.viewNote then OpenEditor(ui.viewNote) else ui.status:SetText('Select a visual note first.') end end)
 Button(page,'Delete selected',388,-556,180,function()
  if not ui.viewNote then ui.status:SetText('Select a visual note first.');return end
  StaticPopupDialogs.VRT_DELETE_VISUAL_NOTE={text='Delete this VRT visual note?',button1='Delete',button2='Cancel',
   timeout=0,whileDead=true,hideOnEscape=true,OnAccept=function()
    local ok,err=V.Remove(ui.viewNote.id);ui.status:SetText(ok and 'Visual note deleted.' or err)
    if ok then ui.viewNote=nil;viewer:Hide();ui.Refresh() end
   end}
  StaticPopup_Show('VRT_DELETE_VISUAL_NOTE')
 end)
 Button(page,'Send selected',582,-556,136,function()
  if not ui.viewNote then ui.status:SetText('Select a visual note first.');return end
  ui.sendTarget:SetText('');sendDialog:Show()
 end)
 Button(page,'Pop out',730,-556,134,function()
  if not ui.viewNote then ui.status:SetText('Select a visual note first.');return end
  V.ShowPopup(ui.viewNote,true);window:Hide()
 end)
 function addon.RefreshNativeVisualNotesUI() if page:IsShown() then ui.Refresh() end end
 page:SetScript('OnShow',ui.Refresh)
 page:SetScript('OnHide',function() picker:Hide();markerPicker:Hide();sendDialog:Hide();viewer:Hide();editor:Hide() end)
 function addon.CloseNativeVisualNotes() picker:Hide();markerPicker:Hide();sendDialog:Hide();viewer:Hide();editor:Hide() end
 ui.Refresh()
end
