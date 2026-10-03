-- Imports: an NSRT invite list (or plain name list) pasted as text, or the players in the damage meter
local _, RaidUtility = ...
local L, NSRT = RaidUtility.L, RaidUtility.NSRT

-- list is positional (as NSRT reads invite lists): entry i goes to group ceil(i/5), slot (i-1)%5+1.
-- Returns the roster and how many non-empty names did not fit in the first 40 slots.
function RaidUtility.RosterFromList(list)
    local roster, overflow = RaidUtility.NewRoster(), 0
    for i, name in ipairs(list) do
        name = RaidUtility.Trim(name)
        if i > 40 then
            if name ~= "" then overflow = overflow + 1 end
        else
            roster[math.ceil(i / 5)][(i - 1) % 5 + 1] = name
        end
    end
    return roster, overflow
end

-- Returns roster, overflow on success, or nil and an error message
function RaidUtility:ImportText(text)
    text = RaidUtility.Trim(text)
    if text == "" then return nil, L["Nothing to import."] end
    local list = NSRT.ParseInviteList(text)
    -- Plain "a, b, c" has no prefix; NSRT's grammar needs one. A pasted column (one name per line) becomes one
    -- positional line, otherwise the parser would only see the first line.
    if not list and not text:find("invitelist:", 1, true) then
        list = NSRT.ParseInviteList("invitelist: " .. text:gsub("%s*[\r\n]+%s*", ", "))
    end
    if not list then return nil, L["No names found in that text."] end
    local roster, overflow = self.RosterFromList(list)
    local found = false
    self.ForEachEntry(roster, function() found = true end)
    if not (found or overflow > 0) then return nil, L["No names found in that text."] end
    return roster, overflow
end

-- Damage meter import: everyone in the Overall session who isn't on the roster yet goes into its empty slots,
-- tanks, then healers, then damage, strongest first. Nothing already placed moves.
-- Returns how many were added and how many didn't fit.
---@param meter MeterReading
function RaidUtility:AddMeterPlayers(roster, members, meter)
    local onRoster = {}
    self.ForEachEntry(roster, function(_, _, entry)
        local member = self:ResolveGroupMember(entry, members)
        onRoster[member and member.key or entry:lower()] = true
    end)
    local list = {}
    for _, p in ipairs(meter.players) do
        if not onRoster[p.member and p.member.key or p.name:lower()] then list[#list + 1] = p end
    end
    local order, Value = self.ROLE_ORDER, self.MeterValue
    table.sort(list, function(x, y)
        if x.role ~= y.role then return order[x.role] < order[y.role] end
        local vx, vy = Value(x.role, x.dps, x.hps) or 0, Value(y.role, y.dps, y.hps) or 0
        if vx ~= vy then return vx > vy end
        return x.name:lower() < y.name:lower()
    end)
    local added = 0
    for g = 1, 8 do
        for s = 1, 5 do
            local p = list[added + 1]
            if p and RaidUtility.Trim(roster[g][s]) == "" then
                roster[g][s] = p.name
                added = added + 1
            end
        end
    end
    return added, #list - added
end

-- "From damage meter" in the Import dialog: adds to the draft (nothing is removed, so no confirmation)
function RaidUtility:ImportFromMeter()
    local Print = self.Print
    if InCombatLockdown() then
        Print(L["Can't read the damage meter in combat."])
        return
    end
    local members = self.GetGroupMembers()
    -- everyone in the Overall session, whichever session the numbers on screen come from
    local meter, err = self:ReadMeter(members, "overall")
    if not meter then
        Print(err)
        return
    end
    if #meter.players == 0 then
        Print(L["The damage meter's Overall session has no players yet."])
    else
        local added, skipped = self:AddMeterPlayers(self.draft, members, meter)
        if added > 0 then
            self:MarkDirty()
            Print(L["Added %d player(s) from the damage meter. Save to keep them."]:format(added))
        end
        if skipped > 0 then
            Print(L["The roster is full, so %d player(s) from the damage meter were not added."]:format(skipped))
        elseif added == 0 then
            Print(L["Everyone the damage meter has seen is already on the roster."])
        end
    end
    self:RefreshUI(true)
end
