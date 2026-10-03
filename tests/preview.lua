-- Preview.lua: the made-up raid behind /nru preview, and the dry-run Arrange/Invite it enables
local H = ...
local utility, test = H.utility, H.test
local Preview = utility.Preview
local NSI = _G.NorthernSkyRaidTools

local function Solo()
    H.raid, H.party, H.group = false, false, {}
end

local function Find(members, name)
    for _, m in ipairs(members) do
        if m.name == name then return m end
    end
end

test("preview refuses to start while you are in a real group", function()
    H.SetParty({ H.Member("You", "Home"), H.Member("Friend", "Home") })
    assert(not Preview.Start())
    assert(not Preview.IsActive() and H.LastMessage():find("Leave your group"))
end)

test("a 20-player preview puts you first and covers the edge cases", function()
    Solo()
    assert(Preview.Start())
    local members = utility.GetGroupMembers()
    assert(#members == 20 and members[1].name == "Tester" and members[1].class == "PRIEST")
    assert(utility.InRaid() and utility.InGroup(), "preview is not treated as a raid")
    local _, reason = utility:ResolveGroupMember("Twin", members)
    assert(reason == "ambiguous", "same-name pair missing")
    assert(utility:ResolveGroupMember("Twin-Stormrage", members), "other-realm twin missing")
    assert(Find(members, "Kaelin-Draenor"), "cross-realm member not shown with realm")
    assert(Find(members, "Quillon").role == "NONE")
    for _, m in ipairs(members) do
        assert(m.subgroup == math.ceil(m.index / 5))
    end
    Preview.Stop()
end)

test("Rosters: Unassigned and Fill from current raid use the preview raid", function()
    Solo()
    Preview.Start()
    assert(#utility:GetUnassigned(utility.NewRoster()) == 20)
    local roster = utility.NewRoster()
    assert(utility:FillFromRaid(roster))
    assert(roster[1][1] == "Tester" and roster[4][5] ~= "" and roster[5][1] == "")
    assert(#utility:GetUnassigned(roster) == 0, "filled roster still leaves people unassigned")
    assert(roster[1][4] == "Twin-Home" and roster[1][5] == "Twin-Stormrage", "same-name pair filled without realms")
    Preview.Stop()
end)

test("Arrange in preview moves the fake raid and never calls NSRT", function()
    Solo()
    Preview.Start()
    local sentinel = {}
    NSI.Groups = sentinel
    local roster = utility.NewRoster()
    roster[8][1], roster[8][2] = "Brannoc", "Twin-Stormrage" -- both start in group 1
    roster[1][1] = "Offline"
    utility:Arrange(nil, roster)
    assert(NSI.Groups == sentinel and not utility.arrangeWatch, "NSRT's sorter was started")
    assert(H.LastMessage():find("would move"), H.LastMessage())
    local members = utility.GetGroupMembers()
    assert(Find(members, "Brannoc").subgroup == 8 and Find(members, "Twin-Stormrage").subgroup == 8)
    NSI.Groups = nil
    Preview.Stop()
end)

test("Arrange in preview keeps every group at 5 or fewer", function()
    Solo()
    Preview.Start(40)
    local members = utility.GetGroupMembers()
    local roster = utility.NewRoster()
    for i = 1, 5 do
        roster[1][i] = members[35 + i].name
    end -- five group-8 players into full group 1
    utility:Arrange(nil, roster)
    local count = {}
    for _, m in ipairs(utility.GetGroupMembers()) do
        count[m.subgroup] = (count[m.subgroup] or 0) + 1
    end
    for g = 1, 8 do
        assert((count[g] or 0) <= 5, "group " .. g .. " has " .. tostring(count[g]))
    end
    Preview.Stop()
end)

test("Invite in preview only reports", function()
    Solo()
    Preview.Start()
    H.invitations = {}
    local roster = utility.NewRoster()
    roster[1][1], roster[1][2] = "Brannoc", "Offline"
    utility:InviteMissing(roster)
    assert(#H.invitations == 0, "invites were sent")
    assert(H.LastMessage():find("would invite Offline"), H.LastMessage())
    Preview.Stop()
end)

test("Split uses the fixture's meter numbers without touching the damage meter", function()
    Solo()
    Preview.Start()
    local meter = C_DamageMeter
    C_DamageMeter = nil
    local players, withData, noRole = utility:GetSplitPlayers()
    C_DamageMeter = meter
    assert(#players == 20 and noRole == 1, "noRole " .. tostring(noRole)) -- Quillon (you get your spec's role)
    assert(withData == 19, "withData " .. tostring(withData)) -- everyone but Newcomer
    local quillon, newcomer
    for _, p in ipairs(players) do
        if p.name == "Quillon" then
            quillon = p
        elseif p.name == "Newcomer" then
            newcomer = p
        end
    end
    assert(quillon.assumedRole and quillon.value == 640000)
    assert(newcomer.hasData == false)
    local sides = utility.BalanceSides(players)
    assert(#sides[1].players == 10 and #sides[2].players == 10)
    Preview.Stop()
end)

test("joining a real group turns the preview off", function()
    Solo()
    Preview.Start()
    H.SetParty({ H.Member("Tester", "Home"), H.Member("Friend", "Home") })
    H.Fire("GROUP_ROSTER_UPDATE")
    assert(not Preview.IsActive() and H.LastMessage():find("joined a group"))
    H.timers = {}
end)

test("/nru preview toggles and clamps the size", function()
    Solo()
    SlashCmdList.NSRTRAIDUTILITY("preview 99")
    assert(Preview.IsActive() and #utility.GetGroupMembers() == 40)
    SlashCmdList.NSRTRAIDUTILITY("preview 1")
    assert(#utility.GetGroupMembers() == 2)
    SlashCmdList.NSRTRAIDUTILITY("preview")
    assert(not Preview.IsActive())
    SlashCmdList.NSRTRAIDUTILITY("preview off")
    assert(not Preview.IsActive(), "'off' started the preview")
    assert(#utility.GetGroupMembers() == 1, "live group (just you, solo) not restored")
end)

test("the banner shows only during the preview", function()
    Solo()
    assert(Preview.Banner() == "")
    Preview.Start()
    assert(Preview.Banner():find("PREVIEW RAID"))
    assert(utility.ui.result.text:find("PREVIEW RAID"), "Rosters tab banner missing")
    Preview.Stop()
    assert(not utility.ui.result.text:find("PREVIEW RAID"), "banner stayed after the preview ended")
end)
