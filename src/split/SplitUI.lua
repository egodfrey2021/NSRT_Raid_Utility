-- Split controls on the Rosters tab: "Generate split" balances the raid into a new roster or the draft, and the
-- balance strip under the grid compares the draft's two sides as you edit it
local _, RaidUtility = ...

local L, Print = RaidUtility.L, RaidUtility.Print
local Widgets = RaidUtility.Widgets
local ROLE_ICON, Short, WHITE = Widgets.ROLE_ICON, Widgets.Short, Widgets.WHITE
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
    if need.kind == "lust" then return L["Side %s has no lust."]:format(side) end
    if need.kind == "rez" then return L["Side %s is short a brez."]:format(side) end
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
    local box = dialog.EditBox
    if not data then return end
    local name = RaidUtility.Trim(box and box:GetText() or "")
    if not RaidUtility:CreateRoster(name, data.roster, data.pins, true) then return end
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
        local box = dialog.EditBox
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

-- Players left out of the split stay on the roster. When only groups 1-4 play, keep them in groups 5-8.
function RaidUtility:KeepLeftOut(roster, leftOut, notes)
    if #leftOut == 0 then return end
    local members, minGroup = self.GetGroupMembers(), self:MaxGroup() == 4 and 5 or 1
    local function Free(g)
        for s = 1, 5 do
            if self.Trim(roster[g][s]) == "" then return s end
        end
    end
    local offline, benched, omitted = 0, 0, 0
    for _, member in ipairs(leftOut) do
        local g = member.subgroup or 8
        local s = g >= minGroup and Free(g)
        if not s then
            for candidate = 8, minGroup, -1 do
                s = Free(candidate)
                if s then
                    g = candidate
                    break
                end
            end
        end
        if s then
            roster[g][s] = member.entry or self.EntryName(member, members)
        else
            omitted = omitted + 1
        end
        if member.online == false then
            offline = offline + 1
        else
            benched = benched + 1
        end
    end
    if offline > 0 then notes[#notes + 1] = L["%d offline player(s) were left out of the split."]:format(offline) end
    if benched > 0 then
        notes[#notes + 1] = L["%d player(s) sitting out in groups 5-8 were left out (Groups 1-4 only)."]:format(benched)
    end
    if omitted > 0 then
        notes[#notes + 1] = L["%d player(s) left out of the split could not be kept on the roster."]:format(omitted)
    end
end

-- Balance the current raid into two sides and put the result in a new roster or the draft
-- (db.splitToNewRoster). A new roster asks before dropping edits; editing the open draft is undoable.
-- In a raid this splits the raid. Out of one (planning solo, e.g. after From damage meter) it splits the players on
-- the roster, with class, spec, role and DPS/HPS from the damage meter.
function RaidUtility:GenerateSplit()
    local inRaid = self.InRaid()
    if not inRaid and not self:HasEntries() then
        Print(L["Join a raid, or put players on the roster, to split."])
        return
    end
    if InCombatLockdown() then
        Print(L["Can't read the damage meter in combat."])
        return
    end
    local players, withData, noRole, meter, guessed, leftOut, unknown
    if inRaid then
        players, withData, noRole, meter, guessed, leftOut = self:GetSplitPlayers()
        if not players then
            Print(withData)
            return
        end
    else
        local members = self.GetGroupMembers()
        local err
        meter, err = self:ReadMeter(members)
        if not meter then
            Print(err)
            return
        end
        players, withData, noRole, guessed, leftOut, unknown = self:GetRosterSplitPlayers(self.draft, members, meter)
    end
    self:SetMeterReading(meter) -- the reading the split used, so the numbers on screen match it
    local opts, notes = self:SplitOptions(), {}
    if not inRaid then
        notes[#notes + 1] = L["Not in a raid, so the players on the roster were split, as the damage meter saw them."]
        if unknown > 0 then
            local missing =
                L["%d player(s) on the roster aren't on the damage meter and were counted as DPS with no data."]
            notes[#notes + 1] = missing:format(unknown)
        end
    end
    if self.db.splitMeterSource == "roles" then
        for _, p in ipairs(players) do
            p.value, p.dps, p.hps = 0, 0, 0
        end
        notes[#notes + 1] = L["Balanced by roles only; the damage meter was left out."]
    elseif withData == 0 then
        notes[#notes + 1] = L["No damage meter data yet, so this split only balances roles."]
    end
    if noRole > 0 then notes[#notes + 1] = L["%d player(s) have no role and were counted as DPS."]:format(noRole) end
    if opts.byPosition and guessed > 0 then
        notes[#notes + 1] = L["%d player(s) with an unknown spec were counted as ranged."]:format(guessed)
    end
    -- pins come from the draft, so they apply before they are saved
    local members = self.GetGroupMembers()
    local pins = self:MemberPins(members)
    for _, p in ipairs(players) do
        p.pin = pins[p.key] or (p.entry and self:PinOf(p.entry, members)) -- roster entries: pinned by their name
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
    if not sides then
        Print(short)
        return
    end
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
    self:KeepLeftOut(roster, leftOut, notes)
    if self.db.splitPI then
        -- each priest goes into the group of their best target on the same side ("Roles only" ranks by spec alone)
        -- "Roles only": who the meter's players are, without their numbers
        local reading = self.db.splitMeterSource == "roles" and self.MeterIdentities(meter) or meter
        local pairsList = self:AssignPI(roster, members, reading, self.db.splitLayout)
        self:PairPI(roster, members, pairsList, self.db.splitLayout, reading)
        for _, pair in ipairs(pairsList) do
            notes[#notes + 1] = self.PIPairText(pair)
        end
    end
    if self.db.splitToNewRoster then
        -- opening another roster resets Undo, so unsaved edits here are confirmed first
        self:ConfirmDiscard(function()
            local data = { roster = roster, notes = notes, pins = self.draftPins }
            StaticPopup_Show("NSRTRAIDUTILITY_SAVE_SPLIT", nil, nil, data)
        end)
    else
        -- into the open roster: an edit like any other, so Undo brings back what was there
        self.draft, self.draftSplit = roster, true
        self:MarkDirty()
        PrintNotes(notes)
        Print(L["Split done. Drag players to adjust it, then Save."])
        self:RefreshUI()
    end
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

    -- the split settings in a few words, and the way to change them (the setup panel)
    ui.summary = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.summary:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    ui.summary:SetWidth(235)
    ui.summary:SetHeight(30)
    ui.summary:SetJustifyH("LEFT")
    ui.summary:SetJustifyV("TOP")
    ui.changeSetup = C.CreateButton(strip, L["Change split setup"], function() self:ToggleSplitSetup() end, 150, 20)
    ui.changeSetup:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -36)

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

    -- outside a raid there are no sides to show: say where they are
    ui.noRaid = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.noRaid:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y - 4)
    ui.noRaid:SetWidth(780)
    ui.noRaid:SetJustifyH("LEFT")
    local noRaid = "Side totals and split setup appear in a raid, or once players are on the roster "
        .. "(e.g. From damage meter in Import/Export)."
    ui.noRaid:SetText(L[noRaid])
end

-- ------------------------------------------------------------
-- Split setup panel: every split setting in one place, next to the button that runs it. NSRT's checkboxes stay
-- open (its dropdown closes on every pick); a group of choices behaves like radio buttons.
-- ------------------------------------------------------------
local function Choices(list)
    local out = {}
    for _, c in ipairs(list) do
        out[#out + 1] = { value = c[1], label = c[2], tip = c[3] }
    end
    return out
end

-- Left column, then right column. key: the saved setting. choices: pick one; toggles: on/off each.
local GROUPS_TIP = "Leave groups 5-8 (players sitting out) out of the split, side totals and PI. "
    .. "On by default in a Mythic raid; offline players are always left out."
local NEW_ROSTER_TIP = "Checked: the split becomes a new roster. "
    .. "Unchecked: it replaces the open roster; Save to keep it."

local SETUP = {
    {
        {
            title = L["Sides"],
            key = "splitLayout",
            choices = (function() -- Split.lua (loaded first) defines the layouts
                local out = {}
                for _, l in ipairs(RaidUtility.SplitLayouts) do
                    out[#out + 1] = { value = l.key, label = l.label }
                end
                return out
            end)(),
        },
        {
            title = L["Balance on"],
            key = "splitMeterSource",
            readMeter = true,
            choices = Choices({
                {
                    "overall",
                    L["Overall session"],
                    L["The damage meter's Overall session: every fight since it was reset."],
                },
                { "lastfight", L["Last fight"], L["The last fight only: closest to how players do on this boss."] },
                { "roles", L["Roles only"], L["Ignore the damage meter: spread roles evenly and nothing else."] },
            }),
        },
        {
            title = L["Raid buffs"],
            key = "splitBuffs",
            choices = Choices({
                { "off", L["Ignore"] },
                { "even", L["On both sides"], L["Each raid buff on both sides when the raid has two of that class."] },
                {
                    "max",
                    L["Most damage from DH/Monk"],
                    L["On both sides, and a lone Demon Hunter or Monk where Chaos Brand/Mystic Touch adds the most."],
                },
            }),
        },
    },
    {
        {
            title = L["Also balance"],
            toggles = Choices({
                {
                    "splitMeleeRanged",
                    L["Even melee/ranged"],
                    L["Spread melee and ranged evenly among healers and DPS."],
                },
                {
                    "splitLustRez",
                    L["Lust and brez"],
                    L["Lust on each side, and up to 2 brez per side."],
                },
                {
                    "splitPI",
                    L["Group priests with PI targets"],
                    L["Move each priest into their best PI target's group, on their own side."],
                },
            }),
        },
        {
            title = L["PI priority"],
            key = "piPriority",
            choices = Choices({
                { "specs", L["Best specs (sims)"], L["Trust the PI sims: for teams that line PI up with cooldowns."] },
                { "balanced", L["Balanced"], L["Half sims, half each player's meter DPS."] },
                { "players", L["Best players (DPS)"], L["The players doing the most damage, whatever their spec."] },
            }),
        },
        {
            title = L["Who plays"],
            toggles = {
                {
                    value = "splitGroups14",
                    label = L["Groups 1-4 only"],
                    tip = L[GROUPS_TIP],
                    get = function() return RaidUtility:ActiveGroupsOnly() end,
                },
            },
        },
        {
            title = L["Result"],
            toggles = Choices({
                {
                    "splitToNewRoster",
                    L["As new roster"],
                    L[NEW_ROSTER_TIP],
                },
            }),
        },
    },
}

-- Re-checks every control from the saved settings
local function RefreshSetup(panel)
    local db = RaidUtility.db
    for _, control in ipairs(panel.controls) do
        local meta = panel.meta[control]
        if meta.key then
            control:SetValue(db[meta.key] == meta.choice)
        else
            control:SetValue(meta.get and meta.get() or db[meta.toggle])
        end
    end
end

function RaidUtility:BuildSplitSetup(frame, C, anchor)
    local ui = self.ui
    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    ui.setup = panel
    panel.controls = {}
    panel.meta = {} -- control -> { label, key + choice (one of a group) or toggle }; NSRT's objects stay untouched
    panel:SetSize(540, 352)
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    panel:SetBackdropColor(0.06, 0.08, 0.11, 0.98)
    panel:SetBackdropBorderColor(0, 0.7, 0.85)
    panel:Hide()
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
    title:SetText(L["Split setup"])

    local function Control(label, tip, getValue, onClick, x, y)
        local box = C.CreateCheckButton(panel, label, getValue, onClick, 250, 20)
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        panel.meta[box] = { label = label }
        if tip then Widgets.Tooltip(box.frame, tip) end
        panel.controls[#panel.controls + 1] = box
        return box
    end
    for col, sections in ipairs(SETUP) do
        local x, y = 14 + (col - 1) * 265, -36
        for _, section in ipairs(sections) do
            local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            heading:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
            heading:SetText(section.title)
            y = y - 16
            if section.key then
                for _, choice in ipairs(section.choices) do
                    local box = Control(
                        choice.label,
                        choice.tip,
                        function() return self.db[section.key] == choice.value end,
                        function()
                            self.db[section.key] = choice.value
                            RefreshSetup(panel)
                            self:RefreshUI(section.readMeter)
                        end,
                        x,
                        y
                    )
                    panel.meta[box].key, panel.meta[box].choice = section.key, choice.value
                    y = y - 20
                end
            else
                for _, toggle in ipairs(section.toggles) do
                    local box = Control(
                        toggle.label,
                        toggle.tip,
                        toggle.get or function() return self.db[toggle.value] end,
                        function(_, value)
                            self.db[toggle.value] = value
                            self:RefreshUI()
                        end,
                        x,
                        y
                    )
                    panel.meta[box].toggle, panel.meta[box].get = toggle.value, toggle.get
                    y = y - 20
                end
            end
            y = y - 8
        end
    end

    local generate = C.CreateButton(panel, L["Generate split"], function()
        panel:Hide()
        self:GenerateSplit()
    end, 150, 24)
    generate:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
    ui.generateButton = generate
    local close = C.CreateButton(panel, L["Close"], function() panel:Hide() end, 90, 24)
    close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 12)
    panel:SetScript("OnShow", RefreshSetup)
end

-- Split raid...: opens the setup panel (or closes it)
function RaidUtility:ToggleSplitSetup()
    local panel = self.ui and self.ui.setup
    if not panel then return end
    if panel:IsShown() then
        panel:Hide()
    else
        RefreshSetup(panel)
        panel:Show()
    end
end

-- "Overall, melee/ranged, lust/rez, buffs" for the strip
function RaidUtility:SplitOptionsSummary()
    local db = self.db
    local source = { overall = L["Overall"], lastfight = L["Last fight"], roles = L["Roles only"] }
    local parts = { source[db.splitMeterSource] or L["Overall"] }
    if db.splitMeleeRanged then parts[#parts + 1] = L["melee/ranged"] end
    if db.splitLustRez then parts[#parts + 1] = L["lust/brez"] end
    if db.splitPI then parts[#parts + 1] = L["PI"] end
    if self:ActiveGroupsOnly() then parts[#parts + 1] = L["groups 1-4"] end
    if db.splitBuffs == "even" then
        parts[#parts + 1] = L["buffs"]
    elseif db.splitBuffs == "max" then
        parts[#parts + 1] = L["buffs (most damage)"]
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
            list[#list + 1] = L["lust"]
        elseif need.kind == "rez" then
            list[#list + 1] = L["brez"]
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
    -- in a raid, or when planning a roster out of one (e.g. after From damage meter)
    if not (self.InRaid() or self:HasEntries()) then
        ui.balance:Hide()
        ui.noRaid:Show()
        return
    end
    ui.balance:Show()
    ui.noRaid:Hide()
    ui.summary:SetText(
        L["%1$s; %2$s."]:format(self.GetSplitLayout(self.db.splitLayout).label, self:SplitOptionsSummary())
    )
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
    if assumed > 0 then notes[#notes + 1] = L["%d without a role (counted as DPS)."]:format(assumed) end
    ui.balanceNote:SetText(table.concat(notes, "  "))
    local tallies = { self.Tally(a.utility), self.Tally(b.utility) }
    ui.missing:SetText(MissingText(self.Shortfalls(tallies, self:SplitOptions())))
    return sideOf
end

-- ------------------------------------------------------------
-- Post to raid: the sides and Power Infusion pairs, sent only when clicked
-- ------------------------------------------------------------
local CHAT_LIMIT = 250 -- chat messages are capped at 255 characters

-- The lines Post to raid would send for the current roster: the sides when it's a split, the PI pairs when that
-- option is on. Empty when there's nothing to post. pairsList: PI pairs already worked out this refresh (optional).
function RaidUtility:AssignmentLines(pairsList)
    local lines = {}
    if not self.InRaid() then return lines end
    if self.draftSplit then
        local _, groups = self.GroupSides(self.draft, self.db.splitLayout, self:MaxGroup())
        local split = L["Split: side A = groups %1$s; side B = groups %2$s"]
        lines[#lines + 1] = split:format(table.concat(groups[1], ", "), table.concat(groups[2], ", "))
    end
    if self.db.splitPI then
        pairsList = pairsList or self:AssignPI(self.draft, self.GetGroupMembers(), self.meter, self:PISides())
        local line = L["PI:"]
        for _, pair in ipairs(pairsList) do
            -- roster entries as written: Name-Realm stays when two players share a name
            local part = " " .. pair.priestEntry .. " -> " .. pair.target.entry
            if #line + #part + 1 > CHAT_LIMIT then
                lines[#lines + 1] = line
                line = L["PI:"]
            end
            line = line .. (line == L["PI:"] and "" or ",") .. part
        end
        if line ~= L["PI:"] then lines[#lines + 1] = line end
    end
    return lines
end

-- True while the game blocks addon chat (e.g. encounter restrictions in a boss fight)
function RaidUtility.ChatBlocked() return C_ChatInfo.InChatMessagingLockdown() == true end

function RaidUtility:PostAssignments()
    -- in combat, the PI pairs from the last refresh: a fresh look at the group could miss hidden names
    local cached = InCombatLockdown() and self.ui and self.ui.piPairs or nil
    local lines = self:AssignmentLines(cached)
    if #lines == 0 then
        Print(L["Nothing to post: generate a split, or turn on Group priests with PI targets."])
        return
    end
    if self.ChatBlocked() then
        Print(L["The game is blocking addon chat right now (encounter restrictions). Try again after the fight."])
        return
    end
    if self.Preview.IsActive() then
        Print(L["Preview: would post to raid chat:"])
        for _, line in ipairs(lines) do
            Print(line)
        end
        return
    end
    -- group finder raids talk in instance chat; RAID and PARTY don't reach them
    local channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or self.InRaid() and "RAID" or "PARTY"
    for _, line in ipairs(lines) do
        local ok = pcall(C_ChatInfo.SendChatMessage, line, channel)
        if not ok then
            Print(L["Could not post to chat; the game may be blocking addon chat right now."])
            return
        end
    end
end
