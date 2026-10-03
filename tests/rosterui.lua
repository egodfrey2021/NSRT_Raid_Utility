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
    utility:BuildRosterTab(H.Frame(), _G.NorthernSkyRaidTools)
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
    utility:BuildRosterTab(H.Frame(), _G.NorthernSkyRaidTools)
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

test("the import popup asks before discarding unsaved edits", function()
    Build({})
    utility.draft[1][1] = "Old"
    utility:MarkDirty()
    H.popup = nil
    Import("x y")
    assert(H.popup and H.popup.which == "NSRTRAIDUTILITY_DISCARD")
    assert(utility.draft[1][1] == "Old", "draft replaced before confirmation")
    H.popup.data()
    assert(utility.draft[1][1] == "x" and utility.draft[1][2] == "y")
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
    assert(ui.groupSlots[2].text.text == "Gone (not in group)", ui.groupSlots[2].text.text)
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
    assert(ui.fillButton.enabled and not ui.splitButton.enabled and not ui.arrangeButton.enabled)
    H.SetParty({})
    H.party = false
    utility:RefreshUI()
    assert(not ui.fillButton.enabled and ui.inviteButton.enabled, "Invite should work solo to form a group")
end)

test("Fill, Clear and Revert ask before discarding unsaved edits", function()
    local ui = Build({ "Ann" })
    for _, button in ipairs({ ui.fillButton, ui.clearButton, ui.revertButton }) do
        utility.draft[1][1] = "Edited"
        utility:MarkDirty()
        H.popup = nil
        button.onClick()
        assert(H.popup and H.popup.which == "NSRTRAIDUTILITY_DISCARD", button.label .. " did not confirm")
        assert(utility.draft[1][1] == "Edited", button.label .. " discarded before confirmation")
        H.popup.data()
        assert(utility.draft[1][1] ~= "Edited", button.label .. " did nothing after confirmation")
    end
    utility:LoadDraft()
    utility.draft[1][1] = "Kept"
    utility.dirty = false
    H.popup = nil
    ui.clearButton.onClick()
    assert(not H.popup and utility.draft[1][1] == "", "Clear on a clean draft should not ask")
    utility:LoadDraft()
end)

test("recent results show in the tab", function()
    local ui = Build({})
    utility.Print("first")
    utility.Print("second")
    utility.Print("third")
    assert(ui.result.text == "second\nthird", ui.result.text)
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
