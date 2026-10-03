-- Core.lua: tab injection, slash commands, refresh scheduling
local H = ...
local utility, test = H.utility, H.test
local NSI = _G.NorthernSkyRaidTools

-- Core builds the real tabs on inject; stub them here and restore for the UI suites
local buildRoster, refreshUI = utility.BuildRosterTab, utility.RefreshUI
utility.BuildRosterTab = function(self, frame) self.ui = { frame = frame } end

local window, menu = H.NSRTWindow()
local ready = false
function NSI:LoadUI()
    if ready then
        window.Initialized, window.MenuFrame = true, menu
        return true
    end
    return false
end
H.Fire("ADDON_LOADED", "NSRT_Raid_Utility")

test("the first tab request survives NSRT still loading", function()
    SlashCmdList.NSRTRAIDUTILITY("")
    assert(not menu.CurrentName, "selected tab before NSRT finished loading")
    ready = true
    window.Initialized, window.MenuFrame = true, menu
    window:Show()
    assert(menu.CurrentName == utility.ROSTER_TAB, "first-open tab was lost")
    assert(menu.AllButtonsByName[utility.ROSTER_TAB], "tab button was not registered")
    assert(#menu.AllFrames == 1, "expected only the Rosters tab")
end)

test("/nru split opens the Rosters tab and generates a split", function()
    local generate, generated = utility.GenerateSplit, false
    utility.GenerateSplit = function() generated = true end
    menu.CurrentName = nil
    SlashCmdList.NSRTRAIDUTILITY("split")
    utility.GenerateSplit = generate
    assert(menu.CurrentName == utility.ROSTER_TAB and generated)
end)

test("/nru sort uses the saved roster and the old arrange command no longer sorts", function()
    local sort, calls = utility.Arrange, {}
    utility.Arrange = function(_, name, roster) calls[#calls + 1] = { name = name, roster = roster } end
    SlashCmdList.NSRTRAIDUTILITY("sort")
    SlashCmdList.NSRTRAIDUTILITY("sort Boss roster")
    SlashCmdList.NSRTRAIDUTILITY("arrange")
    utility.Arrange = sort
    assert(#calls == 2, "unexpected sort command accepted")
    assert(calls[1].name == nil and calls[1].roster == nil, "default sort should use the saved roster")
    assert(calls[2].name == "Boss roster" and calls[2].roster == nil, "named sort should use a saved roster")
end)

test("the addon compartment opens the Rosters tab", function()
    NSRTRaidUtility_OnAddonCompartmentClick()
    assert(menu.CurrentName == utility.ROSTER_TAB)
end)

test("roster updates refresh the visible tab once, after a quiet moment", function()
    local refreshes = 0
    utility.RefreshUI = function() refreshes = refreshes + 1 end
    H.timers = {}
    utility.ui.frame:Hide()
    H.Fire("GROUP_ROSTER_UPDATE")
    H.RunTimers()
    assert(refreshes == 0, "hidden tab was refreshed")
    utility.ui.frame:Show()
    for _ = 1, 5 do
        H.Fire("GROUP_ROSTER_UPDATE")
    end
    assert(refreshes == 0, "refreshed before the delay")
    H.RunTimers()
    assert(refreshes == 1, "burst of updates did not collapse into one refresh")
    window:Hide()
    H.Fire("GROUP_ROSTER_UPDATE")
    H.RunTimers()
    assert(refreshes == 1, "closed options window was refreshed")
    window.visible = true
end)

test("roster updates in combat wait until combat ends", function()
    local refreshes = 0
    utility.RefreshUI = function() refreshes = refreshes + 1 end
    H.timers, H.inCombat = {}, true
    H.Fire("GROUP_ROSTER_UPDATE")
    H.RunTimers()
    assert(refreshes == 0, "refreshed in combat")
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    H.RunTimers()
    assert(refreshes == 1, "missed refresh after combat")
    -- the meter changed during the fight, so the end of combat always refreshes a visible tab
    H.Fire("PLAYER_REGEN_ENABLED")
    H.RunTimers()
    assert(refreshes == 2, "no meter refresh after combat")
    utility.ui.frame:Hide()
    H.Fire("PLAYER_REGEN_ENABLED")
    H.RunTimers()
    utility.ui.frame:Show()
    assert(refreshes == 2, "hidden tab refreshed after combat")
end)

test("nickname changes schedule a refresh", function()
    local refreshes = 0
    utility.RefreshUI = function() refreshes = refreshes + 1 end
    H.timers = {}
    local cb = H.callbacks and H.callbacks.NSRT_NICKNAME_UPDATED
    assert(cb and cb[1] == utility, "nickname callback not registered")
    cb[2]("NSRT_NICKNAME_UPDATED")
    H.RunTimers()
    assert(refreshes == 1)
end)

test("/nru debug toggles debug output", function()
    SlashCmdList.NSRTRAIDUTILITY("debug")
    assert(utility.debug and H.LastMessage():find("on"))
    utility.Debug("hello")
    assert(H.LastMessage():find("hello"))
    SlashCmdList.NSRTRAIDUTILITY("debug")
    assert(not utility.debug)
end)

utility.BuildRosterTab, utility.RefreshUI = buildRoster, refreshUI
