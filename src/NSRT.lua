-- Every use of Northern Sky Raid Tools internals goes through here. _G.NorthernSkyRaidTools is NSRT's private
-- namespace and changes between releases; NSAPI is its public API. Look the namespace up on every call:
-- the options UI (NorthernSkyRaidTools_UI) is load-on-demand and fills in NSUI later.
local _, RaidUtility = ...
local L = RaidUtility.L -- Locales.lua loads first
local NSRT = {}
RaidUtility.NSRT = NSRT

local SORT_TIMEOUT = 25 -- NSRT gives up on a group sort after this many seconds

function NSRT.Get() return _G.NorthernSkyRaidTools end

-- NSRT's ArrangeGroups reads a global `indextosubgroup` that nothing defines, so one of its branches errors and the
-- sort stops. Supply what it expects: raid index -> current subgroup, read live. Packing in
-- Arrange keeps us off that branch most of the time; this makes it safe for the rest and for NSRT's own sorts.
-- Once NSRT fixes the line it stops reading this.
if indextosubgroup == nil then
    ---@diagnostic disable-next-line: lowercase-global (NSRT reads exactly this name)
    indextosubgroup = setmetatable({}, {
        __index = function(_, index)
            if type(index) == "number" then return (select(3, GetRaidRosterInfo(index))) end
        end,
    })
end

-- The options window's tab system and widget factory, once NSRT has finished building the window
function NSRT.GetMenu()
    local NSI = NSRT.Get()
    local NSUI = NSI and NSI.NSUI
    local menu = NSUI and NSUI.Initialized and NSUI.MenuFrame
    local components = NSI and NSI.UI and NSI.UI.Components
    if menu and components then return menu, components end
end

function NSRT.GetWindow()
    local NSI = NSRT.Get()
    return NSI and NSI.NSUI
end

-- NSRT has no plugin API and changes between releases, so every call into it goes through Call: a failure is
-- reported in chat instead of a Lua error, and the error text goes to /nru debug. once: the call runs on every
-- redraw, so report it a single time per session. Returns ok, then the function's results.
local reported = {}
local function Call(message, once, fn, ...)
    local results = { n = select("#", ...) }
    local function Keep(ok, ...)
        results.n = select("#", ...)
        for i = 1, results.n do
            results[i] = select(i, ...)
        end
        return ok
    end
    local ok = Keep(pcall(fn, ...))
    if not ok then
        RaidUtility.Debug("NSRT error: " .. tostring(results[1]))
        if message and not (once and reported[message]) then
            reported[message] = true
            RaidUtility.Print(message)
        end
        return false
    end
    return true, unpack(results, 1, results.n)
end

-- Loads the options UI addon. Returns ready (window built and safe to show), window (nil if loading failed).
function NSRT.LoadWindow()
    local NSI = NSRT.Get()
    if not (NSI and NSI.LoadUI) then return false end
    local ok, ready = Call(nil, false, NSI.LoadUI, NSI, true) -- Core reports "could not be loaded"
    if not ok then return false, nil end
    return ready and NSI.NSUI ~= nil, NSI.NSUI
end

-- NSRT's own check for encounter restrictions (secret auras), which also blocks group sorting. If the check itself
-- fails, sorting is refused: moving players during an encounter we can't detect is worse than not sorting.
function NSRT.Restricted()
    local NSI = NSRT.Get()
    if not (NSI and NSI.Restricted) then return false end
    local message =
        L["NSRT's encounter check failed, so groups won't be sorted. NSRT may have changed; check for an update."]
    local ok, restricted = Call(message, false, NSI.Restricted, NSI)
    return not ok or restricted == true
end

function NSRT.CanSort()
    local NSI = NSRT.Get()
    return NSI and NSI.ArrangeGroups and true or false
end

function NSRT.IsSorting()
    local NSI = NSRT.Get()
    local g = NSI and NSI.Groups
    return g and g.Processing and g.ProcessStart and GetTime() < g.ProcessStart + SORT_TIMEOUT or false
end

