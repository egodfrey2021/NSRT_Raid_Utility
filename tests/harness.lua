-- Test harness: WoW API stubs, a .toc-order loader and a tiny test runner.
-- Group state lives on H (H.raid, H.party, H.group) so each suite can set up its own scenario.
-- Standard Lua the tests need but WoW doesn't have (so the editor's WoW settings don't know them)
---@diagnostic disable-next-line: undefined-field
local io, os, debug, loadfile = _G.io, _G.os, _G.debug, _G.loadfile

local H = { utility = {}, messages = {}, invitations = {}, timers = {}, frames = {} }
H.raid, H.party, H.group = false, false, {}

-- ------------------------------------------------------------
-- Runner
-- ------------------------------------------------------------
local passed, failures = 0, {}

function H.test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failures[#failures + 1] = (H.suite or "?") .. " > " .. name .. "\n" .. tostring(err)
    end
end

function H.Finish()
    for _, f in ipairs(failures) do
        io.write("FAIL ", f, "\n\n")
    end
    io.write(("%d passed, %d failed\n"):format(passed, #failures))
    os.exit(#failures == 0 and 0 or 1)
end

function H.LastMessage() return H.messages[#H.messages] or "" end

-- WoW's string.format accepts positional arguments ("%2$s %1$d"); LuaJIT's doesn't, so translate them
local plainFormat = string.format
---@diagnostic disable-next-line: duplicate-set-field (deliberately replaces the built-in)
string.format = function(fmt, ...)
    if not fmt:find("%%%d+%$") then return plainFormat(fmt, ...) end
    local args, ordered = { ... }, {}
    local plain = fmt:gsub("%%(%d+)%$", function(n)
        ordered[#ordered + 1] = args[tonumber(n)]
        return "%"
    end)
    return plainFormat(plain, unpack(ordered))
end
format = string.format

-- ------------------------------------------------------------
-- Group and unit API
-- ------------------------------------------------------------
function H.Member(name, realm, display, role)
    return { name = name, realm = realm, display = display or name, role = role or "DAMAGER" }
end

function H.SetRaid(members)
    H.raid, H.party, H.group = true, false, members
end
function H.SetParty(members)
    H.raid, H.party, H.group = false, true, members
end

-- You, when not in a group (in a group, you are H.group[1])
H.self = { name = "Tester", realm = "Home", display = "Tester", role = "NONE", class = "PRIEST" }

local function UnitMember(unit)
    if unit == "player" then return H.group[1] or H.self end
    local index = tonumber(unit:match("^raid(%d+)$"))
    if index then return H.raid and H.group[index] end
    index = tonumber(unit:match("^party(%d+)$"))
    if index then return H.party and H.group[index + 1] end
end

function strsplit(separator, text)
    local i = text:find(separator, 1, true)
    if i then return text:sub(1, i - 1), text:sub(i + #separator) end
    return text
end
function IsInRaid() return H.raid end
function IsInGroup() return H.raid or H.party end
function GetNumGroupMembers() return #H.group end
function GetRaidRosterInfo(i)
    local member = H.raid and H.group[i]
    if member then return member.display, nil, member.subgroup or 1, nil, nil, member.class or "MAGE" end
end
function UnitExists(unit) return UnitMember(unit) ~= nil end
function GetUnitName(unit, full)
    local member = UnitMember(unit)
    if member then return full and member.name .. "-" .. member.realm or member.name end
end
function UnitFullName(unit)
    local member = UnitMember(unit)
    if member then return member.name, member.realm end
end
function UnitName(unit)
    local member = UnitMember(unit)
    if member then return member.name end
end
function UnitGUID(unit)
    local member = UnitMember(unit)
    if member then return member.guid or ("Player-" .. member.name .. "-" .. member.realm) end
end
function GetNormalizedRealmName() return "Home" end
function Ambiguate(name, context)
    assert(context == "none" or context == "short")
    local short, realm = strsplit("-", name)
    if context == "short" or realm == "Home" then return short end
    return name
end
function UnitGroupRolesAssigned(unit) return UnitMember(unit).role end
function UnitClass(unit)
    local member = UnitMember(unit)
    local class = member and member.class or "MAGE"
    return class:sub(1, 1) .. class:sub(2):lower(), class
end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end
function UnitAffectingCombat() return false end
H.now, H.inCombat, H.shift = 100, false, false
function IsShiftKeyDown() return H.shift end
function GetTime() return H.now end
function InCombatLockdown() return H.inCombat end
function issecretvalue(v) return H.secret ~= nil and H.secret[v] == true end
function print(text) H.messages[#H.messages + 1] = text end
C_PartyInfo = { InviteUnit = function(name) H.invitations[#H.invitations + 1] = name end }

-- ------------------------------------------------------------
-- C_Timer: nothing fires until a test calls H.RunTimers()
-- ------------------------------------------------------------
local function AddTimer(delay, fn, repeating)
    local t = { delay = delay, fn = fn, repeating = repeating }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    H.timers[#H.timers + 1] = t
    return t
end
C_Timer = {
    After = function(delay, fn) AddTimer(delay, fn) end,
    NewTimer = function(delay, fn) return AddTimer(delay, fn) end,
    NewTicker = function(delay, fn) return AddTimer(delay, fn, true) end,
}
-- Fires each pending timer once, or only those due within maxDelay seconds (tickers stay scheduled)
function H.RunTimers(maxDelay)
    local pending = H.timers
    H.timers = {}
    for _, t in ipairs(pending) do
        if not t.cancelled then
            if maxDelay and t.delay > maxDelay then
                H.timers[#H.timers + 1] = t
            else
                t.fn(t)
                if t.repeating and not t.cancelled then H.timers[#H.timers + 1] = t end
            end
        end
    end
end

-- ------------------------------------------------------------
-- NSRT
-- ------------------------------------------------------------
NSAPI = {
    GetChar = function(_, entry)
        if entry == "Nickname" then return "Healer", "Home" end
        if entry == "PartyNick" then return "Guest", "Away" end
        return entry
    end,
    RegisterCallback = function(owner, event, fn)
        H.callbacks = H.callbacks or {}
        H.callbacks[event] = { owner, fn }
    end,
}
-- spec ID -> true, the shape of NSRT's spec tables
local function SpecSet(...)
    local set = {}
    for _, id in ipairs({ ... }) do
        set[id] = true
    end
    return set
end

_G.NorthernSkyRaidTools = {
    -- copies of NSRT's spec tables (SetupManager.lua): melee damage and melee healers, Bloodlust, battle rez
    meleetable = SpecSet(263, 255, 259, 260, 261, 71, 72, 251, 252, 103, 70, 269, 577, 65, 270),
    lusttable = SpecSet(263, 255, 1473, 1467, 253, 254, 262, 64, 62, 63, 1468, 264),
    resstable = SpecSet(66, 104, 250, 251, 252, 103, 70, 102, 265, 266, 267, 65, 105),
    Restricted = function() return false end,
    InviteList = function(_, list)
        for _, name in ipairs(list) do
            H.invitations[#H.invitations + 1] = name
        end
    end,
    -- same signature as NSRT's (the editor types NSRT's API from these stubs)
    ---@diagnostic disable-next-line: unused-vararg (stub ignores them)
    ArrangeGroups = function(self, ...) -- NSRT passes (firstcall, finalcheck)
        self.Groups.Processing, self.Groups.ProcessStart = true, GetTime()
    end,
    -- Stand-in for NSRT's invite list reader: "invitelist:" lines, comma/semicolon fields are positional,
    -- otherwise names are split on whitespace. Returns false when no line has the prefix.
    GetInviteListFromReminderInput = function(_, text)
        local names
        for line in text:gmatch("[^\r\n]+") do
            local rest = line:match("invitelist:(.*)")
            if rest then
                names = names or {}
                local positional = rest:find("[,;]")
                local pattern = positional and "([^,;]*)" or "(%S+)"
                for field in (positional and rest .. "," or rest):gmatch(pattern .. (positional and "[,;]" or "")) do
                    names[#names + 1] = field:match("^%s*(.-)%s*$")
                end
            end
        end
        return names or false
    end,
}

-- ------------------------------------------------------------
-- Frames: enough of the widget API for the UI code; unknown methods are no-ops
-- ------------------------------------------------------------
function H.Frame(parent)
    local f = { parent = parent, scripts = {}, visible = true, offset = 0, points = {} }
    function f:SetScript(event, callback) self.scripts[event] = callback end
    function f:HookScript(event, callback) self.scripts[event] = callback end
    function f:GetScript(event) return self.scripts[event] end
    function f:IsShown() return self.visible end
    function f:IsVisible()
        local parentFrame = rawget(self, "parent")
        return self.visible and (not parentFrame or parentFrame:IsVisible())
    end
    function f:Show()
        local wasVisible = self.visible
        self.visible = true
        if not wasVisible and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function f:Hide() self.visible = false end
    function f:SetSize(w, h)
        self.width, self.height = w, h
    end
    function f:GetSize() return self.width, self.height end
    function f:CreateFontString() return H.Frame(self) end
    function f:CreateTexture() return H.Frame(self) end
    function f:GetFrameLevel() return 1 end
    function f:SetText(text) self.text = text end
    function f:GetText() return self.text end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:GetPoint() return "TOPLEFT" end
    function f:SetScrollChild(child) self.child = child end
    function f:GetVerticalScrollRange() return math.max(0, self.child.height - self.height) end
    function f:GetVerticalScroll() return self.offset end
    function f:SetVerticalScroll(offset)
        self.offset = offset
        if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, offset) end
    end
    function f:SetEnabled(value) self.enabled = value end
    function f:SetTextColor(r, g, b) self.color = { r, g, b } end
    function f:SetAlpha(a) self.alpha = a end
    function f:IsMouseOver() return self.mouseOver == true end
    H.frames[#H.frames + 1] = f
    return setmetatable(f, {
        __index = function()
            return function() end
        end,
    })
end

function CreateFrame(_, _, parent) return H.Frame(parent) end
UIParent = H.Frame()
StaticPopupDialogs = {}
function StaticPopup_Show(which, text, _, data) H.popup = { which = which, text = text, data = data } end
ACCEPT, CANCEL, YES, NO = "Accept", "Cancel", "Yes", "No"
INLINE_TANK_ICON, INLINE_HEALER_ICON, INLINE_DAMAGER_ICON = "[T]", "[H]", "[D]"
RAID_CLASS_COLORS = { MAGE = { r = 0, g = 0, b = 1 }, PRIEST = { r = 1, g = 1, b = 1 } }
SlashCmdList = {}
date = os.date
-- MinimalScrollBar + ScrollUtil: records the scroll frame the bar was attached to
ScrollUtil = {
    InitScrollFrameWithScrollBar = function(scroll, bar)
        bar.scroll, scroll.bar = scroll, bar
    end,
}

-- The frame Core.lua listens for events on
function H.EventFrame()
    for _, f in ipairs(H.frames) do
        if f.scripts.OnEvent then return f end
    end
end
function H.Fire(event, ...) H.EventFrame().scripts.OnEvent(nil, event, ...) end

-- NSRT's options window, as Core.lua sees it once NSRT_UI has loaded
function H.NSRTWindow()
    local window = H.Frame()
    window:Hide()
    local menu = {
        AllFrames = {},
        AllButtons = {},
        AllFramesByName = { General = H.Frame() },
        AllButtonsByName = { Versions = { frame = H.Frame() } },
    }
    function menu:GetTabFrameByName(name) return self.AllFramesByName[name] end
    function menu:SelectTabByName(name) self.CurrentName = name end
    function window:Show()
        self.visible = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    _G.NorthernSkyRaidTools.NSUI = window
    _G.NorthernSkyRaidTools.UI = {
        Components = {
            CreateButton = function(_, text, fn)
                local button = H.Frame()
                button.frame, button.label, button.onClick, button.enabled = button, text, fn, true
                function button:Enable() self.enabled = true end
                function button:Disable() self.enabled = false end
                return button
            end,
            CreateDropdown = function(_, label, getItems, getSelected)
                local dropdown = H.Frame()
                dropdown.label, dropdown.getItems, dropdown.getSelected = label, getItems, getSelected
                -- clicks the item whose label contains text, as a player picking it from the list would
                function dropdown:Pick(text)
                    for _, item in ipairs(self.getItems()) do
                        if item.label:find(text, 1, true) then return item.onclick(nil, nil, item.value) end
                    end
                    error("no dropdown item " .. text)
                end
                return dropdown
            end,
            -- NSRT calls getValue/setValue with its namespace first
            CreateCheckButton = function(_, text, getValue, setValue)
                local box = H.Frame()
                box.frame, box.label, box.checked = box, text, getValue(_G.NorthernSkyRaidTools)
                function box:SetValue(v) self.checked = not not v end
                function box:GetValue() return self.checked end
                function box:Click()
                    self.checked = not self.checked
                    setValue(_G.NorthernSkyRaidTools, self.checked)
                end
                return box
            end,
        },
    }
    return window, menu
end

-- ------------------------------------------------------------
-- Loading the addon in .toc order
-- ------------------------------------------------------------
-- Like a release build: files between #@do-not-package@ and #@end-do-not-package@ (in-game tests) are skipped
function H.LoadToc(toc)
    local skipping = false
    for line in io.lines(toc) do
        if line:find("^#@do%-not%-package@") then
            skipping = true
        elseif line:find("^#@end%-do%-not%-package@") then
            skipping = false
        else
            local file = not skipping and line:match("^%s*([^#%s].-)%s*$")
            if file then assert(loadfile(file))("NSRT_Raid_Utility", H.utility) end
        end
    end
end

return H
