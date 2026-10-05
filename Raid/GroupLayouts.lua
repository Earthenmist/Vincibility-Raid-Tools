local _, addon = ...
-- Roster-based group layouts.
local layouts={{id='soak3',name='1+2+3 Soak',limit=30},{id='odd20',name='1+3 / 2+4',limit=20},{id='odd30',name='1+3+5 / 2+4+6',limit=30},
 {id='healers',name='One healer per group',limit=30},{id='rolesort',name='Role sort',limit=30},{id='meleeranged',name='Melee / ranged',limit=30}}
local roles={TANK=1,HEALER=2,DAMAGER=3}
local status=''
local operation,applied
local function Known(layout) for _,v in ipairs(layouts) do if v==layout then return true end end end
function addon.GetGroupPresets()
 local list={};for _,v in ipairs(layouts) do list[#list+1]={name=v.name,preset=v} end;return list
end
local function Sorted(roster)
 local list={};for _,v in ipairs(roster) do list[#list+1]=v end
 table.sort(list,function(a,b)
  if a.role~=b.role then return roles[a.role]<roles[b.role] end
  if a.class~=b.class then return a.class<b.class end
  return a.id<b.id
 end);return list
end
local function Split(list,count)
 local teams={}
 for i=1,count do teams[i]={members={},roles={},classes={},capacity=math.floor(#list/count)+(i<=#list%count and 1 or 0)} end
 for _,p in ipairs(list) do
  local best,score
  for i,t in ipairs(teams) do
   if #t.members<t.capacity then
    local s=(t.roles[p.role] or 0)*10000+(t.classes[p.class] or 0)*100+#t.members
    if not score or s<score then best,score=i,s end
   end
  end
  local t=teams[best];t.members[#t.members+1]=p
  t.roles[p.role]=(t.roles[p.role] or 0)+1;t.classes[p.class]=(t.classes[p.class] or 0)+1
 end
 -- Initial role-by-role placement can strand mixed-role classes together.
 -- Swap equal-role members only: preserve every team's size and role counts,
 -- while strictly reducing the sum of squared class counts across teams.
 while true do
  local best,bestGain=nil,0
  for ai=1,#teams-1 do for bi=ai+1,#teams do
   local a,b=teams[ai],teams[bi]
   for i,p in ipairs(a.members) do for j,q in ipairs(b.members) do
    if p.role==q.role and p.class~=q.class then
     local ac,bc=a.classes[p.class] or 0,b.classes[p.class] or 0
     local ad,bd=a.classes[q.class] or 0,b.classes[q.class] or 0
     local gain=2*(ac-bc+bd-ad-2)
     if gain>bestGain then bestGain=gain;best={a=a,b=b,i=i,j=j,p=p,q=q} end
    end
   end end
  end end
  if not best then break end
  local a,b,p,q=best.a,best.b,best.p,best.q
  a.members[best.i],b.members[best.j]=q,p
  a.classes[p.class]=a.classes[p.class]-1;b.classes[p.class]=(b.classes[p.class] or 0)+1
  b.classes[q.class]=b.classes[q.class]-1;a.classes[q.class]=(a.classes[q.class] or 0)+1
 end
 return teams
end
-- Place players into the given groups (5 each): fewest of the same role, then
-- of the same class, then the emptiest group. The list is pre-sorted, so the
-- result does not depend on roster order.
local function Fill(list,groups,plan)
 local size,role,class={},{},{}
 for _,g in ipairs(groups) do size[g]=0;role[g]={};class[g]={} end
 for _,p in ipairs(list) do
  local best,score
  for order,g in ipairs(groups) do
   if size[g]<5 then
    local s=(role[g][p.role] or 0)*1000000+(class[g][p.class] or 0)*10000+size[g]*100+order
    if not score or s<score then best,score=g,s end
   end
  end
  if not best then return false end
  plan[p.id]=best;size[best]=size[best]+1
  role[best][p.role]=(role[best][p.role] or 0)+1;class[best][p.class]=(class[best][p.class] or 0)+1
 end
 return true
end
local function Range(from,count) local list={};for g=from,from+count-1 do list[#list+1]=g end;return list end
-- Melee / ranged: tanks and melee DPS in groups 1-3, ranged DPS in 4-6;
-- healers fill whichever side is smaller. p.range must be set for DPS.
local function MeleeRanged(active,plan)
 local melee,ranged,healers,unknown={},{},{},{}
 for _,p in ipairs(active) do
  if p.role=='HEALER' then healers[#healers+1]=p
  elseif p.role=='TANK' or p.range=='MELEE' then melee[#melee+1]=p
  elseif p.range=='RANGED' then ranged[#ranged+1]=p
  else unknown[#unknown+1]=p.name or '?' end
 end
 if #unknown>0 then table.sort(unknown);return nil,'Spec unknown for '..table.concat(unknown,', ')..'. Add them to the team roster or stand near them, then try again.' end
 for _,p in ipairs(healers) do
  if #melee<#ranged and #melee<15 or #ranged>=15 then melee[#melee+1]=p else ranged[#ranged+1]=p end
 end
 if #melee>15 then return nil,'More than 15 tanks and melee: groups 1–3 are full.' end
 if #ranged>15 then return nil,'More than 15 ranged: groups 4–6 are full.' end
 table.sort(melee,function(a,b) if a.role~=b.role then return roles[a.role]<roles[b.role] end;if a.class~=b.class then return a.class<b.class end;return a.id<b.id end)
 table.sort(ranged,function(a,b) if a.role~=b.role then return roles[a.role]<roles[b.role] end;if a.class~=b.class then return a.class<b.class end;return a.id<b.id end)
 Fill(melee,Range(1,math.max(1,math.ceil(#melee/5))),plan)
 Fill(ranged,Range(4,math.max(1,math.ceil(#ranged/5))),plan)
 return plan
end
function addon.PlanRaidGroups(layout,roster)
 if not Known(layout) then return nil,'Unknown layout. Reopen the list.' end
 local active,seen={},{}
 for _,p in ipairs(roster) do
  if not p.id or seen[p.id] or not p.group or p.group<1 or p.group>8 then return nil,'Raid roster is incomplete. Try again.' end
  seen[p.id]=true
  if p.group<=6 then
   if not roles[p.role] then return nil,(p.name or 'A player')..' needs a tank, healer or DPS role.' end
   if not p.class then return nil,'Class data is incomplete. Try again.' end
   active[#active+1]=p
  end
 end
 if #active==0 then return nil,'No active players in groups 1–6.' end
 if #active>layout.limit then return nil,'This layout supports up to '..layout.limit..' players in groups 1–6.' end
 local plan={};active=Sorted(active)
 if layout.id=='soak3' then
  local dps,support={},{}
  for _,p in ipairs(active) do local t=p.role=='DAMAGER' and dps or support;t[#t+1]=p end
  if #dps==0 then return nil,'No DPS available for the soak groups.' end
  if #dps>15 then return nil,'More than 15 DPS: groups 1–3 cannot hold all soakers.' end
  if #support>15 then return nil,'More than 15 tanks/healers: groups 4–6 are full.' end
  for i,t in ipairs(Split(dps,3)) do for _,p in ipairs(t.members) do plan[p.id]=i end end
  for i,p in ipairs(support) do plan[p.id]=4+math.floor((i-1)/5) end
 elseif layout.id=='healers' then
  -- Healers (and tanks) spread one per group across the groups in use.
  Fill(active,Range(1,math.ceil(#active/5)),plan)
 elseif layout.id=='rolesort' then
  for i,p in ipairs(active) do plan[p.id]=1+math.floor((i-1)/5) end
 elseif layout.id=='meleeranged' then
  local result,err=MeleeRanged(active,plan);if not result then return nil,err end
 else
  for side,t in ipairs(Split(active,2)) do for i,p in ipairs(t.members) do plan[p.id]=side+2*math.floor((i-1)/5) end end
 end;return plan,#active
end
local function ReadRoster()
 local list={}
 for i=1,GetNumGroupMembers() do
  local unit='raid'..i
  local name,_,group,_,_,class,_,online,_,_,_,rosterRole=GetRaidRosterInfo(i)
  local id=UnitGUID(unit)
  if not name or not id or not group then return nil,'Raid roster is updating. Try again.' end
  local role=UnitGroupRolesAssigned(unit);if not roles[role] then role=rosterRole end
  list[#list+1]={id=id,name=name,group=group,class=class,role=role,index=i,unit=unit,online=online}
 end;return list
end
-- Melee or ranged for each DPS: by class where it is fixed, then the player's
-- own spec, the team roster's spec, then a spec read by inspecting.
local fixedRange={MAGE='RANGED',WARLOCK='RANGED',EVOKER='RANGED',PRIEST='RANGED',ROGUE='MELEE',WARRIOR='MELEE',DEATHKNIGHT='MELEE',PALADIN='MELEE',MONK='MELEE'}
local specNames={DEMONHUNTER={havoc='MELEE',devourer='RANGED'},DRUID={feral='MELEE',balance='RANGED'},
 HUNTER={survival='MELEE',['beast mastery']='RANGED',marksmanship='RANGED'},SHAMAN={enhancement='MELEE',elemental='RANGED'}}
local inspected={} -- [guid]=specID, this session
local function SpecRange(specID)
 local A=addon.Assignments
 if A and A.meleeSpecs and A.meleeSpecs[specID] then return 'MELEE' end
 if A and A.rangedSpecs and A.rangedSpecs[specID] then return 'RANGED' end
end
function addon.ResolveRange(p)
 if p.role~='DAMAGER' then return nil end
 if fixedRange[p.class] then return fixedRange[p.class] end
 local A=addon.Assignments
 if p.unit and UnitIsUnit and UnitIsUnit(p.unit,'player') and A and A.PlayerRange then return A.PlayerRange() end
 local roster=A and A.Roster and A.Roster()
 local short=p.name and p.name:gsub('%-.*$',''):lower()
 for _,m in ipairs(roster and roster.members or {}) do
  if short and m.name and m.name:lower()==short and m.spec then
   local range=specNames[p.class] and specNames[p.class][m.spec:lower()];if range then return range end
  end
 end
 if inspected[p.id] then return SpecRange(inspected[p.id]) end
 if p.unit and GetInspectSpecialization then
  local ok,specID=pcall(GetInspectSpecialization,p.unit)
  if ok and type(specID)=='number' and specID>0 then inspected[p.id]=specID;return SpecRange(specID) end
 end
end
local function Signature(roster,includeGroups)
 local t={};for _,p in ipairs(roster) do t[#t+1]=p.id..':'..tostring(p.role)..':'..tostring(p.class)..':'..(includeGroups and p.group or (p.group<=6 and 'active' or 'bench')) end
 table.sort(t);return table.concat(t,'|')
end
local function Allowed()
 if InCombatLockdown() then return false,'Wait until combat ends.' end
 if not IsInRaid() then return false,'Join a raid group first.' end
 if not UnitIsGroupLeader('player') and not UnitIsGroupAssistant('player') then return false,'Raid leader or assistant required.' end
 for i=1,GetNumGroupMembers() do if UnitAffectingCombat('raid'..i) then return false,'A raid member is in combat. Group changes stopped.' end end
 return true
end
-- Why layouts cannot be applied right now (nil when they can); the Groups page greys its buttons.
function addon.GroupLayoutBlocked()
 local ok,err=Allowed();if ok then return nil end;return err
end
local function Finish(message,roster)
 local op=operation;operation=nil;status=message
 if roster then applied={signature=Signature(roster,true),name=op.layout.name} else applied=nil end
 print('Vincibility: '..message)
end
local function GroupMap(roster) local map={};for _,p in ipairs(roster) do map[p.id]=p.group end;return map end
local function Matches(map,roster) for _,p in ipairs(roster) do if map[p.id]~=p.group then return false end end;return true end
local function Step()
 local op=operation;if not op then return end
 local ok,err=Allowed();if not ok then Finish(err);return end
 local roster;roster,err=ReadRoster();if not roster then Finish(err);return end
 if Signature(roster,false)~=op.signature then Finish('Roster or roles changed. Select the layout again.');return end
 if GetTime()-op.started>30 then Finish('Group changes timed out. Check the roster and try again.');return end
 if op.pending then
  if Matches(op.pending,roster) then op.expected=op.pending;op.pending=nil
  else if GetTime()-op.sent>3 then Finish('Group change was not confirmed. Check the roster.');end;return end
 end
 if not Matches(op.expected,roster) then Finish('Groups changed elsewhere. Select the layout again.');return end
 local sizes={0,0,0,0,0,0,0,0};for _,p in ipairs(roster) do sizes[p.group]=sizes[p.group]+1 end
 local moving;for _,p in ipairs(roster) do if op.plan[p.id] and op.plan[p.id]~=p.group then moving=p;break end end
 if not moving then Finish('Applied '..op.layout.name..' to '..op.count..' players.',roster);return end
 local target=op.plan[moving.id];local nextMap=GroupMap(roster);nextMap[moving.id]=target
 local swap
 if sizes[target]>=5 then
  for _,p in ipairs(roster) do if p.group==target and op.plan[p.id] and op.plan[p.id]~=p.group then swap=p;break end end
  if not swap then Finish('No safe group move available. Check the roster.');return end
  nextMap[swap.id]=moving.group
 end
 -- Resolve indices anew, then wait for acknowledgement before another move.
 op.pending=nextMap;op.sent=GetTime()
 if swap then ok,err=pcall(SwapRaidSubgroup,moving.index,swap.index) else ok,err=pcall(SetRaidSubgroup,moving.index,target) end
 if not ok then Finish('WoW rejected the group change. Check permissions and combat.');return end
 status='Applying '..op.layout.name..'…'
end
-- Inspect queue: read unknown DPS specs (one at a time), then apply again.
local inspecting
local function NextInspect()
 local job=inspecting;if not job then return end
 if job.current and ClearInspectPlayer then pcall(ClearInspectPlayer) end
 job.current=table.remove(job.queue,1)
 if not job.current then inspecting=nil;addon.ApplyGroupPreset(job.layout,true);return end
 job.sent=GetTime()
 if not (CanInspect and CanInspect(job.current.unit)) or not pcall(NotifyInspect,job.current.unit) then job.sent=-100 end
end
function addon.OnInspectReady(guid)
 local job=inspecting;if not job or not job.current or guid~=job.current.id then return end
 local ok,specID=pcall(GetInspectSpecialization,job.current.unit)
 if ok and type(specID)=='number' and specID>0 then inspected[job.current.id]=specID end
 NextInspect()
end
function addon.ApplyGroupPreset(layout,inspectedOnce)
 if operation or inspecting then return false,'Group changes are still in progress.' end
 local ok,err=Allowed();if not ok then status=err;return false,err end
 local roster;roster,err=ReadRoster();if not roster then status=err;return false,err end
 if layout and layout.id=='meleeranged' then
  local queue={}
  for _,p in ipairs(roster) do
   if p.group<=6 then p.range=addon.ResolveRange(p);if p.role=='DAMAGER' and not p.range and p.online then queue[#queue+1]=p end end
  end
  if #queue>0 and not inspectedOnce and NotifyInspect then
   applied=nil;inspecting={layout=layout,queue=queue};status='Checking specs for '..#queue..' player'..(#queue==1 and '' or 's')..'…'
   NextInspect();return true,status
  end
 end
 -- A failed attempt replaces any earlier applied state, so its message stays visible.
 local plan,count=addon.PlanRaidGroups(layout,roster);if not plan then applied=nil;status=count;return false,count end
 operation={layout=layout,plan=plan,count=count,signature=Signature(roster,false),expected=GroupMap(roster),started=GetTime()}
 applied=nil;status='Applying '..layout.name..'…';Step();return true,status
end
function addon.GetGroupStatus()
 if applied and not operation then
  local roster=IsInRaid() and ReadRoster()
  if not roster or Signature(roster,true)~=applied.signature then applied=nil;status='Roster changed — select a layout to update.' end
 end;return status
end
function addon.CancelGroupChanges() if operation then Finish('Group changes cancelled. Check current groups.') end end
local timer=CreateFrame('Frame');local elapsed=0
timer:SetScript('OnUpdate',function(_,dt)
 if not operation and not inspecting then return end
 elapsed=elapsed+dt;if elapsed<0.2 then return end;elapsed=0
 if inspecting then
  if InCombatLockdown() then inspecting=nil;status='Wait until combat ends.';return end
  if GetTime()-inspecting.sent>2.5 then NextInspect() end -- no answer: out of range or offline
  return
 end
 Step()
end)
if timer.RegisterEvent then timer:RegisterEvent('INSPECT_READY') end
timer:SetScript('OnEvent',function(_,event,guid) if event=='INSPECT_READY' then addon.OnInspectReady(guid) end end)
SLASH_VINCGROUPS1='/vincgroups'
SlashCmdList.VINCGROUPS=function(message)
 if (message or ''):lower()=='stop' then addon.CancelGroupChanges()
 else print('Vincibility: '..addon.GetGroupStatus()..' Select a layout in /vinc. /vincgroups stop cancels pending moves.') end
end
