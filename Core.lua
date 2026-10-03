-- Injects the Rosters tab into the NSRT options window + events and slash commands
local ADDON, RaidUtility = ...
local L, NSRT = RaidUtility.L, RaidUtility.NSRT
local TABS = {
    { name = "NSRTRaidUtility", label = L["Rosters"], build = "BuildRosterTab" },
}
RaidUtility.ROSTER_TAB = TABS[1].name

-- Roster changes arrive in bursts (a group sort fires one per move), so refreshes wait for a quiet moment
local REFRESH_DELAY = 0.5

local injected, hooked, warned, pendingTab = false, false, false, nil

local function InjectTab()
    if injected then return true end
    local menu, C, NSI = NSRT.GetMenu()
    if not menu then return end -- NSRT is still building its window; retry on the next OnShow

    local refTab = menu:GetTabFrameByName("General")
    local lastBtn = menu.AllButtonsByName["Versions"] -- last sidebar button
    if not (refTab and lastBtn) then
        -- NSRT changed its layout; tell the user once and stop waiting to open our tab
        if not warned then
            warned = true
            RaidUtility.Print(L["Couldn't add tabs to the NSRT window. NSRT may have changed; check for an update."])
        end
        pendingTab = nil
        return
    end

    RaidUtility.menu = menu
    local anchor, gap = lastBtn.frame, -14 -- our buttons form their own block under "Versions"
    for _, tab in ipairs(TABS) do
        local frame = CreateFrame("Frame", "NSUI_TabFrame_" .. tab.name, NSRT.GetWindow(), "BackdropTemplate")
        frame:SetPoint(refTab:GetPoint(1))
        frame:SetSize(refTab:GetSize())
        frame:Hide()

        local btn = C.CreateButton(
            lastBtn.frame:GetParent(),
            tab.label,
            function() menu:SelectTabByName(tab.name) end,
            148,
            22,
            "NSUITabBtn_" .. tab.name
        )
        btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
        anchor, gap = btn.frame, 0

        menu.AllFramesByName[tab.name] = frame
        menu.AllButtonsByName[tab.name] = btn
        table.insert(menu.AllFrames, frame)
        table.insert(menu.AllButtons, btn)

        RaidUtility[tab.build](RaidUtility, frame, NSI)
    end
    injected = true
    return true
end

local function OnUIShow()
    if InjectTab() and pendingTab then
        RaidUtility.menu:SelectTabByName(pendingTab)
        pendingTab = nil
    end
end

local function HookUI()
    local window = NSRT.GetWindow()
    if hooked or not window then return end
    window:HookScript("OnShow", OnUIShow)
    hooked = true
    if window:IsShown() then OnUIShow() end
end

local function OpenTab(name)
    if not (NSRT.Get() and NSRT.Get().LoadUI) then
        RaidUtility.Print(L["NSRT options are not available."])
        return
    end
    pendingTab = name
    local ready, window = NSRT.LoadWindow()
    if ready then
        window:Show()
        OnUIShow()
    elseif not window then -- otherwise NSRT is still building the window and our OnShow hook opens the tab
        pendingTab = nil
        RaidUtility.Print(L["NSRT options could not be loaded."])
    end
end

-- ------------------------------------------------------------
-- Refreshing the Rosters tab when the group changes
-- ------------------------------------------------------------
local refreshTimer

local function RosterTabVisible() return RaidUtility.ui and RaidUtility.ui.frame:IsVisible() end

local function RefreshVisible()
    refreshTimer = nil
    if RosterTabVisible() then RaidUtility:RefreshUI(true) end
end

-- A hidden tab costs nothing: NSRT calls RefreshOptions when it is shown again. Names can be secret in combat and
-- nobody edits rosters mid-pull, so combat refreshes wait for PLAYER_REGEN_ENABLED, which always refreshes a
-- visible tab. Each refresh re-reads the damage meter.
local function ScheduleRefresh()
    if not RosterTabVisible() or InCombatLockdown() then return end
    if refreshTimer then refreshTimer:Cancel() end
    refreshTimer = C_Timer.NewTimer(REFRESH_DELAY, RefreshVisible)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, name)
    if event == "GROUP_ROSTER_UPDATE" then
        if RaidUtility.Preview.IsActive() and IsInGroup() then
            RaidUtility.Preview.Stop(L["Preview raid off: you joined a group."])
        end
        RaidUtility:OnRosterUpdate()
        ScheduleRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- covers roster changes skipped in combat, and the Overall meter session changed during the fight
        ScheduleRefresh()
    elseif name == ADDON then
        RaidUtility:InitDB()
        NSRT.OnNicknameUpdated(RaidUtility, ScheduleRefresh)
        HookUI()
    elseif name == "NorthernSkyRaidTools_UI" then
        HookUI()
    end
end)

-- Minimap addon drawer (## AddonCompartmentFunc in the .toc)
function NSRTRaidUtility_OnAddonCompartmentClick() OpenTab(RaidUtility.ROSTER_TAB) end

-- /nru                 open the Rosters tab (/nsx still works)
-- /nru split           open the Rosters tab and generate a split
-- /nru arrange [name]  sort groups using the active (or named) roster
-- /nru invite          invite roster players not in the group
-- /nru debug           toggle debug output
-- /nru preview [size]  toggle a made-up raid (2-40 players, default 20) for trying the tab solo
SLASH_NSRTRAIDUTILITY1 = "/nru"
SLASH_NSRTRAIDUTILITY2 = "/nsx"
SlashCmdList.NSRTRAIDUTILITY = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "arrange" then
        RaidUtility:Arrange(rest ~= "" and rest or nil)
    elseif cmd == "invite" then
        RaidUtility:InviteMissing()
    elseif cmd == "split" then
        OpenTab(RaidUtility.ROSTER_TAB)
        RaidUtility:GenerateSplit()
    elseif cmd == "preview" then
        if RaidUtility.Preview.IsActive() and (rest == "" or rest == "off") then
            RaidUtility.Preview.Stop()
        elseif rest ~= "off" then
            RaidUtility.Preview.Start(rest)
        end
    elseif cmd == "debug" then
        RaidUtility.debug = not RaidUtility.debug
        RaidUtility.Print(RaidUtility.debug and L["Debug output on."] or L["Debug output off."])
    else
        OpenTab(RaidUtility.ROSTER_TAB)
    end
end
