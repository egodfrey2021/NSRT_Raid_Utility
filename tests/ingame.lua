-- In-game tests (WoWUnit). They check what the offline tests can't: the real client and the real NSRT. WoWUnit runs
-- them at PLAYER_LOGIN (login and /reload), five times 0.1s apart, and shows the results in its own window. Tests
-- must be safe to repeat and leave nothing behind. Not shipped: the .toc lists this file inside a
-- #@do-not-package@ block. Without WoWUnit installed this file does nothing.
if not WoWUnit then return end

local _, RaidUtility = ...
local NSRT, Preview = RaidUtility.NSRT, RaidUtility.Preview
local AreEqual, IsTrue, IsFalse, Exists, Replace =
    WoWUnit.AreEqual, WoWUnit.IsTrue, WoWUnit.IsFalse, WoWUnit.Exists, WoWUnit.Replace

---@class NSRTRaidUtilityTests: WoWUnitGroup
local Tests = WoWUnit("NSRT Raid Utility")

-- WoW client behavior the addon relies on

function Tests:PositionalFormat()
    -- translation keys with 2+ arguments use %1$s placeholders so translators can reorder them
    AreEqual("b a", ("%2$s %1$s"):format("a", "b"))
end

function Tests:AmbiguateDropsOwnRealm()
    -- Arrange sends NSRT short names for your realm, Name-Realm otherwise
    local name, realm = UnitFullName("player")
    realm = (realm and realm ~= "") and realm or GetNormalizedRealmName()
    AreEqual(name, Ambiguate(name .. "-" .. realm, "none"))
    AreEqual("Someone-OtherRealm", Ambiguate("Someone-OtherRealm", "none"))
end

function Tests:SpecRoleFromSpecID()
    -- NSRT.GetSpecRole reads the role from GetSpecializationInfoByID's 5th return (257 = Holy Priest)
    AreEqual("HEALER", (select(5, GetSpecializationInfoByID(257))))
end

function Tests:SecretValueCheckExists() IsTrue(canaccessvalue ~= nil or issecretvalue ~= nil) end

function Tests:FrameXMLGlobals()
    Exists(StaticPopup_Show)
    Exists(ACCEPT)
    Exists(INLINE_TANK_ICON)
    IsTrue(type(RAID_CLASS_COLORS.PRIEST.r) == "number")
    IsTrue(type(ScrollUtil.InitScrollFrameWithScrollBar) == "function")
end

local scrollProbe -- frames can't be destroyed, so the scrollbar probe is built once and reused on every run

function Tests:MinimalScrollBarTemplate()
    -- the Unassigned panel's scrollbar
    local ok, err = pcall(function()
        if scrollProbe then return end
        local scroll = CreateFrame("ScrollFrame", nil, UIParent)
        local bar = CreateFrame("EventFrame", nil, UIParent, "MinimalScrollBar")
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        scroll:Hide()
        bar:Hide()
        scrollProbe = bar
    end)
    AreEqual(nil, ok and nil or err)
end

-- Type of each named field, so a failure names the one that changed ('Tables differ at "LoadUI"')
local function FieldTypes(t, names)
    local types = {}
    for _, name in ipairs(names) do
        types[name] = type(t[name])
    end
    return types
end

local function AllFunctions(names)
    local types = {}
    for _, name in ipairs(names) do
        types[name] = "function"
    end
    return types
end

function Tests:DamageMeterAPI()
    IsTrue(type(C_DamageMeter.GetCombatSessionFromType) == "function")
    IsTrue(type(Enum.DamageMeterSessionType.Overall) == "number")
    IsTrue(type(Enum.DamageMeterType.DamageDone) == "number")
    IsTrue(type(Enum.DamageMeterType.HealingDone) == "number")
    local ok, session = pcall(
        C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall,
        Enum.DamageMeterType.DamageDone
    )
    IsTrue(ok)
    IsTrue(session == nil or type(session) == "table")
end

function Tests:SpecIconRoles()
    -- the damage meter import reads roles from spec icons (meter sources carry specIconID, not a spec ID)
    IsTrue(GetNumClasses() >= 13)
    IsTrue(C_SpecializationInfo.GetNumSpecializationsForClassID(5) == 3) -- priest
    local _, _, _, icon, role = GetSpecializationInfoForClassID(5, 2) -- Holy
    IsTrue(type(icon) == "number")
    AreEqual("HEALER", role)
