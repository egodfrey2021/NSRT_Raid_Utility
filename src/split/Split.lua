-- Split raid: divide the current raid into two balanced sides using the built-in damage meter
local _, RaidUtility = ...
local L = RaidUtility.L

-- Side layouts. Each returns the group numbers for side 1 and side 2, given groups needed per side.
RaidUtility.SplitLayouts = {
    {
        key = "oddeven",
        label = L["Evens/Odds (1, 3 vs 2, 4)"],
        groups = function(n)
            local a, b = {}, {}
            for i = 1, n do
                a[i], b[i] = 2 * i - 1, 2 * i
            end
            return a, b
        end,
    },
    {
        key = "consecutive",
        label = L["Grouped (1-2 vs 3-4)"],
        groups = function(n)
            local a, b = {}, {}
            for i = 1, n do
                a[i], b[i] = i, n + i
            end
            return a, b
        end,
    },
}

-- Whole-sentence messages per meter type; "read" takes the error text
local METER_TEXT = {
    damage = {
        read = L["Could not read the damage meter's damage session: %s"],
        session = L["The damage meter's damage session is invalid."],
        list = L["The damage meter's damage session has an invalid source list."],
        source = L["The damage meter's damage session has an invalid source."],
    },
    healing = {
        read = L["Could not read the damage meter's healing session: %s"],
        session = L["The damage meter's healing session is invalid."],
        list = L["The damage meter's healing session has an invalid source list."],
        source = L["The damage meter's healing session has an invalid source."],
    },
}

-- The session to read. "overall": the Overall session. "lastfight": the Current session, or once that is empty
-- out of combat, the newest stored session.
local function GetSession(source, meterType)
    local Types, Readable = Enum.DamageMeterSessionType, RaidUtility.Readable
    if source ~= "lastfight" then return C_DamageMeter.GetCombatSessionFromType(Types.Overall, meterType) end
    local session = C_DamageMeter.GetCombatSessionFromType(Types.Current, meterType)
    local sources = type(session) == "table" and session.combatSources
    if type(sources) == "table" and #sources > 0 then return session end
    local list = C_DamageMeter.GetAvailableCombatSessions()
    local newest
    for _, info in ipairs(type(list) == "table" and list or {}) do
        local id = type(info) == "table" and info.sessionID
        if Readable(id) and type(id) == "number" and (not newest or id > newest) then newest = id end
    end
    if newest then return C_DamageMeter.GetCombatSessionFromID(newest, meterType) end
    return session
end

-- One Overall meter type: member key -> amountPerSecond, plus every player source (also those no longer in the
-- group). Sources are matched to members by GUID first, then by unambiguous live-member name, never short names.
local function MeterValues(utility, members, meterType, text, source)
    local Readable = RaidUtility.Readable
    local out, sources = {}, {}
    local ok, session = pcall(GetSession, source, meterType)
    if not ok then return nil, text.read:format(tostring(session)) end
    if not session then return out, sources end
    if type(session) ~= "table" then return nil, text.session end
    if not session.combatSources then return out, sources end
    if type(session.combatSources) ~= "table" then return nil, text.list end
    local byGuid = {}
    for _, member in ipairs(members) do
        if member.guid then byGuid[member.guid] = member end
    end
    for _, src in ipairs(session.combatSources) do
        if Readable(src) then
            if type(src) ~= "table" then return nil, text.source end
            local v = src.amountPerSecond
            if Readable(v) and type(v) == "number" then
                local guid = Readable(src.sourceGUID) and type(src.sourceGUID) == "string" and src.sourceGUID or nil
                local name = Readable(src.name) and type(src.name) == "string" and src.name ~= "" and src.name or nil
                local member = guid and byGuid[guid]
                if not member and name then member = utility:ResolveGroupMember(name, members, false) end
                if member then out[member.key] = v end
                -- players only: pets and creatures have no Player- GUID
                if name and (member or (guid and guid:find("^Player%-"))) then
                    local class, icon = src.classFilename, src.specIconID
                    sources[#sources + 1] = {
                        name = name,
                        guid = guid,
                        member = member,
                        value = v,
                        class = Readable(class) and type(class) == "string" and class or nil,
                        specIcon = Readable(icon) and icon or nil,
                    }
                end
            end
        end
    end
    return out, sources
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
RaidUtility.ROLE_ORDER = ROLE_ORDER

-- Spec icon -> { id, role }, built once from the game's spec list (the meter gives a spec icon, not a spec ID)
local specIcons
local function SpecFromIcon(icon)
    if not icon then return end
    if not specIcons then
        specIcons = {}
        for classID = 1, GetNumClasses() do
            for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
                local id, _, _, specIcon, role = GetSpecializationInfoForClassID(classID, i)
                if specIcon and ROLE_ORDER[role] then specIcons[specIcon] = { id = id, role = role } end
            end
        end
    end
    return specIcons[icon]
