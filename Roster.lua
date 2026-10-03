-- Roster data, working draft, and group arranging (uses NSRT's own ArrangeGroups engine)
local _, Extras = ...
local PREFIX = "|cFF00FFFFRoster for NSRT:|r "

local function Print(msg) print(PREFIX .. msg) end
Extras.Print = Print

local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end
Extras.Trim = Trim

-- A roster is 8 groups x 5 slots.
function Extras.NewRoster()
    local r = {}
    for g = 1, 8 do r[g] = { "", "", "", "", "" } end
    return r
end

function Extras.CopyRoster(src)
    local r = Extras.NewRoster()
    if src then
        for g = 1, 8 do for s = 1, 5 do r[g][s] = (src[g] and src[g][s]) or "" end end
    end
    return r
end

function Extras:InitDB()
    NSRTExtrasDB = NSRTExtrasDB or {}
    local db = NSRTExtrasDB
    db.rosters = db.rosters or {}
    if not next(db.rosters) then db.rosters["Default"] = self.NewRoster() end
    db.pool = nil                               -- old shared player pool; Unassigned is now just the live group
    for _, roster in pairs(db.rosters) do roster.bench = nil end
    if not (db.active and db.rosters[db.active]) then db.active = next(db.rosters) end
    self.db = db
    self:LoadDraft()
end

function Extras:GetActive() return self.db.rosters[self.db.active], self.db.active end

function Extras:GetRosterNames()
    local names = {}
    for name in pairs(self.db.rosters) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- ------------------------------------------------------------
-- Draft: all UI edits happen here until Save is pressed
-- ------------------------------------------------------------
function Extras:LoadDraft()
    self.draft = self.CopyRoster(self:GetActive())
    self.dirty = false
end

function Extras:SaveDraft()
    self.db.rosters[self.db.active] = self.CopyRoster(self.draft)
    self.dirty = false
    Print("Saved roster '" .. self.db.active .. "'.")
end

function Extras:MarkDirty() self.dirty = true end

function Extras:CreateRoster(name)
    name = Trim(name)
    if name == "" then return end
    if self.db.rosters[name] then Print("Roster '" .. name .. "' already exists.") return end
    self.db.rosters[name] = self.NewRoster()
    self.db.active = name
    self:LoadDraft()
    return true
end

function Extras:DeleteRoster(name)
    self.db.rosters[name] = nil
    if not next(self.db.rosters) then self.db.rosters["Default"] = self.NewRoster() end
    if self.db.active == name then self.db.active = self:GetRosterNames()[1] end
    self:LoadDraft()
end

-- Resolve a roster entry (character, Name-Realm, or NSRT nickname) to a raid index
function Extras:ResolveRaidIndex(entry)
    entry = Trim(entry)
    if entry == "" or not IsInRaid() then return end
    local base = strsplit("-", entry)
    local char = (NSAPI and NSAPI.GetChar and NSAPI:GetChar(base, true, "GlobalNickNames")) or base
    local idx = char and UnitInRaid(char)
    if not idx then idx = UnitInRaid(entry) end
    if idx then return idx, char end
end

-- Names of everyone currently in your raid or party (including you)
local function CurrentGroupNames()
    local names = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name then names[#names + 1] = name end
        end
    elseif IsInGroup() then
        for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
            if UnitExists(unit) then names[#names + 1] = GetUnitName(unit, true) end
        end
    end
    return names
end

-- Unassigned = current raid/party members not placed in the roster being edited.
local function Key(name) return (strsplit("-", Trim(name))):lower() end
Extras.Key = Key

function Extras:GetUnassigned(roster)
    local placed = {}
    for g = 1, 8 do for s = 1, 5 do
        local v = Trim(roster[g][s])
        if v ~= "" then
            placed[Key(v)] = true
            local _, char = self:ResolveRaidIndex(v)    -- nickname entries hide the real character too
            if char then placed[Key(char)] = true end
        end
    end end
    local list, seen = {}, {}
    for _, name in ipairs(CurrentGroupNames()) do
        local key = Key(name)
        if key ~= "" and not placed[key] and not seen[key] then
            seen[key] = true
            list[#list + 1] = name
        end
    end
    table.sort(list, function(x, y) return x:lower() < y:lower() end)
    return list
end

-- Copy the group's current layout (raid subgroups, or the party as group 1) into roster
function Extras:FillFromRaid(roster)
    if not IsInGroup() then Print("You are not in a group.") return end
    for g = 1, 8 do for s = 1, 5 do roster[g][s] = "" end end
    if IsInRaid() then
        local count = {}
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup = GetRaidRosterInfo(i)
            if name and subgroup then
                count[subgroup] = (count[subgroup] or 0) + 1
                if count[subgroup] <= 5 then roster[subgroup][count[subgroup]] = name end
            end
        end
    else
        for s, name in ipairs(CurrentGroupNames()) do roster[1][s] = name end
    end
    return true
end

function Extras:InviteMissing(roster)
    local NSI = _G.NorthernSkyRaidTools
    roster = roster or self:GetActive()
    local list = {}
    for g = 1, 8 do for s = 1, 5 do
        local entry = Trim(roster[g][s])
        if entry ~= "" and not self:ResolveRaidIndex(entry) then list[#list + 1] = entry end
    end end
    if #list == 0 then Print("Everyone on the roster is already in the group.") return end
    if NSI and NSI.InviteList then NSI:InviteList(list) else
        for _, n in ipairs(list) do C_PartyInfo.InviteUnit(n) end
    end
    Print("Invited " .. #list .. " player(s).")
end

-- roster: a roster table (e.g. the UI draft). rosterName: a saved roster. Neither = active saved roster.
function Extras:Arrange(rosterName, roster)
    local NSI = _G.NorthernSkyRaidTools
    if not (NSI and NSI.ArrangeGroups) then Print("NSRT group sorting is not available.") return end
    if not IsInRaid() then Print("You are not in a raid.") return end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        Print("You need to be raid leader or assistant to move players.") return
    end
    if NSI.Restricted and NSI:Restricted() then Print("Can't sort groups right now (combat restrictions).") return end
    local now = GetTime()
    if NSI.Groups and NSI.Groups.Processing and NSI.Groups.ProcessStart and now < NSI.Groups.ProcessStart + 25 then
        Print("A group sort is already running, please wait.") return
    end
    if self.lastArrange and now - self.lastArrange < 5 then Print("Please wait a few seconds between sorts.") return end

    roster = roster or (rosterName and self.db.rosters[rosterName]) or (not rosterName and self:GetActive())
    if not roster then Print("Roster '" .. tostring(rosterName) .. "' not found.") return end
    self.lastArrange = now

    -- Build NSRT's 40-slot layout. Present players are packed to the top of each group
    -- and the rest is padded with "already done" placeholders, which keeps NSRT's engine
    -- on its well-tested code paths.
    local units, seen, missing = {}, {}, {}
    for g = 1, 8 do
        local slot = 0
        for s = 1, 5 do
            local entry = Trim(roster[g][s])
            if entry ~= "" then
                local idx, char = self:ResolveRaidIndex(entry)
                if idx and not seen[idx] then
                    seen[idx] = true
                    slot = slot + 1
                    local pos, unit = (g - 1) * 5 + slot, "raid" .. idx
                    units[pos] = { sort = pos, name = char or UnitName(unit), unitid = unit,
                                   role = UnitGroupRolesAssigned(unit) }
                elseif not idx then
                    missing[#missing + 1] = entry
                end
            end
        end
        for s = slot + 1, 5 do
            local pos = (g - 1) * 5 + s
            units[pos] = { sort = pos, processed = true }
        end
    end

    if not next(seen) then Print("Nobody on this roster is in the raid.") return end
    if #missing > 0 then Print("Not in raid (slots left open): " .. table.concat(missing, ", ")) end

    NSI.Groups = { Processing = false, units = units, total = 40 }
    NSI:ArrangeGroups(true)   -- NSRT continues the sort on each GROUP_ROSTER_UPDATE
    Print("Sorting groups...")
end
