# NSRT Raid Utility: project context

WoW Retail addon (Lua 5.1, interface 12.1.0) that adds a **Rosters** tab (with built-in raid splitting) to the
Northern Sky Raid Tools (NSRT) options window. Author: Evan. Rules for every change: `.github/CONTRIBUTING.md`.

## What it does
- 8 groups x 5 slots per roster; many named rosters saved in `NSRTRaidUtilityDB.rosters`.
- **Not placed** panel ("In raid, not placed (n)"; `ui.bench*` in code, `GetUnassigned`) = current raid/party members
  minus anyone placed in the roster being edited
  (nothing else; a shared "player pool" existed before v1.0.1 and was removed because names leaked
  between rosters). "Fill from current raid" copies the live subgroup layout into the draft.
- Drag and drop between slots (move/swap), panel to slot (place), slot to panel (un-place; refused for typed names
  not in the group, since they'd vanish). Double-click in the panel places in the first empty slot.
  Click empty slot / double-click name to type (for planning offline players), Tab/Shift-Tab to move between slots.
  Right-click clears a slot. Dropping onto a typed (offline) name moves that name to an empty slot instead of
  deleting it. Slots show role icons; typed names not in the group are grey and tagged "(not in group)".
  Import accepts an NSRT `invitelist:` line (positional) or plain names into the draft.
- Group edits go to a draft (`RaidUtility.draft`); **Save** commits, **Revert** discards, **Undo** steps back. Undo
  works through `MarkDirty`: every edit calls it after changing the draft, so it pushes the state kept from the
  previous call (`lastState`; groups, pins, split mark; 20 deep). `LoadDraft` and `ResetUndo` start fresh. Row 1:
  New, Duplicate (`DuplicateRoster`: the draft as seen, into a new roster), Rename (`RenameRoster`, moves pins and
  split mark), Delete, Save, Undo, Revert. Group header handles (`ui.headerHandles`) drag to swap whole groups. `ConfirmDiscard` (when there are unsaved edits) only guards what Undo can't
  reach: switching rosters, New, Revert, and a split saved as a new roster (they reset the undo history). Fill,
  Clear, imports and a split into the open roster apply at once. `dirty` = `not MatchesSaved()` (groups, pins, split
  mark vs the last save), recomputed in `MarkDirty` and `Undo`. Buttons are enabled only when usable (Save/Revert only when dirty, Arrange/Generate split
  only in a raid); states are set at the end of `RefreshUI`.
- Action row: "Edit" (Fill from raid, Split raid... = opens the Split setup panel, Import/Export, Clear all) and
  "Raid" (Invite missing, Sort groups, Power Infusion = /nru pi). `SetEnabled(button, on, reason)` stores why a
  button is off; `Explain` tooltips (`Widgets.Tooltip` takes a function) show it. Arrange also needs raid lead/assist
  (skipped in preview).
- **Split setup panel** (`BuildSplitSetup`, `ToggleSplitSetup`, SplitUI.lua): every split setting as NSRT checkboxes
  (they stay open; its dropdown closes per pick). Choice groups (`key` + `choice`) act as radios via `RefreshSetup`;
  toggles have `key = false` explicitly (stub frames answer unset fields with a function). The strip shows a summary
  (`SplitOptionsSummary`) and a "Change split setup" button. Outside a raid, `ui.noRaid` replaces the strip.
- **Slot markers** take no name width: pin = `pinBar` (left edge, `Widgets.SIDE_COLOR`, also used for header side
  letters), PI = `piIcon` (spell icon; dimmed on a priest who only gives it). Grey = not in group, said in the tooltip.
  `PITags` returns key -> { gets, gives }. Above the grid: a one-line legend and `ui.caption` (what the numbers are).
- **Post to raid** (`AssignmentLines`/`PostAssignments`, SplitUI.lua): split sides (if `draftSplit`) and PI pairs
  (if `db.splitPI`) via `C_ChatInfo.SendChatMessage` to RAID/PARTY, lines kept under 255 chars; only on click,
  preview prints instead. `ChatBlocked()` (`C_ChatInfo.InChatMessagingLockdown`, e.g. encounter restrictions)
  disables Post and refuses to send; the send is pcall'd. Group finder raids use INSTANCE_CHAT. Combat: `PLAYER_REGEN_DISABLED` -> `ApplyCombatLock(true)` greys the raid actions (the
  event fires before `InCombatLockdown()` is true); `RefreshUI` re-applies it. Invite missing's tooltip lists
  `MissingInvites`. `SetMeterReading` stores the reading and its clock time for the caption.
