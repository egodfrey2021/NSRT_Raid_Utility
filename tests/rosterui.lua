-- RosterUI.lua: the Rosters tab
local H = ...
local utility, Member, test = H.utility, H.Member, H.test

test("all 40 Unassigned slots are reachable by scrolling", function()
    local members = {}
    for i = 1, 40 do
        members[i] = Member("Player" .. i, "Home")
    end
    H.SetRaid(members)
    utility.draft = utility.NewRoster()
    utility:BuildRosterTab(H.Frame(), H.Components())
    local ui = utility.ui
    assert(#ui.benchSlots == 40)
    assert(ui.benchSlots[40].value == "Player9", "last Unassigned slot is unreachable")
    local wheel = ui.benchScroll.scripts.OnMouseWheel
    -- 40 names in 2 columns = 20 rows, 17 visible
    for _ = 1, 3 do
        wheel(nil, -1)
    end
    assert(ui.benchScroll:GetVerticalScroll() == 66, "could not scroll to final row")
    wheel(nil, -1)
    assert(ui.benchScroll:GetVerticalScroll() == 66, "wheel must clamp to benchMaxScroll")
    for _ = 1, 4 do
        wheel(nil, 1)
    end
    assert(ui.benchScroll:GetVerticalScroll() == 0, "wheel must clamp at the top")
    for _ = 1, 3 do
        wheel(nil, -1)
    end
    for i = 35, 40 do
        H.group[i] = nil
    end
    utility:RefreshUI()
    assert(ui.benchMaxScroll == 0 and ui.benchScroll:GetVerticalScroll() == 0, "scroll not clamped to a shorter list")
end)

-- Builds the tab for a raid of the given names; returns ui
local function Build(names)
    local members = {}
    for i, name in ipairs(names) do
        members[i] = Member(name, "Home")
    end
    H.SetRaid(members)
    utility.draft = utility.NewRoster()
    utility.dirty = false
    utility:ResetUndo()
    utility:BuildRosterTab(H.Frame(), H.Components())
    return utility.ui
end

local function DragTo(src, target)
    src.scripts.OnDragStart(src)
    target.mouseOver = true
    src.scripts.OnDragStop(src)
    target.mouseOver = false
end

local function BenchSlot(ui, name)
    for _, slot in ipairs(ui.benchSlots) do
        if slot.value == name then return slot end
    end
end

test("dropping on a typed name moves that name to the first empty slot in the group", function()
    local ui = Build({ "Ann" })
    utility.draft[2][1], utility.draft[2][2] = "Offline", "Other"
    utility:RefreshUI()
    DragTo(BenchSlot(ui, "Ann"), ui.groupSlots[6])
    assert(utility.draft[2][1] == "Ann" and utility.draft[2][2] == "Other")
    assert(utility.draft[2][3] == "Offline", "typed name was lost or misplaced")
    assert(utility.dirty)
end)

test("a displaced typed name falls back to the first empty slot anywhere", function()
    local ui = Build({ "Ann" })
    for s = 1, 5 do
        utility.draft[2][s] = "Typed" .. s
    end
    utility.draft[1][1], utility.draft[1][2] = "A", "B"
    utility:RefreshUI()
    DragTo(BenchSlot(ui, "Ann"), ui.groupSlots[6])
    assert(utility.draft[2][1] == "Ann" and utility.draft[1][3] == "Typed1")
end)

test("a drop that would lose a typed name is refused when the roster is full", function()
    local ui = Build({ "Ann" })
    for g = 1, 8 do
        for s = 1, 5 do
            utility.draft[g][s] = "N" .. g .. s
        end
    end
    utility:RefreshUI()
    DragTo(BenchSlot(ui, "Ann"), ui.groupSlots[1])
    assert(utility.draft[1][1] == "N11", "slot was overwritten")
    assert(H.LastMessage():find("roster is full", 1, true), H.LastMessage())
    assert(not utility.dirty)
end)

test("displacing a live member leaves them in Unassigned", function()
    local ui = Build({ "Ann", "Bob" })
    utility.draft[1][1] = "Bob"
    utility:RefreshUI()
    assert(not BenchSlot(ui, "Bob"))
    DragTo(BenchSlot(ui, "Ann"), ui.groupSlots[1])
    assert(utility.draft[1][1] == "Ann" and utility.draft[1][2] == "")
    assert(BenchSlot(ui, "Bob"), "Bob did not reappear in Unassigned")
end)

local function TabTest(name, shift, from, expected)
    test(name, function()
        local ui = Build({})
        H.shift = shift
        local e, slot = ui.editor, ui.groupSlots[from]
        slot.scripts.OnDoubleClick(slot, "LeftButton")
        assert(e.slot == slot)
        e:SetText("  Typed  ")
        e.scripts.OnTabPressed(e)
        H.shift = false
        assert(utility.draft[slot.g][slot.s] == "Typed", "value not committed")
        assert(e.slot == ui.groupSlots[expected], "editor did not move to slot " .. expected)
        -- losing focus afterwards commits the next slot's text once, to that slot only
        e:SetText("Next")
        e.scripts.OnEditFocusLost(e)
        local target = ui.groupSlots[expected]
        assert(utility.draft[target.g][target.s] == "Next")
        assert(utility.draft[slot.g][slot.s] == "Typed")
    end)
end
TabTest("Tab commits and opens the next slot", false, 1, 2)
TabTest("Tab wraps to the next group", false, 5, 6)
TabTest("Tab wraps from the last slot to the first", false, 40, 1)
TabTest("Shift-Tab goes to the previous slot", true, 6, 5)
TabTest("Shift-Tab wraps from the first slot to the last", true, 1, 40)

test("RosterFromList maps positions to groups and slots", function()
    local list = { "a", " b ", "", "d", "e", "f" }
    local roster, overflow = utility.RosterFromList(list)
    assert(overflow == 0)
    assert(roster[1][1] == "a" and roster[1][2] == "b" and roster[1][3] == "" and roster[1][5] == "e")
    assert(roster[2][1] == "f" and roster[8][5] == "")
end)

test("RosterFromList keeps 40 entries and counts the rest", function()
    local list = {}
    for i = 1, 43 do
        list[i] = "n" .. i
    end
    list[42] = ""
    local roster, overflow = utility.RosterFromList(list)
    assert(roster[8][5] == "n40" and overflow == 2, overflow)
end)

test("ImportText reads prefixed, comma and whitespace lists", function()
    local roster = utility:ImportText("invitelist: a, , c")
    assert(roster[1][1] == "a" and roster[1][2] == "" and roster[1][3] == "c")
    roster = utility:ImportText("a, b, c")
    assert(roster[1][1] == "a" and roster[1][3] == "c")
    roster = utility:ImportText("  a b  c ")
    assert(roster[1][1] == "a" and roster[1][2] == "b" and roster[1][3] == "c" and roster[1][4] == "")
end)

test("ImportText reads one name per line", function()
    local roster = utility:ImportText("Ann\r\nBob\n\nCid\n")
    assert(roster[1][1] == "Ann" and roster[1][2] == "Bob" and roster[1][3] == "Cid", "lines after the first were lost")
end)

test("ImportText rejects empty input with a message", function()
    for _, text in ipairs({ "", "   \n ", "invitelist:", "invitelist: , ," }) do
        local roster, err = utility:ImportText(text)
        assert(roster == nil and type(err) == "string" and err ~= "", text)
    end
end)

test("WoWUtils export preserves empty slots across group boundaries", function()
    local roster = utility.NewRoster()
    roster[1][1], roster[1][3], roster[2][2] = "Ann", "Cid", "Guest-Away"
    local text = utility:ExportWoWUtils(roster)
    assert(text:find("^invitelist: "))
    local roundTrip = utility:ImportText(text)
    for g = 1, 8 do
        for s = 1, 5 do
            assert(roundTrip[g][s] == roster[g][s], ("group %d slot %d"):format(g, s))
        end
    end
end)

test("WoWAudit multi-encounter exports can select distinct invite lists", function()
    local payload = "EncounterID:123;Difficulty:Heroic;Name:First Boss\r\n\r\n"
        .. "invitelist:Alpha-Realm|Beta-Realm;\r\n"
        .. "EncounterID:124;Difficulty:Mythic;Name:Second Boss\n"
        .. "invitelist:Other-Realm Cid-Realm;\n"
    local encounters = utility:WoWAuditEncounters(payload)
    assert(#encounters == 2 and encounters[1].name == "First Boss")
    assert(encounters[2].difficulty == "Mythic")
    local roster = utility:ImportWoWAuditEncounter(encounters[2])
    assert(roster[1][1] == "Other-Realm" and roster[1][2] == "Cid-Realm")
    assert(roster[1][3] == "" and roster[2][1] == "")
    assert(utility:ImportWoWAuditEncounter(encounters[3]) == nil)
end)

test("WoWAudit invite imports keep 40 names and report overflow", function()
    local names = {}
    for i = 1, 43 do
        names[i] = "Player" .. i
    end
    local roster, overflow = utility:ImportWoWAuditEncounter({ names = table.concat(names, " ") })
    assert(roster[8][5] == "Player40" and overflow == 3)
end)

test("WoWAudit export describes the live group, not the draft", function()
    H.SetRaid({ Member("Ann", "Home"), Member("Bob", "Away") })
    H.group[1].classID = 8
    H.group[2].classID = 5
    H.group[2].specID = 257
    utility.draft = utility.NewRoster()
    utility.draft[1][1] = "DraftOnly"
    local text = utility:ExportWoWAuditRaid()
    assert(text == "raidlist:Ann-Home|0|8 Bob-Away|0|5;", text)
    H.inCombat = true
    assert(utility:ExportWoWAuditRaid() == nil)
    H.inCombat = false
    H.secret = { ["Bob"] = true }
    assert(utility:ExportWoWAuditRaid() == nil, "partial raid list was exported")
    H.secret = nil
end)

test("WoWAudit export uses available specs and refuses a preview group", function()
    H.SetRaid({ Member("You", "Home"), Member("Guest", "Away") })
    local oldSpec, oldInspect = utility.PlayerSpecID, GetInspectSpecialization
    utility.PlayerSpecID = function() return 257 end
    GetInspectSpecialization = function(unit) return unit == "raid2" and 63 or 0 end
    local text = utility:ExportWoWAuditRaid()
    utility.PlayerSpecID, GetInspectSpecialization = oldSpec, oldInspect
    assert(text == "raidlist:You-Home|257|8 Guest-Away|63|8;", text)
    H.raid, H.party, H.group = false, false, {}
    utility.Preview.Start(2)
    assert(utility:ExportWoWAuditRaid() == nil)
    utility.Preview.Stop()
end)

local function Import(text)
    StaticPopupDialogs.NSRTRAIDUTILITY_IMPORT.OnAccept({ EditBox = { GetText = function() return text end } })
end

test("the import popup replaces a clean draft and reports the count", function()
    Build({})
    local popup = StaticPopupDialogs.NSRTRAIDUTILITY_IMPORT
    assert(popup.hasEditBox and popup.maxLetters >= 2000)
    utility.draft[1][1] = "Old"
    Import("x, y, z")
    assert(utility.draft[1][1] == "x" and utility.draft[1][3] == "z" and utility.dirty)
    assert(H.LastMessage():find("Imported 3", 1, true), H.LastMessage())
end)

test("exchange imports the chosen WoWAudit encounter into the draft", function()
    local ui = Build({})
    -- The exchange dialog is built when the player requests it.
    for _, frame in ipairs(H.frames) do
        if frame.label == "Import/Export" then
            frame.onClick()
            break
        end
    end
    local panel = ui.exchange
    assert(panel and panel:IsShown())
    panel.box:SetText(
        "EncounterID:1;Difficulty:Heroic;Name:First\ninvitelist:Ann-Home;\n"
            .. "EncounterID:2;Difficulty:Heroic;Name:Second\ninvitelist:Bob-Home;\n"
    )
    panel.box.scripts.OnTextChanged()
    assert(#panel.picker.getItems() == 2)
    panel.import.onClick()
    assert(utility.draft[1][1] == "" and H.LastMessage():find("Select a WoWAudit encounter"))
    panel.picker:Pick("Second")
    utility.draft[1][1] = "Old"
    utility:MarkDirty()
    H.popup = nil
    panel.import.onClick()
    assert(not H.popup and utility.draft[1][1] == "Bob-Home" and utility.dirty, "import should apply at once")
    utility:Undo()
    assert(utility.draft[1][1] == "Old", "Undo did not bring back what the import replaced")
end)

test("exchange export buttons provide selectable text without changing the draft", function()
    local ui = Build({ "Ann" })
    utility.draft[2][1] = "Planned"
    local draft = utility.draft
    local snapshot = utility.CopyRoster(draft)
    for _, frame in ipairs(H.frames) do
        if frame.label == "Import/Export" then frame.onClick() end
    end
    local panel = ui.exchange
    for _, frame in ipairs(H.frames) do
        if frame.label == "Export NSRT list" then frame.onClick() end
    end
    assert(utility:ImportText(panel.box:GetText())[2][1] == "Planned")
    for _, frame in ipairs(H.frames) do
        if frame.label == "Export WoWAudit" then frame.onClick() end
    end
    assert(panel.box:GetText() == "raidlist:Ann-Home|0|8;")
    assert(utility.draft == draft and not utility.dirty and draft[2][1] == snapshot[2][1])
end)

test("the import popup replaces unsaved edits at once, and Undo brings them back", function()
    Build({})
    utility.draft[1][1] = "Old"
    utility:MarkDirty()
    H.popup = nil
    Import("x y")
    assert(not H.popup, "no prompt: Undo covers imports")
    assert(utility.draft[1][1] == "x" and utility.draft[1][2] == "y")
    utility:Undo()
    assert(utility.draft[1][1] == "Old", "Undo did not bring back the replaced edits")
end)

test("the import popup prints an error for unusable text", function()
    Build({})
    Import("   ")
    assert(H.LastMessage():find("Nothing to import", 1, true), H.LastMessage())
end)

test("the Unassigned panel has a scrollbar attached to its scroll frame", function()
    local ui = Build({ "Ann" })
    assert(ui.benchBar and ui.benchBar.scroll == ui.benchScroll and ui.benchScroll.bar == ui.benchBar)
    ui.benchScroll.scripts.OnMouseWheel(nil, -1)
    assert(ui.benchScroll:GetVerticalScroll() == 0, "wheel must stay clamped to benchMaxScroll")
end)

test("a typed name dropped on the unplaced list stays put", function()
    local ui = Build({ "Ann" })
    utility.draft[1][1], utility.draft[1][2] = "Offline", "Ann"
    utility:RefreshUI()
    DragTo(ui.groupSlots[1], ui.benchArea)
    assert(utility.draft[1][1] == "Offline", "typed name was deleted")
    assert(H.LastMessage():find("Right-click the slot", 1, true), H.LastMessage())
    assert(not utility.dirty)
    DragTo(ui.groupSlots[2], ui.benchArea)
    assert(utility.draft[1][2] == "" and BenchSlot(ui, "Ann"), "group member not un-placed")
end)

test("double-clicking an unplaced player puts them in the first empty slot", function()
    local ui = Build({ "Ann", "Bob" })
    utility.draft[1][1] = "Typed"
    utility:RefreshUI()
    local slot = BenchSlot(ui, "Bob")
    slot.scripts.OnDoubleClick(slot, "LeftButton")
    assert(utility.draft[1][2] == "Bob" and utility.dirty)
    assert(not BenchSlot(ui, "Bob"), "Bob still listed as unplaced")
end)

test("slots show role icons for members and tag names not in the group", function()
    local ui = Build({})
    H.SetRaid({ Member("Ann", "Home", nil, "TANK") })
    utility.draft[1][1], utility.draft[1][2] = "Ann", "Gone"
    utility:RefreshUI()
    assert(ui.groupSlots[1].text.text == "[T] Ann", ui.groupSlots[1].text.text)
    assert(ui.groupSlots[2].text.text == "Gone" and ui.groupSlots[2].text.color[1] < 0.6, "not greyed")
    assert(ui.groupSlots[2].tooltip == "Not in your group.", tostring(ui.groupSlots[2].tooltip))
    assert(ui.headers[1].text:find("(2/5)", 1, true), ui.headers[1].text)
    H.SetRaid({})
    H.raid = false
    utility:RefreshUI()
    assert(ui.groupSlots[2].text.text == "Gone", "offline planning should show plain names")
end)

test("the unplaced list header counts who is left", function()
    local ui = Build({ "Ann", "Bob", "Cid" })
    utility.draft[1][1] = "Ann"
    utility:RefreshUI()
    assert(ui.benchHeader.text == "In raid, not placed (2)", ui.benchHeader.text)
    H.SetParty({ Member("Ann", "Home"), Member("Bob", "Home") })
    utility:RefreshUI()
    assert(ui.benchHeader.text == "In group, not placed (1)", ui.benchHeader.text)
end)

test("buttons are enabled only when they can do something", function()
    local ui = Build({ "Ann" })
    assert(not ui.saveButton.enabled and not ui.revertButton.enabled, "Save/Revert enabled with nothing to save")
    assert(ui.status.text == "", "status shown with nothing unsaved")
    assert(not ui.clearButton.enabled and not ui.inviteButton.enabled and not ui.arrangeButton.enabled)
    assert(ui.fillButton.enabled and ui.splitButton.enabled)
    utility.draft[1][1] = "Ann"
    utility:MarkDirty()
    utility:RefreshUI()
    assert(ui.saveButton.enabled and ui.revertButton.enabled and ui.status.text:find("Unsaved"))
    assert(ui.clearButton.enabled and ui.inviteButton.enabled and ui.arrangeButton.enabled)
    H.SetParty({ Member("Ann", "Home"), Member("Bob", "Home") })
    utility:RefreshUI()
    -- out of a raid, a roster with players can still be split; groups can't be sorted
    assert(ui.fillButton.enabled and ui.splitButton.enabled and not ui.arrangeButton.enabled)
    H.SetParty({})
    H.party = false
    utility:RefreshUI()
    assert(not ui.fillButton.enabled and ui.inviteButton.enabled, "Invite should work solo to form a group")
end)

test("Fill and Clear apply at once (Undo covers them); Revert still asks, since it resets Undo", function()
    local ui = Build({ "Ann" })
    for _, button in ipairs({ ui.fillButton, ui.clearButton }) do
        utility.draft[1][1] = "Edited"
        utility:MarkDirty()
        H.popup = nil
        button.onClick()
        assert(not H.popup, button.label .. " should not ask")
        assert(utility.draft[1][1] ~= "Edited", button.label .. " did nothing")
        utility:Undo()
        assert(utility.draft[1][1] == "Edited", "Undo did not bring back what " .. button.label .. " replaced")
    end
    H.popup = nil
    ui.revertButton.onClick()
    assert(H.popup and H.popup.which == "NSRTRAIDUTILITY_DISCARD", "Revert should still ask")
    assert(utility.draft[1][1] == "Edited", "Revert discarded before confirmation")
    H.popup.data()
    assert(utility.draft[1][1] ~= "Edited", "Revert did nothing after confirmation")
    utility:LoadDraft()
end)

test("Unsaved changes clears when the roster matches its last save again", function()
    local ui = Build({ "Ann" })
    utility.draft = utility.CopyRoster(utility:GetActive())
    utility:ResetUndo()
    utility.dirty = false
    local before = utility.draft[1][1]
    utility.draft[1][1] = "Changed"
    utility:MarkDirty()
    utility:RefreshUI()
    assert(utility.dirty and ui.status.text:find("Unsaved", 1, true), "an edit should be unsaved")
    utility:Undo()
    utility:RefreshUI()
    assert(not utility.dirty and ui.status.text == "", "undoing back to the save should clear Unsaved changes")
    -- an edit that puts things back the way they were saved is not a change either
    utility.draft[1][1] = "Changed"
    utility:MarkDirty()
    utility.draft[1][1] = before
    utility:MarkDirty()
    assert(not utility.dirty, "back to the saved roster, so nothing is unsaved")
    -- a pin is a change too
    utility.draftPins["somebody"] = 1
    utility:MarkDirty()
    assert(utility.dirty, "a new pin should be unsaved")
    utility:LoadDraft()
end)

test("recent results show in the tab", function()
    local ui = Build({})
    utility.Print("first")
    utility.Print("second")
    utility.Print("third")
    -- printed together (one frame): the newest, and how many more are in History
    assert(ui.result.text:find("^third") and ui.result.text:find("(+2 more in History)", 1, true), ui.result.text)
    H.now = H.now + 1 -- a later action starts a new batch
    utility.Print("fourth")
    assert(ui.result.text == "fourth", ui.result.text)
    assert(ui.historyButton.enabled, "History should be available")
    ui.historyButton.onClick()
    assert(ui.history.text.text == "first\nsecond\nthird\nfourth", ui.history.text.text)
    H.now = H.now - 1
end)

test("deleting the last roster says a Default roster was made", function()
    Build({})
    local saved, active = utility.db.rosters, utility.db.active
    utility.db.rosters, utility.db.active = { Only = utility.NewRoster() }, "Only"
    utility:DeleteRoster("Only")
    assert(utility.db.active == "Default" and H.LastMessage():find("last roster", 1, true), H.LastMessage())
    utility.db.rosters, utility.db.active = saved, active
    utility:LoadDraft()
end)

test("solo, your own entry shows your class color and spec role", function()
    local ui = Build({})
    H.raid, H.party, H.group = false, false, {}
    local spec, specRole = _G.GetSpecialization, _G.GetSpecializationRole
    _G.GetSpecialization = function() return 1 end
    _G.GetSpecializationRole = function() return "HEALER" end
    utility.draft[1][1], utility.draft[1][2] = "Tester", "Planned"
    utility:RefreshUI()
    _G.GetSpecialization, _G.GetSpecializationRole = spec, specRole
    -- the role icon only appears for a resolved member, so this proves you count as one
    assert(ui.groupSlots[1].text.text == "[H] Tester", ui.groupSlots[1].text.text)
    assert(ui.groupSlots[2].text.text == "Planned", "solo, typed names should stay plain")
    assert(ui.benchHeader.text == "Not placed (0)", ui.benchHeader.text)
    H.invitations = {}
    utility:InviteMissing(utility.draft)
    assert(#H.invitations == 1 and H.invitations[1] == "Planned", "solo invite included yourself")
end)

test("disabled buttons say why, and Arrange needs raid lead or assist", function()
    local ui = Build({ "Ann" })
    assert(ui.reasons[ui.saveButton] == "No unsaved changes.", tostring(ui.reasons[ui.saveButton]))
    assert(ui.reasons[ui.clearButton] == "This roster is empty.", tostring(ui.reasons[ui.clearButton]))
    utility.draft[1][1] = "Ann"
    utility:RefreshUI()
    assert(ui.arrangeButton.enabled and not ui.reasons[ui.arrangeButton], "an enabled button has no reason")
    local leader = _G.UnitIsGroupLeader
    _G.UnitIsGroupLeader = function() return false end
    utility:RefreshUI()
    assert(not ui.arrangeButton.enabled, "Arrange should need lead or assist")
    assert(ui.reasons[ui.arrangeButton]:find("leader or assistant", 1, true), ui.reasons[ui.arrangeButton])
    _G.UnitIsGroupLeader = leader
    H.SetParty({ Member("Ann", "Home") })
    utility.draft = utility.NewRoster()
    utility:RefreshUI()
    assert(ui.reasons[ui.splitButton]:find("Join a raid", 1, true), tostring(ui.reasons[ui.splitButton]))
    assert(ui.noRaid.visible and not ui.balance.visible, "outside a raid, the note replaces the strip")
end)

test("the not placed list puts tanks, then healers, then damage", function()
    local ui = Build({})
    H.SetRaid({
        Member("Zed", "Home", nil, "DAMAGER"),
        Member("Amy", "Home", nil, "DAMAGER"),
        Member("Hal", "Home", nil, "HEALER"),
        Member("Tom", "Home", nil, "TANK"),
    })
    utility:RefreshUI()
    local order = {}
    for i = 1, 4 do
        order[i] = ui.benchSlots[i].value
    end
    assert(table.concat(order, ",") == "Tom,Hal,Amy,Zed", table.concat(order, ","))
end)

test("the Power Infusion button runs /nru pi", function()
    local ui = Build({ "Ann" })
    utility.draft[1][1] = "Ann"
    utility:RefreshUI()
    local pi, ran = utility.PowerInfusion, false
    utility.PowerInfusion = function() ran = true end
    ui.piButton.onClick()
    utility.PowerInfusion = pi
    assert(ran and ui.piButton.enabled)
end)

test("the Power Infusion icon shows only on PI targets and their priests, never on empty slots", function()
    local ui = Build({ "Ann" })
    utility.draft[1][1] = "Ann"
    utility:RefreshUI()
    for i, slot in ipairs(ui.groupSlots) do
        assert(not slot.piIcon.visible, "PI icon on slot " .. i .. " with Power Infusion off")
    end
    utility.db.splitPI = true
    utility:RefreshUI()
    for i, slot in ipairs(ui.groupSlots) do
        assert(not slot.piIcon.visible, "PI icon on slot " .. i .. " with no priest to give it")
    end
    utility.db.splitPI = false
end)

test("a raid lead change refreshes the tab (Arrange depends on it)", function()
    local refreshes = 0
    local refresh = utility.RefreshUI
    utility.RefreshUI = function() refreshes = refreshes + 1 end
    H.timers = {}
    utility.ui.frame:Show()
    H.Fire("PARTY_LEADER_CHANGED")
    H.RunTimers()
    utility.RefreshUI = refresh
    assert(refreshes == 1, "no refresh after the lead changed")
end)

test("Undo steps back through edits, and loading a roster starts fresh", function()
    local ui = Build({ "Ann", "Bob" })
    assert(not ui.undoButton.enabled and ui.reasons[ui.undoButton] == "Nothing to undo.")
    utility.draft[1][1] = "Ann"
    utility:MarkDirty()
    utility.draft[1][2] = "Bob"
    utility:MarkDirty()
    utility:RefreshUI()
    assert(ui.undoButton.enabled, "Undo should be available after an edit")
    ui.undoButton.onClick()
    assert(utility.draft[1][1] == "Ann" and utility.draft[1][2] == "", "Undo did not take back the last edit")
    ui.undoButton.onClick()
    assert(utility.draft[1][1] == "", "Undo did not step back twice")
    assert(not ui.undoButton.enabled, "nothing left to undo")
    -- undo also covers clearing, and a reload forgets the history
    utility.draft[2][1] = "Ann"
    utility:MarkDirty()
    ui.clearButton.onClick()
    assert(utility.draft[2][1] == "")
    ui.undoButton.onClick()
    assert(utility.draft[2][1] == "Ann", "Undo did not bring back a cleared roster")
    utility:LoadDraft()
    assert(not utility:CanUndo(), "loading a roster should start a fresh history")
end)

test("Rename keeps pins and the split mark; Duplicate copies what you see and leaves the original as saved", function()
    Build({ "Ann" })
    local original = utility.db.active
    utility:CreateRoster("Base")
    utility.draft[1][1] = "Ann"
    utility.draftPins["ann-home"] = 2
    utility.draftSplit = true
    utility:SaveDraft()
    StaticPopupDialogs.NSRTRAIDUTILITY_RENAME_ROSTER.OnAccept({ EditBox = { GetText = function() return "Main" end } })
    local db = utility.db
    assert(db.active == "Main" and db.rosters.Main and not db.rosters.Base, "rename failed")
    assert(db.pins.Main["ann-home"] == 2 and db.splitRosters.Main, "pins or split mark lost in the rename")
    -- an unsaved edit goes into the copy, not the original
    utility.draft[1][2] = "Typed"
    utility:MarkDirty()
    local dup = StaticPopupDialogs.NSRTRAIDUTILITY_DUPLICATE_ROSTER
    local box = { text = "", SetText = function(self, t) self.text = t end }
    box.SetFocus, box.HighlightText = function() end, function() end
    dup.OnShow({ EditBox = box })
    assert(box.text == "Main copy", "copy name not prefilled: " .. box.text)
    dup.OnAccept({ EditBox = { GetText = function() return "Boss 2" end } })
    assert(db.active == "Boss 2" and db.rosters["Boss 2"][1][2] == "Typed", "the copy is missing the unsaved edit")
    assert(db.rosters.Main[1][2] == "", "the original picked up the unsaved edit")
    assert(db.pins["Boss 2"]["ann-home"] == 2 and db.splitRosters["Boss 2"], "pins or split mark not copied")
    for _, name in ipairs({ "Main", "Boss 2" }) do
        utility:DeleteRoster(name)
    end
    db.active = original
    utility:LoadDraft()
end)

test("dragging a group header onto another group swaps the two groups", function()
    local ui = Build({})
    utility.draft[1][1], utility.draft[1][2], utility.draft[4][1] = "A1", "A2", "D1"
    utility:RefreshUI()
    local from, to = ui.headerHandles[1], ui.headerHandles[4]
    from.scripts.OnDragStart(from)
    to.mouseOver = true
    from.scripts.OnDragStop(from)
    to.mouseOver = false
    assert(
        utility.draft[4][1] == "A1" and utility.draft[4][2] == "A2" and utility.draft[1][1] == "D1",
        "groups not swapped"
    )
    assert(utility.dirty and utility:CanUndo(), "the swap should be an undoable edit")
end)

test("Invite missing's tooltip lists who would be invited", function()
    local ui = Build({ "Ann" })
    utility.draft[1][1], utility.draft[1][2] = "Ann", "Offline"
    utility:RefreshUI()
    local tip = H.Hover(ui.inviteButton.frame)
    assert(tip:find("Would invite: Offline", 1, true), tip)
    assert(not tip:find("Ann", 1, true), "listed someone already in the group: " .. tip)
end)

test("in combat the raid actions are greyed out with a reason", function()
    local ui = Build({ "Ann" })
    utility.draft[1][1] = "Ann"
    utility:RefreshUI()
    assert(ui.arrangeButton.enabled and ui.splitButton.enabled)
    ui.setup:Show()
    H.Fire("PLAYER_REGEN_DISABLED")
    for _, name in ipairs({ "arrangeButton", "splitButton", "piButton", "fillButton" }) do
        assert(not ui[name].enabled and ui.reasons[ui[name]] == "Not in combat.", name .. " still usable in combat")
    end
    assert(not ui.setup:IsShown(), "the setup panel should close in combat")
    utility:RefreshUI() -- after combat
    assert(ui.arrangeButton.enabled, "buttons should come back after combat")
    -- a hidden tab is left alone (it re-checks combat when it's shown again)
    ui.frame:Hide()
    H.Fire("PLAYER_REGEN_DISABLED")
    ui.frame:Show()
    assert(ui.arrangeButton.enabled, "the combat lock touched a hidden tab")
end)

test("the caption says when the damage meter was read", function()
    local ui = Build({ "Ann" })
    utility:SetMeterReading({ dps = {}, hps = {}, players = { {} }, byName = {}, specByKey = {} })
    utility:RefreshUI()
    assert(ui.caption.text:find("Read at " .. date("%H:%M"), 1, true), ui.caption.text)
    utility:SetMeterReading(nil)
end)

test("in combat the tab keeps the group from before the fight, even with names hidden", function()
    local ui = Build({ "Ann", "Bob" })
    utility.draft[1][1], utility.draft[1][2] = "Ann", "Bob"
    utility:RefreshUI()
    assert(ui.groupSlots[1].text.text:find("Ann", 1, true) and not rawget(ui.groupSlots[1], "tooltip"))
    H.inCombat, H.secret = true, { Ann = true, Bob = true }
    utility:RefreshUI() -- e.g. reopening the tab, or a drag, mid-fight
    local tip = rawget(ui.groupSlots[1], "tooltip")
    assert(not (tip and tip:find("Not in your group", 1, true)), "Ann looked absent in combat")
    assert(ui.caption.text:find("In combat", 1, true), ui.caption.text)
    assert(not ui.inviteButton.enabled, "Invite missing should be locked in combat")
    H.inCombat, H.secret = false, nil
    utility:RefreshUI()
    assert(not ui.caption.text:find("In combat", 1, true), "the combat note stayed after combat")
end)

test("closing the window mid-drag puts the drag back", function()
    local ui = Build({ "Ann" })
    utility.draft[1][1] = "Ann"
    utility:RefreshUI()
    local slot = ui.groupSlots[1]
    slot.scripts.OnDragStart(slot)
    assert(utility.dragSource == slot and slot.alpha == 0.35)
    ui.frame.scripts.OnHide(ui.frame) -- e.g. Escape closes NSRT's window; no drop arrives
    assert(utility.dragSource == nil and slot.alpha == 1, "the drag was left hanging")
end)
