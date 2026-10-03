-- Split controls on the Rosters tab: "Generate split" balances the raid into a new roster or the draft, and the
-- balance strip under the grid compares the draft's two sides as you edit it
local _, RaidUtility = ...

local L, Print = RaidUtility.L, RaidUtility.Print
local ROLE_ICON, Short = RaidUtility.Widgets.ROLE_ICON, RaidUtility.Widgets.Short
local SIDE = { "A", "B" }

-- Notes about how the split was made, printed once it has actually been applied
local function PrintNotes(notes)
    for _, note in ipairs(notes) do
        Print(note)
    end
end

-- What a side is still short of, as a sentence
local function ShortfallText(need)
    local side = SIDE[need.side]
    if need.kind == "lust" then return L["Side %s has no Bloodlust."]:format(side) end
    if need.kind == "rez" then return L["Side %s is short of battle rezzes."]:format(side) end
    for _, buff in ipairs(RaidUtility.RAID_BUFFS) do
        if buff.class == need.key then return L["Side %1$s is missing %2$s."]:format(side, buff.name) end
    end
    return ""
end

-- The split options from saved settings, for BalanceSides and the shortfall checks
function RaidUtility:SplitOptions()
    local db = self.db
    return {
        byPosition = db.splitMeleeRanged,
        lustRez = db.splitLustRez,
        buffs = db.splitBuffs ~= "off",
        debuffMax = db.splitBuffs == "max",
    }
end

-- data: { roster, notes, pins } from GenerateSplit
local function AcceptSaveSplit(dialog, data)
    local box = dialog.EditBox or dialog.editBox
    if not data then return end
    local name = RaidUtility.Trim(box and box:GetText() or "")
    if not RaidUtility:CreateRoster(name, data.roster, data.pins) then return end
    PrintNotes(data.notes)
    Print(L["Saved the split as roster '%s'. Drag players to adjust it."]:format(name))
    RaidUtility:RefreshUI()
end

