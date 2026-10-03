-- Translation seam: L["English text"] returns the translation, or the English key when there is none.
-- To add a locale: if GetLocale() == "deDE" then L["Saved"] = "Gespeichert" ... end
local _, RaidUtility = ...
RaidUtility.L = setmetatable({}, { __index = function(_, key) return key end })
