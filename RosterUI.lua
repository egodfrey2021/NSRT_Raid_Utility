-- Rosters tab: drag-and-drop group grid + unplaced members list, with explicit Save/Revert. The split controls
-- and balance strip live in SplitUI.lua.
local _, RaidUtility = ...
local L, Print = RaidUtility.L, RaidUtility.Print
local Widgets = RaidUtility.Widgets
local WHITE, TopButton, ROLE_ICON = Widgets.WHITE, Widgets.TopButton, Widgets.ROLE_ICON

-- ------------------------------------------------------------
-- Popups
-- ------------------------------------------------------------
local function AcceptNewRoster(dialog)
    local box = dialog.EditBox or dialog.editBox
    if box and RaidUtility:CreateRoster(box:GetText()) then RaidUtility:RefreshUI() end
end

StaticPopupDialogs["NSRTRAIDUTILITY_NEW_ROSTER"] = {
    text = L["Name for the new roster:"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(dialog)
        local box = dialog.EditBox or dialog.editBox
        if box then
            box:SetText("")
            box:SetFocus()
        end
    end,
    OnAccept = AcceptNewRoster,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        AcceptNewRoster(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["NSRTRAIDUTILITY_DELETE_ROSTER"] = {
    text = L['Delete roster "%s"?'],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        RaidUtility:DeleteRoster(data)
        RaidUtility:RefreshUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["NSRTRAIDUTILITY_DISCARD"] = {
    text = L['Discard unsaved changes to "%s"?'],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if data then data() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Replaces the draft with the imported roster; the dirty check happens first so nothing is lost silently
local function AcceptImport(dialog)
    local box = dialog.EditBox or dialog.editBox
    local roster, overflow = RaidUtility:ImportText(box and box:GetText() or "")
    if not roster then
        Print(overflow)
        return
    end
    RaidUtility:ConfirmDiscard(function()
        RaidUtility.draft = roster
        RaidUtility:MarkDirty()
        RaidUtility:RefreshUI()
        local count = 0
        RaidUtility.ForEachEntry(roster, function() count = count + 1 end)
        Print(L["Imported %d name(s) into the draft."]:format(count))
        if overflow > 0 then Print(L["%d name(s) beyond slot 40 were ignored."]:format(overflow)) end
    end)
end

local importText = "Paste an NSRT invite list (invitelist: a, b, c) or a plain list of names, "
    .. "or add everyone in the damage meter's Overall session to the empty slots:"
StaticPopupDialogs["NSRTRAIDUTILITY_IMPORT"] = {
    text = L[importText],
    button1 = ACCEPT,
    button2 = CANCEL,
    button3 = L["From damage meter"],
    OnAlt = function() RaidUtility:ImportFromMeter() end,
    hasEditBox = true,
    maxLetters = 2000,
    OnShow = function(dialog)
        local box = dialog.EditBox or dialog.editBox
        if box then
            box:SetText("")
            box:SetFocus()
        end
    end,
    OnAccept = AcceptImport,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        AcceptImport(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function RaidUtility:ConfirmDiscard(fn)
    if not self.dirty then
        fn()
        return
    end
    StaticPopup_Show("NSRTRAIDUTILITY_DISCARD", self.db.active, nil, fn)
end

-- ------------------------------------------------------------
-- Layout
-- ------------------------------------------------------------
local ACTIONS_Y = -42
local HINT_Y = -72
local GRID_Y = -108
local GROUP_COL_W = 195
local SLOT_W, SLOT_H, SLOT_GAP = 185, 22, 2
local BLOCK_H = 20 + 5 * (SLOT_H + SLOT_GAP) + 16
local BALANCE_Y = GRID_Y - 2 * BLOCK_H - 6
local BENCH_X = 805
local BENCH_COL_W = 112
local BENCH_SLOT_W = 108
local BENCH_ROWS = 17
local BENCH_SLOTS = 40
local MESSAGES = 2 -- recent results shown under the grid

-- Text and color for a slot: class color and role icon for group members (solo, that's you), grey and a tag
-- for typed names that aren't in the group (only while you are in one; offline planning shows plain names)
local function SlotLabel(entry, members)
    if entry == "" then return L["empty"], 0.4, 0.4, 0.4 end
    local member = RaidUtility:ResolveGroupMember(entry, members)
    if not member then
        if not RaidUtility.InGroup() then return entry, 1, 1, 1 end
        return L["%s (not in group)"]:format(entry), 0.55, 0.55, 0.55
    end
    local text = ROLE_ICON[RaidUtility:MemberRole(member)] .. " " .. entry
    local c = member.class and RAID_CLASS_COLORS[member.class]
    if c then return text, c.r, c.g, c.b end
    return text, 1, 1, 1
end

-- Meter number for a slot, like a damage meter row: HPS for healers, DPS for everyone else, from the last
-- meter reading. Typed names of players who left the group still match the meter by name.
local function SlotAmount(entry, members)
    local meter = RaidUtility.meter
    if not meter or entry == "" then return "" end
    local value
    local member = RaidUtility:ResolveGroupMember(entry, members)
    if member then
        value = RaidUtility.MeterValue(RaidUtility:MemberRole(member), meter.dps[member.key], meter.hps[member.key])
    else
        local p = meter.byName[RaidUtility.Trim(entry):lower()]
        value = p and RaidUtility.MeterValue(p.role, p.dps, p.hps)
    end
    return value and Widgets.Short(value) or ""
end

local function ShowEntry(slot, entry, members)
    local text, r, g, b = SlotLabel(entry, members)
    local pin = RaidUtility:PinOf(entry, members)
    if pin then text = "|cFF66CCFF[" .. (pin == 1 and "A" or "B") .. "]|r " .. text end
    slot.text:SetText(text)
    slot.text:SetTextColor(r, g, b)
    slot.amount:SetText(SlotAmount(entry, members))
end

local function EntryColor(entry, members)
    local _, r, g, b = SlotLabel(entry, members)
    return r, g, b
end

-- ------------------------------------------------------------
-- Drag and drop
-- ------------------------------------------------------------
local ghost
local function GetGhost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(SLOT_W, SLOT_H)
    ghost:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    ghost:SetBackdropColor(0, 0, 0, 0.85)
    ghost:SetBackdropBorderColor(0, 1, 1, 0.8)
    ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ghost.text:SetPoint("LEFT", 6, 0)
    ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
    end)
    ghost:Hide()
    return ghost
end

local function FindDropTarget()
    local ui = RaidUtility.ui
    for _, slot in ipairs(ui.groupSlots) do
        if slot:IsVisible() and slot:IsMouseOver() then return slot end
    end
    if ui.benchArea:IsMouseOver() then return ui.benchArea end
end

local function FirstEmptySlot(d, g)
    for _, group in ipairs({ g, 1, 2, 3, 4, 5, 6, 7, 8 }) do
        for s = 1, 5 do
            if RaidUtility.Trim(d[group][s]) == "" then return group, s end
        end
    end
end

local function Drop(src, tgt, value)
    if not (src and tgt) or src == tgt then return end
    local d = RaidUtility.draft
    if src.kind == "group" and tgt.kind == "group" then
        d[src.g][src.s], d[tgt.g][tgt.s] = d[tgt.g][tgt.s], d[src.g][src.s]
    elseif src.kind == "bench" and tgt.kind == "group" then
        -- A typed name (not in the group) would vanish, since only live members come back via Unassigned
        local old = RaidUtility.Trim(d[tgt.g][tgt.s])
        if old ~= "" and not RaidUtility:ResolveGroupMember(old, RaidUtility.ui.members) then
            local g, s = FirstEmptySlot(d, tgt.g)
            if not g then
                Print(L["The roster is full, so there is no free slot for '%s'."]:format(old))
                return
            end
            d[g][s] = old
        end
        d[tgt.g][tgt.s] = value -- a displaced raid member shows up in Unassigned again
    elseif src.kind == "group" and tgt.kind == "bench" then
        -- only group members are listed there, so a typed name dropped on it would just vanish
        if not RaidUtility:ResolveGroupMember(value, RaidUtility.ui.members) then
            local msg = "'%s' isn't in your group, so it can't go to the unplaced list. "
                .. "Right-click the slot to remove it."
            Print(L[msg]:format(value))
            return
        end
        d[src.g][src.s] = ""
    else
        return
    end
    RaidUtility:MarkDirty()
    RaidUtility:RefreshUI()
end

local function OnDragStart(slot)
    if (slot.value or "") == "" then return end
    RaidUtility.dragSource, RaidUtility.dragValue = slot, slot.value
    local g = GetGhost()
    g.text:SetText(slot.value)
    g.text:SetTextColor(EntryColor(slot.value, RaidUtility.ui.members))
    g:Show()
    slot:SetAlpha(0.35)
end

local function OnDragStop(slot)
    if ghost then ghost:Hide() end
    slot:SetAlpha(1)
    local src, value = RaidUtility.dragSource, RaidUtility.dragValue
    RaidUtility.dragSource, RaidUtility.dragValue = nil, nil
    if src then Drop(src, FindDropTarget(), value) end
end

-- Double-clicking an unplaced member puts them in the first empty slot
local function PlaceInFirstEmpty(slot)
    local d = RaidUtility.draft
    local g, s = FirstEmptySlot(d, 1)
    if not g then
        Print(L["The roster is full, so there is no free slot for '%s'."]:format(slot.value))
        return
    end
    d[g][s] = slot.value
    RaidUtility:MarkDirty()
    RaidUtility:RefreshUI()
end

-- Shift-right-click: pin the player to side A, then B, then unpin. Pins are draft edits, kept on Save.
local function CyclePin(entry)
    local key = RaidUtility:PinKey(entry or "", RaidUtility.ui.members)
    if not key then return end
    local pins = RaidUtility.draftPins
    pins[key] = (pins[key] == nil and 1) or (pins[key] == 1 and 2) or nil
    RaidUtility:MarkDirty()
    RaidUtility:RefreshUI()
end

-- ------------------------------------------------------------
-- Inline name editor (click empty slot / double-click a name)
-- ------------------------------------------------------------
local function OpenEditor(slot)
    local ui = RaidUtility.ui
    local e = ui.editor
    e.slot, e.cancelled = slot, false
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", slot, "TOPLEFT", 6, 0)
    e:SetSize(SLOT_W - 6, SLOT_H)
    e:SetText(slot.value or "")
    e:Show()
    e:SetFocus()
    e:HighlightText()
end

local function CommitEditor(e)
    local slot = e.slot
    if e.cancelled or not slot then return end
    local value = RaidUtility.Trim(e:GetText())
    if value ~= (RaidUtility.draft[slot.g][slot.s] or "") then
        RaidUtility.draft[slot.g][slot.s] = value
        RaidUtility:MarkDirty()
        RaidUtility:RefreshUI()
    end
end

-- Tab commits here and moves the editor on without losing focus, so OnEditFocusLost never commits twice
local function TabToNextSlot(e)
    local slots = RaidUtility.ui.groupSlots
    local from = (e.slot.g - 1) * 5 + e.slot.s
    local step = IsShiftKeyDown() and -1 or 1
    local target = slots[(from - 1 + step) % #slots + 1]
    CommitEditor(e)
    OpenEditor(target)
end

local function CreateEditor(parent)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetAutoFocus(false)
    e:SetFrameLevel(parent:GetFrameLevel() + 20)
    e:Hide()
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self)
        self.cancelled = true
        self:ClearFocus()
    end)
    e:SetScript("OnTabPressed", function(self)
        if self.slot then TabToNextSlot(self) end
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self:Hide()
        CommitEditor(self)
    end)
    return e
end

-- ------------------------------------------------------------
-- Slot widget
-- ------------------------------------------------------------
local function CreateSlot(parent, kind, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b.kind = kind
    b:SetSize(w, h)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 0.35)
    b:SetBackdropBorderColor(1, 1, 1, 0.08)
    -- the name ends where the meter number starts, so long names are cut off instead of running under it
    b.amount = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.amount:SetPoint("RIGHT", -6, 0)
    b.amount:SetJustifyH("RIGHT")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", b.amount, "LEFT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", OnDragStart)
    b:SetScript("OnDragStop", OnDragStop)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0, 1, 1, 0.6) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(1, 1, 1, 0.08) end)
    if kind == "group" then
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" and IsShiftKeyDown() then
                CyclePin(self.value)
            elseif button == "RightButton" then
                if (self.value or "") ~= "" then
                    RaidUtility.draft[self.g][self.s] = ""
                    RaidUtility:MarkDirty()
                    RaidUtility:RefreshUI()
                end
            elseif (self.value or "") == "" then
                OpenEditor(self)
            end
        end)
        b:SetScript("OnDoubleClick", function(self, button)
            if button == "LeftButton" then OpenEditor(self) end
        end)
    else
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" and IsShiftKeyDown() then CyclePin(self.value) end
        end)
        b:SetScript("OnDoubleClick", function(self, button)
            if button == "LeftButton" and (self.value or "") ~= "" then PlaceInFirstEmpty(self) end
        end)
    end
    return b
end

-- ------------------------------------------------------------
-- Build tab
-- ------------------------------------------------------------
local function RefreshResult(ui) ui.result:SetText(RaidUtility.Preview.Banner() .. table.concat(ui.messages, "\n")) end

function RaidUtility:BuildRosterTab(frame, NSI)
    local C = NSI.UI.Components
    local ui = { frame = frame, groupSlots = {}, benchSlots = {}, headers = {}, messages = {} }
    self.ui = ui

    -- Row 1: roster picker, new/delete, save/revert
    ui.dropdown = C.CreateDropdown(frame, L["Roster"], function()
        local items = {}
        for _, name in ipairs(self:GetRosterNames()) do
            items[#items + 1] = {
                label = name,
                value = name,
                onclick = function()
                    if name == self.db.active then return end
                    self:ConfirmDiscard(function()
                        self.db.active = name
                        self:LoadDraft()
                        self:RefreshUI()
                    end)
                end,
            }
        end
        return items
    end, function() return self.db.active end, 300)
    ui.dropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)

    TopButton(C, frame, L["New roster"], 330, 120, function()
        self:ConfirmDiscard(function() StaticPopup_Show("NSRTRAIDUTILITY_NEW_ROSTER") end)
    end)
    TopButton(
        C,
        frame,
        L["Delete roster"],
        455,
        120,
        function() StaticPopup_Show("NSRTRAIDUTILITY_DELETE_ROSTER", self.db.active, nil, self.db.active) end
    )
    ui.saveButton = TopButton(C, frame, L["Save"], 605, 90, function()
        self:SaveDraft()
        self:RefreshUI()
    end)
    ui.revertButton = TopButton(C, frame, L["Revert"], 700, 90, function()
        self:ConfirmDiscard(function()
            self:LoadDraft()
            self:RefreshUI()
        end)
    end)

    ui.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 805, -14)

    -- Row 2: what changes the draft, then what acts on the live group (both use the draft, not the saved roster)
    -- Controls are laid out left to right, so widening one moves the rest along. NSRT buttons keep the width
    -- they're given and clip a longer label, so widths need room for the text.
    local rowX = 10
    local function Next(w)
        local at = rowX
        rowX = rowX + w + 5
        return at
    end
    local function Label(text, w)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", Next(w), ACTIONS_Y - 6)
        label:SetWidth(w)
        label:SetJustifyH("LEFT")
        label:SetText(text)
    end
    local function Action(text, w, tooltip, fn)
        local b = C.CreateButton(frame, text, fn, w, 24)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", Next(w), ACTIONS_Y)
        Widgets.Tooltip(b.frame, tooltip)
        return b
    end
    Label(L["Edit draft:"], 62)
    ui.fillButton = Action(
        L["Fill from raid"],
        110,
        L["Replace the draft with your group's current layout."],
        function()
            self:ConfirmDiscard(function()
                if self:FillFromRaid(self.draft) then
                    self:MarkDirty()
                    self:RefreshUI()
                end
            end)
        end
    )
    local splitTip = "Balance the raid into two sides by role and the Overall damage meter session. "
        .. "Out of combat only."
    ui.splitButton = Action(L["Generate split"], 135, L[splitTip], function() self:GenerateSplit() end)
    ui.splitTarget = C.CreateCheckButton(
        frame,
        L["As new roster"],
        function() return self.db.splitToNewRoster end,
        function(_, value) self.db.splitToNewRoster = value end,
        125,
        24
    )
    ui.splitTarget:SetPoint("TOPLEFT", frame, "TOPLEFT", Next(125), ACTIONS_Y)
    local targetTip = "Checked: Generate split creates a new roster. Unchecked: it replaces this draft, "
        .. "and you Save to keep it."
    Widgets.Tooltip(ui.splitTarget.frame, L[targetTip])
    local importTip = "Paste an NSRT invite list or plain names into the draft, slot by slot."
    Action(L["Import list"], 95, L[importTip], function() StaticPopup_Show("NSRTRAIDUTILITY_IMPORT") end)
    ui.clearButton = Action(L["Clear all"], 80, L["Empty all 8 groups in the draft."], function()
        self:ConfirmDiscard(function()
            self.draft = self.NewRoster()
            self:MarkDirty()
            self:RefreshUI()
        end)
    end)
    rowX = rowX + 12 -- gap between the two groups
    Label(L["Raid:"], 38)
    local inviteTip = "Invite the players on this draft who aren't in your group. /nru invite uses the saved roster."
    ui.inviteButton = Action(L["Invite missing"], 120, L[inviteTip], function() self:InviteMissing(self.draft) end)
    local arrangeTip = "Move raid members into the groups on this draft. /nru arrange uses the saved roster."
    ui.arrangeButton = Action(L["Arrange draft"], 125, L[arrangeTip], function() self:Arrange(nil, self.draft) end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, HINT_Y)
    hint:SetWidth(780)
    hint:SetJustifyH("LEFT")
    local hintText = "Drag to move or swap. Click an empty slot or double-click a name to type (Tab moves on). "
        .. "Right-click clears; Shift-right-click pins a player to side A or B for Generate split. "
        .. "Double-click an unplaced player to add them. Grey names aren't in your group."
    hint:SetText(L[hintText])

    for g = 1, 8 do
        local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
        local x, y = 10 + col * GROUP_COL_W, GRID_Y - row * BLOCK_H
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        ui.headers[g] = header
        for s = 1, 5 do
            local slot = CreateSlot(frame, "group", SLOT_W, SLOT_H)
            slot.g, slot.s = g, s
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - 18 - (s - 1) * (SLOT_H + SLOT_GAP))
            table.insert(ui.groupSlots, slot)
        end
    end

    -- Unplaced: everyone in your raid/party who isn't placed in this roster
    local bench = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bench.kind = "bench"
    -- the scrollbar widens the panel to the left: NSRT's content area ends 7px past the right edge
    local barW = 14
    bench:SetPoint("TOPLEFT", frame, "TOPLEFT", BENCH_X - 4 - barW, GRID_Y + 4)
    bench:SetSize(2 * BENCH_COL_W + 4 + barW, 22 + BENCH_ROWS * 22)
    bench:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bench:SetBackdropColor(0, 0, 0, 0.2)
    bench:SetBackdropBorderColor(0, 1, 1, 0.15)
    ui.benchArea = bench
    ui.benchHeader = bench:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.benchHeader:SetPoint("TOPLEFT", bench, "TOPLEFT", 4, -4)
    local scroll = CreateFrame("ScrollFrame", nil, bench)
    scroll:SetPoint("TOPLEFT", bench, "TOPLEFT", 4, -22)
    scroll:SetSize(2 * BENCH_COL_W, BENCH_ROWS * 22)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(2 * BENCH_COL_W, math.ceil(BENCH_SLOTS / 2) * 22)
    scroll:SetScrollChild(content)
    ui.benchScroll, ui.benchContent = scroll, content
    scroll:EnableMouseWheel(true)
    scroll:SetScript(
        "OnMouseWheel",
        function(_, delta)
            scroll:SetVerticalScroll(
                math.max(0, math.min(ui.benchMaxScroll or 0, scroll:GetVerticalScroll() - delta * 22))
            )
        end
    )
    for i = 1, BENCH_SLOTS do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local slot = CreateSlot(content, "bench", BENCH_SLOT_W, 20)
        slot:SetPoint("TOPLEFT", content, "TOPLEFT", col * BENCH_COL_W, -row * 22)
        ui.benchSlots[i] = slot
    end
    local bar = CreateFrame("EventFrame", nil, bench, "MinimalScrollBar")
    bar:SetPoint("TOPRIGHT", bench, "TOPRIGHT", -2, -22)
    bar:SetHeight(BENCH_ROWS * 22)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
    ui.benchBar = bar
    ui.benchEmpty = bench:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.benchEmpty:SetPoint("TOPLEFT", bench, "TOPLEFT", 6, -26)

    ui.editor = CreateEditor(frame)

    self:BuildBalanceStrip(frame, C, BALANCE_Y)

    -- Results of the last actions (also printed to chat), under the preview banner when that is on
    ui.result = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.result:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, BALANCE_Y - 64)
    ui.result:SetWidth(780)
    ui.result:SetJustifyH("LEFT")
    self.OnMessage = function(msg)
        table.insert(ui.messages, msg)
        if #ui.messages > MESSAGES then table.remove(ui.messages, 1) end
        RefreshResult(ui)
    end

    frame.RefreshOptions = function() self:RefreshUI(true) end -- NSRT calls this on tab select
    self:RefreshUI(true)
