local _, addon = ...
local attempted = {}

function addon.GetTanks()
    local tanks = {}
    if InCombatLockdown() or not IsInRaid() then return tanks end
    for i = 1, GetNumGroupMembers() do
        local unit = 'raid'..i
        if UnitGroupRolesAssigned(unit) == 'TANK' then
            local name = GetUnitName(unit, true)
            if name then
                tanks[#tanks+1] = {
                    unit=unit, name=name,
                    leader=UnitIsGroupLeader(unit),
                    assistant=UnitIsGroupAssistant(unit),
                    mainTank=GetPartyAssignment('MAINTANK', unit, true),
                }
            end
        end
    end
    return tanks
end

function addon.UpdateTankAssist()
    if InCombatLockdown() then return end
    local db = VincibilityRaidToolsDB
    if not db or not db.autoTankAssist or not IsInRaid() or not UnitIsGroupLeader('player') then return end
    local _, instanceType = IsInInstance()
    if instanceType == 'pvp' or instanceType == 'arena' or (IsPartyLFG and IsPartyLFG()) then return end
    local promote = C_PartyInfo and C_PartyInfo.PromoteToAssistant or PromoteToAssistant
    if type(promote) ~= 'function' then return end
    local present = {}
    for _,tank in ipairs(addon.GetTanks()) do
        present[tank.name] = true
        -- One attempt per tank/role tenure: no repeated promotion requests or
        -- fighting an officer's subsequent manual demotion.
        if not tank.leader and not tank.assistant and not attempted[tank.name] then
            attempted[tank.name] = true
            local ok = pcall(promote, tank.name, true)
            if not ok then print('Vincibility: could not grant raid assist to '..tank.name..'. Check raid permissions.') end
        end
    end
    for name in pairs(attempted) do if not present[name] then attempted[name]=nil end end
end

function addon.ResetTankAssistAttempts()
    attempted = {}
end