- **Combat**: names can be hidden, so `RefreshUI` reuses `ui.members` from before the fight (the caption says so;
  `PLAYER_REGEN_ENABLED` re-reads). Invite missing refuses in combat (hidden names would look missing); Post to raid
  uses the cached `ui.piPairs` then.
- **Results**: `Print` -> `OnMessage` keeps `ui.log` (40) and `ui.batch` (messages in the same frame = one action);
  the result line shows the newest + "(+N more in History)"; History is a scrollable popup. Both tab buttons use the draft; `/nru arrange` and `/nru invite` use the
  saved roster (tooltips say so).
- **Generate split** (`/nru split` opens Rosters and runs it): splits current raid members into two sides. Tanks,
  then healers, then damage are distributed per role, each player to the side with the lower role total (odd one out
  of a role goes to the smaller side; ties break by name). Values come from Blizzard's `C_DamageMeter` Overall
  session (`amountPerSecond`; DamageDone for tanks/dps, HealingDone for healers), matched to members by
  `sourceGUID` first, then name. Players without an assigned role use NSRT's spec cache, else count as damage
  (`MemberRole`). Names/values can be secret in combat, so the split refuses in combat and skips secret values.
  Layouts: "Evens/Odds" (key "oddeven", formerly "Alternating") or "Grouped" (key "consecutive"). `db.splitToNewRoster` (default true, the
  "As new roster" checkbox) picks a new roster (naming popup) or replacing the draft. There used to be a separate
  Split Raid tab; it was folded in because two tabs with their own state and Arrange buttons confused users,
  and its 20-per-side list couldn't adjust a 40-player split (the grid's drag-swap can).