end

-- A member's spec ID: the preview's, yours, NSRT's spec cache, then the meter's spec icon (meter: optional reading)
function RaidUtility:MemberSpec(member, meter)
    if member.specID then return member.specID end
    if member.unit == "player" then return self.PlayerSpecID() end
    return (member.unit and self.NSRT.GetSpecID(member.unit)) or (meter and meter.specByKey[member.key])
end

-- Classes whose every spec for a role stands in the same place, for when the spec isn't known
local CLASS_POSITION = {
    DAMAGER = {
        ROGUE = "MELEE",
        WARRIOR = "MELEE",
        DEATHKNIGHT = "MELEE",
        PALADIN = "MELEE",
        MONK = "MELEE",
        MAGE = "RANGED",
        WARLOCK = "RANGED",
        PRIEST = "RANGED",
        EVOKER = "RANGED",
    },
    HEALER = {
        PALADIN = "MELEE",
        MONK = "MELEE",
        PRIEST = "RANGED",
        SHAMAN = "RANGED",
        DRUID = "RANGED",
        EVOKER = "RANGED",
    },
}

-- "MELEE" or "RANGED" for a healer or damage dealer, from the spec (NSRT's melee table), else the class when that
-- decides it. Unknown (a hunter, shaman, druid or demon hunter dealing damage, spec not seen) counts as ranged and
-- returns guessed = true.
function RaidUtility:MemberPosition(member, role, meter)
    local spec = self:MemberSpec(member, meter)
    local melee = spec and self.NSRT.IsMeleeSpec(spec)
    if melee ~= nil then return melee and "MELEE" or "RANGED" end
    local byClass = CLASS_POSITION[role] and member.class and CLASS_POSITION[role][member.class]
    if byClass then return byClass end
    return "RANGED", true
end

-- Assigned role, else the spec NSRT has seen, else damage (assumed = true)
function RaidUtility:MemberRole(member)
    if ROLE_ORDER[member.role] then return member.role end
    local role
    if member.unit == "player" then
        role = self.PlayerSpecRole()
    elseif member.unit then
        role = self.NSRT.GetSpecRole(member.unit)
    end
    if role then return role end
    return "DAMAGER", true
end

---@class MeterPlayer
---@field name string     roster entry: EntryName for group members, the meter's name otherwise
---@field member table?   the group member, if in the group
---@field class string?
---@field role string
---@field dps number?
---@field hps number?
---@field specID number?  from the meter's spec icon

---@class MeterReading
---@field dps table<string, number>   member key -> DPS
---@field hps table<string, number>   member key -> HPS
---@field players MeterPlayer[]       everyone the meter saw, in or out of the group
---@field byName table<string, MeterPlayer>   lowercased name -> player, for typed names
---@field specByKey table<string, number>      member key -> spec ID from the meter's spec icon

-- The value that counts for a player: HPS for healers, DPS for everyone else
function RaidUtility.MeterValue(role, dps, hps)
    if role == "HEALER" then return hps end
    return dps
end

-- Merge damage and healing sources into one entry per player
local function MeterPlayers(utility, members, damage, healing)
    local players, byId = {}, {}
    for _, pass in ipairs({ { damage, "dps" }, { healing, "hps" } }) do
        for _, src in ipairs(pass[1]) do
            local member = src.member
            local id = member and member.key or src.guid or src.name:lower()
            local p = byId[id]
            if not p then
                p = {
                    name = member and utility.EntryName(member, members) or src.name,
                    member = member,
                    class = member and member.class or src.class,
                    specIcon = src.specIcon,
                }
                byId[id] = p
                players[#players + 1] = p
            end
            p[pass[2]] = src.value
        end
    end
    for _, p in ipairs(players) do
        local spec = SpecFromIcon(p.specIcon)
        p.specID = spec and spec.id
        p.role = p.member and (utility:MemberRole(p.member))
            or spec and spec.role
            or ((p.hps or 0) > (p.dps or 0) and "HEALER" or "DAMAGER")
        p.specIcon = nil
    end
    return players
end

local function Reading(dps, hps, players)
    local byName, specByKey = {}, {}
    for _, p in ipairs(players) do
        byName[p.name:lower()] = p
        if p.member then specByKey[p.member.key] = p.specID end
    end
    return { dps = dps, hps = hps, players = players, byName = byName, specByKey = specByKey }
end

-- The meter's players without their numbers: who they are (class, spec, role), for "Roles only"
function RaidUtility.MeterIdentities(meter)
    if not meter then return end
    local players = {}
    for i, p in ipairs(meter.players) do
        players[i] = { name = p.name, member = p.member, class = p.class, role = p.role, specID = p.specID }
    end
    return Reading({}, {}, players)
end

-- The preview raid's made-up meter numbers
local function PreviewMeter(utility, members)
    local dps, hps, players = {}, {}, {}
    for _, member in ipairs(members) do
        dps[member.key], hps[member.key] = member.previewDps, member.previewHps
        if member.previewDps or member.previewHps then
            players[#players + 1] = {
                name = utility.EntryName(member, members),
                member = member,
                class = member.class,
                role = (utility:MemberRole(member)),
                dps = member.previewDps,
                hps = member.previewHps,
            }
        end
    end
    return Reading(dps, hps, players)
end

local function LiveMeter(self, members, source)
    local dps, damage = MeterValues(self, members, Enum.DamageMeterType.DamageDone, METER_TEXT.damage, source)
    if not dps then return nil, damage end
    local hps, healing = MeterValues(self, members, Enum.DamageMeterType.HealingDone, METER_TEXT.healing, source)
    if not hps then return nil, healing end
    return Reading(dps, hps, MeterPlayers(self, members, damage, healing))
end

-- The damage meter, solo, in a party or in a raid (the preview raid's numbers while it's on), from the session
-- the split options pick: the Overall session, or the last fight ("Roles only" still shows Overall numbers).
-- Returns a MeterReading, or nil and an error message. Call out of combat: values can be secret in combat.
-- Keep a reading for the slot numbers and strip, and when it was taken (a clock time, for the caption)
function RaidUtility:SetMeterReading(reading)
    self.meter, self.meterTime = reading, reading and date("%H:%M") or nil
end

-- source: "overall" or "lastfight" to override the setting (the meter import always reads Overall)
---@return MeterReading? reading
---@return string? err
function RaidUtility:ReadMeter(members, source)
    if self.Preview.IsActive() then return PreviewMeter(self, members) end
    source = source or (self.db.splitMeterSource == "lastfight" and "lastfight" or "overall")
    return LiveMeter(self, members, source)
end

-- ------------------------------------------------------------
-- Who plays: offline players never do, and with "Groups 1-4 only" neither do groups 5-8 (players sitting out)
-- ------------------------------------------------------------
local MYTHIC_RAID = 16 -- difficulty ID: 20 players fight, and raids park the rest in groups 5-8
RaidUtility.ACTIVE_GROUPS = 4

-- "Groups 1-4 only": the saved choice once the player has made one, else on in a Mythic raid
function RaidUtility:ActiveGroupsOnly()
    if self.db.splitGroups14 ~= nil then return self.db.splitGroups14 end
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "raid" and difficulty == MYTHIC_RAID
end

-- The last roster group that plays: 4 with "Groups 1-4 only", else 8
function RaidUtility:MaxGroup() return self:ActiveGroupsOnly() and self.ACTIVE_GROUPS or 8 end

-- A live member who takes part in a split: online, and in a playing group of the raid
function RaidUtility:Plays(member) return member.online ~= false and (member.subgroup or 1) <= self:MaxGroup() end

-- How many split players have meter data, no role, and a guessed melee/ranged position
local function CountNotes(players)
    local withData, noRole, guessed = 0, 0, 0
    for _, p in ipairs(players) do
        if p.hasData then withData = withData + 1 end
        if p.assumedRole then noRole = noRole + 1 end
        if p.guessedPosition then guessed = guessed + 1 end
    end
    return withData, noRole, guessed
end

-- Raid members with role, position and meter value (HPS for healers, DPS for everyone else). Also returns how
-- many have data, no role, and a guessed position, then the meter reading and the members left out (offline, or
-- sitting out in groups 5-8).
function RaidUtility:GetSplitPlayers()
    local members = self.GetGroupMembers()
    local meter, meterError = self:ReadMeter(members)
    if not meter then return nil, meterError end
    local players, leftOut = {}, {}
    for _, member in ipairs(members) do
        if not self:Plays(member) then
            leftOut[#leftOut + 1] = member
        else
            -- EntryName: Name-Realm when two members share a name, so the roster entry resolves
            local key = member.key
            self:AddSplitPlayer(players, member, self.EntryName(member, members), meter, meter.dps[key], meter.hps[key])
        end
    end
    local withData, noRole, guessed = CountNotes(players)
    return players, withData, noRole, meter, guessed, leftOut
end

-- A roster entry's player for the split and side totals: the group member it names, else the player the damage meter
-- saw under that name, with the class, spec and role the meter gives (how a roster imported from the meter is
-- planned solo). Returns the member (or a stand-in for the meter player), then their DPS and HPS, or nil.
function RaidUtility:EntrySource(entry, members, meter)
    local member = self:ResolveGroupMember(entry, members)
    if member then return member, meter and meter.dps[member.key], meter and meter.hps[member.key] end
    local p = meter and meter.byName[self.Trim(entry):lower()]
    if not p then return end
    local standIn = { key = "meter:" .. p.name:lower(), name = p.name, class = p.class, specID = p.specID }
    standIn.role, standIn.online = p.role, true
    return standIn, p.dps, p.hps
end

-- Out of a raid, the players on the roster are split: as group members when they are, as the damage meter saw them
-- otherwise. Entries the meter doesn't know count as damage with no data. Returns players, how many have data, no
-- role, a guessed position, the entries left out (groups after MaxGroup), and how many the meter didn't know.
function RaidUtility:GetRosterSplitPlayers(roster, members, meter)
    local players, leftOut, seen, unknown, maxGroup = {}, {}, {}, 0, self:MaxGroup()
    self.ForEachEntry(roster, function(g, _, entry)
        local id = entry:lower()
        if seen[id] then return end
        seen[id] = true
        if g > maxGroup then
            leftOut[#leftOut + 1] = { entry = entry, subgroup = g }
            return
        end
        local source, dps, hps = self:EntrySource(entry, members, meter)
        if not source then
            unknown = unknown + 1
            source = { key = "entry:" .. id, name = entry, online = true } -- no role: counted as damage
        end
        self:AddSplitPlayer(players, source, entry, meter, dps, hps)
        players[#players].entry = entry
    end)
    local withData, noRole, guessed = CountNotes(players)
    return players, withData, noRole, guessed, leftOut, unknown
end

-- One playing member as a split player (see GetSplitPlayers)
function RaidUtility:AddSplitPlayer(players, member, name, meter, dps, hps)
    local role, assumed = self:MemberRole(member)
    local position, guessed
    if role ~= "TANK" then
        position, guessed = self:MemberPosition(member, role, meter)
    end
    local lust, rez, buff = self:MemberUtility(member, meter)
    local value = self.MeterValue(role, dps, hps)
    players[#players + 1] = {
        physical = self:PhysicalShare(member, meter),
        key = member.key,
        name = name,
        class = member.class,
        role = role,
        position = position,
        guessedPosition = guessed,
        lust = lust,
        rez = rez,
        buff = buff,
        assumedRole = assumed,
        dps = dps or 0,
        hps = hps or 0,
        value = value or 0,
        hasData = value ~= nil,
    }
end

-- Highest value first; equal values (e.g. a role-only split) fall back to name so results are repeatable
local function ByValueThenName(x, y)
    if x.value ~= y.value then return x.value > y.value end
    return x.name:lower() < y.name:lower()
end

-- ------------------------------------------------------------
-- What players bring: Bloodlust, battle rez, raid buffs
-- ------------------------------------------------------------
-- Raid buffs a side should have when the raid has two or more of the class: the six class buffs players carry, then
-- two debuffs on the enemies they hit.
RaidUtility.RAID_BUFFS = {
    -- name: in chat notes; short: on the balance strip
    { class = "WARRIOR", name = L["Battle Shout"], short = L["Shout"] },
    { class = "PRIEST", name = L["Power Word: Fortitude"], short = L["Fort"] },
    { class = "SHAMAN", name = L["Skyfury"], short = L["Skyfury"] },
    { class = "MAGE", name = L["Arcane Intellect"], short = L["Int"] },
    { class = "DRUID", name = L["Mark of the Wild"], short = L["MotW"] },
    { class = "EVOKER", name = L["Blessing of the Bronze"], short = L["Bronze"] },
    { class = "DEMONHUNTER", name = L["Chaos Brand (magic damage taken)"], short = L["Chaos Brand"] },
    { class = "MONK", name = L["Mystic Touch (physical damage taken)"], short = L["Mystic Touch"] },
}
local BUFF_CLASS = {}
for _, buff in ipairs(RaidUtility.RAID_BUFFS) do
    BUFF_CLASS[buff.class] = buff
end

-- Classes where every spec brings it (NSRT's spec tables list them all), for when the spec isn't known
local LUST_CLASS = { SHAMAN = true, MAGE = true, EVOKER = true, HUNTER = true }
local REZ_CLASS = { DEATHKNIGHT = true, DRUID = true, WARLOCK = true, PALADIN = true }

-- What a member brings: lust and rez (from NSRT's spec tables, else the class), and the class of the raid buff
-- they bring (nil if none)
function RaidUtility:MemberUtility(member, meter)
    local spec = self:MemberSpec(member, meter)
    local lust = spec and self.NSRT.IsLustSpec(spec)
    if lust == nil then lust = LUST_CLASS[member.class] == true end
    local rez = spec and self.NSRT.IsBattleRezSpec(spec)
    if rez == nil then rez = REZ_CLASS[member.class] == true end
    return lust, rez, BUFF_CLASS[member.class] and member.class or nil
end

-- Counts of what a list of players (with lust, rez, buff fields) brings
function RaidUtility.Tally(players)
    local t = { lust = 0, rez = 0, buffs = {} }
    for _, p in ipairs(players) do
        if p.lust then t.lust = t.lust + 1 end
        if p.rez then t.rez = t.rez + 1 end
        if p.buff then t.buffs[p.buff] = (t.buffs[p.buff] or 0) + 1 end
    end
    return t
end

-- What each side is short of, from both sides' tallies: { side, kind, key, id }. With opts.lustRez: a Bloodlust per
-- side, and battle rezzes up to 2 per side (2 with 4+ in the raid, else 1), as NSRT's own side sorting aims for.
-- With opts.buffs: each raid buff on both sides when the raid has two or more of that class.
function RaidUtility.Shortfalls(tallies, opts)
    local out = {}
    local function Need(kind, key, counts, target)
        for side = 1, 2 do
            if counts[side] < target then
                out[#out + 1] = { side = side, kind = kind, key = key, id = kind .. (key or "") .. side }
            end
        end
    end
    local a, b = tallies[1], tallies[2]
    if opts.lustRez then
        if a.lust + b.lust > 0 then Need("lust", nil, { a.lust, b.lust }, 1) end
        local rez = a.rez + b.rez
        if rez > 0 then Need("rez", nil, { a.rez, b.rez }, rez >= 4 and 2 or 1) end
    end
    if opts.buffs then
        for _, buff in ipairs(RaidUtility.RAID_BUFFS) do
            local counts = { a.buffs[buff.class] or 0, b.buffs[buff.class] or 0 }
            if counts[1] + counts[2] >= 2 then Need("buff", buff.class, counts, 1) end
        end
    end
    return out
end

local function Provides(p, need)
    if need.kind == "lust" then return p.lust end
    if need.kind == "rez" then return p.rez end
    return p.buff == need.key
end

-- Fix shortfalls after balancing with swaps: a provider on the other side trades places with a non-provider of the
-- same bucket (role, and melee/ranged when that option is on) on the short side, closest value first. Same-bucket
-- swaps keep role and position counts and barely move DPS/HPS. Pinned players never move, and no swap may create
-- a shortfall that wasn't there. Returns the shortfalls left (e.g. only one Bloodlust in the raid).
function RaidUtility.FixShortfalls(sides, opts)
    local function Current()
        local tallies = { RaidUtility.Tally(sides[1].players), RaidUtility.Tally(sides[2].players) }
        return RaidUtility.Shortfalls(tallies, opts)
    end
    local short = Current()
    for _ = 1, 40 do -- each swap adds a provider where one is missing; the bound only guards against a cycle
        if #short == 0 then break end
        local was = {}
        for _, need in ipairs(short) do
            was[need.id] = true
        end
        local best
        for _, need in ipairs(short) do
            local mine, theirs = sides[need.side].players, sides[3 - need.side].players
            for i, x in ipairs(theirs) do
                if not x.pin and Provides(x, need) then
                    for j, y in ipairs(mine) do
                        if not y.pin and y.bucket == x.bucket and not Provides(y, need) then
                            theirs[i], mine[j] = y, x
                            local ok = true
                            for _, after in ipairs(Current()) do
                                if not was[after.id] then ok = false end
                            end
                            theirs[i], mine[j] = x, y
                            local diff = math.abs(x.value - y.value)
                            if ok and (not best or diff < best.diff) then
                                best = { theirs = theirs, mine = mine, i = i, j = j, diff = diff }
                            end
                        end
                    end
                end
            end
            if best then break end -- fix the first need that can be fixed, then look again
        end
        if not best then break end
        best.theirs[best.i], best.mine[best.j] = best.mine[best.j], best.theirs[best.i]
        short = Current()
    end
    return short
end

-- ------------------------------------------------------------
-- Chaos Brand / Mystic Touch for most damage
-- ------------------------------------------------------------
-- Both are debuffs on the enemies a side hits and don't stack, so one Demon Hunter (or Monk) covers a whole side.
-- Values from the game data (SpellEffect, aura 87 "% damage taken"): Chaos Brand 1490 = 3% to school mask 126 (every
-- magic school), Mystic Touch 113746 = 5% to school mask 1 (physical).
local CHAOS_BRAND, MYSTIC_TOUCH = 0.03, 0.05

-- Rough share of each spec's damage that is physical. These are ESTIMATES from the schools of each spec's main
-- abilities, not measurements, and drift with patches; adjust freely. Unlisted specs use the class value below.
local PHYSICAL_SHARE = {
    [71] = 0.95,
    [72] = 0.95,
    [73] = 0.85, -- Warrior: Arms, Fury, Protection
    [65] = 0.2,
    [66] = 0.4,
    [70] = 0.3, -- Paladin: Holy, Protection, Retribution
    [253] = 0.85,
    [254] = 0.8,
    [255] = 0.7, -- Hunter: Beast Mastery, Marksmanship, Survival
    [259] = 0.5,
    [260] = 0.9,
    [261] = 0.4, -- Rogue: Assassination, Outlaw, Subtlety
    [250] = 0.5,
    [251] = 0.3,
    [252] = 0.4, -- Death Knight: Blood, Frost, Unholy
    [262] = 0,
    [263] = 0.4,
    [264] = 0, -- Shaman: Elemental, Enhancement, Restoration
    [266] = 0.4, -- Warlock: Demonology (the Felguard and Dreadstalkers hit physically)
    [268] = 0.7,
    [269] = 0.8,
    [270] = 0.6, -- Monk: Brewmaster, Windwalker, Mistweaver
    [102] = 0,
    [103] = 0.85,
    [104] = 0.7,
    [105] = 0, -- Druid: Balance, Feral, Guardian, Restoration
    [577] = 0.15,
    [581] = 0.1,
    [1480] = 0, -- Demon Hunter: Havoc, Vengeance, Devourer
}
local CLASS_PHYSICAL = {
    WARRIOR = 0.95,
    ROGUE = 0.6,
    HUNTER = 0.8,
    DEATHKNIGHT = 0.4,
    PALADIN = 0.3,
    MONK = 0.75,
    DRUID = 0.4,
    SHAMAN = 0.2,
    DEMONHUNTER = 0.1,
    WARLOCK = 0.1,
    MAGE = 0,
    PRIEST = 0,
    EVOKER = 0,
}

-- Share of a member's damage that is physical (0 to 1)
function RaidUtility:PhysicalShare(member, meter)
    local spec = self:MemberSpec(member, meter)
    return (spec and PHYSICAL_SHARE[spec]) or CLASS_PHYSICAL[member.class] or 0.5
end

-- Extra damage the two debuffs add across both sides (players carry dps, physical, buff)
local function DebuffGain(sides)
    local gain = 0
    for s = 1, 2 do
        local brand, touch, magic, physical = false, false, 0, 0
        for _, p in ipairs(sides[s].players) do
            brand, touch = brand or p.buff == "DEMONHUNTER", touch or p.buff == "MONK"
            local dps = p.debuffDps or 0
            physical, magic = physical + dps * p.physical, magic + dps * (1 - p.physical)
        end
        gain = gain + (brand and CHAOS_BRAND * magic or 0) + (touch and MYSTIC_TOUCH * physical or 0)
    end
    return gain
end

-- How far apart the sides are, as a share of the larger total (field: "dps" or "hps")
local function Gap(sides, field)
    local a, b = 0, 0
    for _, p in ipairs(sides[1].players) do
        a = a + (p[field] or 0)
    end
    for _, p in ipairs(sides[2].players) do
        b = b + (p[field] or 0)
    end
    local high = math.max(a, b)
    return high > 0 and math.abs(a - b) / high or 0
end

RaidUtility.DEBUFF_TOLERANCE = 0.03 -- how uneven DPS/HPS may get for the debuffs (3% of the stronger side)

-- With a lone Demon Hunter or Monk, its debuff only reaches one side: put it where it adds most, then swap magic
-- dealers toward the Chaos Brand side and physical ones toward the Mystic Touch side. Same-bucket swaps only, never a
-- pinned player, never a new shortfall, and the DPS and HPS gaps between sides may not pass DEBUFF_TOLERANCE (or get
-- worse than they already were). With two or more of each, "even" already covers both sides, which is the most.
function RaidUtility.MaximizeDebuffs(sides, opts)
    local function Tallies() return { RaidUtility.Tally(sides[1].players), RaidUtility.Tally(sides[2].players) } end
    local count = { DEMONHUNTER = 0, MONK = 0 }
    for s = 1, 2 do
        for _, p in ipairs(sides[s].players) do
            if count[p.buff] then count[p.buff] = count[p.buff] + 1 end
        end
    end
    if count.DEMONHUNTER ~= 1 and count.MONK ~= 1 then return end
    local tolerance = RaidUtility.DEBUFF_TOLERANCE
    for _ = 1, 40 do
        local gain, short = DebuffGain(sides), {}
        for _, need in ipairs(RaidUtility.Shortfalls(Tallies(), opts)) do
            short[need.id] = true
        end
        local dpsLimit = math.max(tolerance, Gap(sides, "dps"))
        local hpsLimit = math.max(tolerance, Gap(sides, "hps"))
        local best
        for i, x in ipairs(sides[1].players) do
            for j, y in ipairs(sides[2].players) do
                if not x.pin and not y.pin and x.bucket == y.bucket then
                    sides[1].players[i], sides[2].players[j] = y, x
                    local better = DebuffGain(sides) - gain
                    local ok = better > 0 and Gap(sides, "dps") <= dpsLimit and Gap(sides, "hps") <= hpsLimit
                    if ok and (not best or better > best.better) then
                        for _, need in ipairs(RaidUtility.Shortfalls(Tallies(), opts)) do
                            if not short[need.id] then ok = false end
                        end
                        if ok then best = { i = i, j = j, better = better } end
                    end
                    sides[1].players[i], sides[2].players[j] = x, y
                end
            end
        end
        if not best then return end
        local x, y = sides[1].players[best.i], sides[2].players[best.j]
        sides[1].players[best.i], sides[2].players[best.j] = y, x
    end
end

-- Balance players into two sides: tanks and healers are spread evenly first, then within each role
-- the strongest remaining player goes to the side with the lower total for that role.
-- opts (all optional):
--   byPosition: also spread melee and ranged evenly within healers and within damage (players carry position).
--     Counts are kept even per melee/ranged bucket, but totals are compared across the whole role, so a side that
--     got weaker melee gets stronger ranged.
--   lustRez, buffs: then fix shortfalls with same-bucket swaps (FixShortfalls; players carry lust, rez, buff).
--   debuffMax: then place a lone Demon Hunter/Monk for most damage (MaximizeDebuffs; players carry debuffDps,
--     physical).
-- Players with pin = 1 or 2 go to that side first. Returns sides and the shortfalls that couldn't be fixed,
-- or nil and an error when more than 20 players are pinned to one side.
function RaidUtility.BalanceSides(players, opts)
    opts = opts or {}
    local byPosition = opts.byPosition
    local sides = { { players = {}, count = 0 }, { players = {}, count = 0 } }
    local cap = { math.ceil(#players / 2), math.floor(#players / 2) }
    local pinned = { 0, 0 }
    for _, p in ipairs(players) do
        if p.pin then pinned[p.pin] = pinned[p.pin] + 1 end
    end
    for s = 1, 2 do
        if pinned[s] > 20 then
            return nil,
                L["More than 20 players are pinned to side %s. Unpin some and try again."]:format(s == 1 and "A" or "B")
        end
        if pinned[s] > cap[s] then
            cap[s], cap[3 - s] = pinned[s], #players - pinned[s]
        end
    end
    local buckets, byKey = {}, {}
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        for _, position in ipairs((byPosition and role ~= "TANK") and { "MELEE", "RANGED" } or { "ANY" }) do
            local bucket = { role = role, list = {}, total = 0, count = { 0, 0 } }
            buckets[#buckets + 1], byKey[role .. position] = bucket, bucket
        end
    end
    local roleSum = { TANK = { 0, 0 }, HEALER = { 0, 0 }, DAMAGER = { 0, 0 } }
    for _, p in ipairs(players) do
        local position = (byPosition and p.role ~= "TANK") and (p.position or "RANGED") or "ANY"
        p.bucket = p.role .. position
        local bucket = byKey[p.bucket]
        bucket.total = bucket.total + 1
        if p.pin then
            local s = p.pin
            table.insert(sides[s].players, p)
            sides[s].count = sides[s].count + 1
            bucket.count[s], roleSum[p.role][s] = bucket.count[s] + 1, roleSum[p.role][s] + p.value
        else
            table.insert(bucket.list, p)
        end
    end

    for _, bucket in ipairs(buckets) do
        local list, sum, count = bucket.list, roleSum[bucket.role], bucket.count
        table.sort(list, ByValueThenName)
        local bucketCap = math.ceil(bucket.total / 2)

        -- Is side s a better home than side best? Rules in priority order.
        local function Prefer(s, best, spare)
            if not best then return true end
            local size, bestSize = sides[s].count, sides[best].count
            if spare and size ~= bestSize then return size < bestSize end -- odd one out: smaller side
            if sum[s] ~= sum[best] then return sum[s] < sum[best] end -- lower role total
            return size < bestSize -- tie: smaller side
        end

        for i, p in ipairs(list) do
            -- the odd one out of a bucket goes to the smaller side, so spare tanks/healers don't stack up
            local spare = i == #list and bucket.total % 2 == 1
            local best
            for s = 1, 2 do
                if sides[s].count < cap[s] and count[s] < bucketCap and Prefer(s, best, spare) then best = s end
            end
            best = best or (sides[1].count < cap[1] and 1 or 2) -- bucket cap clashed with side size
            table.insert(sides[best].players, p)
            sides[best].count = sides[best].count + 1
            count[best], sum[best] = count[best] + 1, sum[best] + p.value
        end
    end
    local short = (opts.lustRez or opts.buffs) and RaidUtility.FixShortfalls(sides, opts) or {}
    if opts.debuffMax then RaidUtility.MaximizeDebuffs(sides, opts) end
    return sides, short
end

function RaidUtility.GetSplitLayout(key)
    for _, l in ipairs(RaidUtility.SplitLayouts) do
        if l.key == key then return l end
    end
    return RaidUtility.SplitLayouts[1]
end

-- Group numbers each side uses for the current split
function RaidUtility:GetSplitGroups(sides, layoutKey)
    local n = math.max(1, math.ceil(math.max(#sides[1].players, #sides[2].players) / 5))
    return self.GetSplitLayout(layoutKey).groups(n)
end

-- Build a roster (8x5) from the sides: tanks, then healers, then damage, filling each side's groups in order
function RaidUtility:SplitToRoster(sides, layoutKey)
    local roster = self.NewRoster()
    local groups = { self:GetSplitGroups(sides, layoutKey) }
    for s = 1, 2 do
        local list = {}
        for _, p in ipairs(sides[s].players) do
            list[#list + 1] = p
        end
        table.sort(list, function(x, y)
            if x.role ~= y.role then return ROLE_ORDER[x.role] < ROLE_ORDER[y.role] end
            return ByValueThenName(x, y)
        end)
        for i, p in ipairs(list) do
            local g = groups[s][math.ceil(i / 5)]
            if g then roster[g][(i - 1) % 5 + 1] = p.name end
        end
    end
    return roster
end

-- Which side (1 or 2) each group belongs to in a roster, for the given layout. The groups per side come from
-- the highest group in use, so a roster made by SplitToRoster maps back to the sides it was built from.
-- maxGroup: the last group that plays (4 with "Groups 1-4 only"); later groups get no side
function RaidUtility.GroupSides(roster, layoutKey, maxGroup)
    local highest = 1
    RaidUtility.ForEachEntry(roster, function(g)
        if g <= (maxGroup or 8) then highest = math.max(highest, g) end
    end)
    local a, b = RaidUtility.GetSplitLayout(layoutKey).groups(math.max(1, math.ceil(highest / 2)))
    local sideOf, groups = {}, { a, b }
    for s = 1, 2 do
        for _, g in ipairs(groups[s]) do
            sideOf[g] = s
        end
    end
    return sideOf, groups
end

-- Totals per side for the group members placed in roster. meter: optional MeterReading.
-- Returns sides ({ players, TANK, HEALER, DAMAGER, MELEE, RANGED, dps, hps, withData }), sideOf, groups and
-- assumed roles. MELEE/RANGED count healers and damage dealers.
function RaidUtility:RosterBalance(roster, members, layoutKey, meter)
    local sideOf, groups = self.GroupSides(roster, layoutKey, self:MaxGroup())
    local sides, assumedCount, seen = {}, 0, {}
    for s = 1, 2 do
        sides[s] =
            { players = 0, TANK = 0, HEALER = 0, DAMAGER = 0, MELEE = 0, RANGED = 0, dps = 0, hps = 0, withData = 0 }
        sides[s].utility = {} -- { lust, rez, buff } per placed member, for Tally
    end
    self.ForEachEntry(roster, function(g, _, entry)
        local member, dps, hps = self:EntrySource(entry, members, meter)
        if not (member and member.online) or seen[member.key] then return end
        local side = sides[sideOf[g]]
        if not side then return end
        seen[member.key] = true
        local role, assumed = self:MemberRole(member)
        if assumed then assumedCount = assumedCount + 1 end
        side.players, side[role] = side.players + 1, side[role] + 1
        if role ~= "TANK" then
            local position = self:MemberPosition(member, role, meter)
            side[position] = side[position] + 1
        end
        local lust, rez, buff = self:MemberUtility(member, meter)
        side.utility[#side.utility + 1] = { lust = lust, rez = rez, buff = buff }
        side.dps, side.hps = side.dps + (dps or 0), side.hps + (hps or 0)
        if self.MeterValue(role, dps, hps) then side.withData = side.withData + 1 end
    end)
    return sides, sideOf, groups, assumedCount
end
