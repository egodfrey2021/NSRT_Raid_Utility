-- Roster.lua and NSRT.lua: name resolution, Unassigned, invites, arranging, saved data
local H = ...
local utility, Member, test = H.utility, H.Member, H.test
local NSI = _G.NorthernSkyRaidTools

local function TwinsRaid()
    H.SetRaid({
        Member("Twin", "Home", "Twin"),
        Member("Twin", "Away", "Twin-Away"),
        Member("Healer", "Home", "Healer", "HEALER"),
    })
end

test("Unassigned hides placed members, by full name, short name and nickname", function()
    TwinsRaid()
    local roster = utility.NewRoster()
    assert(#utility:GetUnassigned(roster) == 3)
    roster[1][1] = "Twin-Away"
    assert(#utility:GetUnassigned(roster) == 2)
    roster[1][2] = "Twin"
    assert(#utility:GetUnassigned(roster) == 2, "ambiguous short name hid a player")
    roster[1][2] = "Nickname"
    assert(#utility:GetUnassigned(roster) == 1, "nickname did not hide its character")
end)

test("short names must be unambiguous", function()
    TwinsRaid()
    local member, reason = utility:ResolveGroupMember("Twin")
    assert(member == nil and reason == "ambiguous")
    assert(utility:ResolveGroupMember("Twin-Away").index == 2)
    assert(utility:ResolveGroupMember("twin-away").index == 2, "lookup is case sensitive")
end)

test("resolve results are cached per member list", function()
    TwinsRaid()
    local members = utility.GetGroupMembers()
    local calls, getChar = 0, NSAPI.GetChar
    ---@diagnostic disable-next-line: duplicate-set-field (counting wrapper around the stub)
    NSAPI.GetChar = function(...)
        calls = calls + 1
        return getChar(...)
    end
    utility:ResolveGroupMember("Nickname", members)
    utility:ResolveGroupMember("Nickname", members)
    NSAPI.GetChar = getChar
    assert(calls == 1, "nickname was looked up twice for one member list")
end)

test("members with secret names are skipped", function()
    TwinsRaid()
    H.secret = { ["Twin-Away"] = true }
    local members = utility.GetGroupMembers()
    H.secret = nil
    assert(#members == 2)
end)

test("Arrange packs present players and names same-realm players without a realm", function()
    TwinsRaid()
    NSI.Groups = nil
    utility.lastArrange = nil
    local roster = utility.NewRoster()
    roster[1][1], roster[1][3], roster[2][2] = "Twin-Away", "Healer", "Offline"
    utility:Arrange(nil, roster)
    local units = NSI.Groups.units
    assert(units[1].name == "Twin-Away", "cross-realm player lost their realm")
    assert(units[2].name == "Healer", "same-realm player was sent as Name-Realm")
    assert(units[3].processed and units[6].processed, "gaps were not padded")
    assert(NSI.LastGroupSort == H.now, "NSRT's spam guard was not set")
    assert(H.LastMessage():find("Sorting"))
end)

test("Arrange reports when NSRT finishes, checking after each roster update", function()
    TwinsRaid()
    H.timers = {}
    NSI.Groups, utility.lastArrange = nil, nil
    local roster = utility.NewRoster()
    roster[1][1] = "Healer"
    utility:Arrange(nil, roster)
    H.Fire("GROUP_ROSTER_UPDATE")
    H.RunTimers(1)
    assert(not H.LastMessage():find("arranged"), "reported before NSRT finished")
    NSI.Groups.Processing = false
    assert(not H.LastMessage():find("arranged"), "reported without a roster update")
    H.Fire("GROUP_ROSTER_UPDATE")
    H.RunTimers(1)
    assert(H.LastMessage():find("Groups arranged"))
    H.RunTimers()
    assert(#H.timers == 0, "timeout left running after the sort finished")
end)

test("Arrange reports a sort NSRT stops on its first step", function()
    TwinsRaid()
    H.timers, NSI.Groups, utility.lastArrange = {}, nil, nil
    local arrange = NSI.ArrangeGroups
    ---@diagnostic disable-next-line: unused-vararg (stub ignores them)
    NSI.ArrangeGroups = function(self, ...) -- NSRT passes (firstcall, finalcheck)
        self.Groups.Processing, self.Groups.ProcessStart = false, nil
    end
    local roster = utility.NewRoster()
    roster[1][1] = "Healer"
    utility:Arrange(nil, roster)
    NSI.ArrangeGroups = arrange
    assert(H.LastMessage():find("stopped"), H.LastMessage())
end)

test("Arrange gives up waiting after the timeout", function()
    TwinsRaid()
    H.timers, NSI.Groups, utility.lastArrange = {}, nil, nil
    local roster = utility.NewRoster()
    roster[1][1] = "Healer"
    utility:Arrange(nil, roster)
    H.RunTimers()
    assert(H.LastMessage():find("stopped") and not utility.arrangeWatch)
end)

test("Arrange refuses during a running sort and the cooldown", function()
    TwinsRaid()
    NSI.Groups, utility.lastArrange = { Processing = true, ProcessStart = H.now, units = {}, total = 40 }, nil
    utility:Arrange(nil, utility.NewRoster())
    assert(H.LastMessage():find("already running"))
    NSI.Groups = nil
    utility.lastArrange = H.now
    utility:Arrange(nil, utility.NewRoster())
    assert(H.LastMessage():find("wait a few seconds"))
    utility.lastArrange = nil
end)

test("party: nicknames resolve and only missing players are invited", function()
    H.SetParty({ Member("You", "Home"), Member("Guest", "Away") })
    local roster = utility.NewRoster()
    roster[1][1], roster[1][2], roster[1][3] = "You", "PartyNick", "Offline-Away"
    assert(#utility:GetUnassigned(roster) == 0, "party nickname was not resolved")
    H.invitations = {}
    utility:InviteMissing(roster)
    assert(#H.invitations == 1 and H.invitations[1] == "Offline-Away", "party members were invited")
end)

test("ambiguous names are not invited", function()
    H.SetRaid({ Member("Twin", "Home"), Member("Twin", "Away", "Twin-Away") })
    local roster = utility.NewRoster()
    roster[1][1] = "Twin"
    H.invitations = {}
    utility:InviteMissing(roster)
    assert(#H.invitations == 0 and H.LastMessage():find("ambiguous"), "ambiguous name was invited")
end)

test("v1 saved data migrates: the on/off raid buff setting becomes a mode", function()
    local saved, db = NSRTRaidUtilityDB, utility.db
    for _, case in ipairs({ { true, "even" }, { false, "off" } }) do
        NSRTRaidUtilityDB =
            { version = 1, rosters = { Main = utility.NewRoster() }, active = "Main", splitBuffs = case[1] }
        utility:InitDB()
        assert(NSRTRaidUtilityDB.version == 2, "version not bumped")
        assert(NSRTRaidUtilityDB.splitBuffs == case[2], tostring(NSRTRaidUtilityDB.splitBuffs))
        assert(utility.db.active == "Main" and utility.db.rosters.Main, "rosters lost in the migration")
    end
    NSRTRaidUtilityDB, utility.db = saved, db
    utility:LoadDraft()
end)

test("saved data gets a version and CreateRoster copies its starting data", function()
    assert(NSRTRaidUtilityDB.version == 2)
    local data = utility.NewRoster()
    data[2][3] = "Someone"
    assert(utility:CreateRoster("  From split  ", data))
    assert(utility.db.active == "From split" and utility.draft[2][3] == "Someone")
    data[2][3] = "Changed"
    assert(utility.db.rosters["From split"][2][3] == "Someone", "roster shares the caller's table")
    assert(not utility:CreateRoster("From split"), "duplicate name accepted")
    utility:DeleteRoster("From split")
end)

test("invite lists are read by NSRT, and NSRT errors are contained", function()
    local list = utility.NSRT.ParseInviteList("invitelist: A, , C")
    assert(#list == 3 and list[2] == "" and list[3] == "C")
    assert(utility.NSRT.ParseInviteList("no list here") == nil)
    local reader = NSI.GetInviteListFromReminderInput
    NSI.GetInviteListFromReminderInput = function() error("NSRT changed") end
    assert(utility.NSRT.ParseInviteList("invitelist: A") == nil, "NSRT error escaped")
    NSI.GetInviteListFromReminderInput = nil
    assert(utility.NSRT.ParseInviteList("invitelist: A") == nil)
    NSI.GetInviteListFromReminderInput = reader
end)

test("spec role comes from NSRT's spec cache", function()
    TwinsRaid()
    NSI.GetSpecs = function(_, unit) return unit == "raid3" and 257 end
    GetSpecializationInfoByID = function(id)
        if id == 257 then return id, "Holy", "", 0, "HEALER" end
    end
    assert(utility.NSRT.GetSpecRole("raid3") == "HEALER")
    assert(utility.NSRT.GetSpecRole("raid1") == nil)
    NSI.GetSpecs, _G.GetSpecializationInfoByID = nil, nil
end)

test("indextosubgroup gives NSRT's sorter each raid index's current subgroup", function()
    H.SetRaid({ Member("A", "Home"), Member("B", "Home") })
    H.group[2].subgroup = 6
    assert(indextosubgroup[1] == 1 and indextosubgroup[2] == 6)
    H.group[2].subgroup = 3
    assert(indextosubgroup[2] == 3, "lookup is a snapshot, not live")
    assert(indextosubgroup[3] == nil and indextosubgroup[nil] == nil, "missing index did not return nil")
end)

test("shared short names are written as Name-Realm by Fill and Unassigned", function()
    H.SetRaid({ Member("Twin", "Home", "Twin"), Member("Twin", "Away", "Twin-Away"), Member("Solo", "Home") })
    local unassigned = utility:GetUnassigned(utility.NewRoster())
    table.sort(unassigned)
    assert(table.concat(unassigned, ",") == "Solo,Twin-Away,Twin-Home", table.concat(unassigned, ","))
    local roster = utility.NewRoster()
    utility:FillFromRaid(roster)
    assert(roster[1][1] == "Twin-Home" and roster[1][3] == "Solo")
    assert(#utility:GetUnassigned(roster) == 0, "filled twins did not resolve")
end)