- **Split options** (dropdown "Split:" on the balance strip; NSRT's dropdown closes per pick and has no checks, so
  items carry [x]/(*) and the box shows a summary). `SplitOptions()` -> `BalanceSides(players, opts)`:
  - `byPosition` (`db.splitMeleeRanged`): healers and damage split into MELEE/RANGED buckets, even counts per
    bucket, totals compared across the whole role. Position (`MemberPosition`): spec ID (`MemberSpec`: preview
    fixture, your own, NSRT's spec cache, the meter's spec icon) through NSRT's `NSI.meleetable`
    (`NSRT.IsMeleeSpec`, so we agree with NSRT's sorting), else the class (`CLASS_POSITION`), else ranged (guessed).
  - `lustRez` (`db.splitLustRez`), `buffs` (`db.splitBuffs` ~= "off"): not rules inside the greedy (they would override DPS
    balancing for every provider) but `FixShortfalls` after it: swap a provider with a non-provider of the same
    bucket, closest value first, never a pinned player, never creating a new shortfall. Targets (`Shortfalls`):
    1 Bloodlust per side; battle rez 2 per side with 4+ in the raid, else 1 (NSRT's own side sorting aims for up
    to 2); each `RAID_BUFFS` entry on both sides when the raid has 2+ of the class (the six NSRT buffs from its
    local ReadyCheck.lua list, plus Chaos Brand and Mystic Touch, debuffs on enemies). Lust/rez come from NSRT's
    `lusttable`/`resstable` by spec, else the class (`LUST_CLASS`/`REZ_CLASS`). Unfixed shortfalls become notes.
  - `debuffMax` (`db.splitBuffs` == "max", a v2 mode; v1 stored a boolean): `MaximizeDebuffs` after the shortfall
    pass, only with exactly one Demon Hunter or Monk (Chaos Brand/Mystic Touch don't stack, so with 2+ "even" is
    already best). Hill-climbs same-bucket swaps that raise 3% x magic DPS (Chaos Brand side) + 5% x physical DPS
    (Mystic Touch side); never a pinned player or a new shortfall; DPS and HPS gaps stay within
    `DEBUFF_TOLERANCE` (3%) or no worse than before. Values verified on wago.tools SpellEffect: 1490 aura 87, 3, mask
    126 (all magic); 113746 aura 87, 5, mask 1 (physical). Physical share per spec (`PHYSICAL_SHARE`) is an
    estimate from ability schools, not measured.
  - `db.splitMeterSource`: "overall", "lastfight" (the Current session, else the newest from
    `GetAvailableCombatSessions`; needs in-game confirmation of what Current holds after combat) or "roles"
    (split values zeroed; numbers still shown from Overall).
- **Planning out of a raid**: `EntrySource` turns a roster entry into a member, or a stand-in built from the meter's
  player of that name (class, specID, role, DPS/HPS). Generate split out of a raid splits the roster's players
  (`GetRosterSplitPlayers`; unknown names count as DPS with no data); the balance strip shows when in a raid or the
  roster has names; slots color meter-known names by class (grey in a group). PI uses `EntrySource` throughout (ranking, priests by
  the meter's class, pairing, slot tags), so `/nru pi` works out of a raid too; "Roles only" gives it
  `MeterIdentities` (who, without numbers). Only Post to raid needs a raid.
- **Who plays** (`Plays`, `MaxGroup`, Split.lua): members carry `online` (GetRaidRosterInfo / UnitIsConnected;
  false only when the game says so). Offline players never take part; with "Groups 1-4 only" (`db.splitGroups14`,
  nil = on in a Mythic raid via GetInstanceInfo difficulty 16) neither do groups 5-8. Generate split filters live
  members (`GetSplitPlayers` returns `leftOut`; `KeepLeftOut` keeps them in their own group or the first free one from
  8 down); the strip and PI use roster groups (`GroupSides(roster, layout, maxGroup)` gives 5-8 no side).
  Invite missing turns a nickname into its character (`NSRT.GetChar`) before inviting.
- **Pins** (shift-right-click a slot or unplaced player: side A, B, off): `RaidUtility.draftPins` (`PinKey`: the
  member's Name-Realm key when the entry resolves, else the lowercased entry -> 1|2; `MemberPins` re-resolves at
  split time) is part of the draft: copied in `LoadDraft`, saved to `db.pins[roster]` in `SaveDraft`, dropped by Revert,
  copied to a roster created from a split, removed with a deleted roster. `BalanceSides` places pinned players first.
- **Balance strip** (under the grid, raid only): `RosterBalance` totals each side of the *draft*. `GroupSides` maps
  groups to sides with n = ceil(highest used group / 2) per side, which matches what `SplitToRoster` builds. Roles
  and DPS/HPS always show. Group headers show "(n/5)" and the side letter.
- **Meter reading** (`ReadMeter`, a `MeterReading` in `RaidUtility.meter`): the Overall session, solo, party or raid.
  Taken by `RefreshUI(true)` (tab shown, roster change, and `PLAYER_REGEN_ENABLED`, which always refreshes a visible
  tab) and by Generate split; edits and drags call `RefreshUI()` and reuse it; in combat the last one is kept.
  Read errors there are silent (blank numbers); Generate split and the import report them. Slots show the value
  right-aligned (HPS for healers, `MeterValue`); typed names of players who left match `byName`.
- **Damage meter import** (Import tab, `ImportFromMeter`/`AddMeterPlayers` in Import.lua; always Overall): every
  player source in the session (Player- GUID or a group member; pets/creatures skipped) not already on the roster
  goes into empty slots by role, then value. Roles for non-members come from the source's `specIconID` (icon -> role
  map built once from `GetSpecializationInfoForClassID`), else healer if HPS > DPS. Adds only, so no confirmation.
- **Power Infusion** (`PI.lua`, data in generated `PIData.lua`): `PIPriority` ranks damage dealers on the roster
  (never tanks/healers/Augmentation) by effective gain% x meter DPS. Effective = w x spec gain (`PI_DATA.gain[spec]`,
  class average if the spec isn't seen, marked estimated) + (1 - w) x the average of all specs, w from
  `db.piPriority` (`PI_TRUST`: specs 1, balanced 0.5 default, players 0): sims assume perfect PI timing, which weaker
  groups don't reach, so there the better player wins. Ties fall back to the raw spec gain; players without meter data count at the lowest measured DPS (PI isn't gambled on someone
  unmeasured). `AssignPI`: each priest (class PRIEST, any spec) takes the best untaken target; on a split, from their own side
  first. "A split" = the draft came from Generate split (`draftSplit`, saved per roster in `db.splitRosters`; Fill,
  Clear and imports clear it, drags keep it); `PISides()` passes the layout only then. Generate split's own pairing
  always uses sides. `PairPI` moves the priest into the
  target's group (empty slot, else swap with someone who isn't a target or placed priest); targets never move.
  `/nru pi` prints the top 10 and the pairs and pairs the draft (unsaved edit). Split option `db.splitPI` pairs inside
  Generate split and shows `[PI]`/`[PI>]` tags (`PITags`, tooltip on the priest).
