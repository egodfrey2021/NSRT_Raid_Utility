---@meta
-- Type definitions for the editor and `mise run typecheck` only: not in the .toc, so WoW never loads this, and
-- .pkgmeta leaves it out of releases. The WoW API itself comes from Ketho's annotations (`mise run luals-setup`);
-- this file declares what those don't cover. Keep signatures in step with the real code, because the test stubs
-- are checked against them.

-- ------------------------------------------------------------
-- Globals this addon defines
-- ------------------------------------------------------------

---@class NSRTRaidUtilitySaved
---@field version integer
---@field rosters table<string, string[][]>
---@field active string
---@field splitLayout string?
---@field splitToNewRoster boolean?
---@field splitMeleeRanged boolean?
---@field splitLustRez boolean?
---@field splitBuffs string? "off", "even", or "max"
---@field splitMeterSource string?
---@field pins table<string, table<string, integer>>? roster name -> lowercased entry -> side (1 or 2)

---Saved variables (## SavedVariables in the .toc); nil until WoW loads them
---@type NSRTRaidUtilitySaved?
NSRTRaidUtilityDB = nil

SLASH_NSRTRAIDUTILITY1 = "/nru"
SLASH_NSRTRAIDUTILITY2 = "/nsx"

---Minimap addon drawer click (## AddonCompartmentFunc in the .toc)
function NSRTRaidUtility_OnAddonCompartmentClick() end

---Raid index -> current subgroup. Supplied for NSRT's ArrangeGroups, which reads this global (see NSRT.lua).
---@type table<integer, integer?>
indextosubgroup = {}

-- ------------------------------------------------------------
-- FrameXML globals we use (Ketho's Core annotations cover the API, not Blizzard's UI code)
-- ------------------------------------------------------------

ACCEPT = ""
CANCEL = ""
YES = ""
NO = ""
INLINE_TANK_ICON = ""
INLINE_HEALER_ICON = ""
INLINE_DAMAGER_ICON = ""

---@type GameTooltip
GameTooltip = {}

---@type table<string, { r: number, g: number, b: number, colorStr: string }>
RAID_CLASS_COLORS = {}

---@type table<string, table>
StaticPopupDialogs = {}

---@type table<string, fun(msg: string)>
SlashCmdList = {}

---@param which string
---@param text1 any?
---@param text2 any?
---@param data any?
---@return table? dialog
function StaticPopup_Show(which, text1, text2, data) end

---@param unit string
---@param showServerName boolean?
---@return string? name
function GetUnitName(unit, showServerName) end

ScrollUtil = {}

---@param scrollFrame ScrollFrame
---@param scrollBar Frame
function ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar) end

-- ------------------------------------------------------------
-- Northern Sky Raid Tools: only the parts NSRT.lua and Core.lua use. NSRT has no published API types and its
-- internals change between releases, so re-check these against NSRT when it updates.
-- ------------------------------------------------------------

---@class NSRTGroups
---@field Processing boolean
---@field ProcessStart number?
---@field units table[]
---@field total integer

---@class NSRTMenuFrame
---@field AllFrames Frame[]
---@field AllButtons table[]
---@field AllFramesByName table<string, Frame>
---@field AllButtonsByName table<string, table>
---@field CurrentName string?
local NSRTMenuFrame = {}
---@param name string
---@return Frame?
function NSRTMenuFrame:GetTabFrameByName(name) end
---@param name string
function NSRTMenuFrame:SelectTabByName(name) end

---@class NorthernSkyRaidTools
---@field NSUI (Frame|{ Initialized: boolean?, MenuFrame: NSRTMenuFrame? })?
---@field UI { Components: table }?
---@field Groups NSRTGroups?
---@field LastGroupSort number?
---@field meleetable table<number, boolean>? spec ID -> true for melee damage specs and melee healers
---@field lusttable table<number, boolean>? spec ID -> true for Bloodlust/Heroism specs
---@field resstable table<number, boolean>? spec ID -> true for battle rez specs
NorthernSkyRaidTools = {}

---@param firstcall boolean?
---@param finalcheck boolean?
function NorthernSkyRaidTools:ArrangeGroups(firstcall, finalcheck) end

---@param list string[]
function NorthernSkyRaidTools:InviteList(list) end

---Encounter restrictions (secret auras) active
---@return boolean
function NorthernSkyRaidTools:Restricted() end

---@param force boolean?
---@return boolean ready
function NorthernSkyRaidTools:LoadUI(force) end

---@param unit string
---@return integer|false specID
function NorthernSkyRaidTools:GetSpecs(unit) end

---@param text string invite list text, or the name of a saved invite list or reminder
---@return string[]|false
function NorthernSkyRaidTools:GetInviteListFromReminderInput(text) end

---NSRT's public API
---@class NSAPI
NSAPI = {}

---@param name string character name or nickname
---@param ... any
---@return string? name
---@return string? realm
function NSAPI:GetChar(name, ...) end

---@param target any
---@param event string
---@param callback function
---@param owner any?
function NSAPI.RegisterCallback(target, event, callback, owner) end

-- ------------------------------------------------------------
-- WoWUnit (dev only): the in-game test runner used by tests/ingame.lua
-- ------------------------------------------------------------

---@class WoWUnitGroup

---Creates a test group; its tests run at startup and on the given events
---@overload fun(name: string, ...: string): WoWUnitGroup
WoWUnit = {}

---@param a any
---@param b any
function WoWUnit.AreEqual(a, b) end

---@param value any
function WoWUnit.IsTrue(value) end

---@param value any
function WoWUnit.IsFalse(value) end

---@param value any
function WoWUnit.Exists(value) end

---Replaces table[name] (or the global `name`) for the rest of the running test
---@param tableOrName table|string
---@param name any
---@param replacement any?
function WoWUnit.Replace(tableOrName, name, replacement) end