end

-- NSRT: everything NSRT.lua and Core.lua use. A failure here means NSRT changed; update NSRT.lua and
-- types/globals.lua to match.

local NSRT_METHODS =
    { "ArrangeGroups", "InviteList", "Restricted", "LoadUI", "GetSpecs", "GetInviteListFromReminderInput" }

function Tests:NSRTInternals()
    local NSI = NSRT.Get()
    AreEqual("table", type(NSI))
    AreEqual(AllFunctions(NSRT_METHODS), FieldTypes(NSI, NSRT_METHODS))
end

function Tests:NSRTMeleeTable()
    -- "Even melee/ranged" reads NSRT's spec table (NSRT.IsMeleeSpec); 263 = Enhancement, 262 = Elemental
    local NSI = NSRT.Get()
    AreEqual("table", type(NSI.meleetable))
    IsTrue(NSRT.IsMeleeSpec(263))
    IsFalse(NSRT.IsMeleeSpec(262))
end

function Tests:NSRTLustAndRezTables()
    -- "Bloodlust and battle rez on both sides" reads these; 262 = Elemental, 265 = Affliction, 71 = Arms
    local NSI = NSRT.Get()
    AreEqual("table", type(NSI.lusttable))
    AreEqual("table", type(NSI.resstable))
    IsTrue(NSRT.IsLustSpec(262))
    IsTrue(NSRT.IsBattleRezSpec(265))
    IsFalse(NSRT.IsLustSpec(71))
end

function Tests:NSRTComponents()
    -- the Rosters tab's widgets; NSRT's options UI is load-on-demand, so this only checks once it has loaded
    local NSI = NSRT.Get()
    local C = NSI and NSI.UI and NSI.UI.Components
    if not C then return end
    local names = { "CreateButton", "CreateDropdown", "CreateCheckButton" }
    AreEqual(AllFunctions(names), FieldTypes(C, names))
end

function Tests:NSRTPublicAPI()
    local names = { "GetChar", "RegisterCallback" }
    AreEqual(AllFunctions(names), FieldTypes(NSAPI, names))
end

function Tests:NSRTInviteListGrammar()
    -- "Import list" relies on NSRT's reader: comma lists are positional, empty fields keep a slot open
    AreEqual({ "Ann", "", "Bob" }, NSRT.ParseInviteList("invitelist: Ann, , Bob"))
    AreEqual({ "Ann", "Bob" }, NSRT.ParseInviteList("invitelist: Ann Bob"))
end

function Tests:SortShimInstalled()
    -- NSRT's ArrangeGroups reads this global (see NSRT.lua); it must exist
    Exists(indextosubgroup)
    if IsInRaid() then AreEqual(select(3, GetRaidRosterInfo(1)), indextosubgroup[1]) end
end

-- The addon against the live client

function Tests:LiveGroupMembers()
    if Preview.IsActive() then return end
    local members = RaidUtility.GetGroupMembers()
    if not IsInGroup() then
        AreEqual(0, #members)
        return
    end
    local _, class = UnitClass("player")
    local me
    for _, member in ipairs(members) do
        if UnitIsUnit(member.unit, "player") then me = member end
    end
    Exists(me)
    AreEqual(class, me.class)
end

function Tests:PreviewRoundTrip()
    -- solo only, and never disturb a preview you have open
    if IsInGroup() or Preview.IsActive() then return end
    Replace(RaidUtility, "Print", function() end)
    local NSI = NSRT.Get()
    local groupsBefore = NSI.Groups
    local ok, err = pcall(function()
        IsTrue(Preview.Start(20))
        local members = RaidUtility.GetGroupMembers()
        AreEqual(20, #members)
        AreEqual(UnitName("player"), members[1].name)
        local roster = RaidUtility.NewRoster()
        roster[8][1] = members[2].name
        RaidUtility:Arrange(nil, roster)
        IsTrue(NSI.Groups == groupsBefore) -- dry run: NSRT's sorter was not started
    end)
    Preview.Stop()
    IsFalse(Preview.IsActive())
    if not ok then error(err, 0) end
end