- **src/split/PIData.lua is generated**: `mise run pi-data` (`tools/update-pi-data.py`, needs python3 + network): mean of Ulria's
  sheet (tab "PI Sims - 5 mins patchwerk (on CDs)", 4-piece column, hero trees averaged) and bloodmallet's JSON
  (`chart/get/power_infusion/castingpatchwerk/...`, "X" vs "{X}" = with/without PI), plus a +-0.5 point nudge from
  whoshouldgetpi's per-boss log medians (embedded Next.js `allStats`; raw deltas are biased negative, so rank only).
- **Preview raid** (`/nru preview [size]`): a fixture raid for trying the tab solo; Arrange/Invite are dry runs.
- Slash commands: `/nru` (Rosters), `/nru split`, `/nru arrange [roster]`, `/nru invite`, `/nru preview [size|off]`,
  `/nru pi`, `/nru debug`; `/nsx` is an alias. The minimap addon drawer also opens Rosters.

## Files (load order = .toc order)
The `.toc` stays at the addon root; runtime Lua lives in `src/` and its `roster/` and `split/` folders.
- `src/Locales.lua`: `RaidUtility.L`; `L["English"]` returns the key until translations exist. All user-facing text
  uses it.
- `src/NSRT.lua`: the only place that touches `_G.NorthernSkyRaidTools` internals or `NSAPI`. Every call into NSRT
  goes through its local `Call` (pcall; failure printed in chat, error text to `/nru debug`; `once` for calls made on
  every redraw: nickname lookup, spec cache). StartSort/InviteList/Restricted report and fall back (no sort,
  one-by-one invites, refuse sorting). RosterUI gets NSRT's widget library (`C`) from Core, never NSRT itself. Looks NSRT up on every
  call because NSRT's UI addon is load-on-demand. When NSRT changes, this (plus Core's tab injection) is what breaks.
- `src/Widgets.lua`: shared `WHITE` texture, `ROLE_ICON`, `TopButton`, `Tooltip`.
- `src/roster/Roster.lua`: data model + `db.version` migrations, draft, member list/name resolution, invite, arrange.
- `src/roster/Preview.lua`: `/nru preview`, a fixture raid (you + up to 39 made-up players with the edge cases built in).
- `src/roster/Import.lua`: invite-list text -> roster, and the damage meter import.
- `src/roster/ImportExportUI.lua`: Import/Export panel, text previews, encounter selection, and copyable exports.
- `src/roster/RosterUI.lua`: tab UI, drag and drop, inline editor, popups.
- `src/split/Split.lua`: damage meter reading (`ReadMeter`), roles, side balancing, side -> roster layout, draft side totals.
- `src/split/SplitUI.lua`: Generate split, its naming popup, and the balance strip (built by `BuildRosterTab`).
- `src/split/PIData.lua` (generated, see above) and `src/split/PI.lua`: Power Infusion priority, assignment, pairing, `/nru pi`.
- `src/Core.lua`: injects the Rosters tab into NSRT's window, events, `/nru` slash command (`/nsx` kept as an alias),
  addon compartment click.

