-- Power Infusion: who should get it (spec sims from PIData.lua x each player's damage meter DPS), which priest
-- gives it to whom, and moving each priest into the same group as their target
local _, RaidUtility = ...
local L, Print = RaidUtility.L, RaidUtility.Print

-- Spec -> class, to estimate a gain when a player's spec hasn't been seen (the average of the class's specs)
local SPEC_CLASS = {
    [62] = "MAGE",
    [63] = "MAGE",
    [64] = "MAGE",
    [70] = "PALADIN",
    [71] = "WARRIOR",
    [72] = "WARRIOR",
    [102] = "DRUID",
    [103] = "DRUID",
    [251] = "DEATHKNIGHT",
    [252] = "DEATHKNIGHT",
    [253] = "HUNTER",
    [254] = "HUNTER",
    [255] = "HUNTER",
    [258] = "PRIEST",
    [259] = "ROGUE",
    [260] = "ROGUE",
    [261] = "ROGUE",
    [262] = "SHAMAN",
    [263] = "SHAMAN",
    [265] = "WARLOCK",
    [266] = "WARLOCK",
    [267] = "WARLOCK",
    [269] = "MONK",
    [577] = "DEMONHUNTER",
    [1467] = "EVOKER",
    [1480] = "DEMONHUNTER",
}

local function ClassAverage(class)
    local sum, n = 0, 0
    for spec, gain in pairs(RaidUtility.PI_DATA.gain) do
        if SPEC_CLASS[spec] == class then
            sum, n = sum + gain, n + 1
        end
    end
    return n > 0 and sum / n or nil
end

-- Expected PI gain in percent for a damage dealer, and whether it's estimated from the class (spec not seen).
-- nil for tanks, healers, and specs the sims leave out (Augmentation).
function RaidUtility:PIGain(member, meter)
    if self:MemberRole(member) ~= "DAMAGER" then return end
    local spec = self:MemberSpec(member, meter)
    if spec then return self.PI_DATA.gain[spec] end
    local gain = ClassAverage(member.class)
    if gain then return gain, true end
end

-- How much to trust the sims (db.piPriority). The sims assume PI is lined up perfectly with cooldowns, which strong
-- teams get close to and weaker ones don't; there the better player gets more from PI whatever their spec. Each
-- spec's gain is blended toward the average of all specs: effective = w x spec gain + (1 - w) x average.
RaidUtility.PI_TRUST = { specs = 1, balanced = 0.5, players = 0 }

local averageGain
local function AverageGain()
    if not averageGain then
        local sum, n = 0, 0
        for _, gain in pairs(RaidUtility.PI_DATA.gain) do
            sum, n = sum + gain, n + 1
        end
        averageGain = n > 0 and sum / n or 0
    end
    return averageGain
end

-- Damage dealers on the roster, best Power Infusion target first: { member, entry, gain, effective, dps, value,
-- estimated, noData }. value = effective gain% (see PI_TRUST) x the player's DPS from the meter. Players without
-- meter data count at the lowest measured DPS: PI isn't gambled on someone who can't be measured. Ties (e.g. no
-- meter data at all with "players") fall back to the spec's own gain.
function RaidUtility:PIPriority(roster, members, meter)
    local w = self.PI_TRUST[self.db.piPriority] or self.PI_TRUST.balanced
    local list, seen, lowest, maxGroup = {}, {}, nil, self:MaxGroup()
    self.ForEachEntry(roster, function(g, _, entry)
        -- a group member, or the player the damage meter saw under that name (planning out of a raid)
        local member, dps = self:EntrySource(entry, members, meter)
        -- offline players, and with "Groups 1-4 only" players sitting out in 5-8, don't get PI
        if not member or seen[member.key] or not member.online or g > maxGroup then return end
        seen[member.key] = true
        local gain, estimated = self:PIGain(member, meter)
        if not gain then return end
        if dps and dps > 0 then
            lowest = math.min(lowest or dps, dps)
        else
            dps = nil
        end
        list[#list + 1] = { member = member, entry = entry, gain = gain, dps = dps, estimated = estimated }
    end)
    for _, item in ipairs(list) do
        item.noData = item.dps == nil
        item.effective = w * item.gain + (1 - w) * AverageGain()
        item.value = item.effective / 100 * (item.dps or lowest or 1)
    end
    table.sort(list, function(a, b)
        if math.abs(a.value - b.value) > 1e-9 then return a.value > b.value end
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.entry:lower() < b.entry:lower()
    end)
    return list
end

-- Each priest on the roster takes the best target not yet taken, never themselves. layoutKey: the roster is a split,
-- so a priest's own side comes first (nil: no sides, the best target anywhere). Returns pairs ({ priest,
-- priestEntry, target }) and the priority list.
function RaidUtility:AssignPI(roster, members, meter, layoutKey)
    local list = self:PIPriority(roster, members, meter)
    local maxGroup = self:MaxGroup()
    local sideOf = layoutKey and self.GroupSides(roster, layoutKey, maxGroup) or {}
    local side, priests, seen = {}, {}, {}
    self.ForEachEntry(roster, function(g, _, entry)
        local member = self:EntrySource(entry, members, meter) -- the meter knows a priest's class too
        if not member or seen[member.key] or not member.online or g > maxGroup then return end
        seen[member.key] = true
        side[member.key] = sideOf[g]
        if member.class == "PRIEST" then priests[#priests + 1] = { member = member, entry = entry } end
    end)
    local taken, result = {}, {}
    for _, priest in ipairs(priests) do
        local pick
        for pass = 1, 2 do -- own side, then anyone
            for _, item in ipairs(list) do
                local key = item.member.key
                if
                    not taken[key]
                    and key ~= priest.member.key
                    and (pass == 2 or side[key] == side[priest.member.key])
                then
                    pick = item
                    break
                end
            end
            if pick then break end
        end
        if pick then
            taken[pick.member.key] = true
            result[#result + 1] = { priest = priest.member, priestEntry = priest.entry, target = pick }
        end
    end
    return result, list
end

-- Move each priest into their target's group: an empty slot there, else swap with anyone who is neither a target
-- nor a paired priest (a typed name too). On a split (layoutKey given), never across sides: that would undo the
-- balancing, pins and lust/buff fixes. A priest who is also someone's target stays put. Sets pair.apart on pairs
-- left in different groups (and pair.otherSide when that's why). Returns how many priests moved.
-- meter: the reading the pairs came from, so players known only to the meter are found on the roster too
function RaidUtility:PairPI(roster, members, pairsList, layoutKey, meter)
    local sideOf = layoutKey and self.GroupSides(roster, layoutKey, self:MaxGroup()) or {}
    local busy = {} -- members that must stay put: targets and priests already placed
    for _, pair in ipairs(pairsList) do
        busy[pair.target.member.key] = true
    end
    local function Where(key)
        for g = 1, 8 do
            for s = 1, 5 do
                local member = self:EntrySource(roster[g][s], members, meter)
                if member and member.key == key then return g, s end
            end
        end
    end
    local moved = 0
    for _, pair in ipairs(pairsList) do
        local pg, ps = Where(pair.priest.key)
        local tg = Where(pair.target.member.key)
        pair.apart, pair.otherSide = pg ~= tg, pg and tg and sideOf[pg] ~= sideOf[tg]
        if pg and tg and pg ~= tg and not pair.otherSide and not busy[pair.priest.key] then
            local slot
            for s = 1, 5 do
                local entry = self.Trim(roster[tg][s])
                local member = entry ~= "" and self:EntrySource(entry, members, meter)
                if entry == "" then
                    slot = s
                    break
                elseif not slot and not (member and busy[member.key]) then
                    slot = s -- anyone but a PI target or a placed priest, typed names included
                end
            end
            if slot then
                roster[pg][ps], roster[tg][slot] = roster[tg][slot], roster[pg][ps]
                moved, pair.apart = moved + 1, false
            end
        end
        busy[pair.priest.key] = true
    end
    return moved
end

-- The layout to keep priests on their own side with: only when the draft is a split (it came from Generate split)
function RaidUtility:PISides() return self.draftSplit and self.db.splitLayout or nil end

-- Who gives Power Infusion to whom on the draft, for the slot markers: member key -> { gets = priest's entry,
-- gives = target's entry } (a Shadow Priest can be both). Also returns the pairs, for Post to raid.
function RaidUtility:PITags(members)
    if not (self.db.splitPI and (self.InRaid() or self:HasEntries())) then return {}, {} end
    local tags = {}
    local function Tag(key)
        tags[key] = tags[key] or {}
        return tags[key]
    end
    local pairsList = self:AssignPI(self.draft, members, self.meter, self:PISides())
    for _, pair in ipairs(pairsList) do
        Tag(pair.target.member.key).gets = pair.priestEntry
        Tag(pair.priest.key).gives = pair.target.entry
    end
    return tags, pairsList
end

-- "Shadow gives Power Infusion to Assa." with why they're apart when they are
function RaidUtility.PIPairText(pair)
    local priest, target = pair.priestEntry, pair.target.entry
    if pair.otherSide then
        return L["%1$s gives Power Infusion to %2$s (other side, so not moved together)."]:format(priest, target)
    elseif pair.apart then
        return L["%1$s gives Power Infusion to %2$s (no free spot in that group)."]:format(priest, target)
    end
    return L["%1$s gives Power Infusion to %2$s."]:format(priest, target)
end

local function PercentText(item)
    local text = format("%.1f%%", item.gain)
    if item.estimated then text = text .. "?" end
    return text
end

-- /nru pi: print the priority list and who gives PI to whom, and move each priest into their target's group on
-- the draft (an edit like any other: Save keeps it)
-- In a raid or not: players on the roster that the damage meter knows are ranked and paired too
function RaidUtility:PowerInfusion()
    if not (self.InRaid() or self:HasEntries()) then
        Print(L["Put players on the roster (or join a raid) to rank them for Power Infusion."])
        return
    end
    if InCombatLockdown() then
        Print(L["Can't read the damage meter in combat."])
        return
    end
    local members = self.GetGroupMembers()
    local meter, err = self:ReadMeter(members)
    if not meter then
        Print(err)
        return
    end
    self:SetMeterReading(meter)
    local pairsList, list = self:AssignPI(self.draft, members, meter, self:PISides())
    if #list == 0 then
        Print(L["No DPS on this roster to rank for Power Infusion."])
        return
    end
    local mode = {
        specs = L["Power Infusion priority, trusting the sims (? = spec not seen yet):"],
        balanced = L["Power Infusion priority, balancing sims and damage meter DPS (? = spec not seen yet):"],
        players = L["Power Infusion priority, by damage meter DPS (? = spec not seen yet):"],
    }
    Print(mode[self.db.piPriority] or mode.balanced)
    Print(L["Spec gains from PI sims dated %s."]:format(self.PI_DATA.updated))
    for i = 1, math.min(10, #list) do
        local item = list[i]
        local dps = item.noData and L["no meter data"] or (RaidUtility.Widgets.Short(item.dps) .. " " .. L["DPS"])
        Print(L["%1$d. %2$s: %3$s, %4$s"]:format(i, item.entry, PercentText(item), dps))
    end
    if #pairsList == 0 then
        Print(L["No priests on this roster."])
        return
    end
    if self.draftSplit then Print(L["This roster is a split, so each priest takes a target on their own side."]) end
    local moved = self:PairPI(self.draft, members, pairsList, self:PISides(), meter)
    for _, pair in ipairs(pairsList) do
        Print(self.PIPairText(pair))
    end
    if moved > 0 then
        self:MarkDirty()
        Print(L["Moved %d priest(s) into their target's group. Save to keep it."]:format(moved))
    end
    self:RefreshUI()
end
