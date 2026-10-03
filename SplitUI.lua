-- Split Raid tab: preview two balanced sides, tweak by clicking, then send to the Rosters tab or arrange
local _, Extras = ...

local WHITE = "Interface\\Buttons\\WHITE8x8"
local COL_X     = { 10, 420 }
local COL_W     = 400
local ROW_H     = 18
local ROWS      = 20
local LIST_Y    = -112

local ROLE_ICON = {
    TANK    = INLINE_TANK_ICON or "T",
    HEALER  = INLINE_HEALER_ICON or "H",
    DAMAGER = INLINE_DAMAGER_ICON or "D",
}

local function Short(n)
    if n >= 1e6 then return format("%.2fM", n / 1e6) end
    if n >= 1e3 then return format("%.1fK", n / 1e3) end
    return format("%d", n)
end

local function CreateRow(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(COL_W - 10, ROW_H - 1)
    b:SetBackdrop({ bgFile = WHITE })
    b:SetBackdropColor(0, 0, 0, 0.35)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", 6, 0)
    b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.value:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0, 1, 1, 0.15) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0.35) end)
    b:SetScript("OnClick", function(self) Extras:MoveSplitPlayer(self.side, self.index) end)
    return b
end

function Extras:RunSplit()
    if not IsInRaid() then self.Print("You are not in a raid.") return end
    if InCombatLockdown() then self.Print("Can't read the damage meter in combat.") return end
    local players, withData = self:GetSplitPlayers()
    if not players then self.Print(withData) return end
    if withData == 0 then
        self.Print("No damage meter data yet, so this split only balances roles.")
    end
    self.split = { sides = self.BalanceSides(players), noData = withData == 0 }
    self:RefreshSplitUI()
end

function Extras:MoveSplitPlayer(from, index)
    local sides = self.split and self.split.sides
    if not (sides and sides[from].players[index]) then return end
    local to = 3 - from
    if #sides[to].players >= 20 then return end
    table.insert(sides[to].players, table.remove(sides[from].players, index))
    sides[from].count, sides[to].count = #sides[from].players, #sides[to].players
    self:RefreshSplitUI()
end

function Extras:SplitRoster()
    if not self.split then self.Print("Press Split raid first.") return end
    return self:SplitToRoster(self.split.sides, self.db.splitLayout)
end

function Extras:BuildSplitTab(frame, NSI)
    local C = NSI.UI.Components
    local ui = { rows = { {}, {} } }
    self.splitUI = ui
    self.db.splitLayout = self.GetSplitLayout(self.db.splitLayout).key

    ui.layout = C.CreateDropdown(frame, "Layout",
        function()
            local items = {}
            for _, l in ipairs(self.SplitLayouts) do
                items[#items + 1] = { label = l.label, value = l.key, onclick = function()
                    self.db.splitLayout = l.key
                    self:RefreshSplitUI()
                end }
            end
            return items
        end,
        function() return self.GetSplitLayout(self.db.splitLayout).label end, 300)
    ui.layout:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)

    local function TopButton(text, x, w, fn)
        local b = C.CreateButton(frame, text, fn, w, 22)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -10)
        return b
    end
    TopButton("Split raid", 330, 130, function() self:RunSplit() end)
    TopButton("Send to Rosters tab", 470, 170, function()
        local roster = self:SplitRoster()
        if not roster then return end
        self:ConfirmDiscard(function()
            self.draft = roster
            self:MarkDirty()
            if self.ui then self:RefreshUI() end
            if self.menu then self.menu:SelectTabByName(self.ROSTER_TAB) end
        end)
    end)
    TopButton("Arrange groups now", 650, 170, function()
        local roster = self:SplitRoster()
        if roster then self:Arrange(nil, roster) end
    end)

    ui.info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.info:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -44)
    ui.info:SetWidth(810)
    ui.info:SetJustifyH("LEFT")

    for s = 1, 2 do
        ui["header" .. s] = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ui["header" .. s]:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X[s], -72)
        ui["totals" .. s] = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ui["totals" .. s]:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X[s], -90)
        for i = 1, ROWS do
            local row = CreateRow(frame)
            row.side, row.index = s, i
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X[s], LIST_Y - (i - 1) * ROW_H)
            ui.rows[s][i] = row
        end
    end

    frame.RefreshOptions = function() self:RefreshSplitUI() end
    self:RefreshSplitUI()
end

function Extras:RefreshSplitUI()
    local ui = self.splitUI
    if not ui then return end
    ui.layout:Refresh()
    local split = self.split
    if not split then
        ui.info:SetText("Press Split raid to divide the raid into two sides. Tanks and healers are spread evenly, "
            .. "then players are balanced by the Overall damage meter session: DPS, or HPS for healers.")
    else
        ui.info:SetText((split.noData and "|cFFFF9900No damage meter data: balanced by role only.|r " or "")
            .. "Click a player to move them to the other side. Send to Rosters tab to review and save, "
            .. "or Arrange groups now.")
    end

    local groups = split and { self:GetSplitGroups(split.sides, self.db.splitLayout) }
    for s = 1, 2 do
        local side = split and split.sides[s]
        ui["header" .. s]:SetText(side and ("Side " .. s .. ": groups " .. table.concat(groups[s], ", ")) or "")
        if side then
            local t = self.SideTotals(side)
            ui["totals" .. s]:SetText(format("%d players   %s %d  %s %d  %s %d     DPS %s   HPS %s",
                #side.players, ROLE_ICON.TANK, t.TANK, ROLE_ICON.HEALER, t.HEALER, ROLE_ICON.DAMAGER, t.DAMAGER,
                Short(t.dps), Short(t.hps)))
        else
            ui["totals" .. s]:SetText("")
        end
        for i, row in ipairs(ui.rows[s]) do
            local p = side and side.players[i]
            if p then
                local c = p.class and RAID_CLASS_COLORS[p.class]
                row.name:SetText(ROLE_ICON[p.role] .. " " .. Ambiguate(p.name, "short"))
                if c then row.name:SetTextColor(c.r, c.g, c.b) else row.name:SetTextColor(1, 1, 1) end
                row.value:SetText(p.hasData and (Short(p.value) .. (p.role == "HEALER" and " HPS" or " DPS")) or "no data")
                row:Show()
            else
                row:Hide()
            end
        end
    end
end
