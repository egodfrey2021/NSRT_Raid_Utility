-- Split.lua and SplitUI.lua: reading the damage meter, balancing sides, Generate split and the balance strip
local H = ...
local utility, Member, test = H.utility, H.Member, H.test

Enum = { DamageMeterSessionType = { Overall = 1 }, DamageMeterType = { DamageDone = 2, HealingDone = 3 } }
C_DamageMeter = {}

-- Swaps the meter stub (one assignment site, so the editor doesn't see six definitions of the same field)
local function SetMeter(fn) C_DamageMeter.GetCombatSessionFromType = fn end
-- The stored-session API used by "last fight" (nil, nil to remove it again)
local function SetStoredSessions(list, fetch)
    C_DamageMeter.GetAvailableCombatSessions, C_DamageMeter.GetCombatSessionFromID = list, fetch
end

local function Twins() H.SetRaid({ Member("Twin", "Home"), Member("Twin", "Away", "Twin-Away") }) end

test("meter values attach to the right realm", function()
    Twins()
    SetMeter(function(_, meterType)
        if meterType == 2 then
            return {
                combatSources = {
                    { name = "Twin-Away", amountPerSecond = 150 },
                    { name = "Twin", amountPerSecond = 999 },
                },
            }
        end
        return { combatSources = {} }
    end)
    local players, count = utility:GetSplitPlayers()
    assert(#players == 2 and count == 1)
    assert(players[1].hasData == false and players[2].value == 150, "meter values crossed realms")
end)

test("a missing session allows a role-only split", function()
    Twins()
    SetMeter(function() return nil end)
    local players, count = utility:GetSplitPlayers()
    assert(#players == 2 and count == 0)
end)

test("meter errors are reported, not treated as empty", function()
    Twins()
    SetMeter(function() error("meter failure") end)
    local players, count = utility:GetSplitPlayers()
    assert(players == nil and count:find("meter failure"), "meter error was mistaken for empty data")
    SetMeter(function(_, meterType)
        if meterType == 3 then error("healing failure") end
        return nil
    end)
    players, count = utility:GetSplitPlayers()
    assert(players == nil and count:find("healing failure"), "healing meter failure was ignored")
end)

local function Src(name, value, guid) return { name = name, amountPerSecond = value, sourceGUID = guid } end
local function DamageMeter(sources)
    SetMeter(function(_, meterType) return { combatSources = meterType == 2 and sources or {} } end)
end

test("meter GUID match beats a misleading name", function()
    H.SetRaid({ Member("Alice", "Home"), Member("Bob", "Home") })
    -- the name says Alice but the GUID is Bob's
    DamageMeter({ Src("Alice", 500, "Player-Bob-Home") })
    local players, count = utility:GetSplitPlayers()
    assert(count == 1 and players[2].value == 500 and not players[1].hasData, "GUID did not win over the name")
end)

test("meter falls back to the name when sourceGUID is secret or missing", function()
    H.SetRaid({ Member("Alice", "Home"), Member("Bob", "Home") })
    H.secret = { ["secret-guid"] = true }
    DamageMeter({ Src("Alice", 300, "secret-guid"), Src("Bob", 200) })
    local players, count = utility:GetSplitPlayers()
    H.secret = nil
    assert(count == 2 and players[1].value == 300 and players[2].value == 200, "name fallback failed")
end)

test("spec role fills in a missing role and the rest are counted", function()
    H.SetRaid({
        Member("Tanky", "Home", nil, "NONE"),
        Member("Nobody", "Home", nil, "NONE"),
        Member("Bob", "Home"),
    })
    DamageMeter({})
    local NSI = _G.NorthernSkyRaidTools
    NSI.GetSpecs = function(_, unit) return unit == "raid1" and 73 or nil end
    local old = _G.GetSpecializationInfoByID
    _G.GetSpecializationInfoByID = function() return 73, "Protection", "", 0, "TANK" end
    local players, _, noRole = utility:GetSplitPlayers()
    NSI.GetSpecs, _G.GetSpecializationInfoByID = nil, old
    assert(players[1].role == "TANK" and not players[1].assumedRole, "spec role not used")
    assert(players[2].role == "DAMAGER" and players[2].assumedRole, "role-less player not marked")
    assert(players[3].role == "DAMAGER" and not players[3].assumedRole)
    assert(noRole == 1, "noRole count wrong")
end)

test("equal values are ordered by name", function()
    local function Sides(names)
        local players = {}
        for _, n in ipairs(names) do
            players[#players + 1] = { name = n, role = "DAMAGER", value = 0, dps = 0, hps = 0 }
        end
        return utility.BalanceSides(players)
    end
    local function Names(side)
        local out = {}
        for _, p in ipairs(side.players) do
            out[#out + 1] = p.name
        end
        return table.concat(out, ",")
    end
    local a = Sides({ "delta", "Alpha", "charlie", "Bravo" })
    local b = Sides({ "Bravo", "charlie", "Alpha", "delta" })
    assert(Names(a[1]) == Names(b[1]) and Names(a[2]) == Names(b[2]), "order depends on input")
    assert(Names(a[1]) == "Alpha,charlie" and Names(a[2]) == "Bravo,delta", Names(a[1]) .. " | " .. Names(a[2]))
    local roster = utility:SplitToRoster(a, "consecutive")
    assert(roster[1][1] == "Alpha" and roster[1][2] == "charlie", "roster tie order")
end)

-- A four-player raid with damage numbers, and the Rosters tab built for it
local function SplitRaid()
    H.SetRaid({
        Member("Ann", "Home", nil, "TANK"),
        Member("Bob", "Home", nil, "HEALER"),
        Member("Cid", "Home"),
        Member("Dee", "Home"),
    })
    DamageMeter({ Src("Ann", 1500), Src("Cid", 1000), Src("Dee", 500) })
    H.NSRTWindow()
    utility:LoadDraft()
    utility:BuildRosterTab(H.Frame(), _G.NorthernSkyRaidTools)
    H.popup = nil
end

local function DraftNames()
    local names = {}
    utility.ForEachEntry(utility.draft, function(_, _, entry) names[#names + 1] = entry end)
    table.sort(names)
    return table.concat(names, ",")
end

test("a failed split leaves the draft alone", function()
    SplitRaid()
    SetMeter(function() error("meter failure") end)
    utility.draft[1][1] = "Keep"
    utility:GenerateSplit()
    assert(utility.draft[1][1] == "Keep" and not H.popup, "failed split changed the draft")
    assert(H.LastMessage():find("meter failure"), H.LastMessage())
    utility:LoadDraft()
end)

test("Generate split makes a new roster when the toggle is on", function()
    SplitRaid()
    utility.db.splitToNewRoster = true
    local activeBefore = utility.db.active
    local rosterBefore = utility.CopyRoster(utility.db.rosters[activeBefore])
    utility:GenerateSplit()
    assert(H.popup and H.popup.which == "NSRTRAIDUTILITY_SAVE_SPLIT" and H.popup.data, "naming popup not shown")
    local dialog = StaticPopupDialogs.NSRTRAIDUTILITY_SAVE_SPLIT
    local box = {
        text = "",
        SetText = function(self, t) self.text = t end,
        SetFocus = function() end,
        GetText = function(self) return self.text end,
    }
    dialog.OnShow({ EditBox = box })
    assert(box.text:find("^Split "), "name not prefilled")
    box.text = "Split Test"
    assert(H.popup.data.roster and H.popup.data.notes, "popup data should carry the roster and its notes")
    dialog.OnAccept({ EditBox = box }, H.popup.data)
    assert(utility.db.active == "Split Test" and not utility.dirty, "roster not created")
    assert(DraftNames() == "Ann,Bob,Cid,Dee", DraftNames())
    for g = 1, 8 do
        for s = 1, 5 do
            assert(utility.db.rosters[activeBefore][g][s] == rosterBefore[g][s], "previous roster changed")
        end
    end
    assert(utility.ui.result.text:find("Split Test", 1, true), "result not shown in the tab")
    utility:DeleteRoster("Split Test")
    utility.db.active = activeBefore
    utility:LoadDraft()
end)

test("with the toggle off, Generate split replaces the draft after confirming unsaved edits", function()
    SplitRaid()
    utility.db.splitToNewRoster = false
    local active = utility.db.active
    utility.draft[1][1] = "Old"
    utility:MarkDirty()
    utility:GenerateSplit()
    assert(H.popup and H.popup.which == "NSRTRAIDUTILITY_DISCARD", "unsaved edits not confirmed")
    assert(utility.draft[1][1] == "Old", "draft replaced before confirmation")
    H.popup.data()
    assert(DraftNames() == "Ann,Bob,Cid,Dee" and utility.dirty, DraftNames())
    assert(utility.db.active == active and utility.db.rosters[active][1][1] ~= "Ann", "saved roster was changed")
    utility.db.splitToNewRoster = true
    utility:LoadDraft()
end)

test("the As new roster checkbox saves its setting", function()
    SplitRaid()
    utility.db.splitToNewRoster = true
    local box = utility.ui.splitTarget
    assert(box:GetValue() == true)
    box:Click()
    assert(utility.db.splitToNewRoster == false, "unchecking was not saved")
    box:Click()
    assert(utility.db.splitToNewRoster == true)
end)

test("groups map to sides for both layouts, matching SplitToRoster", function()
    local roster = utility.NewRoster()
    for g = 1, 4 do
        roster[g][1] = "x" .. g
    end
    local sideOf = utility.GroupSides(roster, "oddeven")
    assert(sideOf[1] == 1 and sideOf[2] == 2 and sideOf[3] == 1 and sideOf[4] == 2)
    sideOf = utility.GroupSides(roster, "consecutive")
    assert(sideOf[1] == 1 and sideOf[2] == 1 and sideOf[3] == 2 and sideOf[4] == 2)
    -- a 25-player split uses three groups per side
    local players = {}
    for i = 1, 25 do
        players[i] = { key = "p" .. i, name = "P" .. i, role = "DAMAGER", value = i, dps = i, hps = 0 }
    end
    local sides = utility.BalanceSides(players)
    for _, layout in ipairs({ "oddeven", "consecutive" }) do
        local split = utility:SplitToRoster(sides, layout)
        local sideOfGroup = utility.GroupSides(split, layout)
        local onSide = {}
        for s = 1, 2 do
            for _, p in ipairs(sides[s].players) do
                onSide[p.name] = s
            end
        end
        utility.ForEachEntry(
            split,
            function(g, _, entry)
                assert(sideOfGroup[g] == onSide[entry], layout .. ": " .. entry .. " mapped to the wrong side")
            end
        )
    end
end)

test("the balance strip compares the draft's sides", function()
    SplitRaid()
    utility.db.splitLayout = "oddeven"
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[1][2] = "Ann", "Bob" -- side A
    utility.draft[2][1], utility.draft[2][2] = "Cid", "Dee" -- side B
    utility.draft[2][3] = "Offline"
    utility:RefreshUI(true) -- reads the meter, no split needed
    local ui = utility.ui
    assert(ui.balance.visible, "strip hidden in a raid")
    assert(ui.sideText[1].text:find("Side A (groups 1): 2 players", 1, true), ui.sideText[1].text)
    assert(ui.sideText[1].text:find("[T] 1  [H] 1  [D] 0", 1, true), ui.sideText[1].text)
    assert(ui.sideText[2].text:find("Side B (groups 2): 2 players", 1, true), ui.sideText[2].text)
    assert(ui.sideText[1].text:find("DPS 1.5K", 1, true), ui.sideText[1].text)
    -- 1500 vs 1500 DPS; healing is all zero
    assert(ui.balanceNote.text:find("DPS: even.", 1, true), ui.balanceNote.text)
    assert(ui.balanceNote.text:find("3/4 with meter data (Overall)", 1, true), ui.balanceNote.text)
    assert(ui.headers[1].text:find("(2/5)", 1, true) and ui.headers[1].text:find("A"), ui.headers[1].text)
    assert(ui.headers[2].text:find("(3/5)", 1, true) and ui.headers[2].text:find("B"), ui.headers[2].text)
    -- meter numbers on each row: DPS for Ann (tank) and Cid, nothing for a healer without healing data
    assert(ui.groupSlots[1].amount.text == "1.5K", tostring(ui.groupSlots[1].amount.text))
    assert(ui.groupSlots[2].amount.text == "", "Bob has no HPS, so no number")
    assert(ui.groupSlots[6].amount.text == "1.0K" and ui.groupSlots[8].amount.text == "", "typed name got a number")
    utility.draft[2][2] = ""
    utility:RefreshUI()
    assert(ui.balanceNote.text:find("DPS: side A +33%.", 1, true), ui.balanceNote.text)
    utility.meter = nil
    utility:RefreshUI()
    assert(not ui.sideText[1].text:find("DPS"), "DPS shown without meter data")
    assert(ui.groupSlots[1].amount.text == "", "number shown without meter data")
    assert(ui.balanceNote.text:find("No damage meter data"), ui.balanceNote.text)
    H.SetParty({ Member("Ann", "Home") })
    utility:RefreshUI()
    assert(not ui.balance.visible, "strip shown outside a raid")
    assert(not ui.headers[1].text:find("A", 1, true), "side marker shown outside a raid")
    utility:LoadDraft()
end)

test("solo, the tab reads your own numbers from the meter", function()
    SplitRaid()
    H.raid, H.party, H.group = false, false, {}
    DamageMeter({ Src("Tester", 2500, "Player-Tester-Home") })
    utility.draft = utility.NewRoster()
    utility.draft[1][1] = "Tester"
    utility:RefreshUI(true)
    assert(utility.ui.groupSlots[1].amount.text == "2.5K", tostring(utility.ui.groupSlots[1].amount.text))
    -- in combat the last reading is kept (values can be secret then)
    DamageMeter({ Src("Tester", 9000, "Player-Tester-Home") })
    H.inCombat = true
    utility:RefreshUI(true)
    H.inCombat = false
    assert(utility.ui.groupSlots[1].amount.text == "2.5K", "meter re-read in combat")
    utility:RefreshUI() -- an edit or drag reuses the reading
    assert(utility.ui.groupSlots[1].amount.text == "2.5K", "meter re-read without a refresh event")
    utility:LoadDraft()
end)

-- Damage and healing sessions with separate sources, for the meter import
local function Meter(damage, healing)
    SetMeter(function(_, meterType) return { combatSources = meterType == 2 and damage or healing } end)
end

test("From damage meter fills empty slots with everyone the meter saw, by role and value", function()
    SplitRaid()
    local spec = { _G.GetNumClasses, _G.C_SpecializationInfo, _G.GetSpecializationInfoForClassID }
    _G.GetNumClasses = function() return 1 end
    _G.C_SpecializationInfo = { GetNumSpecializationsForClassID = function() return 2 end }
    _G.GetSpecializationInfoForClassID = function(_, i)
        if i == 1 then return 1, "Restoration", "", 111, "HEALER" end
        return 2, "Fire", "", 222, "DAMAGER"
    end
    local gone = Src("Gone-Away", 300, "Player-Gone-Away")
    gone.specIconID, gone.classFilename = 111, "PRIEST" -- left the group; a healer by spec
    Meter({ Src("Ann", 1500), Src("Cid", 1000), Src("Wolf", 900, "Creature-0-1-2-3-4-5"), gone }, {
        Src("Bob", 4000),
        Src("Gone-Away", 5000, "Player-Gone-Away"),
    })
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[1][2] = "Cid", "Keep"
    utility.dirty = false
    utility:ImportFromMeter()
    _G.GetNumClasses, _G.C_SpecializationInfo, _G.GetSpecializationInfoForClassID = spec[1], spec[2], spec[3]
    local d = utility.draft
    assert(d[1][1] == "Cid" and d[1][2] == "Keep", "existing placements moved")
    assert(d[1][3] == "Ann", "tank not first: " .. d[1][3])
    assert(d[1][4] == "Gone-Away" and d[1][5] == "Bob", "healers not ordered by HPS: " .. d[1][4] .. "," .. d[1][5])
    assert(d[2][1] == "", "a pet or creature was imported: " .. d[2][1])
    assert(utility.dirty and H.LastMessage():find("Added 3", 1, true), H.LastMessage())
    -- a typed name of someone who left still gets their number, and stays tagged as not in the group
    local slot = utility.ui.groupSlots[4]
    assert(
        slot.amount.text == "5.0K" and slot.text.text:find("not in group"),
        slot.amount.text .. " " .. slot.text.text
    )
    utility:ImportFromMeter()
    assert(H.LastMessage():find("already on the roster", 1, true), H.LastMessage())
    utility:LoadDraft()
end)

test("From damage meter reports players that don't fit", function()
    SplitRaid()
    Meter({ Src("Ann", 1500), Src("Cid", 1000) }, {})
    for g = 1, 8 do
        for s = 1, 5 do
            utility.draft[g][s] = (g == 8 and s == 5) and "" or ("N" .. g .. s)
        end
    end
    utility:ImportFromMeter()
    assert(utility.draft[8][5] == "Ann", utility.draft[8][5])
    assert(H.LastMessage():find("1 player(s) from the damage meter were not added", 1, true), H.LastMessage())
    utility:LoadDraft()
end)

test("From damage meter is refused in combat and lives in the Import dialog", function()
    SplitRaid()
    local dialog = StaticPopupDialogs.NSRTRAIDUTILITY_IMPORT
    assert(dialog.button3 == "From damage meter" and dialog.OnAlt, "button missing from the Import dialog")
    H.inCombat = true
    utility.draft = utility.NewRoster()
    dialog.OnAlt()
    H.inCombat = false
    assert(utility.draft[1][1] == "" and H.LastMessage():find("in combat"), H.LastMessage())
    utility:LoadDraft()
end)

test("a split writes Name-Realm for players who share a name, so every entry resolves", function()
    SplitRaid()
    Twins()
    DamageMeter({})
    utility.db.splitToNewRoster = false
    utility.dirty = false
    utility:GenerateSplit()
    local members = utility.GetGroupMembers()
    assert(DraftNames() == "Twin-Away,Twin-Home", DraftNames())
    assert(#utility:GetUnassigned(utility.draft, members) == 0, "a split entry did not resolve to its player")
    utility.db.splitToNewRoster = true
    utility:LoadDraft()
end)

test("split notes print only once the split is applied", function()
    SplitRaid()
    H.SetRaid({ Member("Ann", "Home", nil, "TANK"), Member("Nobody", "Home", nil, "NONE") })
    utility.db.splitToNewRoster = false
    utility.draft[1][1] = "Edited"
    utility:MarkDirty()
    local before = #H.messages
    utility:GenerateSplit()
    assert(#H.messages == before, "printed before the discard was confirmed: " .. H.LastMessage())
    H.popup.data()
    local notes = table.concat(H.messages, "\n", before + 1)
    assert(notes:find("1 player(s) have no role", 1, true) and notes:find("is in the draft", 1, true), notes)
    utility.db.splitToNewRoster = true
    utility:LoadDraft()
end)

test("Even melee/ranged keeps melee apart without giving up the DPS balance", function()
    local function P(name, position, value)
        return { name = name, role = "DAMAGER", position = position, value = value, dps = value, hps = 0 }
    end
    local players =
        { P("Big", "MELEE", 100), P("Small", "MELEE", 1), P("RangeA", "RANGED", 50), P("RangeB", "RANGED", 49) }
    local function Melee(side)
        local n = 0
        for _, p in ipairs(side.players) do
            if p.position == "MELEE" then n = n + 1 end
        end
        return n
    end
    local plain = utility.BalanceSides(players)
    assert(Melee(plain[1]) ~= Melee(plain[2]), "fixture no longer stacks melee without the option")
    local sides = utility.BalanceSides(players, { byPosition = true })
    assert(Melee(sides[1]) == 1 and Melee(sides[2]) == 1, "melee not spread evenly")
    -- the side that got the weak melee player gets the stronger ranged one
    local function Has(side, name)
        for _, p in ipairs(side.players) do
            if p.name == name then return true end
        end
    end
    local weak = Has(sides[1], "Small") and sides[1] or sides[2]
    assert(Has(weak, "RangeA"), "ranged not used to even out the totals")
end)

test("melee or ranged comes from the spec, then the class", function()
    H.SetRaid({
        Member("Enh", "Home"), -- spec from NSRT's cache: Enhancement (melee)
        Member("Rogue", "Home"),
        Member("Lock", "Home"),
        Member("Hunter", "Home"),
        Member("Pally", "Home", nil, "HEALER"),
    })
    H.group[2].class, H.group[3].class, H.group[4].class, H.group[5].class = "ROGUE", "WARLOCK", "HUNTER", "PALADIN"
    local NSI = _G.NorthernSkyRaidTools
    NSI.GetSpecs = function(_, unit) return unit == "raid1" and 263 or nil end
    local members = utility.GetGroupMembers()
    local function Position(i, role) return utility:MemberPosition(members[i], role or "DAMAGER") end
    assert(Position(1) == "MELEE", "spec from NSRT not used")
    assert(Position(2) == "MELEE" and Position(3) == "RANGED", "class not used")
    local position, guessed = Position(4)
    assert(position == "RANGED" and guessed, "a hunter without a spec should count as ranged, guessed")
    assert(Position(5, "HEALER") == "MELEE", "holy paladins heal in melee")
    -- the meter's spec icon fills in a spec NSRT hasn't seen: Survival
    local meter = { specByKey = { [members[4].key] = 255 } }
    assert(utility:MemberPosition(members[4], "DAMAGER", meter) == "MELEE", "meter spec not used")
    NSI.GetSpecs = nil
end)

test("the Even melee/ranged option is saved, off by default, and shown on the strip", function()
    SplitRaid()
    assert(utility.db.splitMeleeRanged == false, "option should start off")
    local ui = utility.ui
    assert(not ui.sideText[1].text:find("melee"), "melee counts shown with the option off")
    ui.options:Pick("Even melee/ranged")
    assert(utility.db.splitMeleeRanged == true, "turning it on was not saved")
    assert(ui.options.getSelected() == "Overall, melee/ranged", ui.options.getSelected())
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[1][2] = "Ann", "Cid" -- Ann tanks (not counted); Cid is a mage: ranged
    utility:RefreshUI()
    assert(ui.sideText[1].text:find("0 melee, 1 ranged", 1, true), ui.sideText[1].text)
    ui.options:Pick("Even melee/ranged")
    assert(utility.db.splitMeleeRanged == false)
    utility:LoadDraft()
end)

test("Generate split with Even melee/ranged notes players whose spec wasn't seen", function()
    SplitRaid()
    -- Bob a priest healer (ranged), Cid a hunter with no spec (could be Survival: guessed), Dee a rogue (melee)
    H.group[2].class, H.group[3].class, H.group[4].class = "PRIEST", "HUNTER", "ROGUE"
    utility.db.splitMeleeRanged, utility.db.splitToNewRoster = true, false
    utility.dirty = false
    local before = #H.messages
    utility:GenerateSplit()
    local notes = table.concat(H.messages, "\n", before + 1)
    assert(notes:find("1 player(s) have a spec that hasn't been seen yet", 1, true), notes)
    -- the two damage dealers, one melee and one ranged, end up on different sides
    local sideOf = utility.GroupSides(utility.draft, utility.db.splitLayout)
    local where = {}
    utility.ForEachEntry(utility.draft, function(g, _, entry) where[entry] = sideOf[g] end)
    assert(where.Cid ~= where.Dee, "melee and ranged damage stacked on one side")
    utility.db.splitToNewRoster = true
    before = #H.messages
    utility.db.splitMeleeRanged = false
    utility:LoadDraft()
    utility.db.splitToNewRoster = false
    utility:GenerateSplit()
    notes = table.concat(H.messages, "\n", before + 1)
    assert(not notes:find("hasn't been seen", 1, true), "spec note shown with the option off")
    utility.db.splitToNewRoster = true
    utility:LoadDraft()
end)

-- Damage dealers for the swap-pass tests: name, value, and what they bring
local function Dps(name, value, extra)
    local p = { name = name, role = "DAMAGER", value = value, dps = value, hps = 0, lust = false, rez = false }
    for k, v in pairs(extra or {}) do
        p[k] = v
    end
    return p
end
local function SideOf(sides, name)
    for s = 1, 2 do
        for _, p in ipairs(sides[s].players) do
            if p.name == name then return s end
        end
    end
end
local function Total(side)
    local sum = 0
    for _, p in ipairs(side.players) do
        sum = sum + p.value
    end
    return sum
end

test("Bloodlust on both sides: a same-bucket swap fixes plain balancing that stacked it", function()
    -- by value alone: 100 -> A, 99 -> B, 98 -> B (lower total), 97 -> A, so both shamans land on side A
    local players = {
        Dps("ShamA", 100, { lust = true }),
        Dps("Big", 99),
        Dps("Mid", 98),
        Dps("ShamB", 97, { lust = true }),
    }
    local plain = utility.BalanceSides(players)
    assert(SideOf(plain, "ShamA") == SideOf(plain, "ShamB"), "fixture no longer stacks the lusts")
    local sides, short = utility.BalanceSides(players, { lustRez = true })
    assert(#short == 0, "a fixable shortfall was left")
    assert(SideOf(sides, "ShamA") ~= SideOf(sides, "ShamB"), "lust still on one side")
    assert(#sides[1].players == 2 and #sides[2].players == 2, "side sizes changed")
    assert(math.abs(Total(sides[1]) - Total(sides[2])) <= 2, "the swap wrecked the DPS balance")
end)

test("a lone Bloodlust is reported, and pinned players are never swapped", function()
    local sides, short = utility.BalanceSides(
        { Dps("Sham", 100, { lust = true }), Dps("Other", 90) },
        { lustRez = true }
    )
    assert(#short == 1 and short[1].kind == "lust" and short[1].side ~= SideOf(sides, "Sham"), "shortfall not reported")
    local players = {
        Dps("ShamA", 100, { lust = true, pin = 1 }),
        Dps("ShamB", 97, { lust = true, pin = 1 }),
        Dps("Big", 99),
        Dps("Mid", 98),
    }
    sides, short = utility.BalanceSides(players, { lustRez = true })
    assert(SideOf(sides, "ShamA") == 1 and SideOf(sides, "ShamB") == 1, "a pinned player was moved")
    assert(#short == 1 and short[1].side == 2, "side B's missing lust should be reported")
end)

test("battle rez: 2 per side with 4 in the raid, and a buff swap never takes a side's only Bloodlust", function()
    local players = {
        Dps("Lock1", 100, { rez = true }),
        Dps("Lock2", 99, { rez = true }),
        Dps("Lock3", 50, { rez = true }),
        Dps("Lock4", 49, { rez = true }),
        Dps("A", 98),
        Dps("B", 97),
        Dps("C", 48),
        Dps("D", 47),
    }
    local sides, short = utility.BalanceSides(players, { lustRez = true })
    local rez = { 0, 0 }
    for s = 1, 2 do
        for _, p in ipairs(sides[s].players) do
            if p.rez then rez[s] = rez[s] + 1 end
        end
    end
    assert(#short == 0 and rez[1] == 2 and rez[2] == 2, "battle rez not 2 per side: " .. rez[1] .. "/" .. rez[2])
end)

test("a swap that would take a side's only Bloodlust is refused", function()
    -- B lacks Mark of the Wild. Swapping a druid for Sham is the closest in value but takes B's only Bloodlust; the
    -- swap with X is safe. Nobody is pinned, so only the no-new-shortfall rule picks the safe one (without it the
    -- pass swaps Sham out and back until it gives up, leaving Mark of the Wild unfixed).
    local function P(name, value, extra)
        local p = Dps(name, value, extra)
        p.bucket = "DAMAGERANY"
        return p
    end
    local sides = {
        {
            players = {
                P("Druid1", 90, { buff = "DRUID" }),
                P("Druid2", 80, { buff = "DRUID" }),
                P("Mage", 70, { lust = true }),
            },
        },
        { players = { P("Sham", 89, { lust = true }), P("X", 10) } },
    }
    local short = utility.FixShortfalls(sides, { lustRez = true, buffs = true })
    assert(SideOf(sides, "Sham") == 2, "B's only Bloodlust was swapped away")
    assert(#short == 0, "Mark of the Wild should be fixed with the safe swap")
    assert(SideOf(sides, "X") == 1, "the safe swap was not used")
end)

test("pins are draft edits: Revert drops them, Save keeps them, a split's new roster copies them", function()
    SplitRaid()
    utility.draft = utility.NewRoster()
    utility.draft[1][1] = "Ann"
    utility:RefreshUI()
    local ui = utility.ui
    H.shift = true
    ui.groupSlots[1].scripts.OnClick(ui.groupSlots[1], "RightButton")
    H.shift = false
    assert(utility.draftPins["ann-home"] == 1 and utility.dirty, "shift-right-click did not pin to side A")
    assert(ui.groupSlots[1].text.text:find("[A]", 1, true), ui.groupSlots[1].text.text)
    assert(utility.draft[1][1] == "Ann", "pinning cleared the slot")
    utility:LoadDraft()
    assert(not utility.draftPins["ann-home"], "Revert kept the pin")
    -- pin on the unplaced list too: A, then B
    utility:RefreshUI()
    local slot
    for _, s in ipairs(ui.benchSlots) do
        if s.value == "Cid" then slot = s end
    end
    H.shift = true
    slot.scripts.OnClick(slot, "RightButton")
    slot.scripts.OnClick(slot, "RightButton")
    H.shift = false
    assert(utility.draftPins["cid-home"] == 2, "second shift-right-click should pin to side B")
    utility:SaveDraft()
    assert(utility.db.pins[utility.db.active]["cid-home"] == 2, "Save did not keep the pin")
    -- Generate split honours it, and the new roster takes the pins along
    utility.db.splitToNewRoster = true
    utility:GenerateSplit()
    local data = H.popup.data
    local sideOf = utility.GroupSides(data.roster, utility.db.splitLayout)
    utility.ForEachEntry(data.roster, function(g, _, entry)
        if entry == "Cid" then assert(sideOf[g] == 2, "pinned player not on side B") end
    end)
    local box = { GetText = function() return "Pinned Split" end }
    StaticPopupDialogs.NSRTRAIDUTILITY_SAVE_SPLIT.OnAccept({ EditBox = box }, data)
    assert(utility.db.pins["Pinned Split"] and utility.db.pins["Pinned Split"]["cid-home"] == 2, "pins not copied")
    utility:DeleteRoster("Pinned Split")
    assert(utility.db.pins["Pinned Split"] == nil, "pins left behind by a deleted roster")
    for name in pairs(utility.db.pins) do
        utility.db.pins[name] = nil
    end
    utility.db.active = utility:GetRosterNames()[1]
    utility:LoadDraft()
end)

test("meter source: last fight reads the Current session, roles only ignores the meter", function()
    SplitRaid()
    local asked
    SetMeter(function(sessionType, meterType)
        asked = sessionType
        if meterType ~= 2 then return { combatSources = {} } end
        local value = sessionType == 2 and 7000 or 1500
        return { combatSources = { Src("Ann", value) } }
    end)
    Enum.DamageMeterSessionType.Current = 2 -- Overall is 1 in this suite
    utility.draft = utility.NewRoster()
    utility.draft[1][1] = "Ann"
    local ui = utility.ui
    ui.options:Pick("Balance on the last fight")
    assert(utility.db.splitMeterSource == "lastfight" and asked == 2, "Current session not read")
    assert(ui.groupSlots[1].amount.text == "7.0K", ui.groupSlots[1].amount.text)
    assert(ui.options.getSelected():find("^Last fight"), ui.options.getSelected())
    ui.options:Pick("Balance on roles only")
    assert(ui.groupSlots[1].amount.text == "1.5K", "roles only should still show Overall numbers")
    assert(ui.balanceNote.text:find("roles only", 1, true), ui.balanceNote.text)
    utility.db.splitToNewRoster = false
    local before = #H.messages
    utility:GenerateSplit()
    local notes = table.concat(H.messages, "\n", before + 1)
    assert(notes:find("Balanced by roles only", 1, true), notes)
    ui.options:Pick("Balance on the Overall session")
    utility.db.splitToNewRoster = true
    utility:LoadDraft()
end)

test("last fight falls back to the newest stored session once Current is empty", function()
    SplitRaid()
    SetMeter(function() return { combatSources = {} } end) -- Current (and Overall) empty
    local fetched
    SetStoredSessions(function() return { { sessionID = 3 }, { sessionID = 9 } } end, function(id, meterType)
        fetched = id
        return { combatSources = meterType == 2 and { Src("Ann", 4200) } or {} }
    end)
    utility.db.splitMeterSource = "lastfight"
    utility.draft = utility.NewRoster()
    utility.draft[1][1] = "Ann"
    utility:RefreshUI(true)
    utility.db.splitMeterSource = "overall"
    SetStoredSessions(nil, nil)
    assert(fetched == 9, "did not read the newest session")
    assert(utility.ui.groupSlots[1].amount.text == "4.2K", utility.ui.groupSlots[1].amount.text)
    utility:LoadDraft()
end)

test("the strip lists what each side is missing when the options are on", function()
    SplitRaid()
    -- Cid and Dee bring Bloodlust; Ann (tank) and Bob (healer) don't. The harness's default class, MAGE, would.
    H.group[1].class, H.group[2].class, H.group[3].class, H.group[4].class = "WARRIOR", "PRIEST", "SHAMAN", "MAGE"
    utility.db.splitLustRez, utility.db.splitLayout = true, "oddeven"
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[1][2], utility.draft[1][3] = "Ann", "Cid", "Dee" -- all on side A
    utility.draft[2][1] = "Bob"
    utility:RefreshUI()
    assert(utility.ui.missing.text == "Missing on B: Bloodlust.", utility.ui.missing.text)
    utility.db.splitLustRez = false
    utility:RefreshUI()
    assert(utility.ui.missing.text == "", "shortfall shown with the option off")
    utility:LoadDraft()
end)

test("Chaos Brand and Mystic Touch count as buffs a side needs", function()
    local players = {
        Dps("DH1", 100, { buff = "DEMONHUNTER" }),
        Dps("Big", 99),
        Dps("Mid", 98),
        Dps("DH2", 97, { buff = "DEMONHUNTER" }),
        Dps("Monk", 60, { buff = "MONK" }), -- only one monk: nothing to spread
        Dps("Low", 59),
    }
    local plain = utility.BalanceSides(players)
    assert(SideOf(plain, "DH1") == SideOf(plain, "DH2"), "fixture no longer stacks the demon hunters")
    local sides, short = utility.BalanceSides(players, { buffs = true })
    assert(SideOf(sides, "DH1") ~= SideOf(sides, "DH2"), "Chaos Brand still on one side only")
    assert(#short == 0, "a lone monk is not a shortfall")
    local names = {}
    for _, buff in ipairs(utility.RAID_BUFFS) do
        names[buff.class] = buff.name
    end
    assert(names.DEMONHUNTER:find("Chaos Brand", 1, true) and names.MONK:find("Mystic Touch", 1, true))
end)

test("a pin works however the slot names the player (short name for a cross-realm player)", function()
    SplitRaid()
    H.SetRaid({
        Member("Ann", "Home", nil, "TANK"),
        Member("Kaelin", "Draenor", "Kaelin-Draenor"),
        Member("Cid", "Home"),
        Member("Dee", "Home"),
    })
    utility.draft = utility.NewRoster()
    utility.draft[1][1] = "Kaelin" -- typed short; the roster name would be Kaelin-Draenor
    utility:RefreshUI()
    H.shift = true
    local slot = utility.ui.groupSlots[1]
    slot.scripts.OnClick(slot, "RightButton")
    slot.scripts.OnClick(slot, "RightButton") -- side B
    H.shift = false
    assert(utility.draftPins["kaelin-draenor"] == 2, "pin not stored for the player")
    utility.db.splitToNewRoster = false
    utility:GenerateSplit()
    H.popup.data() -- pinning is an unsaved edit, so the split asks before replacing the draft
    local sideOf = utility.GroupSides(utility.draft, utility.db.splitLayout)
    local found
    utility.ForEachEntry(utility.draft, function(g, _, entry)
        if entry == "Kaelin-Draenor" then found = sideOf[g] end
    end)
    assert(found == 2, "pinned player not on side B: " .. tostring(found))
    utility.db.splitToNewRoster = true
    utility:LoadDraft()
end)

-- Hand-built sides for the debuff pass: name, DPS, physical share, buff, and extra fields
local function D(name, dps, physical, buff, extra)
    local p = Dps(name, dps, { buff = buff, physical = physical, debuffDps = dps, bucket = "DAMAGERANY" })
    for k, v in pairs(extra or {}) do
        p[k] = v
    end
    return p
end

test("most damage: a lone Demon Hunter ends up with the magic dealers", function()
    local sides = {
        { players = { D("DH", 100, 0.1, "DEMONHUNTER"), D("Warrior", 100, 0.95, "WARRIOR") } },
        { players = { D("Mage1", 100, 0, "MAGE"), D("Mage2", 100, 0, "MAGE") } },
    }
    utility.MaximizeDebuffs(sides, { buffs = true, debuffMax = true })
    assert(SideOf(sides, "DH") ~= SideOf(sides, "Warrior"), "Chaos Brand left on the physical side")
    assert(SideOf(sides, "Mage1") ~= SideOf(sides, "Mage2"), "Arcane Intellect should still be on both sides")
end)

test("most damage never pushes the DPS gap past the tolerance, or moves a pinned player", function()
    local sides = {
        { players = { D("DH", 100, 0.1, "DEMONHUNTER"), D("Warrior", 100, 0.95) } },
        { players = { D("Mage", 150, 0), D("Lock", 50, 0) } },
    }
    -- every swap that helps Chaos Brand leaves one side 250 vs 150
    utility.MaximizeDebuffs(sides, { buffs = true, debuffMax = true })
    assert(SideOf(sides, "DH") == 1 and SideOf(sides, "Warrior") == 1, "a swap broke the DPS balance")
    sides = {
        { players = { D("DH", 100, 0.1, "DEMONHUNTER", { pin = 1 }), D("Warrior", 100, 0.95, nil, { pin = 1 }) } },
        { players = { D("Mage1", 100, 0), D("Mage2", 100, 0) } },
    }
    utility.MaximizeDebuffs(sides, { buffs = true, debuffMax = true })
    assert(SideOf(sides, "DH") == 1 and SideOf(sides, "Warrior") == 1, "a pinned player moved")
end)

test("most damage leaves two Demon Hunters alone: one per side already covers everyone", function()
    local sides = {
        { players = { D("DH1", 100, 0.1, "DEMONHUNTER"), D("Warrior", 100, 0.95) } },
        { players = { D("DH2", 100, 0.1, "DEMONHUNTER"), D("Rogue", 100, 0.9) } },
    }
    utility.MaximizeDebuffs(sides, { buffs = true, debuffMax = true })
    assert(SideOf(sides, "DH1") == 1 and SideOf(sides, "DH2") == 2 and SideOf(sides, "Warrior") == 1)
end)

test("Generate split with most damage says where the lone Demon Hunter went", function()
    SplitRaid()
    H.group[1].class, H.group[2].class, H.group[3].class, H.group[4].class = "WARRIOR", "PRIEST", "DEMONHUNTER", "MAGE"
    utility.db.splitBuffs, utility.db.splitToNewRoster = "max", false
    utility.dirty = false
    local before = #H.messages
    utility:GenerateSplit()
    local notes = table.concat(H.messages, "\n", before + 1)
    assert(notes:find("Chaos Brand is on side", 1, true), notes)
    assert(utility.ui.options.getSelected():find("buffs (most damage)", 1, true), utility.ui.options.getSelected())
    utility.ui.options:Pick("Raid buffs: ignore")
    assert(utility.db.splitBuffs == "off")
    utility.db.splitToNewRoster = true
    utility:LoadDraft()
end)
