-- PI.lua and PIData.lua: Power Infusion priority, priest assignment, and pairing priests with their targets
local H = ...
local utility, Member, test = H.utility, H.Member, H.test
local NSI = _G.NorthernSkyRaidTools

-- A raid with specs (through NSRT's spec cache) and classes; members: { name, class, role, spec }
local function Raid(list)
    local group, specs = {}, {}
    for i, m in ipairs(list) do
        group[i] = Member(m[1], "Home", nil, m[3] or "DAMAGER")
        group[i].class = m[2]
        specs["raid" .. i] = m[4]
    end
    H.SetRaid(group)
    NSI.GetSpecs = function(_, unit) return specs[unit] end
end

-- A damage meter with these DPS numbers (name -> DPS)
local function Meter(dps)
    local sources = {}
    for name, value in pairs(dps) do
        sources[#sources + 1] = { name = name, amountPerSecond = value }
    end
    H.SetMeter(function(_, meterType) return { combatSources = meterType == 2 and sources or {} } end)
end

local function Draft(entries)
    utility.draft = utility.NewRoster()
    for i, entry in ipairs(entries) do
        utility.draft[math.ceil(i / 5)][(i - 1) % 5 + 1] = entry
    end
end

local function GroupOf(name)
    for g = 1, 8 do
        for s = 1, 5 do
            if utility.draft[g][s] == name then return g end
        end
    end
end

test("the PI data ranks the sims' top specs above the bottom ones", function()
    local gain = utility.PI_DATA.gain
    assert(gain[259] > gain[261], "Assassination should beat Subtlety")
    assert(not gain[1473], "Augmentation should not be a target")
    for spec, value in pairs(gain) do
        assert(value > 0 and value < 15, "implausible gain for spec " .. spec)
    end
end)

test("priority is spec gain x the player's DPS, damage dealers only", function()
    Raid({
        { "Tank", "WARRIOR", "TANK", 73 },
        { "Assa", "ROGUE", "DAMAGER", 259 },
        { "Sub", "ROGUE", "DAMAGER", 261 },
        { "Hunter", "HUNTER", "DAMAGER", nil }, -- spec not seen: the class average, marked estimated
        { "Healer", "PRIEST", "HEALER", 257 },
    })
    -- Assa 300K x ~6.6% beats Sub 900K x ~0.9%; the hunter, with no meter data, counts at the lowest (300K)
    Meter({ Assa = 300000, Sub = 900000 })
    local members = utility.GetGroupMembers()
    Draft({ "Tank", "Assa", "Sub", "Hunter", "Healer" })
    utility.db.piPriority = "specs" -- trust the sims fully for this one
    local list = utility:PIPriority(utility.draft, members, utility:ReadMeter(members))
    utility.db.piPriority = "balanced"
    assert(#list == 3, "tanks and healers must not be ranked: " .. #list)
    assert(list[1].entry == "Assa", "best target: " .. list[1].entry)
    local hunter
    for _, item in ipairs(list) do
        if item.entry == "Hunter" then hunter = item end
    end
    assert(hunter.estimated and hunter.noData, "hunter should be an estimate with no meter data")
    NSI.GetSpecs = nil
end)

test("each priest gets a different best target on their own side, and moves into its group", function()
    Raid({
        { "Shadow", "PRIEST", "DAMAGER", 258 },
        { "Assa", "ROGUE", "DAMAGER", 259 },
        { "Aff", "WARLOCK", "DAMAGER", 265 },
        { "Fury", "WARRIOR", "DAMAGER", 72 },
        { "Holy", "PRIEST", "HEALER", 257 },
        { "Mage", "MAGE", "DAMAGER", 64 },
    })
    Meter({ Shadow = 200000, Assa = 200000, Aff = 200000, Fury = 200000, Mage = 200000 })
    local members = utility.GetGroupMembers()
    -- Evens/Odds: groups 1 and 3 are side A, group 2 side B
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[1][2] = "Shadow", "Fury" -- A
    utility.draft[3][1], utility.draft[3][2] = "Assa", "Mage" -- A
    utility.draft[2][1], utility.draft[2][2] = "Holy", "Aff" -- B
    local pairsList = utility:AssignPI(utility.draft, members, utility:ReadMeter(members), "oddeven")
    assert(#pairsList == 2, "both priests should get a target")
    local to = {}
    for _, pair in ipairs(pairsList) do
        to[pair.priestEntry] = pair.target.entry
    end
    assert(to.Shadow == "Assa", "Shadow's best same-side target is Assa, got " .. tostring(to.Shadow))
    assert(to.Holy == "Aff", "Holy's only same-side target is Aff, got " .. tostring(to.Holy))
    local moved = utility:PairPI(utility.draft, members, pairsList, "oddeven")
    assert(moved == 1 and GroupOf("Shadow") == GroupOf("Assa"), "Shadow not moved next to Assa")
    assert(GroupOf("Assa") == 3, "a PI target was moved")
    assert(GroupOf("Holy") == GroupOf("Aff"), "already together, so nothing to do")
    NSI.GetSpecs = nil
end)

test("/nru pi prints the priority and the pairs, and pairs the draft as an unsaved edit", function()
    Raid({
        { "Shadow", "PRIEST", "DAMAGER", 258 },
        { "Assa", "ROGUE", "DAMAGER", 259 },
        { "Fury", "WARRIOR", "DAMAGER", 72 },
    })
    Meter({ Shadow = 200000, Assa = 250000, Fury = 260000 })
    H.NSRTWindow()
    utility:LoadDraft()
    utility:BuildRosterTab(H.Frame(), H.Components())
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[2][1], utility.draft[2][2] = "Fury", "Assa", "Shadow"
    utility.draft[1][2] = "Shadow2" -- a typed name, not a member
    utility.dirty = false
    local before = #H.messages
    SlashCmdList.NSRTRAIDUTILITY("pi")
    local out = table.concat(H.messages, "\n", before + 1)
    assert(out:find("1. Assa:", 1, true), out)
    assert(out:find("Shadow gives Power Infusion to Assa.", 1, true), out)
    assert(out:find("PI sims dated " .. utility.PI_DATA.updated, 1, true), "the sim date is missing: " .. out)
    assert(not utility.dirty and GroupOf("Shadow") == GroupOf("Assa"), "already together: nothing should move")
    -- move Shadow to group 1 (with Fury). On a normal roster sides don't matter: Shadow follows Assa, the best
    -- target, back into group 2
    utility.draft[2][2], utility.draft[1][3] = "", "Shadow"
    assert(not utility.draftSplit, "a hand-built draft is not a split")
    before = #H.messages
    SlashCmdList.NSRTRAIDUTILITY("pi")
    out = table.concat(H.messages, "\n", before + 1)
    assert(out:find("Shadow gives Power Infusion to Assa.", 1, true), out)
    assert(not out:find("is a split", 1, true), "split note on a normal roster")
    assert(GroupOf("Shadow") == 2 and utility.dirty, "Shadow not moved into Assa's group")
    assert(H.LastMessage():find("Save to keep it", 1, true), H.LastMessage())
    -- on a split, a priest stays on their side: Shadow (group 1, side A) takes Fury, not Assa on side B
    utility.draft[2][2], utility.draft[1][3] = "", "Shadow"
    utility.draftSplit = true
    before = #H.messages
    SlashCmdList.NSRTRAIDUTILITY("pi")
    out = table.concat(H.messages, "\n", before + 1)
    assert(out:find("Shadow gives Power Infusion to Fury.", 1, true), out)
    assert(out:find("is a split", 1, true), "no note that sides apply: " .. out)
    assert(out:find("1. Assa:", 1, true), "the printed ranking is overall, whatever the sides: " .. out)
    -- the slot markers follow the same rule (shown with the split option on)
    utility.db.splitPI = true
    utility:RefreshUI()
    local tags = {}
    for _, slot in ipairs(utility.ui.groupSlots) do
        local tip = rawget(slot, "tooltip") or "" -- stub frames answer any missing field with a function
        if slot.piIcon.visible and tip:find("Gets Power Infusion from Shadow", 1, true) then
            tags[#tags + 1] = slot.value
        end
        if slot.value == "Shadow" then assert(slot.piIcon.visible and tip == "Gives Power Infusion to Fury.", tip) end
    end
    assert(#tags == 1 and tags[1] == "Fury", "target tag missing")
    utility.draftSplit = false
    utility.db.splitPI = false
    utility:LoadDraft()
    NSI.GetSpecs = nil
end)

test("Generate split with the PI option puts each priest with their target", function()
    Raid({
        { "Tank1", "WARRIOR", "TANK", 73 },
        { "Tank2", "PALADIN", "TANK", 66 },
        { "Shadow", "PRIEST", "DAMAGER", 258 },
        { "Assa", "ROGUE", "DAMAGER", 259 },
        { "Aff", "WARLOCK", "DAMAGER", 265 },
        { "Fury", "WARRIOR", "DAMAGER", 72 },
        { "Mage", "MAGE", "DAMAGER", 64 },
        { "Sub", "ROGUE", "DAMAGER", 261 },
        { "Disc", "PRIEST", "HEALER", 256 },
        { "Druid", "DRUID", "HEALER", 105 },
        { "Hunter", "HUNTER", "DAMAGER", 254 },
        { "Lock", "WARLOCK", "DAMAGER", 267 },
    })
    Meter({ Shadow = 200, Assa = 210, Aff = 220, Fury = 230, Mage = 240, Sub = 250, Hunter = 205, Lock = 215 })
    H.NSRTWindow()
    utility:LoadDraft()
    utility:BuildRosterTab(H.Frame(), H.Components())
    utility.db.splitPI, utility.db.splitToNewRoster = true, false
    utility.dirty = false
    local before = #H.messages
    utility:GenerateSplit()
    local out = table.concat(H.messages, "\n", before + 1)
    local pairsSeen = 0
    for priest, target in out:gmatch("(%a+) gives Power Infusion to (%a+)%.") do
        pairsSeen = pairsSeen + 1
        assert(GroupOf(priest) == GroupOf(target), priest .. " is not in " .. target .. "'s group")
    end
    assert(pairsSeen == 2, "expected both priests paired:\n" .. out)
    utility.db.splitPI, utility.db.splitToNewRoster = false, true
    utility:LoadDraft()
    NSI.GetSpecs = nil
end)

test("/nru pi works on the preview raid", function()
    H.raid, H.party, H.group = false, false, {}
    utility.Preview.Start(20)
    Draft({})
    utility:FillFromRaid(utility.draft)
    local before = #H.messages
    SlashCmdList.NSRTRAIDUTILITY("pi")
    local out = table.concat(H.messages, "\n", before + 1)
    assert(out:find("Power Infusion priority", 1, true) and out:find("gives Power Infusion to", 1, true), out)
    utility.Preview.Stop()
    utility:LoadDraft()
end)

test("a priest paired across sides is never moved there: pins, balance and buffs stay as they are", function()
    Raid({
        { "Priest1", "PRIEST", "HEALER", 257 }, -- healers, so not targets themselves
        { "Priest2", "PRIEST", "HEALER", 257 },
        { "Priest3", "PRIEST", "HEALER", 256 },
        { "Assa", "ROGUE", "DAMAGER", 259 },
        { "Aff", "WARLOCK", "DAMAGER", 265 },
        { "Fury", "WARRIOR", "DAMAGER", 72 },
        { "Pinned", "SHAMAN", "DAMAGER", 263 },
    })
    Meter({ Assa = 300, Aff = 300, Fury = 300, Pinned = 100 })
    local members = utility.GetGroupMembers()
    -- side A (groups 1, 3): three priests, two damage dealers. Side B (group 2): Fury and a pinned shaman.
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[1][2], utility.draft[1][3] = "Priest1", "Priest2", "Priest3"
    utility.draft[3][1], utility.draft[3][2] = "Assa", "Aff"
    utility.draft[2][1], utility.draft[2][2] = "Fury", "Pinned"
    local before = utility.CopyRoster(utility.draft)
    local pairsList = utility:AssignPI(utility.draft, members, utility:ReadMeter(members), "oddeven")
    utility:PairPI(utility.draft, members, pairsList, "oddeven")
    local sideOf = utility.GroupSides(utility.draft, "oddeven")
    local function Side(name)
        for g = 1, 8 do
            for s = 1, 5 do
                if utility.draft[g][s] == name then return sideOf[g] end
            end
        end
    end
    for _, name in ipairs({ "Priest1", "Priest2", "Priest3", "Assa", "Aff" }) do
        assert(Side(name) == 1, name .. " changed sides")
    end
    assert(Side("Fury") == 2 and utility.draft[2][2] == before[2][2], "side B was disturbed")
    local across
    for _, pair in ipairs(pairsList) do
        if pair.otherSide then across = pair end
    end
    assert(across and across.target.entry == "Fury", "the third priest's cross-side pairing should be reported")
    assert(utility.PIPairText(across):find("other side", 1, true), utility.PIPairText(across))
    NSI.GetSpecs = nil
    utility:LoadDraft()
end)

test("PI priority: specs, balanced or players decides between a top spec and a stronger player", function()
    Raid({ { "Assa", "ROGUE", "DAMAGER", 259 }, { "Fury", "WARRIOR", "DAMAGER", 72 } })
    Meter({ Assa = 200000, Fury = 400000 })
    local members = utility.GetGroupMembers()
    Draft({ "Assa", "Fury" })
    assert(utility.db.piPriority == "balanced", "balanced should be the default")
    local function Best(mode)
        utility.db.piPriority = mode
        return utility:PIPriority(utility.draft, members, utility:ReadMeter(members))[1].entry
    end
    assert(Best("specs") == "Assa", "trusting the sims, the top spec wins")
    assert(Best("balanced") == "Fury", "balanced: double the DPS outweighs the spec gap")
    assert(Best("players") == "Fury", "by DPS, the stronger player wins")
    -- with no meter data at all, every mode falls back to the sims
    Meter({})
    assert(Best("players") == "Assa", "no meter data: the spec gain breaks the tie")
    utility.db.piPriority = "balanced"
    NSI.GetSpecs = nil
end)

test("PI refuses a failed meter read instead of using a cached reading", function()
    Raid({ { "Shadow", "PRIEST", "DAMAGER", 258 }, { "Assa", "ROGUE", "DAMAGER", 259 } })
    Meter({ Assa = 200000 })
    local cached = utility:ReadMeter(utility.GetGroupMembers())
    utility:SetMeterReading(cached)
    Draft({ "Shadow", "Assa" })
    H.SetMeter(function() error("PI meter failure") end)
    local before = #H.messages
    utility:PowerInfusion()
    assert(#H.messages == before + 1 and H.LastMessage():find("PI meter failure", 1, true), H.LastMessage())
    assert(utility.meter == cached and utility.draft[1][1] == "Shadow" and utility.draft[1][2] == "Assa")
    NSI.GetSpecs = nil
    utility:LoadDraft()
end)

test("the PI priority setting is picked in the Split dropdown and named by /nru pi", function()
    Raid({ { "Shadow", "PRIEST", "DAMAGER", 258 }, { "Assa", "ROGUE", "DAMAGER", 259 } })
    Meter({ Assa = 200000 })
    H.NSRTWindow()
    utility:LoadDraft()
    utility:BuildRosterTab(H.Frame(), H.Components())
    Draft({ "Shadow", "Assa" })
    H.Choose("Best players (DPS)")
    assert(utility.db.piPriority == "players")
    local before = #H.messages
    SlashCmdList.NSRTRAIDUTILITY("pi")
    assert(H.messages[before + 1]:find("by damage meter DPS", 1, true), H.messages[before + 1])
    H.Choose("Balanced")
    assert(utility.db.piPriority == "balanced")
    utility:LoadDraft()
    NSI.GetSpecs = nil
end)

test("Post to raid sends the split sides and PI pairs, and only on a click", function()
    Raid({ { "Shadow", "PRIEST", "DAMAGER", 258 }, { "Assa", "ROGUE", "DAMAGER", 259 } })
    Meter({ Assa = 200000 })
    H.NSRTWindow()
    utility:LoadDraft()
    utility:BuildRosterTab(H.Frame(), H.Components())
    Draft({ "Shadow", "Assa" })
    utility:RefreshUI()
    local ui = utility.ui
    assert(
        not ui.postButton.enabled and ui.reasons[ui.postButton]:find("Nothing to post", 1, true),
        "nothing to post yet"
    )
    utility.draftSplit, utility.db.splitPI = true, true
    utility:RefreshUI()
    assert(ui.postButton.enabled, "split + PI should be postable")
    local tip = H.Hover(ui.postButton.frame)
    assert(tip:find("Sends to raid chat", 1, true) and tip:find("Shadow -> Assa", 1, true), tip)
    H.chat = {}
    assert(#H.chat == 0, "nothing should be sent before the click")
    ui.postButton.onClick()
    assert(#H.chat == 2 and H.chat[1].channel == "RAID", "expected two raid chat lines")
    assert(H.chat[1].text:find("^Split: side A = groups 1"), H.chat[1].text)
    assert(H.chat[2].text == "PI: Shadow -> Assa", H.chat[2].text)
    utility.draftSplit, utility.db.splitPI = false, false
    utility:LoadDraft()
    NSI.GetSpecs = nil
end)

test("Post to raid in the preview raid only prints what it would send", function()
    H.raid, H.party, H.group = false, false, {}
    utility.Preview.Start(20)
    utility:LoadDraft()
    Draft({})
    utility:FillFromRaid(utility.draft)
    utility.db.splitPI = true
    H.chat = {}
    local before = #H.messages
    utility:PostAssignments()
    local out = table.concat(H.messages, "\n", before + 1)
    assert(#H.chat == 0, "the preview sent a real chat message")
    assert(out:find("would post to raid chat", 1, true) and out:find("PI:", 1, true), out)
    utility.db.splitPI = false
    utility.Preview.Stop()
    utility:LoadDraft()
end)

test("Post to raid waits out chat lockdown, and uses instance chat in group finder raids", function()
    Raid({ { "Shadow", "PRIEST", "DAMAGER", 258 }, { "Assa", "ROGUE", "DAMAGER", 259 } })
    H.NSRTWindow()
    utility:LoadDraft()
    utility:BuildRosterTab(H.Frame(), H.Components())
    Draft({ "Shadow", "Assa" })
    utility.draftSplit = true
    utility:RefreshUI()
    local ui = utility.ui
    H.chatLockdown = true
    utility:RefreshUI()
    assert(
        not ui.postButton.enabled and ui.reasons[ui.postButton]:find("blocking addon chat", 1, true),
        "no lockdown reason"
    )
    H.chat = {}
    utility:PostAssignments()
    assert(#H.chat == 0 and H.LastMessage():find("blocking addon chat", 1, true), "posted during lockdown")
    H.chatLockdown = false
    H.instance = true
    utility:PostAssignments()
    H.instance = false
    assert(#H.chat == 1 and H.chat[1].channel == "INSTANCE_CHAT", "group finder raids need instance chat")
    utility.draftSplit = false
    utility:LoadDraft()
    NSI.GetSpecs = nil
end)

test("PI skips players sitting out in groups 5-8 (Groups 1-4 only) and offline players", function()
    Raid({
        { "Shadow", "PRIEST", "DAMAGER", 258 },
        { "Assa", "ROGUE", "DAMAGER", 259 },
        { "Fury", "WARRIOR", "DAMAGER", 72 },
        { "Aff", "WARLOCK", "DAMAGER", 265 },
    })
    H.group[4].offline = true
    Meter({ Shadow = 100, Assa = 300, Fury = 100, Aff = 300 })
    local members = utility.GetGroupMembers()
    utility.draft = utility.NewRoster()
    utility.draft[1][1], utility.draft[1][2], utility.draft[1][3] = "Shadow", "Fury", "Aff"
    utility.draft[5][1] = "Assa" -- sitting out
    utility.db.splitGroups14 = true
    local pairsList, list = utility:AssignPI(utility.draft, members, utility:ReadMeter(members), nil)
    utility.db.splitGroups14 = nil
    for _, item in ipairs(list) do
        assert(item.entry ~= "Assa" and item.entry ~= "Aff", item.entry .. " should not be ranked")
    end
    assert(#pairsList == 1 and pairsList[1].target.entry == "Fury", "Shadow should PI Fury, the only one playing")
    NSI.GetSpecs = nil
    utility:LoadDraft()
end)

test("solo, Power Infusion ranks and pairs players known only from the damage meter", function()
    H.raid, H.party, H.group = false, false, {}
    local function Seen(name, value, icon, class)
        return {
            name = name,
            amountPerSecond = value,
            sourceGUID = "Player-" .. name .. "-Home",
            specIconID = icon,
            classFilename = class,
        }
    end
    -- icon 222 = Fire Mage (the harness's spec list); the priest has no spec icon, only its class
    H.SetMeter(function(_, meterType)
        if meterType == 2 then
            return { combatSources = { Seen("Mage", 900, 222, "MAGE"), Seen("Priest", 300, nil, "PRIEST") } }
        end
        return { combatSources = {} }
    end)
    H.NSRTWindow()
    utility:LoadDraft()
    utility:BuildRosterTab(H.Frame(), H.Components())
    Draft({ "Mage", "Typed1", "Typed2", "Typed3", "Typed4", "Priest" }) -- Mage in group 1, Priest in group 2
    utility:RefreshUI(true)
    local ui = utility.ui
    assert(ui.piButton.enabled, "Power Infusion should work solo with players on the roster")
    utility.db.splitPI = true
    local before = #H.messages
    ui.piButton.onClick()
    local out = table.concat(H.messages, "\n", before + 1)
    assert(out:find("1. Mage:", 1, true), "the meter's Fire Mage should be ranked: " .. out)
    assert(out:find("Priest gives Power Infusion to Mage.", 1, true), out)
    assert(GroupOf("Priest") == GroupOf("Mage"), "the priest should move into the mage's group")
    -- and the slots show it
    utility:RefreshUI()
    local mageTip
    for _, slot in ipairs(ui.groupSlots) do
        if slot.value == "Mage" then mageTip = rawget(slot, "tooltip") end
    end
    assert(mageTip and mageTip:find("Gets Power Infusion from Priest", 1, true), tostring(mageTip))
    utility.db.splitPI = false
    utility:LoadDraft()
end)
