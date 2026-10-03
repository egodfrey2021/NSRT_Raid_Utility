# NSRT Raid Utility

Build saved raid rosters inside the **Northern Sky Raid Tools** window and sort your raid into them with one click.

Requires [Northern Sky Raid Tools](https://www.curseforge.com/wow/addons/northern-sky-raid-tools).

## Features

- Adds a **Rosters** tab to the NSRT options window (`/ns`, `/nru`, or the minimap addon drawer)
- Lay out all 8 groups by drag and drop: move, swap, or drag back to the unplaced list
- The **not placed** list shows everyone in your raid or party who isn't in the roster yet, with scrolling for full raids; double-click a name to drop it in the first empty slot
- Slots show role icons and class colors; names you typed for players who aren't in your group are greyed out and tagged
- **Fill from raid** copies your raid's current groups into the roster
- Click an empty slot or double-click a name to type, so you can plan for people who aren't online; Tab / Shift-Tab moves to the next / previous slot
- **Import list** pastes an NSRT `invitelist:` line (or plain comma / space separated names) into the roster, slot by slot. Its **From damage meter** button instead adds everyone in the meter's Overall session who isn't on the roster yet (always the Overall session, including players who have left the group) to the empty slots: tanks, then healers, then damage, strongest first
- Each slot shows the player's DPS (HPS for healers) right-aligned, like a damage meter, read from the built-in meter's Overall session when the tab opens, when the group changes and after each fight. Works solo, in a party or in a raid
- Keep as many rosters as you like (one per boss, progression vs. farm, etc.)
- Edits stay pending until you press **Save**, and **Revert** undoes them. Anything that would throw away unsaved edits asks first
- **Arrange draft** moves everyone into place using NSRT's own group sorter, and tells you when it's done
- **Invite missing** invites players on the roster who aren't in the group
- Results also show in the tab, not only in chat
- Works with NSRT nicknames and realm-qualified character names; use `Name-Realm` when two players share a name
- **Generate split** divides the raid into two balanced sides, as **Evens/Odds** groups (1/3/5/7 vs 2/4/6/8) or **Grouped** (e.g. 1-2 vs 3-4). Tanks and healers are spread evenly (players without an assigned role use the spec NSRT has seen, otherwise count as damage), then players are balanced using the built-in damage meter's Overall session (DPS, and HPS for healers). With **As new roster** checked (the default) the split becomes a new roster; unchecked, it replaces the draft you're editing. Adjust it by dragging, like any roster. The **Split** options dropdown under the groups adds optional rules, all off by default:
  - **Even melee/ranged**: spreads melee and ranged players evenly among healers and among damage dealers, still balancing DPS/HPS (specs come from NSRT, the damage meter, or the class; a spec that hasn't been seen counts as ranged)
  - **Bloodlust and battle rez on both sides**: a Bloodlust/Heroism per side and up to 2 battle rezzes per side
  - **Raid buffs**: *on both sides* spreads Battle Shout, Fortitude, Skyfury, Arcane Intellect, Mark of the Wild, Blessing of the Bronze, Chaos Brand (+3% magic damage taken) and Mystic Touch (+5% physical damage taken) whenever the raid has two of that class. *For most damage* also places a lone Demon Hunter or Monk on the side where its debuff adds the most, moving magic dealers toward Chaos Brand and physical ones toward Mystic Touch while the sides stay within 3% DPS of each other
  - **Balance on**: the Overall session, the last fight, or roles only

  Lust, rez and buffs are fixed after balancing by swapping players of the same role (and position), so the DPS balance barely moves; anything that can't be fixed (say, only one Bloodlust in the raid) is reported.
- **Shift-right-click** a player to pin them to side A, again for side B, again to unpin. Generate split places pinned players first. Pins belong to the roster and are kept on Save, like any other edit
- In a raid, the **balance strip** under the groups compares the two sides as you edit: players, roles, DPS/HPS and the difference between the sides

## Slash commands

- `/nru`: open the Rosters tab
- `/nru split`: open the Rosters tab and generate a split
- `/nru arrange [roster]`: sort the raid using the active (or named) **saved** roster; the tab's Arrange draft uses your unsaved edits
- `/nru invite`: invite players on the active **saved** roster who are not in the group
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
