-- Rosters tab: drag-and-drop group grid + unplaced members list, with explicit Save/Revert. The split controls
-- and balance strip live in SplitUI.lua.
local _, RaidUtility = ...
local L, Print = RaidUtility.L, RaidUtility.Print
local Widgets = RaidUtility.Widgets
local WHITE, TopButton, ROLE_ICON = Widgets.WHITE, Widgets.TopButton, Widgets.ROLE_ICON
local SIDE_COLOR = Widgets.SIDE_COLOR

-- ------------------------------------------------------------
-- Popups
-- ------------------------------------------------------------
local function AcceptNewRoster(dialog)
    local box = dialog.EditBox
    if box and RaidUtility:CreateRoster(box:GetText()) then RaidUtility:RefreshUI() end
end

StaticPopupDialogs["NSRTRAIDUTILITY_NEW_ROSTER"] = {
    text = L["Name for the new roster:"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(dialog)
        local box = dialog.EditBox
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

-- A name popup prefilled by fill(); accept(name) returns true when it worked
local function NamePopup(text, fill, accept)
    local function Accept(dialog)
        local box = dialog.EditBox
        if box and accept(box:GetText()) then RaidUtility:RefreshUI() end
    end
    return {
        text = text,
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 40,
        OnShow = function(dialog)
            local box = dialog.EditBox
            if box then
                box:SetText(fill())
                box:SetFocus()
                box:HighlightText()
            end
        end,
        OnAccept = Accept,
        EditBoxOnEnterPressed = function(box)
            local dialog = box:GetParent()
            Accept(dialog)
            dialog:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

StaticPopupDialogs["NSRTRAIDUTILITY_RENAME_ROSTER"] = NamePopup(
    L["New name for this roster:"],
    function() return RaidUtility.db.active end,
    function(name) return RaidUtility:RenameRoster(name) end
)
StaticPopupDialogs["NSRTRAIDUTILITY_DUPLICATE_ROSTER"] = NamePopup(
    L["Name for the copy:"],
    function() return L["%s copy"]:format(RaidUtility.db.active) end,
    function(name) return RaidUtility:DuplicateRoster(name) end
)

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
    local box = dialog.EditBox
    local roster, overflow = RaidUtility:ImportText(box and box:GetText() or "")
    if not roster then
        Print(overflow)
        return
    end
    RaidUtility.draft, RaidUtility.draftSplit = roster, false
    RaidUtility:MarkDirty()
    RaidUtility:RefreshUI()
    local count = 0
    RaidUtility.ForEachEntry(roster, function() count = count + 1 end)
    Print(L["Imported %d name(s). Save to keep them."]:format(count))
    if overflow > 0 then Print(L["%d name(s) beyond slot 40 were ignored."]:format(overflow)) end
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
        local box = dialog.EditBox
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
local HISTORY = 40 -- messages kept for the History popup

-- Text and color for a slot: class color and role icon for group members (solo, that's you), grey for typed
-- names that aren't in the group (only while you are in one; offline planning shows plain names). The fourth
-- return is true for that grey "not in your group" case; the tooltip says it, so the name keeps its width.
-- A name the damage meter knows (someone not in the group) gets the class and role the meter saw: full color when
-- planning solo, still grey in a group, where "not in your group" matters. The fifth return is the meter's player.
local function SlotLabel(entry, members)
    if entry == "" then return L["empty"], 0.4, 0.4, 0.4 end
    local member = RaidUtility:ResolveGroupMember(entry, members)
    if not member then
        local seen = RaidUtility.meter and RaidUtility.meter.byName[RaidUtility.Trim(entry):lower()]
        local text = seen and ROLE_ICON[seen.role] and (ROLE_ICON[seen.role] .. " " .. entry) or entry
        if RaidUtility.InGroup() then return text, 0.55, 0.55, 0.55, true, seen end
        local c = seen and seen.class and RAID_CLASS_COLORS[seen.class]
        if c then return text, c.r, c.g, c.b, false, seen end
        return text, 1, 1, 1, false, seen
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

-- Markers take no name width: a pin is a colored bar on the left edge (the side's color), Power Infusion is its
-- spell icon on the right (dimmed on the priest giving it). Details are in the slot's tooltip.
local function ShowEntry(slot, entry, members)
    local text, r, g, b, absent, seen = SlotLabel(entry, members)
    local tips = {}
    if absent then tips[#tips + 1] = L["Not in your group."] end
    if seen then
        local spec = seen.specID and select(2, GetSpecializationInfoByID(seen.specID))
        tips[#tips + 1] = spec and L["%s, from the damage meter."]:format(spec) or L["Class from the damage meter."]
    end
    local pin = RaidUtility:PinOf(entry, members)
    if pin then
        slot.pinBar:SetColorTexture(SIDE_COLOR[pin][1], SIDE_COLOR[pin][2], SIDE_COLOR[pin][3], 0.9)
        slot.pinBar:Show()
        tips[#tips + 1] = L["Pinned to side %s for Generate split."]:format(pin == 1 and "A" or "B")
    else
        slot.pinBar:Hide()
    end
    local member = entry ~= "" and RaidUtility:EntrySource(entry, members, RaidUtility.meter)
    local tag = member and RaidUtility.ui.piTags[member.key] or nil -- nil, never false: "no tag" either way
    slot.piIcon:SetShown(tag ~= nil)
    slot.amount:ClearAllPoints()
    slot.amount:SetPoint("RIGHT", tag and -24 or -6, 0)
    if tag then
        -- full color on a target, dimmed on a priest who only gives it
        local shade = tag.gets and 1 or 0.5
        slot.piIcon:SetVertexColor(shade, shade, shade)
        if tag.gets then tips[#tips + 1] = L["Gets Power Infusion from %s."]:format(tag.gets) end
        if tag.gives then tips[#tips + 1] = L["Gives Power Infusion to %s."]:format(tag.gives) end
    end
    slot.tooltip = #tips > 0 and table.concat(tips, "\n") or nil
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

-- The window can close mid-drag (Escape), and then no drop arrives: put the drag back the way it was
local function ResetDrag()
    if ghost then ghost:Hide() end
    local source = RaidUtility.dragSource
    if source then source:SetAlpha(1) end
    RaidUtility.dragSource, RaidUtility.dragValue, RaidUtility.dragGroup = nil, nil, nil
end

-- Group headers drag whole groups: drop on another group's header or any of its slots to swap the two groups
local function GroupUnderMouse()
    local ui = RaidUtility.ui
    for g, handle in ipairs(ui.headerHandles) do
        if handle:IsMouseOver() then return g end
    end
    for _, slot in ipairs(ui.groupSlots) do
        if slot:IsVisible() and slot:IsMouseOver() then return slot.g end
    end
end

local function OnGroupDragStart(handle)
    RaidUtility.dragGroup = handle.g
    local g = GetGhost()
    g.text:SetText(L["Group %d"]:format(handle.g))
    g.text:SetTextColor(1, 0.82, 0)
    g:Show()
end

local function OnGroupDragStop()
    if ghost then ghost:Hide() end
    local from, to = RaidUtility.dragGroup, GroupUnderMouse()
    RaidUtility.dragGroup = nil
    if not (from and to) or from == to then return end
    local d = RaidUtility.draft
    d[from], d[to] = d[to], d[from]
    RaidUtility:MarkDirty()
    RaidUtility:RefreshUI()
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
    b.pinBar = b:CreateTexture(nil, "ARTWORK")
    b.pinBar:SetPoint("TOPLEFT", 1, -1)
    b.pinBar:SetPoint("BOTTOMLEFT", 1, 1)
    b.pinBar:SetWidth(3)
    b.pinBar:Hide()
    b.piIcon = b:CreateTexture(nil, "ARTWORK")
    b.piIcon:SetTexture(Widgets.PI_ICON)
    b.piIcon:SetSize(h - 6, h - 6)
    b.piIcon:SetPoint("RIGHT", -4, 0)
    b.piIcon:Hide()
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
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0, 1, 1, 0.6)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 0.08)
        if self.tooltip then GameTooltip:Hide() end
    end)
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
-- The result line: the newest message, and how many more came with it (all of them are in History). Messages
-- printed in the same frame belong to one action (a split prints several notes at once).
local function RefreshResult(ui)
    local banner = RaidUtility.Preview.Banner()
    local latest = ui.log[#ui.log] or ""
    if #ui.batch > 1 then
        latest = latest .. "  |cFF999999" .. L["(+%d more in History)"]:format(#ui.batch - 1) .. "|r"
    end
    ui.result:SetText(banner ~= "" and (banner .. "\n" .. latest) or latest)
    if #ui.log > 0 then
        ui.historyButton:Enable()
    else
        ui.historyButton:Disable()
    end
    if ui.history and ui.history:IsShown() then
        ui.history.text:SetText(table.concat(ui.log, "\n"))
        ui.history.content:SetHeight(math.max(200, (ui.history.text:GetStringHeight() or 0) + 8))
    end
end

-- Every recent message, scrollable: the full notes of a split, PI pairings, and so on
local function ShowHistory(frame, C)
    local ui = RaidUtility.ui
    local panel = ui.history
    if not panel then
        panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        ui.history = panel
        panel:SetSize(640, 290)
        panel:SetPoint("CENTER", frame, "CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:EnableMouse(true)
        panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
        panel:SetBackdropColor(0.06, 0.08, 0.11, 0.98)
        panel:SetBackdropBorderColor(0, 0.7, 0.85)
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
        title:SetText(L["History (newest last)"])
        local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -34)
        scroll:SetSize(588, 206)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(588, 200)
        scroll:SetScrollChild(content)
        panel.text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        panel.text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        panel.text:SetWidth(580)
        panel.text:SetJustifyH("LEFT")
        panel.content, panel.scroll = content, scroll
        local close = C.CreateButton(panel, L["Close"], function() panel:Hide() end, 90, 24)
        close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 12)
    end
    panel:Show()
    RefreshResult(ui)
    panel.scroll:SetVerticalScroll(panel.scroll:GetVerticalScrollRange()) -- newest at the bottom
end

local function ShowExchange(frame, C)
    local panel = RaidUtility.ui.exchange
    if panel then
        panel:Show()
        return
    end
    panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    RaidUtility.ui.exchange = panel
    panel:SetSize(700, 360)
    panel:SetPoint("CENTER", frame, "CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    panel:SetBackdropColor(0.06, 0.08, 0.11, 0.98)
    panel:SetBackdropBorderColor(0, 0.7, 0.85)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
    title:SetText(L["Import / export"])
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -37)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")
    local hintText = "WoWUtils exports keep group slots. WoWAudit encounter lists contain names only; "
        .. "importing fills slots in order."
    hint:SetText(L[hintText])
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -257)
    status:SetWidth(665)
    status:SetJustifyH("LEFT")
    local pasteHint = L["Paste a WoWAudit encounter export above, or use an export button to select text for copying."]
    status:SetText(pasteHint)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -77)
    scroll:SetSize(646, 172)
    local box = CreateFrame("EditBox", nil, scroll)
    panel.box = box
    box:SetWidth(626)
    box:SetHeight(172)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetScript("OnEscapePressed", function() panel:Hide() end)
    box:SetScript("OnTextChanged", function()
        panel.selected = nil
        box:SetHeight(math.max(172, box:GetNumLines() * 14 + 16))
        status:SetText(pasteHint)
    end)
    scroll:SetScrollChild(box)

    local encounters = {}
    local picker = C.CreateDropdown(panel, L["Encounter"], function()
        encounters = RaidUtility:WoWAuditEncounters(box:GetText())
        local items = {}
        for i, encounter in ipairs(encounters) do
            items[#items + 1] = {
                label = L["%1$s (%2$s)"]:format(encounter.name, encounter.difficulty),
                value = i,
                onclick = function() panel.selected = i end,
            }
        end
        return items
    end, function()
        local encounter = encounters[panel.selected]
        return encounter and L["%1$s (%2$s)"]:format(encounter.name, encounter.difficulty) or L["Select encounter"]
    end, 260)
    picker:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -281)
    panel.picker = picker

    local function Button(text, x, y, w, fn)
        local button = C.CreateButton(panel, text, fn, w, 24)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        return button
    end
    panel.import = Button(L["Import encounter"], 300, -281, 160, function()
        local choices = RaidUtility:WoWAuditEncounters(box:GetText())
        local index = panel.selected or (#choices == 1 and 1)
        if not index then
            RaidUtility.Print(L["Select a WoWAudit encounter to import."])
            return
        end
        local roster, overflow = RaidUtility:ImportWoWAuditEncounter(choices[index])
        if not roster then
            RaidUtility.Print(overflow)
            return
        end
        RaidUtility.draft, RaidUtility.draftSplit = roster, false
        RaidUtility:MarkDirty()
        RaidUtility:RefreshUI()
        panel:Hide()
        local count = 0
        RaidUtility.ForEachEntry(roster, function() count = count + 1 end)
        RaidUtility.Print(L["Imported %d name(s). Save to keep them."]:format(count))
        if overflow > 0 then RaidUtility.Print(L["%d name(s) beyond slot 40 were ignored."]:format(overflow)) end
        RaidUtility.Print(L["WoWAudit invite lists do not include raid group positions."])
    end)
    Button(L["Close"], 565, -281, 105, function() panel:Hide() end)
    Button(L["Import NSRT list"], 16, -321, 145, function()
        panel:Hide()
        StaticPopup_Show("NSRTRAIDUTILITY_IMPORT")
    end)
    Button(L["Export NSRT list"], 171, -321, 155, function()
        box:SetText(RaidUtility:ExportWoWUtils(RaidUtility.draft))
        box:SetFocus()
        box:HighlightText()
        status:SetText(L["Copy this list, group positions included, anywhere that takes an NSRT invite list."])
    end)
    Button(L["Export WoWAudit"], 336, -321, 165, function()
        local text, err = RaidUtility:ExportWoWAuditRaid()
        if not text then
            RaidUtility.Print(err)
            return
        end
        box:SetText(text)
        box:SetFocus()
        box:HighlightText()
        status:SetText(
            L["Copy this live group snapshot into a WoWAudit raid plan; it does not include group positions."]
        )
    end)
end

-- C: NSRT's widget library (NSI.UI.Components), from Core's tab injection
function RaidUtility:BuildRosterTab(frame, C)
    local ui = {
        frame = frame,
        groupSlots = {},
        benchSlots = {},
        headers = {},
        headerHandles = {},
        log = {},
        batch = {},
        reasons = {}, -- NSRT button -> why it's disabled (see SetEnabled)
    }
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

    -- a button's tooltip: what it does (a string, or a function for live text), and why it's off when it is
    local function Explain(button, tip)
        Widgets.Tooltip(button.frame, function()
            local base = type(tip) == "function" and tip() or tip
            local reason = ui.reasons[button]
            if not reason then return base end
            return (base and base .. "\n\n" or "") .. "|cFFFF6060" .. reason .. "|r"
        end)
    end
    local newButton = TopButton(C, frame, L["New"], 320, 70, function()
        self:ConfirmDiscard(function() StaticPopup_Show("NSRTRAIDUTILITY_NEW_ROSTER") end)
    end)
    Explain(newButton, L["Start an empty roster."])
    ui.duplicateButton = TopButton(
        C,
        frame,
        L["Duplicate"],
        395,
        90,
        function() StaticPopup_Show("NSRTRAIDUTILITY_DUPLICATE_ROSTER") end
    )
    Explain(ui.duplicateButton, L["Copy this roster, unsaved changes included, to a new one (e.g. one per boss)."])
    ui.renameButton = TopButton(
        C,
        frame,
        L["Rename"],
        490,
        80,
        function() StaticPopup_Show("NSRTRAIDUTILITY_RENAME_ROSTER") end
    )
    Explain(ui.renameButton, L["Rename this roster."])
    local deleteButton = TopButton(
        C,
        frame,
        L["Delete"],
        575,
        75,
        function() StaticPopup_Show("NSRTRAIDUTILITY_DELETE_ROSTER", self.db.active, nil, self.db.active) end
    )
    Explain(deleteButton, L["Delete this roster (asks first)."])
    ui.saveButton = TopButton(C, frame, L["Save"], 665, 70, function()
        self:SaveDraft()
        self:RefreshUI()
    end)
    Explain(ui.saveButton, L["Save your changes to this roster."])
    ui.undoButton = TopButton(C, frame, L["Undo"], 740, 70, function()
        if self:Undo() then self:RefreshUI() end
    end)
    Explain(ui.undoButton, L["Undo your last change (up to 20 steps)."])
    ui.revertButton = TopButton(C, frame, L["Revert"], 815, 75, function()
        self:ConfirmDiscard(function()
            self:LoadDraft()
            self:RefreshUI()
        end)
    end)
    Explain(ui.revertButton, L["Go back to the last save."])

    ui.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 900, -14)

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
        Explain(b, tooltip)
        return b
    end
    Label(L["Edit:"], 62)
    ui.fillButton = Action(L["Fill from raid"], 110, L["Copy your group's current layout into this roster."], function()
        if self:FillFromRaid(self.draft) then
            self.draftSplit = false
            self:MarkDirty()
            self:RefreshUI()
        end
    end)
    local splitTip = "Choose how to split the raid into two balanced sides, then generate the split."
    ui.splitButton = Action(L["Split raid..."], 120, L[splitTip], function() self:ToggleSplitSetup() end)
    local exchangeTip = "Import NSRT or WoWUtils lists, import WoWAudit encounters, or export for copying."
    Action(L["Import/Export"], 115, L[exchangeTip], function() ShowExchange(frame, C) end)
    ui.clearButton = Action(L["Clear all"], 80, L["Empty all 8 groups."], function()
        self.draft, self.draftSplit = self.NewRoster(), false
        self:MarkDirty()
        self:RefreshUI()
    end)
    rowX = rowX + 12 -- gap between the two groups
    Label(L["Raid:"], 38)
    local inviteTip = "Invite everyone on this roster who isn't in your group, unsaved changes included. "
        .. "/nru invite uses the saved roster."
    -- the tooltip lists who would get an invite, so nobody is surprised by one
    ui.inviteButton = Action(L["Invite missing"], 120, function()
        local list = self:MissingInvites(self.draft, ui.members)
        if #list == 0 then return L[inviteTip] end
        local shown = {}
        for i = 1, math.min(5, #list) do
            shown[i] = list[i]
        end
        local who = table.concat(shown, ", ") .. (#list > 5 and " " .. L["+%d more"]:format(#list - 5) or "")
        return L[inviteTip] .. "\n\n" .. L["Would invite: %s"]:format(who)
    end, function() self:InviteMissing(self.draft) end)
    local arrangeTip = "Sort the raid into these groups, unsaved changes included. /nru arrange uses the saved roster."
    ui.arrangeButton = Action(L["Sort groups"], 125, L[arrangeTip], function() self:Arrange(nil, self.draft) end)
    local piTip = "List who should get Power Infusion and move each priest into their target's group (/nru pi)."
    ui.piButton = Action(L["Power Infusion"], 130, L[piTip], function() self:PowerInfusion() end)

    -- a one-line legend, and what the slot numbers are (more in each slot's tooltip)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, HINT_Y)
    hint:SetWidth(780)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    local hintText = "Drag: move or swap.  Click empty / double-click: type.  Right-click: clear.  "
        .. "Shift-right-click: pin to side A/B.  Grey: not in your group."
    hint:SetText(L[hintText])
    ui.caption = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, HINT_Y - 14)
    ui.caption:SetWidth(780)
    ui.caption:SetJustifyH("LEFT")
    ui.caption:SetWordWrap(false)

    for g = 1, 8 do
        local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
        local x, y = 10 + col * GROUP_COL_W, GRID_Y - row * BLOCK_H
        -- the header is a handle: drag it onto another group to swap all five players
        local handle = CreateFrame("Button", nil, frame)
        handle:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y + 2)
        handle:SetSize(SLOT_W, 16)
        handle:RegisterForDrag("LeftButton")
        handle.g = g
        handle:SetScript("OnDragStart", OnGroupDragStart)
        handle:SetScript("OnDragStop", OnGroupDragStop)
        Widgets.Tooltip(handle, L["Drag onto another group to swap the two groups."])
        ui.headerHandles[g] = handle
        local header = handle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", handle, "TOPLEFT", 0, -2)
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
    self:BuildSplitSetup(frame, C, ui.splitButton.frame)

    -- Results (also printed to chat): the newest one under the strip, all recent ones in History
    ui.result = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.result:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, BALANCE_Y - 64)
    ui.result:SetWidth(580)
    ui.result:SetJustifyH("LEFT")
    ui.result:SetWordWrap(false)
    ui.postButton = C.CreateButton(frame, L["Post to raid"], function() self:PostAssignments() end, 95, 20)
    ui.postButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 600, BALANCE_Y - 62)
    Explain(ui.postButton, function()
        local lines = self:AssignmentLines(ui.piPairs)
        if #lines == 0 then return L["Send the split sides and PI assignments to raid chat."] end
        return L["Sends to raid chat:"] .. "\n" .. table.concat(lines, "\n")
    end)
    ui.historyButton = C.CreateButton(frame, L["History"], function() ShowHistory(frame, C) end, 90, 20)
    ui.historyButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 700, BALANCE_Y - 62)
    self.OnMessage = function(msg)
        local now = GetTime()
        if now ~= ui.batchTime then
            ui.batch, ui.batchTime = {}, now
        end
        table.insert(ui.batch, msg)
        table.insert(ui.log, msg)
        if #ui.log > HISTORY then table.remove(ui.log, 1) end
        RefreshResult(ui)
    end

    frame:HookScript("OnHide", ResetDrag) -- our own frame, but NSRT shows and hides it with its tabs
    -- NSRT calls this on tab select; the setup panel starts closed each time the tab comes back
    frame.RefreshOptions = function()
        ui.setup:Hide()
        self:RefreshUI(true)
    end
    self:RefreshUI(true)
end

-- reason: shown in the button's tooltip while it's off. Kept in ui.reasons, not on NSRT's button object.
local function SetEnabled(button, enabled, reason)
    RaidUtility.ui.reasons[button] = not enabled and reason or nil
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

local function ColorCode(rgb) return format("|cFF%02X%02X%02X", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255) end

-- What the slot numbers are, for the caption above the grid
local function NumbersCaption(self)
    if not self.meter or not next(self.meter.players) then
        return L["Slot numbers show DPS (HPS for healers) once the damage meter has data."]
    end
    local source = self.db.splitMeterSource
    local text
    if source == "lastfight" then
        text = L["Slot numbers: DPS (HPS for healers) in the last fight."]
    elseif source == "roles" then
        text = L["Slot numbers: Overall DPS (HPS for healers). The split ignores them (Balance on: Roles only)."]
    else
        text = L["Slot numbers: DPS (HPS for healers) over the damage meter's Overall session."]
    end
    -- a clock time rather than "N min ago", which would go stale between refreshes
    if self.meterTime then text = text .. " " .. L["Read at %s."]:format(self.meterTime) end
    return text
end

-- In combat the raid actions can't run (sorting, splitting and reading the meter refuse), so their buttons say so.
-- inCombat: PLAYER_REGEN_DISABLED fires just before InCombatLockdown() turns true, so the event passes it in.
function RaidUtility:ApplyCombatLock(inCombat)
    local ui = self.ui
    if not (ui and ui.frame:IsVisible()) or not (inCombat or InCombatLockdown()) then return end
    local reason = L["Not in combat."]
    local locked = { ui.arrangeButton, ui.splitButton, ui.generateButton, ui.piButton, ui.fillButton, ui.inviteButton }
    for _, button in ipairs(locked) do
        SetEnabled(button, false, reason)
    end
    ui.setup:Hide()
end

-- readMeter: take a fresh damage meter reading (tab shown, group changed, combat ended). Edits and drags reuse
-- the last one; in combat the last one is kept, since values can be secret then.
---@param readMeter boolean?
function RaidUtility:RefreshUI(readMeter)
    local ui = self.ui
    if not ui then return end
    local d = self.draft
    -- names can be hidden in combat, so keep the group as it was before the fight; it's re-read when combat ends
    local inCombat = InCombatLockdown()
    local members = inCombat and ui.members or self.GetGroupMembers()
    ui.members = members
    if readMeter and not InCombatLockdown() then self:SetMeterReading((self:ReadMeter(members))) end
    local piPairs
    ui.piTags, piPairs = self:PITags(members) -- the pairs are reused below, so they're worked out once
    ui.piPairs = piPairs -- and by Post to raid, which may be clicked in combat

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
        if sideOf and sideOf[g] then
            text = text .. "  " .. ColorCode(SIDE_COLOR[sideOf[g]]) .. (sideOf[g] == 1 and "A" or "B") .. "|r"
        end
        header:SetText(text)
    end

    -- tanks, then healers, then damage: raid leads look for "the healer I haven't placed"
    local list, rank = self:GetUnassigned(d, members), {}
    for _, name in ipairs(list) do
        local member = self:ResolveGroupMember(name, members)
        rank[name] = member and self.ROLE_ORDER[self:MemberRole(member)] or 4
    end
    table.sort(list, function(x, y)
        if rank[x] ~= rank[y] then return rank[x] < rank[y] end
        return x:lower() < y:lower()
    end)
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

    local noRaid, empty = L["Join a raid first (or try /nru preview)."], L["This roster is empty."]
    local leads = self.Preview.IsActive() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    SetEnabled(ui.saveButton, self.dirty, L["No unsaved changes."])
    SetEnabled(ui.undoButton, self:CanUndo(), L["Nothing to undo."])
    local nothingToPost = L["Nothing to post: generate a split, or turn on Group priests with PI targets."]
    local chatBlocked = self.ChatBlocked()
    local postReason = chatBlocked and L["The game is blocking addon chat right now."] or nothingToPost
    SetEnabled(ui.postButton, not chatBlocked and #self:AssignmentLines(piPairs) > 0, postReason)
    SetEnabled(ui.revertButton, self.dirty, L["No unsaved changes."])
    SetEnabled(ui.fillButton, inGroup, L["Join a group first."])
    -- out of a raid, the roster's players can still be split (with what the damage meter knows about them)
    local canSplit, noSplit = inRaid or total > 0, L["Join a raid, or put players on the roster, to split."]
    SetEnabled(ui.splitButton, canSplit, noSplit)
    SetEnabled(ui.generateButton, canSplit, noSplit)
    SetEnabled(ui.clearButton, total > 0, empty)
    SetEnabled(ui.inviteButton, total > 0, empty)
    SetEnabled(ui.piButton, total > 0, empty) -- the meter knows players out of a raid too
    local arrangeReason = not inRaid and noRaid or total == 0 and empty or L["You need to be raid leader or assistant."]
    SetEnabled(ui.arrangeButton, inRaid and total > 0 and leads, arrangeReason)
    if not canSplit and ui.setup:IsShown() then ui.setup:Hide() end
    ui.caption:SetText(inCombat and L["In combat: names and numbers update when combat ends."] or NumbersCaption(self))
    self:ApplyCombatLock()

    RefreshResult(ui)
    ui.status:SetText(self.dirty and "|cFFFF9900" .. L["Unsaved changes"] .. "|r" or "")
    ui.dropdown:Refresh()
end