end

local function SetEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

-- readMeter: take a fresh damage meter reading (tab shown, group changed, combat ended). Edits and drags reuse
-- the last one; in combat the last one is kept, since values can be secret then.
---@param readMeter boolean?
function RaidUtility:RefreshUI(readMeter)
    local ui = self.ui
    if not ui then return end
    local d = self.draft
    local members = self.GetGroupMembers()
    ui.members = members
    if readMeter and not InCombatLockdown() then self.meter = (self:ReadMeter(members)) end

    local filled, total = {}, 0
    for _, slot in ipairs(ui.groupSlots) do
        local v = d[slot.g][slot.s] or ""
        slot.value = v
        ShowEntry(slot, v, members)
        if self.Trim(v) ~= "" then
            filled[slot.g], total = (filled[slot.g] or 0) + 1, total + 1
        end
    end

    local sideOf = self:RefreshBalance(members)
    for g, header in ipairs(ui.headers) do
        local text = L["Group %1$d (%2$d/5)"]:format(g, filled[g] or 0)
        if sideOf and sideOf[g] then text = text .. "  |cFF66CCFF" .. (sideOf[g] == 1 and "A" or "B") .. "|r" end
        header:SetText(text)
    end

    local list = self:GetUnassigned(d, members)
    for i, slot in ipairs(ui.benchSlots) do
        local name = list[i]
        slot.value = name
        if name then
            ShowEntry(slot, name, members)
            slot:Show()
        else
            slot:Hide()
        end
    end
    ui.benchMaxScroll = math.max(0, math.ceil(#list / 2) - BENCH_ROWS) * 22
    -- the scrollbar's range follows the content height, so fit it to the list (never shorter than the view)
    ui.benchContent:SetSize(2 * BENCH_COL_W, math.max(BENCH_ROWS, math.ceil(#list / 2)) * 22)
    ui.benchScroll:SetVerticalScroll(math.min(ui.benchScroll:GetVerticalScroll(), ui.benchMaxScroll))
    local inRaid, inGroup = self.InRaid(), self.InGroup()
    local benchTitle = inRaid and L["In raid, not placed (%d)"]
        or inGroup and L["In group, not placed (%d)"]
        or L["Not placed (%d)"]
    ui.benchHeader:SetText(benchTitle:format(#list))
    ui.benchEmpty:SetText(#list == 0 and (inGroup and L["Everyone is placed."] or L["Not in a group."]) or "")

    SetEnabled(ui.saveButton, self.dirty)
    SetEnabled(ui.revertButton, self.dirty)
    SetEnabled(ui.fillButton, inGroup)
    SetEnabled(ui.splitButton, inRaid)
    SetEnabled(ui.clearButton, total > 0)
    SetEnabled(ui.inviteButton, total > 0)
    SetEnabled(ui.arrangeButton, inRaid and total > 0)
    ui.splitTarget:SetValue(self.db.splitToNewRoster)

    RefreshResult(ui)
    ui.status:SetText(self.dirty and "|cFFFF9900" .. L["Unsaved changes"] .. "|r" or "")
    ui.dropdown:Refresh()
end
