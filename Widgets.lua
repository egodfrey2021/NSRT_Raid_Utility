-- Small widget helpers shared by the Rosters tab and its split controls
local _, RaidUtility = ...
local Widgets = {}
RaidUtility.Widgets = Widgets

Widgets.WHITE = "Interface\\Buttons\\WHITE8x8"

Widgets.ROLE_ICON = {
    TANK = INLINE_TANK_ICON,
    HEALER = INLINE_HEALER_ICON,
    DAMAGER = INLINE_DAMAGER_ICON,
}

-- Meter-style number: 950, 1.5K, 1.21M
function Widgets.Short(n)
    if n >= 1e6 then return format("%.2fM", n / 1e6) end
    if n >= 1e3 then return format("%.1fK", n / 1e3) end
    return format("%d", n)
end

-- NSRT-styled button on the tab's top row. C is NSI.UI.Components.
function Widgets.TopButton(C, frame, text, x, w, fn)
    local b = C.CreateButton(frame, text, fn, w, 22)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -10)
    return b
end

-- Hover text on a frame. Hooks rather than replaces, so NSRT's own hover effects keep working.
function Widgets.Tooltip(frame, text)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
