-- Injects the Rosters and Split Raid tabs into the NSRT options window + events and slash commands
local ADDON, Extras = ...
local TABS = {
    { name = "NSRTExtras",      label = "Rosters",    build = "BuildRosterTab" },
    { name = "NSRTExtrasSplit", label = "Split Raid", build = "BuildSplitTab" },
}
Extras.ROSTER_TAB, Extras.SPLIT_TAB = TABS[1].name, TABS[2].name

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

    Extras.menu = menu
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

        Extras[tab.build](Extras, frame, NSI)
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
        if Extras.ui then Extras:RefreshUI() end
    elseif name == ADDON then
        Extras:InitDB()
        HookUI()
    elseif name == "NorthernSkyRaidTools_UI" then
        HookUI()
    end
end)

-- /nsx                 open the Rosters tab
-- /nsx split           open the Split Raid tab
-- /nsx arrange [name]  sort groups using the active (or named) roster
-- /nsx invite          invite roster players not in the group
SLASH_NSRTEXTRAS1 = "/nsx"
SlashCmdList.NSRTEXTRAS = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "arrange" then
        Extras:Arrange(rest ~= "" and rest or nil)
    elseif cmd == "invite" then
        Extras:InviteMissing()
    elseif cmd == "split" then
        OpenTab(Extras.SPLIT_TAB)
    else
        OpenTab(Extras.ROSTER_TAB)
    end
end