Not loaded by WoW: `types/globals.lua` (`---@meta` declarations for the type checker), `tests/` (LuaJIT suites),
except `tests/ingame.lua`: WoWUnit tests of the real client and NSRT, listed in the .toc inside `#@do-not-package@`
(dev builds only; the packager strips it, the offline harness skips it, and it returns early without WoWUnit).

## Conventions
CONTRIBUTING.md in short: idle until the NSRT window opens, no surprises (nothing moves/invites/saves without a
click), event-driven, no Lua errors/taint, Retail 12.x only, NSRT via `NSRT.lua`, whole-sentence `L[...]` strings.
- `RaidUtility.GetGroupMembers()` builds the member list with a `byShort` index and a resolve cache; build it once per
  refresh and pass it to `ResolveGroupMember`/`GetUnassigned`. Members with secret names are skipped
  (`RaidUtility.Readable`).
- Who is in the group comes only from `GetGroupMembers()` (members carry `class`, `role`, `subgroup`; solo it is
  just you, unit "player", so your own entry resolves and Invite skips you; your role comes from your spec) and
  `RaidUtility.InRaid()/InGroup()`. Don't call `IsInRaid`/`UnitClass`/`GetRaidRosterInfo` elsewhere, or the preview
  raid stops covering that code. In preview, Arrange/Invite must stay dry runs (`Preview.Apply` moves fake members).
- Roster entries for members use `EntryName`: Name-Realm when two members share a short name.
- `GROUP_ROSTER_UPDATE` and NSRT nickname changes refresh the Rosters tab after a 0.5s quiet period
  (`REFRESH_DELAY` in Core.lua), and not at all in combat (deferred to `PLAYER_REGEN_ENABLED`).
- Reshaping existing saved data needs a step in `Migrate` (Roster.lua) and a bump of `DB_VERSION`. A new optional
  field just gets a default in `InitDB` (like `splitLayout`, `splitToNewRoster`): a fresh DB starts at the current
  version, so Migrate steps never run for new users anyway.

## How it hooks into NSRT (no official plugin API exists)
- NSRT exposes `_G.NorthernSkyRaidTools` (internal namespace, unstable) and `NSAPI` (public).
- Options UI is a separate load-on-demand addon `NorthernSkyRaidTools_UI`, built in a coroutine.
  We hook `NSI.NSUI` OnShow and inject only once `NSUI.Initialized` is true.
- Tab injection: add our frame/button to `NSUI.MenuFrame.AllFrames/AllButtons/AllFramesByName/
  AllButtonsByName`; NSRT's own SelectTab then shows/hides/highlights it. Button is anchored under
  the "Versions" sidebar button. Uses `NSI.UI.Components` (CreateButton, CreateDropdown, CreateCheckButton) for styling.
- Name resolution uses `NSAPI:GetChar(name, true, "GlobalNickNames")` so NSRT nicknames work.

