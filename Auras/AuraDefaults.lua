local _,addon=...
-- Default aura sounds for the current raids: the personal debuffs players
-- usually want a call-out for (spell and encounter IDs are game data). Each type
-- plays a DBM voice line, so every player hears it in their chosen DBM voice
-- pack. Loaded once (missing bosses only) and per boss with Restore defaults.
-- Co-tank and raid overview defaults need no list: an empty list already
-- shows all boss and dispellable debuffs.
local U=addon.Auras
U.defaultVoices={
 Targeted='targetyou',Spread='scatter',Soak='helpsoak',Fixate='fixateyou',Debuff='debuffyou',Bomb='bombyou',
 HealAbsorb='absorbyou',DropPool='poolyou',Move='keepmove',Clear='runout',Done='safenow',Break='breakchain',
 Feather='carefly',Obelisk='movetopillar',Boss='movetoboss',Collect='gatheritem',Rune='runeyou',
 Fire='debuffyou',Frost='frostyou',Light='lightyou',Void='voidyou',Red='redyou',Blue='blueyou',
 North='north',South='south',East='east',West='west',Left='left',Right='right',
 Ranged='fixateyou',Suck='debuffyou',Countdown='debuffyou',
}
-- {encounterID, name, {spellID, type, 'removed' or nil}, ...}
U.defaultSounds={
 {3176,'Imperator Averzian',{1260203,'Soak'},{1249265,'Soak'},{1280023,'Targeted'},{1283069,'Fixate'}},
 {3177,'Vorasius',{1254113,'Fixate'}},
 {3179,'Fallen-King Salhadaar',{1248697,'Debuff'},{1268992,'Targeted'},{1253024,'Targeted'}},
 {3178,'Vaelgor & Ezzorak',{1255612,'Targeted'},{1270497,'Spread'}},
 {3180,'Lightblinded Vanguard',{1248994,'Targeted'},{1248985,'Targeted'},{1246487,'Spread'},{1248721,'HealAbsorb'}},
 {3181,'Crown of the Cosmos',{1232470,'Obelisk'},{1260027,'Obelisk'},{1239111,'Break'},{1233602,'Targeted'},{1237623,'Targeted'},{1259861,'Targeted'},{1283236,'DropPool'},{1238708,'Feather'}},
 {3306,'Chimaerus',{1257087,'Clear'},{1264756,'Targeted'}},
 {3182,"Belo'ren",{1241339,'Void'},{1241292,'Light'},{1242091,'Targeted'},{1241992,'Targeted'}},
 {3183,'Midnight Falls',{1284527,'Targeted'},{1281184,'Spread'},{1249609,'Rune'},{1285510,'Targeted'},{1279512,'Targeted'},{1286294,'Red'},{1284984,'Blue'}},
 {3159,'Rotmire',{1222088,'Spread'},{1221639,'Boss'},{1299508,'Ranged'}},
 {3379,'Nymrissa Wavecaller',{1258901,'Targeted'},{1313393,'Debuff'}},
 {3470,"Nek'zali the Soulcoiler",{1306666,'Targeted'},{1294933,'Clear'},{1287427,'Debuff'}},
 {3445,'Entombed Sentinels',{1288260,'Targeted'},{1288297,'DropPool'},{1288297,'Move','removed'},{1296880,'Debuff'}},
 {3455,'Vashnik the Malignant',{1295224,'Suck'},{1294994,'Move'},{1281913,'Targeted'}},
 {3497,'The Lost Explorers',{1295886,'Fire'},{1295935,'Frost'},{1297625,'Bomb'},{1296092,'Targeted'},{1296025,'Targeted'}},
 {3420,'Sszorak',{1305963,'Debuff'},{1285453,'North'},{1285425,'South'},{1297096,'West'},{1297111,'East'},{1305621,'Targeted'},{1297707,'Left'},{1299899,'Right'}},
 {3421,'The Twin Fangs',{1293979,'Targeted'},{1290814,'Spread'}},
 {3429,'The Coiled Altar',{1283485,'Targeted'},{1299266,'Targeted'},{1297435,'Targeted'},{1282419,'Countdown'},{1310498,'Countdown'},{1282419,'Move','removed'},{1310498,'Move','removed'},
  {1286901,'Bomb'},{1310881,'Bomb'},{1286837,'Collect'},{1286837,'Done','removed'},{1285911,'Fixate'}},
 {3492,"Ula'tek",{1305163,'Targeted'},{1293046,'Targeted'},{1312967,'Spread'},{1301118,'Debuff'},{1311611,'Break'}},
}
-- Raid (or lair) of each boss, in picker order (current season first).
U.raids={
 {"The Unbinding of Kith'ix",{3513}}, -- 12.1.5
 {'The Venomous Abyss',{3445,3470,3420,3429,3497,3421,3492,3455}},
 {'The Voidspire',{3176,3177,3179,3178,3180,3181}},
 {"March on Quel'Danas",{3182,3183}},
 {'The Dreamrift',{3306}},
 {'Sporefall',{3159}},
 {'The Tidebound Grotto',{3379}},
}
U.raidOf={};for _,raid in ipairs(U.raids) do for _,id in ipairs(raid[2]) do U.raidOf[id]=raid[1] end end
-- Default sound entries for a boss (nil when there are none).
function U.DefaultsFor(bossID)
 for _,boss in ipairs(U.defaultSounds) do
  if boss[1]==bossID then
   local sounds={}
   for index=3,#boss do
    local entry=boss[index]
    sounds[#sounds+1]={spell=entry[1],unit='player',when=entry[3] or 'applied',sound='DBM:'..U.defaultVoices[entry[2]]}
   end
   return sounds,boss[2]
  end
 end
end
local function SameSound(a,b) return a.spell==b.spell and a.unit==b.unit and a.when==b.when end
-- Add the defaults a boss is missing (keeps your own sounds and changes).
function U.RestoreDefaults(bossID)
 local defaults,name=U.DefaultsFor(bossID)
 if not defaults then return false,'No default sounds for this boss.' end
 local config=U.Boss(bossID,true,name)
 local added=0
 for _,sound in ipairs(defaults) do
  local exists=false;for _,mine in ipairs(config.sounds) do if SameSound(mine,sound) then exists=true end end
  if not exists then config.sounds[#config.sounds+1]=sound;added=added+1 end
 end
 if added>0 then U.Touched(config) end
 return added,name
end
-- First load: every boss without a config gets its defaults. Version 1 (not
-- the current time) so clients that seed the same defaults already match.
function U.SeedDefaults()
 local store=U.Store()
 if store.seeded then return 0 end
 local count=0
 for _,boss in ipairs(U.defaultSounds) do
  if not store.bosses[boss[1]] then
   local sounds,name=U.DefaultsFor(boss[1])
   store.bosses[boss[1]]={name=name,sounds=sounds,overview={},cotank={},updated=1}
   count=count+1
  end
 end
 store.seeded=1;U.dirty=true
 return count
end
-- Bosses grouped by raid for the picker: {{name=raid, bosses={{id,name},...}},...}.
function U.RaidList()
 local groups,byName={},{}
 for _,raid in ipairs(U.raids) do local group={name=raid[1],bosses={}};groups[#groups+1]=group;byName[raid[1]]=group end
 for _,boss in ipairs(U.BossList()) do
  local raidName=U.raidOf[boss.id] or 'Other'
  if not byName[raidName] then byName[raidName]={name=raidName,bosses={}};groups[#groups+1]=byName[raidName] end
  local list=byName[raidName].bosses;list[#list+1]=boss
 end
 -- Bosses in encounter order within each known raid.
 for _,raid in ipairs(U.raids) do
  local order={};for index,id in ipairs(raid[2]) do order[id]=index end
  table.sort(byName[raid[1]].bosses,function(a,b) return (order[a.id] or 99)<(order[b.id] or 99) end)
 end
 local list={};for _,group in ipairs(groups) do if #group.bosses>0 then list[#list+1]=group end end
 return list
end
-- Bosses listed before they have defaults or a timeline.
U.bossNames={[3513]="Kith'ix"}
-- Boss names for the picker (defaults, timelines and anything configured).
function U.BossList()
 local names={}
 for id,name in pairs(U.bossNames) do names[id]=name end
 for _,boss in ipairs(U.defaultSounds) do names[boss[1]]=boss[2] end
 for id,boss in pairs(addon.AssignmentTimelines or {}) do if type(boss)=='table' and boss.name then names[id]=boss.name end end
 for id,config in pairs(U.Store().bosses) do if id~=0 and config.name then names[id]=names[id] or config.name end end
 local list={};for id,name in pairs(names) do list[#list+1]={id=id,name=name} end
 table.sort(list,function(a,b) return a.name<b.name end)
 return list
end
