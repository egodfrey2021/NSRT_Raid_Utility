-- Roster data, working draft, and group arranging (uses NSRT's own ArrangeGroups engine)
local _, RaidUtility = ...
local L, NSRT = RaidUtility.L, RaidUtility.NSRT
local PREFIX = "|cFF00FFFFNSRT Raid Utility:|r "
local DB_VERSION = 2

-- Also shown in the Rosters tab (OnMessage), so results don't get lost in a busy chat
local function Print(msg)
    print(PREFIX .. msg)
    if RaidUtility.OnMessage then RaidUtility.OnMessage(msg) end
end
RaidUtility.Print = Print

-- /nru debug toggles this
function RaidUtility.Debug(msg)
    if RaidUtility.debug then print(PREFIX .. "|cFF888888" .. msg .. "|r") end
end

local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end
RaidUtility.Trim = Trim

-- False for secret values (names and numbers can be hidden from addons in combat)
local function Readable(v)
    if v == nil then return false end
    return canaccessvalue(v)
end
RaidUtility.Readable = Readable

---@alias Roster string[][] 8 groups x 5 slots of names ("" = empty)

-- A roster is 8 groups x 5 slots.
function RaidUtility.NewRoster()
    local r = {}
    for g = 1, 8 do
        r[g] = { "", "", "", "", "" }
    end
    return r
end

function RaidUtility.CopyRoster(src)
    local r = RaidUtility.NewRoster()
    if src then
        for g = 1, 8 do
            for s = 1, 5 do
                r[g][s] = (src[g] and src[g][s]) or ""
            end
        end
    end
    return r
end

-- fn(g, s, entry) for every non-empty slot, entry trimmed
function RaidUtility.ForEachEntry(roster, fn)
    for g = 1, 8 do
        for s = 1, 5 do
            local entry = Trim(roster[g][s])
            if entry ~= "" then fn(g, s, entry) end
        end
    end
end

local function ReportAmbiguous(list)
    if #list > 0 then Print(L["Use Name-Realm for ambiguous entries: "] .. table.concat(list, ", ")) end
end

-- Upgrade steps for older saved data go here, in order: if db.version < 2 then ... db.version = 2 end
local function Migrate(db)
    db.version = db.version or 1 -- data from before versioning already has the v1 layout
    if db.version < 2 then
        -- splitBuffs was on/off; it is now a mode: "off", "even", or "max" (Chaos Brand/Mystic Touch for most damage)
        if type(db.splitBuffs) == "boolean" then db.splitBuffs = db.splitBuffs and "even" or "off" end
        db.version = 2
    end
end

function RaidUtility:InitDB()
    NSRTRaidUtilityDB = NSRTRaidUtilityDB or { version = DB_VERSION }
    local db = NSRTRaidUtilityDB
    Migrate(db)
    db.rosters = db.rosters or {}
    if not next(db.rosters) then db.rosters["Default"] = self.NewRoster() end
    if not (db.active and db.rosters[db.active]) then db.active = next(db.rosters) end
    -- "Generate split" target: a new roster (default) or the open draft
    if db.splitToNewRoster == nil then db.splitToNewRoster = true end
    -- "Even melee/ranged": optional extra rule for Generate split
    if db.splitMeleeRanged == nil then db.splitMeleeRanged = false end
    if db.splitLustRez == nil then db.splitLustRez = false end
    if db.splitPI == nil then db.splitPI = false end
    -- Power Infusion ranking: "specs" (trust the sims), "balanced", or "players" (damage meter DPS)
    if not (db.piPriority == "specs" or db.piPriority == "players") then db.piPriority = "balanced" end
    if not (db.splitBuffs == "even" or db.splitBuffs == "max") then db.splitBuffs = "off" end
    -- what the split balances on: "overall" session, "lastfight", or "roles" only
    if not (db.splitMeterSource == "lastfight" or db.splitMeterSource == "roles") then
        db.splitMeterSource = "overall"
    end
    -- players pinned to a side for Generate split, per roster (the draft has its own copy until Save)
    db.pins = db.pins or {}
    -- rosters that came from Generate split (roster name -> true): Power Infusion keeps priests on their own side there
    db.splitRosters = db.splitRosters or {}
    self.db = db
    self:LoadDraft()
end

function RaidUtility:GetActive() return self.db.rosters[self.db.active], self.db.active end

function RaidUtility:GetRosterNames()
    local names = {}
    for name in pairs(self.db.rosters) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- ------------------------------------------------------------
-- Draft: all UI edits happen here until Save is pressed
-- ------------------------------------------------------------
-- Pins: player -> side (1 or 2) for Generate split. Part of the draft like the groups. Keyed by PinKey.
local function CopyPins(pins)
    local copy = {}
    for key, side in pairs(pins or {}) do
        copy[key] = side
    end
    return copy
end

-- Undo: every edit calls MarkDirty after changing the draft, so the state before it is the one kept from the last
-- call (or from loading). A copy of the groups, pins and split mark, up to UNDO_STEPS deep.
local UNDO_STEPS = 20

local function DraftState(self)
    return { draft = self.CopyRoster(self.draft), pins = CopyPins(self.draftPins), split = self.draftSplit }
end

function RaidUtility:LoadDraft()
    self.draft = self.CopyRoster(self:GetActive())
    self.draftPins = CopyPins(self.db.pins[self.db.active])
    self.draftSplit = self.db.splitRosters[self.db.active] == true -- draft came from Generate split
    self.dirty = false
    self:ResetUndo() -- a different roster: nothing to undo
end

-- Forget the undo history; the current draft becomes the starting point
function RaidUtility:ResetUndo()
    self.undo, self.lastState = {}, DraftState(self)
end

-- True when the draft matches the open roster's last save: groups, pins and split mark. "Unsaved changes" means
-- this is false, so undoing back to the save, or dragging someone out and back, clears it.
function RaidUtility:MatchesSaved()
    local saved = self:GetActive()
    for g = 1, 8 do
        for s = 1, 5 do
            if Trim(self.draft[g][s]) ~= Trim(saved and saved[g] and saved[g][s]) then return false end
        end
    end
    local savedPins = self.db.pins[self.db.active] or {}
    for key, side in pairs(self.draftPins) do
        if savedPins[key] ~= side then return false end
    end
    for key, side in pairs(savedPins) do
        if self.draftPins[key] ~= side then return false end
    end
    return (self.draftSplit == true) == (self.db.splitRosters[self.db.active] == true)
end

-- Steps back one edit. Returns true if there was one.
function RaidUtility:Undo()
    local state = table.remove(self.undo)
    if not state then return end
    self.draft, self.draftPins, self.draftSplit = state.draft, state.pins, state.split
    self.lastState = DraftState(self)
    self.dirty = not self:MatchesSaved()
    return true
end

function RaidUtility:CanUndo() return #self.undo > 0 end

-- True when the draft has at least one name on it
function RaidUtility:HasEntries()
    local any = false
    self.ForEachEntry(self.draft, function() any = true end)
    return any
end

function RaidUtility:SaveDraft()
    self.db.rosters[self.db.active] = self.CopyRoster(self.draft)
    self.db.pins[self.db.active] = next(self.draftPins) and CopyPins(self.draftPins) or nil
    self.db.splitRosters[self.db.active] = self.draftSplit or nil
    self.dirty = false
    Print(L["Saved roster '%s'."]:format(self.db.active))
end

function RaidUtility:MarkDirty()
    self.dirty = not self:MatchesSaved()
    table.insert(self.undo, self.lastState)
    if #self.undo > UNDO_STEPS then table.remove(self.undo, 1) end
    self.lastState = DraftState(self)
end

-- Rename the open roster; its pins and split mark go with it, and unsaved changes stay unsaved
function RaidUtility:RenameRoster(name)
    name = Trim(name)
    local old = self.db.active
    if not (name and old) or name == "" or name == old then return end
    if self.db.rosters[name] then
        Print(L["Roster '%s' already exists."]:format(name))
        return
    end
    -- the roster, its pins and its split mark move to the new name
    for _, byName in ipairs({ self.db.rosters, self.db.pins or {}, self.db.splitRosters or {} }) do
        local value = byName[old]
        byName[old] = nil
        byName[name] = value
    end
    self.db.active = name
    Print(L["Renamed roster '%1$s' to '%2$s'."]:format(old, name))
    return true
end

-- Save what you see (unsaved changes included) as a new roster and open it; the original keeps its last save
function RaidUtility:DuplicateRoster(name)
    local source = self.db.active
    if not self:CreateRoster(name, self.draft, self.draftPins, self.draftSplit) then return end
    Print(L["Copied '%1$s' to '%2$s'."]:format(source, self.db.active))
    return true
end

-- data, pins: optional roster and pins to start from (copied). isSplit: made by Generate split.
function RaidUtility:CreateRoster(name, data, pins, isSplit)
    name = Trim(name)
    if name == "" then return end
    if self.db.rosters[name] then
        Print(L["Roster '%s' already exists."]:format(name))
        return
    end
    self.db.rosters[name] = self.CopyRoster(data)
    self.db.pins[name] = pins and next(pins) and CopyPins(pins) or nil
    self.db.splitRosters[name] = isSplit or nil
    self.db.active = name
    self:LoadDraft()
    return true
end

function RaidUtility:DeleteRoster(name)
    self.db.rosters[name] = nil
    self.db.pins[name] = nil
    self.db.splitRosters[name] = nil
    if not next(self.db.rosters) then
        self.db.rosters["Default"] = self.NewRoster()
        Print(L['That was the last roster, so an empty "Default" roster was created.'])
    end
    if self.db.active == name then self.db.active = self:GetRosterNames()[1] end
    self:LoadDraft()
end

-- ------------------------------------------------------------
-- Group members and name resolution
-- ------------------------------------------------------------
---@class GroupMember
---@field unit string        "raid3" / "party1" / "player"
---@field index number?      raid index (nil in a party)
---@field name string        name as Blizzard displays it (no realm for your own realm)
---@field fullName string    Name-Realm
---@field guid string?
---@field shortKey string    lowercased name
---@field realmKey string    lowercased realm
---@field key string         lowercased Name-Realm, unique per member
---@field class string?      class file, e.g. "MAGE"
---@field classID number?    numeric Blizzard class ID
---@field role string?       assigned role: "TANK", "HEALER", "DAMAGER" or "NONE"
---@field subgroup number    raid group (1 in a party)
---@field online boolean     false only for players the game reports offline

-- The live group, or the preview raid while it's on. Everything that asks "who is in the group" goes through
-- these, so the preview exercises the same code as a real raid.
function RaidUtility.InRaid() return RaidUtility.Preview.IsActive() or IsInRaid() end
function RaidUtility.InGroup() return RaidUtility.Preview.IsActive() or IsInGroup() end

-- A member from a character's name and realm; fields adds unit, index, name (as displayed) and the rest
function RaidUtility.NewMember(name, realm, fields)
    local fullName = name .. "-" .. realm
    local member = { shortKey = name:lower(), realmKey = realm:lower(), fullName = fullName, key = fullName:lower() }
    for k, v in pairs(fields) do
        member[k] = v
    end
    return member
end

local function AddToList(members, member)
    members[#members + 1] = member
    local same = members.byShort[member.shortKey]
    if same then
        same[#same + 1] = member
    else
        members.byShort[member.shortKey] = { member }
    end
end

-- Current raid/party. The list also carries byShort (shortKey -> members) and a resolve cache, so build it
-- once per refresh and pass it around. Members whose names are secret right now are left out.
function RaidUtility.GetGroupMembers()
    local members = { byShort = {}, resolved = {} }
    if RaidUtility.Preview.IsActive() then
        for _, member in ipairs(RaidUtility.Preview.Members()) do
            AddToList(members, member)
        end
        return members
    end
    local function AddMember(unit, index, displayName, subgroup, online)
        if not Readable(displayName) then return end
        local unitName, unitRealm = UnitFullName(unit)
        local name = Readable(unitName) and unitName or strsplit("-", displayName)
        if not name then return end
        local realm = Readable(unitRealm) and unitRealm ~= "" and unitRealm
            or select(2, strsplit("-", displayName))
            or GetNormalizedRealmName()
        local guid = UnitGUID(unit)
        local _, class, classID = UnitClass(unit)
        local role = UnitGroupRolesAssigned(unit)
        AddToList(
            members,
            RaidUtility.NewMember(name, realm, {
                unit = unit,
                index = index,
                name = displayName,
                subgroup = subgroup,
                guid = Readable(guid) and guid or nil,
                class = Readable(class) and class or nil,
                classID = Readable(classID) and classID or nil,
                role = Readable(role) and role or nil, -- the tab can refresh in combat, and roles key tables
                -- false only when the game says so; an unknown or hidden value counts as online
                online = not (Readable(online) and online == false),
            })
        )
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup, _, _, _, _, online = GetRaidRosterInfo(i)
            if name then AddMember("raid" .. i, i, name, subgroup, online) end
        end
    else
        -- solo, the group is just you (as WoW's own frames show it), so your roster entry resolves like anyone's
        local units = IsInGroup() and { "player", "party1", "party2", "party3", "party4" } or { "player" }
        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                local name = GetUnitName(unit, true)
                if name then AddMember(unit, nil, name, 1, UnitIsConnected(unit)) end
            end
        end
    end
    return members
end

-- Your role from your current spec, or nil. Your own spec is always known, unlike other players'.
function RaidUtility.PlayerSpecRole()
    local spec = GetSpecialization()
    local role = spec and GetSpecializationRole(spec)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
end

-- Your current spec ID, or nil
function RaidUtility.PlayerSpecID()
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec)
    if type(specID) == "number" and specID > 0 then return specID end
end

local function FindMember(entry, members)
    local name, realm = strsplit("-", entry)
    if not name or name == "" then return end
    local same = members.byShort[name:lower()]
    if not same then return end
    realm = realm and realm:lower()
    local found
    for _, member in ipairs(same) do
        if not realm or member.realmKey == realm then
            if found then return nil, "ambiguous" end
            found = member
        end
    end
    return found
end

local function Resolve(entry, members, resolveNickname)
    local member, reason = FindMember(entry, members)
    if member or reason or not resolveNickname or entry:find("-", 1, true) then return member, reason end
    local char, realm = NSRT.GetChar(entry)
    if char then
        if realm and not char:find("-", 1, true) then char = char .. "-" .. realm end
        return FindMember(char, members)
    end
end

-- An unqualified name must match exactly one member; nicknames use NSRT's public API.
-- Returns member, or nil plus "ambiguous" when a short name matches several members.
function RaidUtility:ResolveGroupMember(entry, members, resolveNickname)
    entry = Trim(entry)
    if entry == "" then return end
    members = members or self.GetGroupMembers()
    resolveNickname = resolveNickname ~= false
    local cacheKey = (resolveNickname and "n:" or "p:") .. entry
    local hit = members.resolved[cacheKey]
    if not hit then
        hit = { Resolve(entry, members, resolveNickname) }
        members.resolved[cacheKey] = hit
    end
    return hit[1], hit[2]
end

-- The key a pin is stored under: the member's Name-Realm key when the entry resolves (so "Kaelin", "Kaelin-Draenor"
-- and a nickname all pin the same player), else the lowercased entry (a typed name of someone not in the group)
function RaidUtility:PinKey(entry, members)
    entry = Trim(entry)
    if entry == "" then return end
    local member = self:ResolveGroupMember(entry, members)
    return member and member.key or entry:lower()
end

-- The side a roster entry is pinned to, or nil
function RaidUtility:PinOf(entry, members)
    local key = self:PinKey(entry, members)
    return key and self.draftPins[key]
end

-- Pins by member key for the current group: stored keys of typed names are resolved again, in case that player has
-- joined since
function RaidUtility:MemberPins(members)
    local out = {}
    for key, side in pairs(self.draftPins) do
        local member = self:ResolveGroupMember(key, members)
        out[member and member.key or key] = side
    end
    return out
end

-- The name to put in a roster for this member: as displayed, unless another member shares the short name, in which
-- case Name-Realm (a bare "Twin" would be ambiguous and never resolve)
function RaidUtility.EntryName(member, members)
    return #members.byShort[member.shortKey] > 1 and member.fullName or member.name
end

-- Unassigned = current raid/party members not placed in the roster being edited.
function RaidUtility:GetUnassigned(roster, members)
    members = members or self.GetGroupMembers()
    local placed = {}
    self.ForEachEntry(roster, function(_, _, entry)
        local member = self:ResolveGroupMember(entry, members)
        if member then placed[member.key] = true end
    end)
    local list = {}
    for _, member in ipairs(members) do
        if not placed[member.key] then list[#list + 1] = self.EntryName(member, members) end
    end
    table.sort(list, function(x, y) return x:lower() < y:lower() end)
    return list
end

-- Copy the group's current layout (raid subgroups, or the party as group 1) into roster
function RaidUtility:FillFromRaid(roster)
    if not self.InGroup() then
        Print(L["You are not in a group."])
        return
    end
    for g = 1, 8 do
        for s = 1, 5 do
            roster[g][s] = ""
        end
    end
    local count, members = {}, self.GetGroupMembers()
    for _, member in ipairs(members) do
        local g = member.subgroup
        count[g] = (count[g] or 0) + 1
        if count[g] <= 5 then roster[g][count[g]] = self.EntryName(member, members) end
    end
    return true
end

-- Who Invite missing would invite (entries not in the group), and entries too ambiguous to tell
function RaidUtility:MissingInvites(roster, members)
    members = members or self.GetGroupMembers()
    local list, ambiguous = {}, {}
    self.ForEachEntry(roster, function(_, _, entry)
        local member, reason = self:ResolveGroupMember(entry, members)
        if reason == "ambiguous" then
            ambiguous[#ambiguous + 1] = entry
        elseif not member then
            -- a nickname of someone outside the group: invite their character, not the nickname
            local char, realm = NSRT.GetChar(entry)
            if char and char:lower() ~= entry:lower() then
                entry = (realm and realm ~= "" and not char:find("-", 1, true)) and (char .. "-" .. realm) or char
            end
            list[#list + 1] = entry
        end
    end)
    return list, ambiguous
end

function RaidUtility:InviteMissing(roster)
    -- names can be hidden in combat, so raid members would look missing and be invited again
    if InCombatLockdown() then
        Print(L["Can't check who is missing in combat."])
        return
    end
    roster = roster or self:GetActive()
    local list, ambiguous = self:MissingInvites(roster)
    ReportAmbiguous(ambiguous)
    if #list == 0 then
        if #ambiguous == 0 then Print(L["Everyone on the roster is already in the group."]) end
        return
    end
    if self.Preview.IsActive() then
        Print(L["Preview: would invite %s. Nothing was sent."]:format(table.concat(list, ", ")))
        return
    end
    if not NSRT.InviteList(list) then
        for _, n in ipairs(list) do
            C_PartyInfo.InviteUnit(n)
        end
    end
    Print(L["Sent invites to %d player(s)."]:format(#list))
end

-- ------------------------------------------------------------
-- Arranging
-- ------------------------------------------------------------
local ARRANGE_COOLDOWN = 5
local ARRANGE_TIMEOUT = 30 -- seconds; NSRT itself gives up after 25, but only notices on a roster update

-- Report how NSRT's sort ended, once it has. NSRT prints its own reason when it stops early.
local function CheckArrange()
    local watch = RaidUtility.arrangeWatch
    if not watch then return end
    local state = NSRT.SortState()
    if state == "running" and not watch.expired then return end
    watch.timeout:Cancel()
    RaidUtility.arrangeWatch = nil
    Print(state == "done" and L["Groups sorted."] or L["Group sorting stopped before it finished."])
end

-- NSRT moves the next player on each GROUP_ROSTER_UPDATE; look one frame later, after its handler has run
function RaidUtility:OnRosterUpdate()
    if self.arrangeWatch then C_Timer.After(0, CheckArrange) end
end

local function WatchArrange()
    if RaidUtility.arrangeWatch then RaidUtility.arrangeWatch.timeout:Cancel() end
    local watch = {}
    watch.timeout = C_Timer.NewTimer(ARRANGE_TIMEOUT, function()
        watch.expired = true
        CheckArrange()
    end)
    RaidUtility.arrangeWatch = watch
    CheckArrange() -- NSRT can stop on its very first step (players in combat)
end

-- roster: a roster table (e.g. the UI draft). rosterName: a saved roster. Neither = active saved roster.
-- The checks that only matter when players really move
local function CanArrangeLive(self, now)
    if not NSRT.CanSort() then
        Print(L["NSRT group sorting is not available."])
        return
    end
    if not IsInRaid() then
        Print(L["You are not in a raid."])
        return
    end
    if InCombatLockdown() then -- moving raid members is protected in combat
        Print(L["Can't move players in combat."])
        return
    end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        Print(L["You need to be raid leader or assistant to move players."])
        return
    end
    if NSRT.Restricted() then
        Print(L["Can't sort groups while encounter restrictions are active."])
        return
    end
    if NSRT.IsSorting() then
        Print(L["A group sort is already running, please wait."])
        return
    end
    if self.lastArrange and now - self.lastArrange < ARRANGE_COOLDOWN then
        Print(L["Please wait a few seconds between sorts."])
        return
    end
    return true
end

function RaidUtility:Arrange(rosterName, roster)
    local preview, now = self.Preview.IsActive(), GetTime()
    if not preview and not CanArrangeLive(self, now) then return end

    roster = roster or (rosterName and self.db.rosters[rosterName]) or (not rosterName and self:GetActive())
    if not roster then
        Print(L["Roster '%s' not found."]:format(tostring(rosterName)))
        return
    end

    -- Build NSRT's 40-slot layout. Present players are packed to the top of each group and the rest is
    -- padded with "already done" placeholders: NSRT's ArrangeGroups references an undefined
    -- `indextosubgroup` when a group has a gap of 2+ slots before the target slot, and packing avoids it.
    local units, seen, missing, ambiguous, placements = {}, {}, {}, {}, {}
    local members = self.GetGroupMembers()
    local slots = {}
    self.ForEachEntry(roster, function(g, _, entry)
        local member, reason = self:ResolveGroupMember(entry, members)
        local idx = member and member.index
        if member and idx and not seen[idx] then
            seen[idx] = true
            slots[g] = (slots[g] or 0) + 1
            local pos, unit = (g - 1) * 5 + slots[g], "raid" .. idx
            -- NSRT finds players with UnitInRaid(name): short name on your realm, Name-Realm otherwise
            local target = { sort = pos, name = Ambiguate(member.fullName, "none"), unitid = unit, role = member.role }
            units[pos] = target
            placements[#placements + 1] = { member = member, group = g }
            self.Debug(("slot %d: %s -> %s"):format(pos, entry, target.name))
        elseif reason == "ambiguous" then
            ambiguous[#ambiguous + 1] = entry
        elseif not idx then
            missing[#missing + 1] = entry
        end
    end)
    for pos = 1, 40 do
        units[pos] = units[pos] or { sort = pos, processed = true }
    end

    ReportAmbiguous(ambiguous)
    if not next(seen) then
        Print(L["Nobody on this roster is in the raid."])
        return
    end
    if #missing > 0 then Print(L["Not in raid (slots left open): "] .. table.concat(missing, ", ")) end

    if preview then
        local moved = self.Preview.Apply(placements)
        Print(L["Preview: %d player(s) would move. Nothing was sent to the game."]:format(moved))
        return
    end
    if not NSRT.StartSort(units) then return end -- NSRT's sorter failed and said so; no cooldown for a retry
    self.lastArrange = now
    Print(L["Sorting groups..."])
    WatchArrange()
end