## Arranging: important decisions
- Uses NSRT's engine `NSI:ArrangeGroups(true)` by setting `NSI.Groups = {units, total=40}` (and
  `NSI.LastGroupSort`, so NSRT's own 5s spam guard covers our sorts). NSRT continues the sort on each
  GROUP_ROSTER_UPDATE (its EventHandler), with combat checks (it prints who is in combat) and a 25s timeout.
  On each GROUP_ROSTER_UPDATE (one frame later, after NSRT's handler) we read `NSRT.SortState()` and print
  "Groups arranged" or "stopped"; a 30s timeout bounds the wait. No polling.
- NSRT finds players with `UnitInRaid(name)`, so units carry `Ambiguate(fullName, "none")`: short name on your
  realm, Name-Realm otherwise (same as NSRT's own InviteList).
- We deliberately do NOT call `NSI:ArrangeFromReminder`: it runs `ShiftLeader`, which can move the
  raid leader into group 2 and pull someone into group 1, breaking explicit layouts.
- Players present in the raid are packed to the top of each group and the rest padded with
  `{processed=true}` placeholders. Reason: NSRT's ArrangeGroups has a bug (references undefined
  `indextosubgroup`) in the branch taken when a group has a gap of 2+ slots before the target slot.
  Packing avoids that path most of the time. Still present in NSRT 12.1.24 (SetupManager.lua:389); not yet
  reported upstream.
- Second layer: `NSRT.lua` defines the missing global `indextosubgroup` (raid index -> live subgroup via
  GetRaidRosterInfo) if it's nil, so the broken branch works instead of erroring. This also fixes NSRT's own sorts.
  Simulating NSRT's real ArrangeGroups over random layouts: packing alone still hit the bug in ~0.3% of layouts under
  one raid-index model; with the shim, 0 of 24,000. Keep both until NSRT fixes the line.

## Related
- WoWUtils has its own Group Arrangement on its Setup page that exports an NSRT `invitelist:` line
  (positional, comma separated); the NSRT/WoWUtils list option reads it via `NSRT.ParseInviteList`.

## Development
- Setup and the full workflow are in README.md "Development". Tools are pinned in `mise.toml`.
- `mise run check` = StyLua format check + luacheck + ASCII check + LuaLS typecheck + tests; CI
  (`.github/workflows/ci.yml`) runs the same and gates the release job. Run `mise run fmt` then `mise run check`
  before calling work done. StyLua won't wrap concatenations inside `L[...]`: build long keys in a local.
- Tests: `tests/harness.lua` stubs the WoW API and loads files in .toc order; one suite per area (`tests/roster.lua`,
  `split.lua`, `core.lua`, `rosterui.lua`, `preview.lua`, `pi.lua`). `H.SetMeter` is the one place tests swap the
  damage meter stub (LuaLS flags a second assignment site as a duplicate definition). C_Timer is manual (`H.RunTimers(maxDelay)`); the harness
  emulates WoW's positional `%1$s` format, which LuaJIT lacks; `print` is captured (use `io.write` when debugging).
- Type checking: `.luarc.json` + `types/globals.lua` (NSRT's API, our saved variables and globals, the FrameXML
  globals we use). WoW API types are Ketho's annotations, fetched by `mise run luals-setup` into `.luals/`
  (gitignored), pinned by `WOW_API_VERSION` to match the VS Code extension. LuaLS reads the whole workspace, so test
  stubs must match the declared signatures; declare any new NSRT call or UI global in `types/globals.lua`.
- In game: the addon folder must be `Interface/AddOns/NSRT_Raid_Utility` (README "Load it in the game"). `/reload`
  picks up .lua changes; .toc changes need a full client restart. Try changes with `/nru preview` first. Not yet
  verified in game beyond basic UI.
- NSRT's source, for checking the internals we hook, is in its installed addon folders `NorthernSkyRaidTools/` and
  `NorthernSkyRaidTools_UI/`.

## Releasing
- Repo is packaged with BigWigsMods/packager via `.github/workflows/release.yml` on tag push; the release job only
  runs after the reusable CI check passes. Actions are pinned to commit SHAs (version in a trailing comment).
- `## Version: @project-version@` is replaced by the git tag.
- Needs repo secret `CF_API_TOKEN` (CurseForge API token).
- CurseForge project ID 1722253 is in the .toc (`X-Curse-Project-ID`); GitHub repo egodfrey2021/NSRT_Raid_Utility.
- CurseForge Relations: set Northern Sky Raid Tools as a required dependency.
- Public name "NSRT Raid Utility"; folder NSRT_Raid_Utility, SavedVariables NSRTRaidUtilityDB. Up to v1.1.0 it was
  "Roster for NSRT" in folder NSRT_Extras (NSRTExtrasDB); the rename does not carry old saved data over.
- `.pkgmeta` excludes tests/, types/, tools/, mise.toml, stylua.toml (dotfiles are skipped automatically); media/
  ships (toc IconTexture). The packager only copies files git tracks. `mise run package` (`tools/check-package.sh`,
  also run in CI) builds the release folder without uploading and fails if dev files ship, the in-game test block
  survives, or a .toc file is missing. New top-level dev files need a `.pkgmeta` entry and a line in that script.
- Dependabot (`.github/dependabot.yml`) opens weekly PRs for the SHA-pinned workflow actions.
