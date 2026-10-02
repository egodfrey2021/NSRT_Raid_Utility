-- Injects the Rosters tab into the NSRT options window + events and slash commands
local ADDON, Extras = ...
local TAB_NAME, TAB_LABEL = "NSRTExtras", "Rosters"

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

    local frame = CreateFrame("Frame", "NSUI_TabFrame_" .. TAB_NAME, NSUI, "BackdropTemplate")
    frame:SetPoint(refTab:GetPoint(1))
    frame:SetSize(refTab:GetSize())
    frame:Hide()

    local btn = NSI.UI.Components.CreateButton(lastBtn.frame:GetParent(), TAB_LABEL,
        function() menu:SelectTabByName(TAB_NAME) end, 148, 22, "NSUITabBtn_" .. TAB_NAME)
    btn:SetPoint("TOPLEFT", lastBtn.frame, "BOTTOMLEFT", 0, -14)

    menu.AllFramesByName[TAB_NAME]  = frame
    menu.AllButtonsByName[TAB_NAME] = btn
    table.insert(menu.AllFrames, frame)
    table.insert(menu.AllButtons, btn)

    Extras:BuildRosterTab(frame, NSI)
    injected = true
end

local function HookUI()
    local NSI = _G.NorthernSkyRaidTools
    if hooked or not (NSI and NSI.NSUI) then return end
    NSI.NSUI:HookScript("OnShow", InjectTab)
    hooked = true
    if NSI.NSUI:IsShown() then InjectTab() end
end

local function OpenTab()
    local NSI = _G.NorthernSkyRaidTools
    if NSI and NSI:LoadUI(true) and NSI.NSUI then
        NSI.NSUI:Show()
        InjectTab()
        if NSI.NSUI.MenuFrame then NSI.NSUI.MenuFrame:SelectTabByName(TAB_NAME) end
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
    else
        OpenTab()
    end
end
