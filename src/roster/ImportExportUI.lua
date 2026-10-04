-- Import and export text in separate views; imports edit the draft, exports only produce text to copy.
local _, RaidUtility = ...
local L, Print = RaidUtility.L, RaidUtility.Print
local WHITE = RaidUtility.Widgets.WHITE

local function CountNames(roster)
    local count = 0
    RaidUtility.ForEachEntry(roster, function() count = count + 1 end)
    return count
end

local function TextArea(parent, y, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    scroll:SetSize(646, height)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetWidth(626)
    box:SetHeight(height)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetText("")
    scroll:SetScrollChild(box)
    return box, scroll
end

local function Label(parent, text, y, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    label:SetWidth(660)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

function RaidUtility:ShowImportExport(frame, C)
    local panel = self.ui.importExport
    if panel then
        panel:Show()
        return
    end

    panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    self.ui.importExport = panel
    panel:SetSize(700, 470)
    panel:SetPoint("CENTER", frame, "CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    panel:SetBackdropColor(0.06, 0.08, 0.11, 0.98)
    panel:SetBackdropBorderColor(0, 0.7, 0.85)
    panel:Hide()

    Label(panel, L["Import / export"], -14, "GameFontNormal")
    local close = C.CreateButton(panel, L["Close"], function() panel:Hide() end, 90, 24)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -10)

    local importView = CreateFrame("Frame", nil, panel)
    importView:SetSize(700, 390)
    importView:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -72)
    local exportView = CreateFrame("Frame", nil, panel)
    exportView:SetSize(700, 390)
    exportView:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -72)
    panel.importView, panel.exportView = importView, exportView

    local mode, view, pastes, encounters = "list", "import", { list = "", audit = "" }, {}
    local readyRoster, overflow, count
    local sourceButtons = {}
    local hint = Label(importView, "", -36)
    local pasteLabel = Label(importView, L["Text to import:"], -74, "GameFontNormalSmall")
    local input, inputScroll = TextArea(importView, -92, 135)
    panel.importText = input
    input:SetScript("OnEscapePressed", function() panel:Hide() end)
    local preview = Label(importView, "", -267)
    panel.preview = preview
    local impact = Label(importView, "", -298)
    local result = Label(importView, "", -326)
    panel.importResult = result

    local picker, RefreshPreview
    picker = C.CreateDropdown(importView, L["Encounter"], function()
        local items = {}
        for i, encounter in ipairs(encounters) do
            local label = L["%1$d. %2$s (%3$s)"]:format(i, encounter.name, encounter.difficulty)
            if not encounter.names or encounter.names == "" then label = label .. " " .. L["(no invite list)"] end
            items[#items + 1] = {
                label = label,
                value = i,
                onclick = function()
                    panel.selected = i
                    picker:Refresh()
                    RefreshPreview()
                end,
            }
        end
        return items
    end, function()
        local encounter = encounters[panel.selected or (#encounters == 1 and 1)]
        return encounter and L["%1$s (%2$s)"]:format(encounter.name, encounter.difficulty) or L["Select encounter"]
    end, 300)
    picker:SetPoint("TOPLEFT", importView, "TOPLEFT", 16, -233)
    panel.picker = picker

    local function ApplyImport()
        if not readyRoster then
            result:SetText(L["Paste a valid list or select an encounter before importing."])
            return
        end
        RaidUtility.draft, RaidUtility.draftSplit = readyRoster, false
        RaidUtility:MarkDirty()
        RaidUtility:RefreshUI()
        local summary = L["Imported %d name(s). Save to keep them."]:format(count)
        Print(summary)
        if overflow > 0 then
            local ignored = L["%d name(s) beyond slot 40 were ignored."]:format(overflow)
            Print(ignored)
            summary = summary .. " " .. ignored
        end
        result:SetText(summary)
    end
    local listButton = C.CreateButton(importView, L["Import NSRT/WoWUtils list"], ApplyImport, 220, 24)
    listButton:SetPoint("TOPLEFT", importView, "TOPLEFT", 16, -362)
    panel.importList = listButton

    local auditButton = C.CreateButton(importView, L["Import encounter"], ApplyImport, 160, 24)
    auditButton:SetPoint("TOPLEFT", importView, "TOPLEFT", 16, -362)
    panel.importEncounter = auditButton

    local meterButton = C.CreateButton(
        importView,
        L["Add from damage meter"],
        function() result:SetText(RaidUtility:ImportFromMeter()) end,
        190,
        24
    )
    meterButton:SetPoint("TOPLEFT", importView, "TOPLEFT", 16, -362)
    panel.importMeter = meterButton

    RefreshPreview = function()
        readyRoster, overflow, count = nil, 0, 0
        if mode == "meter" then
            preview:SetText(L["This adds players the Overall session has seen but leaves placed names alone."])
        elseif mode == "list" then
            local text = input:GetText()
            local roster, err = RaidUtility:ImportText(text)
            if roster then
                count = CountNames(roster)
                if count > 0 then
                    readyRoster, overflow = roster, err
                else
                    preview:SetText(L["No names fit in the first 40 slots. Check the list before importing."])
                end
            else
                preview:SetText(text == "" and L["Paste an invite list or names above."] or err)
            end
        else
            encounters = RaidUtility:WoWAuditEncounters(input:GetText())
            local index = panel.selected or (#encounters == 1 and 1)
            if #encounters == 0 then
                preview:SetText(L["Paste a WoWAudit encounter export above."])
            elseif not index then
                preview:SetText(L["Found %d encounters. Select one above."]:format(#encounters))
            else
                local roster, err = RaidUtility:ImportWoWAuditEncounter(encounters[index])
                if roster then
                    readyRoster, overflow, count = roster, err, CountNames(roster)
                else
                    preview:SetText(err)
                end
            end
        end
        if readyRoster then
            local summary = L["%d name(s) ready to import."]:format(count)
            if overflow > 0 then
                summary = summary .. " " .. L["%d beyond slot 40 will be ignored."]:format(overflow)
            end
            preview:SetText(summary)
        end
        if readyRoster then
            (mode == "list" and listButton or auditButton):Enable()
        else
            listButton:Disable()
            auditButton:Disable()
        end
        picker:Refresh()
    end

    input:SetScript("OnTextChanged", function()
        if mode ~= "meter" then pastes[mode] = input:GetText() end
        panel.selected = false
        input:SetHeight(math.max(135, input:GetNumLines() * 14 + 16))
        inputScroll:SetVerticalScroll(0)
        result:SetText("")
        RefreshPreview()
    end)

    local function SelectSource(selected)
        if mode ~= "meter" then pastes[mode] = input:GetText() end
        mode = selected
        panel.selected = false
        input:SetText(pastes[mode] or "")
        local isText = mode ~= "meter"
        if not isText then input:ClearFocus() end
        inputScroll:SetShown(isText)
        picker:SetShown(mode == "audit")
        pasteLabel:SetShown(isText)
        for key, button in pairs(sourceButtons) do
            button.frame:SetAlpha(key == mode and 1 or 0.6)
        end
        listButton.frame:SetShown(mode == "list")
        auditButton.frame:SetShown(mode == "audit")
        meterButton.frame:SetShown(mode == "meter")
        if mode == "list" then
            hint:SetText(
                L["Paste an NSRT or WoWUtils invitelist: line, or a plain list of names. Empty slots are kept."]
            )
            impact:SetText(L["Import replaces the open draft. Undo restores the old draft; Save keeps the import."])
        elseif mode == "audit" then
            hint:SetText(
                L["Paste a WoWAudit encounter export. Invite lists have no group positions; names fill slots in order."]
            )
            impact:SetText(L["Import replaces the open draft. Undo restores the old draft; Save keeps the import."])
        else
            hint:SetText(L["Add players from the damage meter's Overall session, sorted by role and value."])
            impact:SetText(L["Placed names stay where they are. Undo removes added names; Save keeps them."])
        end
        result:SetText("")
        local compact = mode == "meter"
        local function Move(label, y)
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", importView, "TOPLEFT", 16, y)
        end
        Move(preview, compact and -72 or -267)
        Move(impact, compact and -102 or -298)
        Move(result, compact and -138 or -326)
        meterButton.frame:ClearAllPoints()
        meterButton.frame:SetPoint("TOPLEFT", importView, "TOPLEFT", 16, compact and -190 or -362)
        if view == "import" then panel:SetHeight(compact and 310 or 470) end
        RefreshPreview()
    end
    panel.selectSource = SelectSource

    local function Source(text, key, x, width)
        local button = C.CreateButton(importView, text, function() SelectSource(key) end, width, 24)
        button:SetPoint("TOPLEFT", importView, "TOPLEFT", x, -4)
        sourceButtons[key] = button
    end
    Source(L["NSRT / WoWUtils list"], "list", 16, 190)
    Source(L["WoWAudit encounter"], "audit", 216, 190)
    Source(L["Damage meter"], "meter", 416, 150)

    Label(exportView, L["Choose what to export:"], -6, "GameFontNormalSmall")
    local output, outputScroll = TextArea(exportView, -121, 228)
    panel.exportText = output
    output:SetScript("OnEscapePressed", function() panel:Hide() end)
    output:SetScript("OnTextChanged", function() output:SetHeight(math.max(228, output:GetNumLines() * 14 + 16)) end)
    Label(exportView, L["Text to copy (select it and press Ctrl+C):"], -98, "GameFontNormalSmall")
    local exportInfo = Label(exportView, "", -66)
    local exportStatus = Label(exportView, "", -354)
    panel.exportStatus = exportStatus
    local function ShowOutput(text, description)
        output:SetText(text)
        outputScroll:SetVerticalScroll(0)
        output:SetFocus()
        output:HighlightText()
        exportStatus:SetText(L["Text selected. Press Ctrl+C to copy it."])
        exportInfo:SetText(description)
    end
    local exportList = C.CreateButton(
        exportView,
        L["Export draft as NSRT list"],
        function()
            ShowOutput(
                RaidUtility:ExportWoWUtils(RaidUtility.draft),
                L["Draft roster, with group positions. Use where NSRT invite lists are accepted."]
            )
        end,
        230,
        24
    )
    exportList:SetPoint("TOPLEFT", exportView, "TOPLEFT", 16, -35)
    panel.exportList = exportList
    local exportAudit = C.CreateButton(exportView, L["Export live group for WoWAudit"], function()
        local text, err = RaidUtility:ExportWoWAuditRaid()
        if not text then
            output:SetText("")
            exportInfo:SetText(L["Export text appears below; it will not change the roster."])
            exportStatus:SetText(err)
            Print(err)
            return
        end
        ShowOutput(text, L["Live group snapshot, not the draft. Group positions are not included."])
    end, 260, 24)
    exportAudit:SetPoint("TOPLEFT", exportView, "TOPLEFT", 256, -35)
    panel.exportAudit = exportAudit

    local importTab, exportTab
    local function SelectView(target)
        view = target
        importView:SetShown(view == "import")
        exportView:SetShown(view == "export")
        importTab.frame:SetAlpha(view == "import" and 1 or 0.6)
        exportTab.frame:SetAlpha(view == "export" and 1 or 0.6)
        panel:SetHeight(view == "import" and mode == "meter" and 310 or 470)
        if view == "import" then
            output:ClearFocus()
            RefreshPreview()
        else
            input:ClearFocus()
        end
    end
    panel.selectView = SelectView
    importTab = C.CreateButton(panel, L["Import"], function() SelectView("import") end, 110, 24)
    importTab:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -40)
    exportTab = C.CreateButton(panel, L["Export"], function() SelectView("export") end, 110, 24)
    exportTab:SetPoint("TOPLEFT", panel, "TOPLEFT", 136, -40)
    panel:SetScript("OnShow", function()
        output:SetText("")
        exportStatus:SetText("")
        exportInfo:SetText(L["Export text appears below; it will not change the roster."])
        result:SetText("")
        SelectView("import")
    end)
    panel:SetScript("OnHide", function()
        input:ClearFocus()
        output:ClearFocus()
    end)
    SelectSource("list")
    panel:Show()
end
