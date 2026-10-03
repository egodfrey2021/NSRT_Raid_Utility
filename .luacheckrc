-- luacheck config. Run: mise exec -- luacheck .
std = "lua51"
max_line_length = 120
exclude_files = { ".git/", ".luals/", ".release/", "media/", "types/" }   -- types/ is editor-only ---@meta

-- Globals this addon writes.
globals = {
    "NSRTRaidUtilityDB",
    "SLASH_NSRTRAIDUTILITY1", "SLASH_NSRTRAIDUTILITY2",
    "SlashCmdList", "StaticPopupDialogs",
    "NSRTRaidUtility_OnAddonCompartmentClick",
    "indextosubgroup",   -- supplied for NSRT's ArrangeGroups, see NSRT.lua
}

-- WoW API, FrameXML and NSRT globals this addon reads. An unknown global here usually means a typo.
read_globals = {
    -- Lua extensions Blizzard adds
    "format", "strsplit",
    -- Frames and UI
    "CreateFrame", "UIParent", "GetCursorPosition", "StaticPopup_Show", "RAID_CLASS_COLORS",
    "INLINE_TANK_ICON", "INLINE_HEALER_ICON", "INLINE_DAMAGER_ICON",
    "ACCEPT", "CANCEL", "YES", "NO", "GameTooltip", "GameFontHighlightSmall",
    -- Group and unit API
    "IsInGroup", "IsInRaid", "GetNumGroupMembers", "GetRaidRosterInfo", "GetUnitName", "UnitFullName",
    "UnitClass", "UnitExists", "UnitGroupRolesAssigned", "UnitIsGroupAssistant", "UnitIsGroupLeader",
    "GetNormalizedRealmName", "Ambiguate", "C_PartyInfo", "UnitGUID", "UnitName", "UnitAffectingCombat",
    "GetSpecializationInfoByID", "GetSpecialization", "GetSpecializationRole", "GetInspectSpecialization",
    "GetSpecializationInfoForClassID", "GetNumClasses", "C_SpecializationInfo", "GetSpecializationInfo",
    -- Misc API
    "GetTime", "InCombatLockdown", "Enum", "C_DamageMeter", "C_Timer", "issecretvalue", "canaccessvalue",
    "UnitIsUnit", "WoWUnit",   -- WoWUnit: dev-only in-game test runner (tests/ingame.lua)
    "ScrollUtil", "GetLocale", "IsShiftKeyDown", "date", "GetFileIDFromPath", "UnitIsConnected", "GetInstanceInfo", "C_ChatInfo", "LE_PARTY_CATEGORY_INSTANCE",
    -- Northern Sky Raid Tools public API
    "NSAPI",
}

-- The test harness stubs the WoW API as globals.
files["tests/"] = { allow_defined_top = true, ignore = { "111", "112", "121", "122", "131", "212" } }
