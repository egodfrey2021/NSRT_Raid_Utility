# Roster for NSRT (folder: NSRT_Extras): project context

WoW Retail addon (Lua, interface 12.1.0) that adds a **Rosters** tab to the
Northern Sky Raid Tools (NSRT) options window. Author: Evan.

## What it does
- 8 groups x 5 slots per roster; many named rosters saved in `NSRTExtrasDB.rosters`.
- **Unassigned** panel = current raid/party members minus anyone placed in the roster being edited
  (nothing else; a shared "player pool" existed before v1.0.1 and was removed because names leaked
  between rosters). "Fill from current raid" copies the live subgroup layout into the draft.
- Drag and drop between slots (move/swap), Unassigned to slot (place), slot to Unassigned (un-place).
  Click empty slot / double-click name to type (for planning offline players). Right-click clears a slot.
- Group edits go to a draft (`Extras.draft`); **Save** commits, **Revert** discards, switching or
  creating rosters with unsaved edits asks to confirm.
- **Arrange groups** sorts the real raid to match the draft; `/nsx arrange` uses the saved roster.

## Files
- `Roster.lua`: data model, draft, name resolution, invite, arrange.
- `RosterUI.lua`: tab UI, drag and drop, inline editor, popups.
- `Core.lua`: injects the tab into NSRT's window, events, `/nsx` slash command.

## How it hooks into NSRT (no official plugin API exists)
- NSRT exposes `_G.NorthernSkyRaidTools` (internal namespace, unstable) and `NSAPI` (public).
- Options UI is a separate load-on-demand addon `NorthernSkyRaidTools_UI`, built in a coroutine.
  We hook `NSI.NSUI` OnShow and inject only once `NSUI.Initialized` is true.
- Tab injection: add our frame/button to `NSUI.MenuFrame.AllFrames/AllButtons/AllFramesByName/
  AllButtonsByName`; NSRT's own SelectTab then shows/hides/highlights it. Button is anchored under
  the "Versions" sidebar button. Uses `NSI.UI.Components` (CreateButton, CreateDropdown) for styling.
- Name resolution uses `NSAPI:GetChar(name, true, "GlobalNickNames")` so NSRT nicknames work.

## Arranging: important decisions
- Uses NSRT's engine `NSI:ArrangeGroups(true)` by setting `NSI.Groups = {units, total=40}`.
  NSRT continues the sort on each GROUP_ROSTER_UPDATE (its EventHandler), with combat checks
  and a 25s timeout.
- We deliberately do NOT call `NSI:ArrangeFromReminder`: it runs `ShiftLeader`, which can move the
  raid leader into group 2 and pull someone into group 1, breaking explicit layouts.
- Players present in the raid are packed to the top of each group and the rest padded with
  `{processed=true}` placeholders. Reason: NSRT's ArrangeGroups has a bug (references undefined
  `indextosubgroup`) in the branch taken when a group has a gap of 2+ slots before the target slot.
  Packing avoids that path. Worth reporting upstream to Reloe.

## Related
- WoWUtils has its own Group Arrangement on its Setup page that exports an NSRT `invitelist:` line
  (positional, comma separated). Possible future feature: import that line into a roster.

## Releasing
- Repo is packaged with BigWigsMods/packager via `.github/workflows/release.yml` on tag push.
- `## Version: @project-version@` is replaced by the git tag. `.pkgmeta` excludes README/CLAUDE/media.
- Needs repo secret `CF_API_TOKEN` (CurseForge API token).
- CurseForge project ID 1722253 is in the .toc (`X-Curse-Project-ID`); GitHub repo egodfrey2021/NSRT_Extras.
- CurseForge Relations: set Northern Sky Raid Tools as a required dependency.
- Public name: "Roster for NSRT". Folder/SavedVariables stay NSRT_Extras / NSRTExtrasDB so existing data carries over.
- Not yet tested in-game beyond basic UI; syntax-checked only.
