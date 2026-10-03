-- Split raid: divide the current raid into two balanced sides using the built-in damage meter
local _, Extras = ...

-- Side layouts. Each returns the group numbers for side 1 and side 2, given groups needed per side.
Extras.SplitLayouts = {
    { key = "oddeven", label = "Alternating (1, 3 vs 2, 4)",
      groups = function(n)
          local a, b = {}, {}
          for i = 1, n do a[i], b[i] = 2 * i - 1, 2 * i end
          return a, b
      end },
    { key = "consecutive", label = "Grouped (1-2 vs 3-4)",
      groups = function(n)
          local a, b = {}, {}
          for i = 1, n do a[i], b[i] = i, n + i end
          return a, b
      end },
}

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Overall-session per-second values from Blizzard's damage meter, keyed by Extras.Key(name).
-- Out of combat the source list is readable; in combat names/values can be secret, so skip those.
local function MeterValues(meterType)
    local out = {}
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum.DamageMeterSessionType) then return out end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Overall, meterType)
    if not (ok and session and session.combatSources) then return out end
    for _, src in ipairs(session.combatSources) do
        local name, v = src.name, src.amountPerSecond
        if name and v and not IsSecret(name) and not IsSecret(v) and type(v) == "number" then
            out[Extras.Key(name)] = v
        end
    end
    return out
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

-- Raid members with role and meter value (HPS for healers, DPS for everyone else)
function Extras:GetSplitPlayers()
    if not (Enum.DamageMeterType) then return nil, "The damage meter isn't available." end
    local dps = MeterValues(Enum.DamageMeterType.DamageDone)
    local hps = MeterValues(Enum.DamageMeterType.HealingDone)
    local players, withData = {}, 0
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
        if name then
            local role = UnitGroupRolesAssigned("raid" .. i)
            if not ROLE_ORDER[role] then role = "DAMAGER" end
            local key = self.Key(name)
            local value = (role == "HEALER" and hps[key]) or (role ~= "HEALER" and dps[key]) or nil
            if value then withData = withData + 1 end
            players[#players + 1] = { name = name, class = classFile, role = role,
                                      dps = dps[key] or 0, hps = hps[key] or 0, value = value or 0, hasData = value ~= nil }
        end
    end
    return players, withData
end

-- Balance players into two sides: tanks and healers are spread evenly first, then within each role
-- the strongest remaining player goes to the side with the lower total for that role.
function Extras.BalanceSides(players)
    local sides = { { players = {}, count = 0 }, { players = {}, count = 0 } }
    local cap = { math.ceil(#players / 2), math.floor(#players / 2) }
    local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
    for _, p in ipairs(players) do table.insert(byRole[p.role], p) end

    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local list = byRole[role]
        table.sort(list, function(x, y) return x.value > y.value end)
        local roleCap = math.ceil(#list / 2)
        local roleCount, roleSum = { 0, 0 }, { 0, 0 }
        for i, p in ipairs(list) do
            -- the odd one out of a role goes to the smaller side, so spare tanks/healers don't stack up
            local spare = i == #list and #list % 2 == 1
            local best
            for s = 1, 2 do
                if sides[s].count < cap[s] and roleCount[s] < roleCap then
                    local better
                    if not best then better = true
                    elseif spare and sides[s].count ~= sides[best].count then better = sides[s].count < sides[best].count
                    elseif roleSum[s] ~= roleSum[best] then better = roleSum[s] < roleSum[best]
                    else better = sides[s].count < sides[best].count end
                    if better then best = s end
                end
            end
            best = best or (sides[1].count < cap[1] and 1 or 2)   -- role cap clashed with side size
            table.insert(sides[best].players, p)
            sides[best].count = sides[best].count + 1
            roleCount[best], roleSum[best] = roleCount[best] + 1, roleSum[best] + p.value
        end
    end
    return sides
end

function Extras.SideTotals(side)
    local t = { dps = 0, hps = 0, TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, p in ipairs(side.players) do
        t.dps, t.hps = t.dps + p.dps, t.hps + p.hps
        t[p.role] = t[p.role] + 1
    end
    return t
end

function Extras.GetSplitLayout(key)
    for _, l in ipairs(Extras.SplitLayouts) do if l.key == key then return l end end
    return Extras.SplitLayouts[1]
end

-- Group numbers each side uses for the current split
function Extras:GetSplitGroups(sides, layoutKey)
    local n = math.max(1, math.ceil(math.max(#sides[1].players, #sides[2].players) / 5))
    return self.GetSplitLayout(layoutKey).groups(n)
end

-- Build a roster (8x5) from the sides: tanks, then healers, then damage, filling each side's groups in order
function Extras:SplitToRoster(sides, layoutKey)
    local roster = self.NewRoster()
    local groups = { self:GetSplitGroups(sides, layoutKey) }
    for s = 1, 2 do
        local list = {}
        for _, p in ipairs(sides[s].players) do list[#list + 1] = p end
        table.sort(list, function(x, y)
            if x.role ~= y.role then return ROLE_ORDER[x.role] < ROLE_ORDER[y.role] end
            return x.value > y.value
        end)
        for i, p in ipairs(list) do
            local g = groups[s][math.ceil(i / 5)]
            if g then roster[g][(i - 1) % 5 + 1] = p.name end
        end
    end
    return roster
end
