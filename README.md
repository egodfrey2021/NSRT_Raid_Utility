# NSRT Raid Utility

Build saved raid rosters inside the **Northern Sky Raid Tools** window and sort your raid into them with one click.

Requires [Northern Sky Raid Tools](https://www.curseforge.com/wow/addons/northern-sky-raid-tools).

## Features

- Adds a **Rosters** tab to the NSRT options window (`/ns`, `/nru`, or the minimap addon drawer)
- Lay out all 8 groups by drag and drop: move, swap, or drag back to the unplaced list. Drag a group's header onto another group to swap the two groups
- The **not placed** list shows everyone in your raid or party who isn't in the roster yet (tanks, then healers, then damage), with scrolling for full raids; double-click a name to drop it in the first empty slot
- Slots show role icons and class colors; names you typed for players who aren't in your group are greyed out. Markers take no room from the name: a colored left edge for a pinned side, the Power Infusion icon for PI. Hover a slot for the details; a one-line legend sits above the groups
- **Fill from raid** copies your raid's current groups into the roster
- Click an empty slot or double-click a name to type, so you can plan for people who aren't online; Tab / Shift-Tab moves to the next / previous slot
- **Import/Export** opens the list tools: import NSRT/WoWUtils positional `invitelist:` text into the draft, export the draft in the same NSRT format with all empty slots preserved, or paste a WoWAudit multi-encounter invite export and choose which encounter's names to put into the draft. WoWAudit invites contain no group positions: names fill slots in list order. **Export WoWAudit** copies a `raidlist:` snapshot of the *live* group (names, available spec IDs and class IDs) for a WoWAudit raid plan, not the draft or its group layout. Exporting never saves or rearranges anyone. **Import NSRT list** also accepts plain comma/space-separated names and offers **From damage meter**: add players seen in the Overall session who aren't on the draft yet, into empty slots by role and value. WoWUtils can export NSRT invite lists, but whether its website accepts them as input is unverified; the reverse-direction export is for tools that accept NSRT-format lists
- Names imported from the damage meter keep the class and role the meter saw (class colors and role icons; the tooltip names the spec), so a roster planned solo reads like a raid
- Each slot shows the player's DPS (HPS for healers) right-aligned, like a damage meter, read from the built-in meter's Overall session when the tab opens, when the group changes and after each fight. Works solo, in a party or in a raid
- Keep as many rosters as you like (one per boss, progression vs. farm, etc.). **Duplicate** copies the open roster, unsaved changes included, to a new one (build a base comp, then one copy per boss); **Rename** renames it. Pins and the split mark come along
- Edits stay pending until you press **Save**. **Undo** steps back one change at a time (up to 20: drags, clears, imports, and a split into the open roster), and **Revert** goes back to the last save. Fill from raid, Clear all, imports and a split into the open roster happen right away (Undo brings back what they replaced); switching rosters, New, Revert and a split saved as a new roster ask before dropping unsaved changes, since Undo can't reach across rosters. **Unsaved changes** only shows while the roster differs from its last save
- **Sort groups** moves everyone into place using NSRT's own group sorter, unsaved changes included, and tells you when it's done
- **Invite missing** invites players on the roster who aren't in the group; hover it to see who that would be
- Results also show in the tab, not only in chat: the newest one under the groups, and **History** for everything recent (a split's full notes, PI pairings)
- Disabled buttons say why when you hover them (not in a raid, nothing to save, not raid lead or assist, in combat, ...). In combat, Sort groups, Split raid..., Power Infusion and Fill from raid are greyed out until it ends
- **Post to raid** (next to History) sends the split's sides and the Power Infusion pairs to raid chat, only when you click it; hover it to see the lines first. In the preview raid it only prints them
- Works with NSRT nicknames and realm-qualified character names; use `Name-Realm` when two players share a name
- **Split raid...** opens the **Split setup** panel with every split setting in one place (sides layout, what to balance on, the optional rules below, PI priority, and **As new roster**) and its **Generate split** button. Generate split divides the raid into two balanced sides (out of a raid, it splits the players on the roster instead, using what the damage meter knows about them, so you can plan from a meter import while solo), as **Evens/Odds** groups (1/3/5/7 vs 2/4/6/8) or **Grouped** (e.g. 1-2 vs 3-4). Tanks and healers are spread evenly (players without an assigned role use the spec NSRT has seen, otherwise count as damage), then players are balanced using the built-in damage meter's Overall session (DPS, and HPS for healers). With **As new roster** checked (the default) the split becomes a new roster; unchecked, it replaces the draft you're editing. Adjust it by dragging, like any roster. Optional rules, all off by default:
  - **Even melee/ranged**: spreads melee and ranged players evenly among healers and among damage dealers, still balancing DPS/HPS (specs come from NSRT, the damage meter, or the class; a spec that hasn't been seen counts as ranged)
  - **Lust and brez**: a Bloodlust/Heroism on each side and up to 2 battle res per side
  - **Raid buffs**: *on both sides* spreads Battle Shout, Fortitude, Skyfury, Arcane Intellect, Mark of the Wild, Blessing of the Bronze, Chaos Brand (+3% magic damage taken) and Mystic Touch (+5% physical damage taken) whenever the raid has two of that class. *For most damage* also places a lone Demon Hunter or Monk on the side where its debuff adds the most, moving magic dealers toward Chaos Brand and physical ones toward Mystic Touch while the sides stay within 3% DPS of each other
  - **Balance on**: the Overall session, the last fight, or roles only

  - **Groups 1-4 only**: leaves players sitting out in groups 5-8 out of the split, the side totals and Power Infusion, and keeps them in those groups. On by default in a Mythic raid (20 players fight there); once you tick or untick it, your choice sticks. Offline players are always left out the same way

  Lust, rez and buffs are fixed after balancing by swapping players of the same role (and position), so the DPS balance barely moves; anything that can't be fixed (say, only one Bloodlust in the raid) is reported.
- **Power Infusion** (the button, or `/nru pi`) ranks the DPS on the roster by expected PI gain (the spec's simulated gain x that player's DPS on the damage meter; **PI priority** in Split setup sets how far the sims count: *best specs* for well-practiced teams, *balanced* by default, or *best players* by DPS alone), says which priest should PI whom (each priest takes the best target on their side). Out of a raid it works on the roster's players with what the damage meter knows about them (a priest is recognised by class, targets by spec and DPS), and moves each priest into their target's group. The **Group priests with PI targets** split option does the same as part of Generate split, and marks targets with the Power Infusion icon (dimmed on the priest giving it; hover for who). Spec gains come from [Ulria's PI sims](https://docs.google.com/spreadsheets/d/1exJeu5eVe4bTmyg3WFx5PTxIWvDLi0j-WW-XWpGoG88), [bloodmallet](https://bloodmallet.com/chart/power_infusion) and [whoshouldgetpi](https://www.whoshouldgetpi.com/); see `PIData.lua` for the date
- **Shift-right-click** a player to pin them to side A, again for side B, again to unpin. Generate split places pinned players first. Pins belong to the roster and are kept on Save, like any other edit
- In a raid, the **balance strip** under the groups compares the two sides as you edit: players, roles, DPS/HPS and the difference between the sides, plus a summary of the split settings and a **Change split setup** button. A caption above the groups says what the slot numbers are (DPS, HPS for healers, from which meter session, and the time they were read)

## Slash commands

- `/nru`: open the Rosters tab
- `/nru split`: open the Rosters tab and generate a split
- `/nru arrange [roster]`: sort the raid using the active (or named) **saved** roster; the tab's Sort groups button uses your unsaved changes
- `/nru invite`: invite players on the active **saved** roster who are not in the group
- `/nru pi`: Power Infusion priority list, who gives PI to whom, and each priest moved into their target's group on the draft
- `/nru preview [size]`: toggle a made-up raid (default 20, up to 40 players) to try the tab without a group.
  Arrange and Invite only report what they would do; nothing is sent to the game
- `/nru debug`: toggle debug output (what each roster entry resolved to when arranging)
- `/nsx` still works as an alias for `/nru`

## Notes

- Moving players requires raid leader or assistant, and players in combat can't be moved.
- Split balancing reads the damage meter out of combat; reset the meter before a session if you want fresh numbers. If the meter has no session data, the split balances roles only; a meter read error is reported instead.
- This is an unofficial companion addon and isn't affiliated with Northern Sky or the NSRT authors.

## License

MIT, see [LICENSE](LICENSE).

## Development

### 1. Tools

You need [mise](https://mise.jdx.dev), git, curl and tar. mise installs everything else at the pinned versions:
LuaJIT (Lua 5.1, like the game), luacheck, lua-language-server, and StyLua.

```sh
git clone https://github.com/egodfrey2021/NSRT_Raid_Utility.git
cd NSRT_Raid_Utility
mise trust            # first time only: allow this repo's mise.toml
mise install
mise run luals-setup  # downloads the WoW API annotations into .luals/ (gitignored)
mise run check        # lint, type-check and tests; should end with "0 failed" and "no problems found"
```

### 2. Editor (VS Code)

1. Install the **Lua** extension (sumneko.lua), the **WoW API** extension (ketho.wow-api), and **StyLua**
   (JohnnyMorganz.stylua). StyLua reads `stylua.toml`; turn on format on save for Lua files if you like.
2. Open the repository folder. The committed `.luarc.json` points the Lua extension at `.luals/`, so the editor
   uses the same WoW API annotations and settings as `mise run typecheck` and CI.
3. Run **Developer: Reload Window** after `mise run luals-setup` or any change to `.luarc.json`.

`.luarc.json` takes priority over `Lua.*` entries in `.vscode/settings.json`. The latter is ignored by git, so
machine-specific editor settings can stay local. Run `mise run luals-setup` to provide the annotations referenced
by the shared `.luarc.json`. If you upgrade the WoW API extension, set `WOW_API_VERSION` in `mise.toml` to its
version and run `mise run luals-setup` again.

### 3. Load it in the game

The game loads addons from `World of Warcraft/_retail_/Interface/AddOns/`. Either clone the repository there, or
keep it wherever you like and link it in as `AddOns/NSRT_Raid_Utility`:

- **Windows** (Command Prompt as administrator, or with Developer Mode enabled):
  `mklink /D "<WoW folder>\_retail_\Interface\AddOns\NSRT_Raid_Utility" "<path to the repository>"`
- **macOS / Linux:** `ln -s "<path to the repository>" "<WoW folder>/_retail_/Interface/AddOns/NSRT_Raid_Utility"`

Northern Sky Raid Tools must be installed and enabled. BugSack and BugGrabber make Lua errors easy to copy.

`/reload` picks up changes to `.lua` files. Changes to the `.toc` (such as adding a file) need a full game
restart. The version in the AddOn list shows `@project-version@` for a development copy; releases replace it.

### 4. Test

| Command | What it does |
| --- | --- |
| `mise run check` | Everything CI runs: `fmt-check`, `lint`, `typecheck`, `test` |
| `mise run fmt` | Format every Lua file with StyLua |
| `mise run package` | Build the release folder with the BigWigs packager (no upload) and check what ships |
| `mise run pi-data` | Regenerate `PIData.lua` (Power Infusion gain per spec) from the PI sims sheet, bloodmallet and whoshouldgetpi; needs `python3` and network. Rerun when the sims update, then commit the new file |
| `mise run test` | Behavior tests under LuaJIT (`tests/`; the harness stubs the WoW API) |
| `mise run lint` | luacheck, plus a check for non-ASCII characters |
| `mise run typecheck` | lua-language-server, as the editor sees it |

**In-game tests:** install [WoWUnit](https://www.curseforge.com/wow/addons/wowunit). With it enabled,
`tests/ingame.lua` runs at every login and `/reload` and reports in WoWUnit's window. These tests check the real
client and the real Northern Sky Raid Tools: the NSRT functions this addon calls, the damage meter API, Blizzard UI
globals, and a preview raid round trip. If one fails after an NSRT update, NSRT changed something we depend on.
Release builds leave the file out (the `.toc` lists it in a `#@do-not-package@` block), and without WoWUnit it does
nothing.

In game, `/nru preview [size]` gives you a made-up raid (default 20 players) so you can try the tab solo.
Arrange and Invite only report what they would do. Anything that really moves or invites players needs a real
group where you are leader or assistant. `/nru debug` prints what each roster entry resolved to when arranging.

### 5. Contributing

Read [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) before changing code: it lists the rules every change is
checked against. CI runs `mise run check` on every push and pull request, and a release tag only publishes when it
passes.
