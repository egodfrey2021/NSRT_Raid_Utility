-- Rosters tab: drag-and-drop group grid + "In raid" list, with explicit Save/Revert
local _, RaidUtility = ...

-- ------------------------------------------------------------
-- Popups
-- ------------------------------------------------------------
local function AcceptNewRoster(dialog)
    local box = dialog.EditBox or dialog.editBox
    if box and RaidUtility:CreateRoster(box:GetText()) then RaidUtility:RefreshUI() end
end

StaticPopupDialogs["NSRTRAIDUTILITY_NEW_ROSTER"] = {
    text = "Name for the new roster:",
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 40,
    OnShow = function(dialog)
        local box = dialog.EditBox or dialog.editBox
        if box then box:SetText(""); box:SetFocus() end
    end,
    OnAccept = AcceptNewRoster,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        AcceptNewRoster(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["NSRTRAIDUTILITY_DELETE_ROSTER"] = {
    text = "Delete roster \"%s\"?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data) RaidUtility:DeleteRoster(data); RaidUtility:RefreshUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["NSRTRAIDUTILITY_DISCARD"] = {
    text = "Discard unsaved changes to \"%s\"?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data) if data then data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function RaidUtility:ConfirmDiscard(fn)
    if not self.dirty then fn() return end
    StaticPopup_Show("NSRTRAIDUTILITY_DISCARD", self.db.active, nil, fn)
end

-- ------------------------------------------------------------
-- Layout
-- ------------------------------------------------------------
local GRID_Y        = -90
local GROUP_COL_W   = 195
local SLOT_W, SLOT_H, SLOT_GAP = 185, 22, 2
local BLOCK_H       = 20 + 5 * (SLOT_H + SLOT_GAP) + 16
local BENCH_X       = 805
local BENCH_COL_W   = 112
local BENCH_SLOT_W  = 108
local BENCH_ROWS    = 18

local WHITE = "Interface\\Buttons\\WHITE8x8"

local function EntryColor(entry)
    if entry == "" then return 0.4, 0.4, 0.4 end
    if not IsInRaid() then return 1, 1, 1 end
    local idx = RaidUtility:ResolveRaidIndex(entry)
    if not idx then return 0.55, 0.55, 0.55 end        -- on roster, not in raid
    local _, classFile = UnitClass("raid" .. idx)
    local c = classFile and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
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

local function Drop(src, tgt, value)
    if not (src and tgt) or src == tgt then return end
    local d = RaidUtility.draft
    if src.kind == "group" and tgt.kind == "group" then
        d[src.g][src.s], d[tgt.g][tgt.s] = d[tgt.g][tgt.s], d[src.g][src.s]   -- move or swap
    elseif src.kind == "bench" and tgt.kind == "group" then
        d[tgt.g][tgt.s] = value        -- a displaced raid member shows up in Unassigned again
    elseif src.kind == "group" and tgt.kind == "bench" then
        d[src.g][src.s] = ""           -- un-place
    else
        return
    end
    RaidUtility:MarkDirty()
    RaidUtility:RefreshUI()
end

local function OnDragStart(slot)
    if (slot.value or "") == "" then return end
    RaidUtility.dragSource, RaidUtility.dragValue, RaidUtility.dragIndex = slot, slot.value, slot.i
    local g = GetGhost()
    g.text:SetText(slot.value)
    g.text:SetTextColor(EntryColor(slot.value))
    g:Show()
    slot:SetAlpha(0.35)
end

local function OnDragStop(slot)
    if ghost then ghost:Hide() end
    slot:SetAlpha(1)
    local src, value, index = RaidUtility.dragSource, RaidUtility.dragValue, RaidUtility.dragIndex
    RaidUtility.dragSource, RaidUtility.dragValue, RaidUtility.dragIndex = nil, nil, nil
    if src then Drop(src, FindDropTarget(), value) end
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

local function CreateEditor(parent)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetAutoFocus(false)
    e:SetFrameLevel(parent:GetFrameLevel() + 20)
    e:Hide()
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self.cancelled = true; self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self)
        local slot = self.slot
        self:Hide()
        if self.cancelled or not slot then return end
        local value = RaidUtility.Trim(self:GetText())
        if value ~= (RaidUtility.draft[slot.g][slot.s] or "") then
            RaidUtility.draft[slot.g][slot.s] = value
            RaidUtility:MarkDirty()
            RaidUtility:RefreshUI()
        end
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
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
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
            if button == "RightButton" then
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
    end
    return b
end

-- ------------------------------------------------------------
-- Build tab
-- ------------------------------------------------------------
function RaidUtility:BuildRosterTab(frame, NSI)
    local C = NSI.UI.Components
    local ui = { groupSlots = {}, benchSlots = {} }
    self.ui = ui

    -- Row 1: roster picker, new/delete, save/revert
    ui.dropdown = C.CreateDropdown(frame, "Roster",
        function()
            local items = {}
            for _, name in ipairs(self:GetRosterNames()) do
                items[#items + 1] = { label = name, value = name, onclick = function()
                    if name == self.db.active then return end
                    self:ConfirmDiscard(function()
                        self.db.active = name
                        self:LoadDraft()
                        self:RefreshUI()
                    end)
                end }
            end
            return items
        end,
        function() return self.db.active .. (self.dirty and " *" or "") end, 300)
    ui.dropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)

    local function TopButton(text, x, w, fn)
        local b = C.CreateButton(frame, text, fn, w, 22)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -10)
        return b
    end
    TopButton("New roster", 330, 120, function()
        self:ConfirmDiscard(function() StaticPopup_Show("NSRTRAIDUTILITY_NEW_ROSTER") end)
    end)
    TopButton("Delete roster", 455, 120, function()
        StaticPopup_Show("NSRTRAIDUTILITY_DELETE_ROSTER", self.db.active, nil, self.db.active)
    end)
    TopButton("Save", 605, 90, function() self:SaveDraft(); self:RefreshUI() end)
    TopButton("Revert", 700, 90, function() self:LoadDraft(); self:RefreshUI() end)

    ui.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 805, -14)

    -- Row 2: actions (all work on the draft)
    local actions = {
        { "Fill from current raid", function()
            if self:FillFromRaid(self.draft) then self:MarkDirty(); self:RefreshUI() end
        end },
        { "Clear all", function() self.draft = self.NewRoster(); self:MarkDirty(); self:RefreshUI() end },
        { "Invite missing", function() self:InviteMissing(self.draft) end },
        { "Arrange groups", function() self:Arrange(nil, self.draft) end },
    }
    for i, a in ipairs(actions) do
        local b = C.CreateButton(frame, a[1], a[2], 170, 24)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 10 + (i - 1) * 180, -45)
    end

    -- Group grid: 4 columns x 2 rows
    for g = 1, 8 do
        local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
        local x, y = 10 + col * GROUP_COL_W, GRID_Y - row * BLOCK_H
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        header:SetText("Group " .. g)
        for s = 1, 5 do
            local slot = CreateSlot(frame, "group", SLOT_W, SLOT_H)
            slot.g, slot.s = g, s
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - 18 - (s - 1) * (SLOT_H + SLOT_GAP))
            table.insert(ui.groupSlots, slot)
        end
    end

    -- Unassigned: everyone in your raid/party who isn't placed in this roster
    local bench = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bench.kind = "bench"
    bench:SetPoint("TOPLEFT", frame, "TOPLEFT", BENCH_X - 4, GRID_Y + 4)
    bench:SetSize(2 * BENCH_COL_W + 4, 22 + BENCH_ROWS * 22)
    bench:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bench:SetBackdropColor(0, 0, 0, 0.2)
    bench:SetBackdropBorderColor(0, 1, 1, 0.15)
    ui.benchArea = bench
    local bh = bench:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bh:SetPoint("TOPLEFT", bench, "TOPLEFT", 4, -4)
    bh:SetText("Unassigned")
    for i = 1, BENCH_ROWS * 2 do
        local col, row = math.floor((i - 1) / BENCH_ROWS), (i - 1) % BENCH_ROWS
        local slot = CreateSlot(bench, "bench", BENCH_SLOT_W, 20)
        slot.i = i
        slot:SetPoint("TOPLEFT", bench, "TOPLEFT", 4 + col * BENCH_COL_W, -22 - row * 22)
        ui.benchSlots[i] = slot
    end
    ui.benchEmpty = bench:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.benchEmpty:SetPoint("TOPLEFT", bench, "TOPLEFT", 6, -26)
    ui.benchMore = bench:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.benchMore:SetPoint("BOTTOMRIGHT", bench, "BOTTOMRIGHT", -6, 4)

    ui.editor = CreateEditor(frame)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, GRID_Y - 2 * BLOCK_H - 4)
    hint:SetWidth(780)
    hint:SetJustifyH("LEFT")
    hint:SetText("Drag to move or swap. Double-click to type a name. Right-click to clear. Press Save to keep changes.")

    frame.RefreshOptions = function() self:RefreshUI() end   -- NSRT calls this on tab select
    self:RefreshUI()
end

function RaidUtility:RefreshUI()
    local ui = self.ui
    if not ui then return end
    local d = self.draft

    for _, slot in ipairs(ui.groupSlots) do
        local v = d[slot.g][slot.s] or ""
        slot.value = v
        slot.text:SetText(v ~= "" and v or "empty")
        slot.text:SetTextColor(EntryColor(v))
    end

    local list = self:GetUnassigned(d)
    for i, slot in ipairs(ui.benchSlots) do
        local name = list[i]
        slot.value = name
        if name then
            slot.text:SetText(name)
            slot.text:SetTextColor(EntryColor(name))
            slot:Show()
        else
            slot:Hide()
        end
    end
    local extra = #list - #ui.benchSlots
    ui.benchMore:SetText(extra > 0 and ("+" .. extra .. " more") or "")
    ui.benchEmpty:SetText(#list == 0 and (IsInGroup() and "Everyone is placed." or "Not in a group.") or "")

    ui.status:SetText(self.dirty and "|cFFFF9900Unsaved changes|r" or "|cFF55FF55Saved|r")
    ui.dropdown:Refresh()
end
