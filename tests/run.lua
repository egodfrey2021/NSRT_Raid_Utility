-- Runs the addon's behaviour tests outside the game. From the repo root: mise run test
---@diagnostic disable-next-line: undefined-field
local dofile, loadfile = _G.dofile, _G.loadfile -- standard Lua, not in WoW
local H = dofile("tests/harness.lua")
H.LoadToc("NSRT_Raid_Utility.toc")
NSRTRaidUtilityDB = nil
H.utility:InitDB()

-- Each suite owns one area of the addon; suites share the loaded addon and run in this order.
for _, suite in ipairs({ "roster", "split", "core", "rosterui", "preview" }) do
    H.suite = suite
    assert(loadfile("tests/" .. suite .. ".lua"))(H)
end
H.Finish()