StaticPopupDialogs["NSRTRAIDUTILITY_SAVE_SPLIT"] = {
    text = L["Name for the new roster:"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(dialog)
        local box = dialog.EditBox or dialog.editBox
        if box then
            box:SetText(L["Split %s"]:format(date("%b %d %H:%M")))
            box:SetFocus()
        end
    end,
    OnAccept = AcceptSaveSplit,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        AcceptSaveSplit(dialog, dialog.data)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Balance the current raid into two sides and put the result in a new roster or the draft
-- (db.splitToNewRoster). Both replace the draft, so unsaved edits are confirmed first.
function RaidUtility:GenerateSplit()
    if not self.InRaid() then
        Print(L["You are not in a raid."])
        return
    end
    if InCombatLockdown() then
        Print(L["Can't read the damage meter in combat."])
        return
    end
    local players, withData, noRole, meter, guessed = self:GetSplitPlayers()
    if not players then
        Print(withData)
        return
    end
    self.meter = meter -- the reading the split used, so the numbers on screen match it
    local opts, notes = self:SplitOptions(), {}
    if self.db.splitMeterSource == "roles" then
        for _, p in ipairs(players) do
            p.value, p.dps, p.hps = 0, 0, 0
        end
        notes[#notes + 1] = L["Balanced by roles only; the damage meter was left out."]
    elseif withData == 0 then
        notes[#notes + 1] = L["No damage meter data yet, so this split only balances roles."]
    end
    if noRole > 0 then notes[#notes + 1] = L["%d player(s) have no role and were counted as damage."]:format(noRole) end
    if opts.byPosition and guessed > 0 then
        notes[#notes + 1] =
            L["%d player(s) have a spec that hasn't been seen yet and were counted as ranged."]:format(guessed)
    end
    -- pins come from the draft, so they apply before they are saved
    local pins = self:MemberPins(self.GetGroupMembers())
    for _, p in ipairs(players) do
        p.pin = pins[p.key]
    end
    -- damage each player counts for when placing Chaos Brand/Mystic Touch: their DPS, else their role's average
    -- (or a stand-in by role when nobody has meter data)
    local sum, n = {}, {}
    for _, p in ipairs(players) do
        if p.dps > 0 then
            sum[p.role], n[p.role] = (sum[p.role] or 0) + p.dps, (n[p.role] or 0) + 1
        end
    end
    local STAND_IN = { DAMAGER = 1, TANK = 0.5, HEALER = 0.1 }
    for _, p in ipairs(players) do
        p.debuffDps = p.dps > 0 and p.dps or (n[p.role] and sum[p.role] / n[p.role]) or STAND_IN[p.role]
    end
    local sides, short = self.BalanceSides(players, opts)
    if opts.debuffMax then
        for _, check in ipairs({ { "DEMONHUNTER", L["Chaos Brand"] }, { "MONK", L["Mystic Touch"] } }) do
            local where, count = nil, 0
            for side = 1, 2 do
                for _, p in ipairs(sides[side].players) do
                    if p.buff == check[1] then
                        where, count = side, count + 1
                    end
                end
            end
            if count == 1 then
                local placed = L["%1$s is on side %2$s, where it adds the most damage."]
                notes[#notes + 1] = placed:format(check[2], SIDE[where])
            end
        end
    end
    for _, need in ipairs(short) do
        notes[#notes + 1] = ShortfallText(need)
    end
    local roster = self:SplitToRoster(sides, self.db.splitLayout)
    self:ConfirmDiscard(function()
        if self.db.splitToNewRoster then
            local data = { roster = roster, notes = notes, pins = self.draftPins }
            StaticPopup_Show("NSRTRAIDUTILITY_SAVE_SPLIT", nil, nil, data)
        else
            self.draft = roster
            self:MarkDirty()
            PrintNotes(notes)
            Print(L["The split is in the draft. Drag players to adjust it, then Save."])
            self:RefreshUI()
        end
    end)
end

-- ------------------------------------------------------------
-- Balance strip
-- ------------------------------------------------------------
function RaidUtility:BuildBalanceStrip(frame, C, y)
    local ui = self.ui
    self.db.splitLayout = self.GetSplitLayout(self.db.splitLayout).key
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
    strip:SetSize(780, 60)
    ui.balance = strip

    -- NSRT gives a dropdown's own label half its width, which clips the layout names, so the label is separate
    local label = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -6)
    label:SetText(L["Sides:"])
    ui.layout = C.CreateDropdown(strip, "", function()
        local items = {}
        for _, l in ipairs(self.SplitLayouts) do
            items[#items + 1] = {
                label = l.label,
                value = l.key,
                onclick = function()
                    self.db.splitLayout = l.key
                    self:RefreshUI()
                end,
            }
        end
        return items
    end, function() return self.GetSplitLayout(self.db.splitLayout).label end, 195)
    ui.layout:SetPoint("TOPLEFT", strip, "TOPLEFT", 40, 0)

    -- Split options: toggles and the meter source. NSRT's dropdown closes on each pick and has no check marks, so
    -- the items carry [x] / (*) and the box shows a summary.
    local optionsLabel = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optionsLabel:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -32)
    optionsLabel:SetText(L["Split:"])
    ui.options = C.CreateDropdown(
        strip,
        "",
        function() return self:SplitOptionItems() end,
        function() return self:SplitOptionsSummary() end,
        195
    )
    ui.options:SetPoint("TOPLEFT", strip, "TOPLEFT", 40, -26)

    ui.sideText = {}
    for s = 1, 2 do
        local text = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", strip, "TOPLEFT", 250, -(s - 1) * 16)
        text:SetWidth(530)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false) -- one line each, so a long line can't spill onto the next side's
        ui.sideText[s] = text
    end
    -- one line each, never wrapped, so they can't run into the result lines below the strip
    ui.balanceNote = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.balanceNote:SetPoint("TOPLEFT", strip, "TOPLEFT", 250, -33)
    ui.balanceNote:SetWidth(530)
    ui.balanceNote:SetJustifyH("LEFT")
    ui.balanceNote:SetWordWrap(false)
    ui.missing = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.missing:SetPoint("TOPLEFT", strip, "TOPLEFT", 250, -47)
    ui.missing:SetWidth(530)
    ui.missing:SetJustifyH("LEFT")
    ui.missing:SetWordWrap(false)
end

local TOGGLES = {
    { key = "splitMeleeRanged", label = L["Even melee/ranged"], short = L["melee/ranged"] },
    { key = "splitLustRez", label = L["Bloodlust and battle rez on both sides"], short = L["lust/rez"] },
}
-- splitBuffs: "even" spreads every buff; "max" also places a lone Demon Hunter/Monk where its debuff adds most
local BUFF_MODES = {
    { value = "off", label = L["Raid buffs: ignore"] },
    { value = "even", label = L["Raid buffs: on both sides"], short = L["buffs"] },
    {
        value = "max",
        label = L["Raid buffs: on both sides, Chaos Brand/Mystic Touch for most damage"],
        short = L["buffs (most damage)"],
    },
}
local SOURCES = {
    { value = "overall", label = L["Balance on the Overall session"], short = L["Overall"] },
    { value = "lastfight", label = L["Balance on the last fight"], short = L["Last fight"] },
    { value = "roles", label = L["Balance on roles only"], short = L["Roles only"] },
}

function RaidUtility:SplitOptionItems()
    local db, items = self.db, {}
    for _, toggle in ipairs(TOGGLES) do
        items[#items + 1] = {
            label = (db[toggle.key] and "[x] " or "[  ] ") .. toggle.label,
            value = toggle.key,
            onclick = function()
                db[toggle.key] = not db[toggle.key]
                self:RefreshUI()
            end,
        }
    end
    for _, mode in ipairs(BUFF_MODES) do
        items[#items + 1] = {
            label = (db.splitBuffs == mode.value and "(*) " or "(  ) ") .. mode.label,
            value = mode.value,
            onclick = function()
                db.splitBuffs = mode.value
                self:RefreshUI()
            end,
        }
    end
    for _, source in ipairs(SOURCES) do
        items[#items + 1] = {
            label = (db.splitMeterSource == source.value and "(*) " or "(  ) ") .. source.label,
            value = source.value,
            onclick = function()
                db.splitMeterSource = source.value
                self:RefreshUI(true) -- a different session: read the meter again
            end,
        }
    end
    return items
end

-- "Overall, melee/ranged, lust/rez" for the dropdown box
function RaidUtility:SplitOptionsSummary()
    local parts = {}
    for _, source in ipairs(SOURCES) do
        if self.db.splitMeterSource == source.value then parts[1] = source.short end
    end
    for _, toggle in ipairs(TOGGLES) do
        if self.db[toggle.key] then parts[#parts + 1] = toggle.short end
    end
    for _, mode in ipairs(BUFF_MODES) do
        if mode.short and self.db.splitBuffs == mode.value then parts[#parts + 1] = mode.short end
    end
    return table.concat(parts, ", ")
end

-- "DPS: side B +4%." from two totals
local function Difference(a, b, more, even)
    if a == b then return even end
    local high, low = math.max(a, b), math.min(a, b)
    return more:format(SIDE[a > b and 1 or 2], math.floor((high - low) / high * 100 + 0.5))
end

-- "Missing on B: Bloodlust, Fortitude." for the strip, one clause per side
local function MissingText(short)
    local bySide = { {}, {} }
    for _, need in ipairs(short) do
        local list = bySide[need.side]
        if need.kind == "lust" then
            list[#list + 1] = L["Bloodlust"]
        elseif need.kind == "rez" then
            list[#list + 1] = L["battle rez"]
        else
            for _, buff in ipairs(RaidUtility.RAID_BUFFS) do
                if buff.class == need.key then list[#list + 1] = buff.short end
            end
        end
    end
    local parts = {}
    for s = 1, 2 do
        if #bySide[s] > 0 then
            parts[#parts + 1] = L["Missing on %1$s: %2$s."]:format(SIDE[s], table.concat(bySide[s], ", "))
        end
    end
    return table.concat(parts, "  ")
end

-- Fills the strip from the draft; returns group -> side for the group headers, or nil when it is hidden
function RaidUtility:RefreshBalance(members)
    local ui = self.ui
    ui.layout:Refresh()
    ui.options:Refresh()
    if not self.InRaid() then
        ui.balance:Hide()
        return
    end
    ui.balance:Show()
    local meter = self.meter
    local sides, sideOf, groups, assumed = self:RosterBalance(self.draft, members, self.db.splitLayout, meter)
    local a, b = sides[1], sides[2]
    local withData = a.withData + b.withData
    for s = 1, 2 do
        local t = sides[s]
        local text = L["Side %1$s (groups %2$s): %3$d players"]:format(
            SIDE[s],
            table.concat(groups[s], ", "),
            t.players
        ) .. format(
            "   %s %d  %s %d  %s %d",
            ROLE_ICON.TANK,
            t.TANK,
            ROLE_ICON.HEALER,
            t.HEALER,
            ROLE_ICON.DAMAGER,
            t.DAMAGER
        )
        if self.db.splitMeleeRanged then
            text = text .. "   " .. L["%1$d melee, %2$d ranged"]:format(t.MELEE, t.RANGED)
        end
        if withData > 0 then
            text = text .. "   " .. L["DPS"] .. " " .. Short(t.dps) .. "   " .. L["HPS"] .. " " .. Short(t.hps)
        end
        ui.sideText[s]:SetText(text)
    end

    local notes = {}
    if withData > 0 then
        notes[#notes + 1] = Difference(a.dps, b.dps, L["DPS: side %1$s +%2$d%%."], L["DPS: even."])
        notes[#notes + 1] = Difference(a.hps, b.hps, L["HPS: side %1$s +%2$d%%."], L["HPS: even."])
        local coverage = self.db.splitMeterSource == "lastfight" and L["%1$d/%2$d with meter data (last fight)."]
            or L["%1$d/%2$d with meter data (Overall)."]
        notes[#notes + 1] = coverage:format(withData, a.players + b.players)
    else
        notes[#notes + 1] = L["No damage meter data for these players yet."]
    end
    if self.db.splitMeterSource == "roles" then notes[#notes + 1] = L["Split uses roles only."] end
    if assumed > 0 then notes[#notes + 1] = L["%d without a role (counted as damage)."]:format(assumed) end
    ui.balanceNote:SetText(table.concat(notes, "  "))
    local tallies = { self.Tally(a.utility), self.Tally(b.utility) }
    ui.missing:SetText(MissingText(self.Shortfalls(tallies, self:SplitOptions())))
    return sideOf
end
