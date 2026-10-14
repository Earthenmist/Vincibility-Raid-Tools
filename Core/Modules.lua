local _,addon=...
-- Modules the player can switch off (Settings > Modules). A disabled module
-- leaves the sidebar and stops its background work (auto-shown notes,
-- reminders, ready-check windows, aura sounds...); its saved data is kept, so
-- enabling it again restores everything. Personal: never synced.
addon.modules={
 {key='notes',page='Notes',name='Notes',text='Raid and boss text notes; they can open by themselves for the raid leader.'},
 {key='visual',page='Visual Notes',name='Visual Notes',text='Drawn boss plans on the map; they can open when you reach the boss.'},
 {key='reminders',page='Reminders',name='Reminders',text='Timed and triggered reminders with bars, text, icons and sounds.'},
 {key='assignments',page='Assignments',name='Assignments',text='Boss timelines, cooldown and action assignments, test pulls and the leader view.'},
 {key='groups',page='Groups',name='Groups',text='Group layouts and raid invites from the calendar.'},
 {key='readycheck',page='Ready Check',name='Ready Check',text='Raid overview, personal warnings, chat report and consumables on ready checks.'},
 {key='auras',page='Auras',name='Auras',text='Aura sounds, raid debuff overview and co-tank debuffs.'},
 {key='panel',name='Raid panel',text='The compact raid panel and its crest icon (ready check, pull, markers, layouts).'},
}
function addon.ModuleEnabled(key)
 local db=VincibilityRaidToolsDB
 return not (db and type(db.modules)=='table' and db.modules[key]==false)
end
-- Page name -> module key (pages without a module are always shown).
function addon.ModuleForPage(page)
 for _,module in ipairs(addon.modules) do if module.page==page then return module.key end end
end
local hooks={}
-- Modules register what to do when they are switched on or off.
function addon.OnModuleChanged(key,fn) hooks[key]=hooks[key] or {};table.insert(hooks[key],fn) end
function addon.SetModuleEnabled(key,on)
 if InCombatLockdown() then return false,'Change modules out of combat.' end
 local known=false;for _,module in ipairs(addon.modules) do if module.key==key then known=true end end
 if not known then return false,'Unknown module.' end
 VincibilityRaidToolsDB=VincibilityRaidToolsDB or {}
 local db=VincibilityRaidToolsDB
 if type(db.modules)~='table' then db.modules={} end
 if on then db.modules[key]=nil else db.modules[key]=false end
 for _,fn in ipairs(hooks[key] or {}) do pcall(fn,on and true or false) end
 for _,fn in ipairs(hooks['*'] or {}) do pcall(fn,key,on and true or false) end
 return true
end
-- What each module stops or restarts when switched.
addon.OnModuleChanged('notes',function() if addon.UpdateNativeTextNote then addon.UpdateNativeTextNote() end end)
addon.OnModuleChanged('visual',function(on) if on and addon.UpdateVisualNote then addon.UpdateVisualNote() elseif addon.NativeVisualNotes and addon.NativeVisualNotes.HidePopup then addon.NativeVisualNotes.HidePopup() end end)
addon.OnModuleChanged('reminders',function() local R=addon.Reminders;if R and R.Rebuild and not InCombatLockdown() then R.Rebuild() end;if addon.ReminderDisplay and addon.ReminderDisplay.Clear then addon.ReminderDisplay.Clear() end end)
addon.OnModuleChanged('assignments',function(on) local A=addon.Assignments;if not on and A and A.Runtime and A.Runtime.running then A.Runtime.Stop() end end)
addon.OnModuleChanged('auras',function() local U=addon.Auras;if U then U.dirty=true;U.RegisterSounds() end;if addon.AuraDisplays then addon.AuraDisplays.Refresh() end end)
addon.OnModuleChanged('panel',function() if addon.UpdateRaidPanelVisibility then addon.UpdateRaidPanelVisibility() end end)