-- How the last sort ended: "running", "done", or "stopped" (NSRT clears ProcessStart when it aborts,
-- and prints its own reason, e.g. which players are in combat)
function NSRT.SortState()
    local NSI = NSRT.Get()
    local g = NSI and NSI.Groups
    if not g then return "stopped" end
    if g.Processing then return NSRT.IsSorting() and "running" or "stopped" end
    return g.ProcessStart and "done" or "stopped"
end

-- units: NSRT's 40-slot layout. NSRT continues the sort on each GROUP_ROSTER_UPDATE. Returns true if it started.
function NSRT.StartSort(units)
    local NSI = NSRT.Get()
    NSI.Groups = { Processing = false, units = units, total = 40 }
    NSI.LastGroupSort = GetTime() -- share NSRT's spam guard with its own sort buttons
    local message = L["NSRT's group sorter failed. NSRT may have changed; check for an update."]
    if Call(message, false, NSI.ArrangeGroups, NSI, true) then return true end
    NSI.Groups.Processing, NSI.Groups.ProcessStart = false, nil -- nothing is running
end

-- Returns true when NSRT sent the invites (false: the caller invites one by one)
function NSRT.InviteList(list)
    local NSI = NSRT.Get()
    if not (NSI and NSI.InviteList) then return false end
    local message = L["NSRT's invite failed, so the invites were sent one by one."]
    return (Call(message, false, NSI.InviteList, NSI, list))
end

-- Character for an NSRT nickname: name, realm (realm may be nil). Runs on every redraw for names that don't match a
-- group member, so a failure is reported once and nicknames are skipped.
function NSRT.GetChar(nickname)
    if not (NSAPI and NSAPI.GetChar) then return end
    local message = L["NSRT's nickname lookup failed, so nicknames aren't matched. NSRT may have changed."]
    local ok, name, realm = Call(message, true, NSAPI.GetChar, NSAPI, nickname, true, "GlobalNickNames")
    if ok then return name, realm end
end

-- Role from the spec NSRT has seen for this unit (via LibSpecialization), or nil
-- Spec ID NSRT has seen for a unit (its own spec cache), or nil. Read on every redraw, so a failure is reported
-- once rather than on every refresh.
function NSRT.GetSpecID(unit)
    local NSI = NSRT.Get()
    if not (NSI and NSI.GetSpecs) then return end
    local message = L["Couldn't read NSRT's spec cache, so roles and specs from NSRT are skipped."]
    local ok, specID = Call(message, true, NSI.GetSpecs, NSI, unit)
    if ok and type(specID) == "number" and specID > 0 then return specID end
end

function NSRT.GetSpecRole(unit)
    local specID = NSRT.GetSpecID(unit)
    if specID then
        local role = select(5, GetSpecializationInfoByID(specID))
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
end

-- Whether a spec is in one of NSRT's spec tables (read at runtime), so this addon and NSRT's group sorting agree.
-- nil if NSRT no longer has the table.
local function InSpecTable(name, specID)
    local NSI = NSRT.Get()
    local t = NSI and NSI[name]
    if type(t) == "table" then return t[specID] == true end
end

-- Melee damage specs and melee healers (tanks aren't listed)
function NSRT.IsMeleeSpec(specID) return InSpecTable("meleetable", specID) end
-- Specs that bring Bloodlust/Heroism
function NSRT.IsLustSpec(specID) return InSpecTable("lusttable", specID) end
-- Specs that bring a battle rez
function NSRT.IsBattleRezSpec(specID) return InSpecTable("resstable", specID) end

-- Positional list of names (NSRT's own invite list reader: "invitelist:" lines, or the name of an invite list or
-- reminder saved in NSRT), or nil. We call NSRT rather than keep a copy so the grammar always matches.
function NSRT.ParseInviteList(text)
    local NSI = NSRT.Get()
    if not (NSI and NSI.GetInviteListFromReminderInput) then return end
    local ok, list = pcall(NSI.GetInviteListFromReminderInput, NSI, text)
    if ok and type(list) == "table" then return list end
end

-- fn() runs whenever someone's NSRT nickname changes
function NSRT.OnNicknameUpdated(owner, fn)
    if NSAPI and NSAPI.RegisterCallback then NSAPI.RegisterCallback(owner, "NSRT_NICKNAME_UPDATED", fn) end
end
