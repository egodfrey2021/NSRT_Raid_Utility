-- Every use of Northern Sky Raid Tools internals goes through here. _G.NorthernSkyRaidTools is NSRT's private
-- namespace and changes between releases; NSAPI is its public API. Look the namespace up on every call:
-- the options UI (NorthernSkyRaidTools_UI) is load-on-demand and fills in NSUI later.
local _, RaidUtility = ...
local NSRT = {}
RaidUtility.NSRT = NSRT

local SORT_TIMEOUT = 25 -- NSRT gives up on a group sort after this many seconds

function NSRT.Get() return _G.NorthernSkyRaidTools end

-- NSRT 12.1.24's ArrangeGroups reads a global `indextosubgroup` it never defines (SetupManager.lua:389), so that
-- branch errors and the sort stops. Supply what it expects: raid index -> current subgroup, read live. Packing in
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
    if menu and components then return menu, components, NSI end
end

function NSRT.GetWindow()
    local NSI = NSRT.Get()
    return NSI and NSI.NSUI
end

-- Loads the options UI addon. Returns ready (window built and safe to show), window (nil if loading failed).
function NSRT.LoadWindow()
    local NSI = NSRT.Get()
    if not (NSI and NSI.LoadUI) then return false end
    local ready = NSI:LoadUI(true)
    return ready and NSI.NSUI ~= nil, NSI.NSUI
end

-- NSRT's own check for encounter restrictions (secret auras), which also blocks group sorting
function NSRT.Restricted()
    local NSI = NSRT.Get()
    return NSI and NSI.Restricted and NSI:Restricted() or false
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

-- units: NSRT's 40-slot layout. NSRT continues the sort on each GROUP_ROSTER_UPDATE.
function NSRT.StartSort(units)
    local NSI = NSRT.Get()
    NSI.Groups = { Processing = false, units = units, total = 40 }
    NSI.LastGroupSort = GetTime() -- share NSRT's spam guard with its own sort buttons
    NSI:ArrangeGroups(true)
end

-- Returns true when NSRT sent the invites
function NSRT.InviteList(list)
    local NSI = NSRT.Get()
    if NSI and NSI.InviteList then
        NSI:InviteList(list)
        return true
    end
end

-- Character for an NSRT nickname: name, realm (realm may be nil)
function NSRT.GetChar(nickname)
    if NSAPI and NSAPI.GetChar then return NSAPI:GetChar(nickname, true, "GlobalNickNames") end
end

-- Role from the spec NSRT has seen for this unit (via LibSpecialization), or nil
-- Spec ID NSRT has seen for a unit (its own spec cache), or nil
function NSRT.GetSpecID(unit)
    local NSI = NSRT.Get()
    local specID = NSI and NSI.GetSpecs and NSI:GetSpecs(unit)
    if type(specID) == "number" and specID > 0 then return specID end
end

function NSRT.GetSpecRole(unit)
    local specID = NSRT.GetSpecID(unit)
    if specID and GetSpecializationInfoByID then
        local role = select(5, GetSpecializationInfoByID(specID))
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
end

-- Whether a spec is in one of NSRT's spec tables (SetupManager.lua), so this addon and NSRT's group sorting agree.
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
