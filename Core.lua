-- Injects the Rosters and Split Raid tabs into the NSRT options window + events and slash commands
local ADDON, RaidUtility = ...
local TABS = {
    { name = "NSRTRaidUtility",      label = "Rosters",    build = "BuildRosterTab" },
    { name = "NSRTRaidUtilitySplit", label = "Split Raid", build = "BuildSplitTab" },
}
RaidUtility.ROSTER_TAB, RaidUtility.SPLIT_TAB = TABS[1].name, TABS[2].name

local injected, hooked = false, false

local function InjectTab()
    if injected then return end
    local NSI  = _G.NorthernSkyRaidTools
    local NSUI = NSI and NSI.NSUI
    local menu = NSUI and NSUI.Initialized and NSUI.MenuFrame
    if not (menu and NSI.UI and NSI.UI.Components) then return end

    local refTab  = menu:GetTabFrameByName("General")
    local lastBtn = menu.AllButtonsByName["Versions"]   -- last sidebar button
    if not (refTab and lastBtn) then return end

    RaidUtility.menu = menu
    local anchor, gap = lastBtn.frame, -14     -- our buttons form their own block under "Versions"
    for _, tab in ipairs(TABS) do
        local frame = CreateFrame("Frame", "NSUI_TabFrame_" .. tab.name, NSUI, "BackdropTemplate")
        frame:SetPoint(refTab:GetPoint(1))
        frame:SetSize(refTab:GetSize())
        frame:Hide()

        local btn = NSI.UI.Components.CreateButton(lastBtn.frame:GetParent(), tab.label,
            function() menu:SelectTabByName(tab.name) end, 148, 22, "NSUITabBtn_" .. tab.name)
        btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
        anchor, gap = btn.frame, 0

        menu.AllFramesByName[tab.name]  = frame
        menu.AllButtonsByName[tab.name] = btn
        table.insert(menu.AllFrames, frame)
        table.insert(menu.AllButtons, btn)

        RaidUtility[tab.build](RaidUtility, frame, NSI)
    end
    injected = true
end

local function HookUI()
    local NSI = _G.NorthernSkyRaidTools
    if hooked or not (NSI and NSI.NSUI) then return end
    NSI.NSUI:HookScript("OnShow", InjectTab)
    hooked = true
    if NSI.NSUI:IsShown() then InjectTab() end
end

local function OpenTab(name)
    local NSI = _G.NorthernSkyRaidTools
    if NSI and NSI:LoadUI(true) and NSI.NSUI then
        NSI.NSUI:Show()
        InjectTab()
        if NSI.NSUI.MenuFrame then NSI.NSUI.MenuFrame:SelectTabByName(name) end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, name)
    if event == "GROUP_ROSTER_UPDATE" then
        if RaidUtility.ui then RaidUtility:RefreshUI() end
    elseif name == ADDON then
        RaidUtility:InitDB()
        HookUI()
    elseif name == "NorthernSkyRaidTools_UI" then
        HookUI()
    end
end)

-- /nru                 open the Rosters tab (/nsx still works)
-- /nru split           open the Split Raid tab
-- /nru arrange [name]  sort groups using the active (or named) roster
-- /nru invite          invite roster players not in the group
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
        OpenTab(RaidUtility.SPLIT_TAB)
    else
        OpenTab(RaidUtility.ROSTER_TAB)
    end
end
