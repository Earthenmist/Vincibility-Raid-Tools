local _,addon=...
-- Raid-planning cooldowns per class, grouped for the assignment picker.
-- Original curated list of long-standing spell IDs. Entries whose spell the
-- client does not know are hidden at runtime, so a retired or mistyped ID
-- never shows. role limits a spell to players in that group role (healer
-- cooldowns only for healers, taunts only for tanks); with no assigned role
-- every spell shows. '!HEALER' hides a spell from healers (interrupts that
-- healing specs lack). Each class's interrupt is listed first in Utility.
local A=addon.Assignments
A.cooldownCategories={{'raid','Raid CD'},{'external','Externals'},{'movement','Movement'},{'utility','Utility'}}
local H,T,D,NH='HEALER','TANK','DAMAGER','!HEALER'
local catalogue={
 DEATHKNIGHT={{56222,'utility',T},{47528,'utility'},{48707,'utility'},{51052,'raid'},{49576,'utility'},{61999,'utility'}},
 DEMONHUNTER={{185245,'utility',T},{183752,'utility'},{196718,'raid'},{179057,'utility'}},
 DRUID={{6795,'utility',T},{106839,'utility',NH},{78675,'utility',D},{740,'raid',H},{33891,'raid',H},{102342,'external',H},{29166,'external'},{106898,'movement'},{102793,'utility'},{20484,'utility'}},
 EVOKER={{351338,'utility'},{363534,'raid',H},{359816,'raid',H},{374227,'raid'},{357170,'external',H},{370665,'utility'},{374968,'movement'},{390386,'utility'}},
 HUNTER={{147362,'utility'},{187707,'utility'},{53480,'external'},{264667,'utility'},{34477,'utility'}},
 MAGE={{2139,'utility'},{414660,'raid'},{80353,'utility'},{414664,'utility'}},
 MONK={{115546,'utility',T},{116705,'utility',NH},{115310,'raid',H},{116849,'external',H},{116844,'utility'}},
 PALADIN={{62124,'utility',T},{96231,'utility',NH},{31821,'raid',H},{31884,'raid',H},{6940,'external'},{1022,'external'},{1044,'external'},{633,'external'},{190784,'movement'}},
 PRIEST={{15487,'utility',D},{62618,'raid',H},{47536,'raid',H},{64843,'raid',H},{200183,'raid',H},{15286,'raid'},{33206,'external',H},{47788,'external',H},{10060,'external'},{73325,'utility'},{32375,'utility'}},
 ROGUE={{1766,'utility'},{114018,'utility'}},
 SHAMAN={{57994,'utility'},{98008,'raid',H},{108280,'raid',H},{114052,'raid',H},{198838,'raid',H},{192077,'movement'},{2825,'utility'},{32182,'utility'},{192058,'utility'},{8143,'utility'}},
 WARLOCK={{19647,'utility'},{89766,'utility',D},{20707,'utility'},{111771,'movement'},{30283,'utility'}},
 WARRIOR={{355,'utility',T},{6552,'utility'},{97462,'raid'},{3411,'external'}},
}
A.cooldownCatalogue=catalogue
local known={}
local function Known(spellID)
 if known[spellID]==nil then
  local info=A.SpellInfo and A.SpellInfo(spellID)
  known[spellID]=info and {name=info.name,icon=info.iconID} or false
 end
 return known[spellID]
end
-- Cooldowns for a class/role, optionally one category: {spellID,category,name,icon}.
function A.CooldownsFor(class,role,category)
 local list={}
 for _,spell in ipairs(catalogue[class] or {}) do
  local spellID,kind,needs=spell[1],spell[2],spell[3]
  local allowed=not needs or not role or role=='NONE' or role==needs or (needs:sub(1,1)=='!' and role~=needs:sub(2))
  if (not category or category==kind) and allowed then
   local info=Known(spellID)
   if info then list[#list+1]={spellID=spellID,category=kind,name=info.name,icon=info.icon} end
  end
 end
 return list
end
function A.ResetCooldownCache() known={} end
