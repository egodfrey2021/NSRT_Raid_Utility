-- Import and export text in separate views; imports edit the draft, exports only produce text to copy.
local _, RaidUtility = ...
local L, Print = RaidUtility.L, RaidUtility.Print
local WHITE = RaidUtility.Widgets.WHITE

local function CountNames(roster)
    local count = 0
    RaidUtility.ForEachEntry(roster, function() count = count + 1 end)
    return count
end

local function Section(parent)
    local section = CreateFrame("Frame", nil, parent)
    section:SetSize(700, 390)
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -36)
    return section
end

local function Label(parent, text, y, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    label:SetWidth(660)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function TextArea(parent, y, height)
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    border:SetSize(660, height)
    border:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    border:SetBackdropColor(0, 0, 0, 0.85)
    border:SetBackdropBorderColor(0.3, 0.5, 0.55, 0.9)

    local scroll = CreateFrame("ScrollFrame", nil, border, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", border, "TOPLEFT", 8, -8)
    scroll:SetSize(624, height - 16)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetWidth(598)
    box:SetHeight(height - 16)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetText("")
    scroll:SetScrollChild(box)
    return box, scroll
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
    panel.selected = false

    local textView = Section(importView)
    local meterView = Section(importView)
    panel.textView, panel.meterView = textView, meterView
    local hint = Label(textView, "", -4)
    local pasteStep = Label(textView, "", -37, "GameFontNormalSmall")
    local input, inputScroll = TextArea(textView, -56, 125)
    panel.importText = input
    input:SetScript("OnEscapePressed", function() panel:Hide() end)
    local preview = Label(textView, "", -231)
    Label(textView, L["Import replaces the open draft. Undo restores it; Save keeps the import."], -260)
    local result = Label(textView, "", -283)

    local pickerView = CreateFrame("Frame", nil, textView)
    pickerView:SetSize(700, 30)
    pickerView:SetPoint("TOPLEFT", textView, "TOPLEFT", 0, -190)
    local picker, RefreshPreview
    picker = C.CreateDropdown(pickerView, L["Encounter"], function()
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
    picker:SetPoint("TOPLEFT", pickerView, "TOPLEFT", 16, 0)
    panel.picker = picker

    local reviewTextAction
    local function ApplyImport()
        if not readyRoster then
            result:SetText(L["Paste a valid list or select an encounter before importing."])
            return
        end
        RaidUtility.draft, RaidUtility.draftSplit = readyRoster, false
        RaidUtility:MarkDirty()
        RaidUtility:RefreshUI()
        Print(L["Imported %d name(s). Save to keep them."]:format(count))
        local summary = L["Imported %d name(s) to the draft. Review the roster, then Save."]:format(count)
        if overflow > 0 then
            local ignored = L["%d name(s) beyond slot 40 were ignored."]:format(overflow)
            Print(ignored)
            summary = summary .. " " .. ignored
        end
        result:SetText(summary)
        reviewTextAction:Show()
    end
    local listAction = CreateFrame("Frame", nil, textView)
    listAction:SetSize(700, 28)
    listAction:SetPoint("TOPLEFT", textView, "TOPLEFT", 0, -318)
    local listButton = C.CreateButton(listAction, L["Import into draft"], ApplyImport, 170, 24)
    listButton:SetPoint("TOPLEFT", listAction, "TOPLEFT", 16, 0)
    panel.importList = listButton

    local auditAction = CreateFrame("Frame", nil, textView)
    auditAction:SetSize(700, 28)
    auditAction:SetPoint("TOPLEFT", textView, "TOPLEFT", 0, -318)
    local auditButton = C.CreateButton(auditAction, L["Import into draft"], ApplyImport, 170, 24)
    auditButton:SetPoint("TOPLEFT", auditAction, "TOPLEFT", 16, 0)
    panel.importEncounter = auditButton
    reviewTextAction = CreateFrame("Frame", nil, textView)
    reviewTextAction:SetSize(700, 28)
    reviewTextAction:SetPoint("TOPLEFT", textView, "TOPLEFT", 0, -318)
    local reviewText = C.CreateButton(reviewTextAction, L["Review roster"], function() panel:Hide() end, 150, 24)
    reviewText:SetPoint("TOPLEFT", reviewTextAction, "TOPLEFT", 200, 0)
    panel.reviewText = reviewText
    reviewTextAction:Hide()

    RefreshPreview = function()
        readyRoster, overflow, count = nil, 0, 0
        if mode == "list" then
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
        elseif mode == "audit" then
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
        if mode == "list" and readyRoster then
            listButton:Enable()
        else
            listButton:Disable()
        end
        if mode == "audit" and readyRoster then
            auditButton:Enable()
        else
            auditButton:Disable()
        end
        picker:Refresh()
    end

    input:SetScript("OnTextChanged", function()
        if mode ~= "meter" then pastes[mode] = input:GetText() end
        panel.selected = false
        input:SetHeight(math.max(109, input:GetNumLines() * 14 + 16))
        inputScroll:SetVerticalScroll(0)
        result:SetText("")
        reviewTextAction:Hide()
        RefreshPreview()
    end)

    Label(meterView, L["2. Add players from the damage meter's Overall session."], -4, "GameFontNormalSmall")
    Label(meterView, L["Only empty slots are filled. Nothing changes until you click Add."], -47)
    local meterResult = Label(meterView, "", -90)
    local reviewMeter
    local meterButton = C.CreateButton(meterView, L["Add to draft"], function()
        local message, added = RaidUtility:ImportFromMeter()
        meterResult:SetText(message)
        if added and added > 0 then reviewMeter.frame:Show() end
    end, 150, 24)
    meterButton:SetPoint("TOPLEFT", meterView, "TOPLEFT", 16, -153)
    panel.importMeter = meterButton
    reviewMeter = C.CreateButton(meterView, L["Review roster"], function() panel:Hide() end, 150, 24)
    reviewMeter:SetPoint("TOPLEFT", meterView, "TOPLEFT", 200, -153)
    panel.reviewMeter = reviewMeter
    reviewMeter.frame:Hide()

    local sourcePicker
    local sourceNames = {
        list = L["NSRT / WoWUtils list"],
        audit = L["WoWAudit encounter"],
        meter = L["Damage meter"],
    }
    local function SelectSource(selected)
        if mode ~= "meter" then pastes[mode] = input:GetText() end
        mode = selected
        panel.selected = false
        if mode ~= "meter" then input:SetText(pastes[mode]) end
        textView:SetShown(mode ~= "meter")
        meterView:SetShown(mode == "meter")
        pickerView:SetShown(mode == "audit")
        listAction:SetShown(mode == "list")
        auditAction:SetShown(mode == "audit")
        if mode == "list" then
            hint:SetText(L["NSRT or WoWUtils invitelist: text and plain names are accepted. Empty slots are kept."])
            pasteStep:SetText(L["2. Paste an invite list or names to preview:"])
        elseif mode == "audit" then
            hint:SetText(L["WoWAudit encounter invite lists have no group positions; names fill slots in order."])
            pasteStep:SetText(L["2. Paste a WoWAudit encounter export to preview:"])
        else
            input:ClearFocus()
        end
        panel.preview = mode == "meter" and meterResult or preview
        panel.importResult = mode == "meter" and meterResult or result
        if view == "import" then panel:SetHeight(mode == "meter" and 310 or 470) end
        result:SetText("")
        meterResult:SetText("")
        reviewTextAction:Hide()
        reviewMeter.frame:Hide()
        RefreshPreview()
        sourcePicker:Refresh()
    end
    panel.selectSource = SelectSource

    sourcePicker = C.CreateDropdown(importView, L["1. Import from:"], function()
        local items = {}
        for _, key in ipairs({ "list", "audit", "meter" }) do
            items[#items + 1] = {
                label = sourceNames[key],
                value = key,
                onclick = function() SelectSource(key) end,
            }
        end
        return items
    end, function() return sourceNames[mode] end, 350)
    sourcePicker:SetPoint("TOPLEFT", importView, "TOPLEFT", 16, -4)
    panel.sourcePicker = sourcePicker

    Label(exportView, L["1. Generate text from:"], -6, "GameFontNormalSmall")
    local output, outputScroll = TextArea(exportView, -123, 205)
    panel.exportText = output
    output:SetScript("OnEscapePressed", function() panel:Hide() end)
    output:SetScript("OnTextChanged", function() output:SetHeight(math.max(189, output:GetNumLines() * 14 + 16)) end)
    Label(exportView, L["2. Copy the selected text with Ctrl+C:"], -102, "GameFontNormalSmall")
    local exportInfo = Label(exportView, "", -68)
    local exportStatus = Label(exportView, "", -346)
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
        meterResult:SetText("")
        reviewTextAction:Hide()
        reviewMeter.frame:Hide()
        SelectView("import")
    end)
    panel:SetScript("OnHide", function()
        input:ClearFocus()
        output:ClearFocus()
    end)
    SelectSource("list")
    panel:Show()
end
