# NSRT Raid Utility

Build saved raid rosters inside the **Northern Sky Raid Tools** window and sort your raid into them with one click.

Requires [Northern Sky Raid Tools](https://www.curseforge.com/wow/addons/northern-sky-raid-tools).

## Features

### Build a roster

Open the **Rosters** tab from `/ns`, `/nru`, or the minimap addon drawer. Each roster has eight groups of five slots.
You can keep separate rosters for different bosses or comps.

- Drag players between slots, back to **Not placed**, or between group headers to swap whole groups. The Not placed list shows current raid or party members who have no slot, with tanks and healers first. Double-click a name to place it in the first empty slot.
- Click an empty slot or double-click a name to type someone who isn't in the group. Tab and Shift-Tab move between slots. NSRT nicknames work; use `Name-Realm` if two players share a name.
- **Fill from raid** copies the current raid groups. Slots show roles, class colors, DPS (HPS for healers), and PI or side-pin markers. Hover a slot for details. Meter numbers come from the built-in damage meter's Overall session and refresh when the tab opens, the group changes, or a fight ends.
- Changes go into the **draft**, your unsaved roster. **Save** keeps them; **Undo** steps back up to 20 edits, including imports and splits into the open draft. **Revert** returns to the last save. Switching rosters, creating a new roster, Revert, and saving a split as a new roster ask before discarding unsaved changes because Undo cannot cross rosters.
- **Duplicate** copies the draft, including pins and whether it is a split, into a new roster. **Rename** changes the open roster's name.
- **Sort groups** uses the draft and NSRT's group sorter to move raiders. **Invite missing** invites players on the draft who aren't in the group; hover to see the invite list. Results appear under the groups and in **History**. Disabled buttons explain why on hover.

### Import and export

- Open **Import/Export** and choose **Import** or **Export**. Under Import, choose a source from **Import from**. Selecting one does not change the roster: paste a list to preview it, or choose **Damage meter** and click **Add to draft**. List imports replace the draft (Undo restores it); Damage meter adds players from the Overall session to empty slots without moving placed names. After importing, click **Review roster**, check the draft, then **Save** to keep it.
- NSRT/WoWUtils positional `invitelist:` text keeps empty slots; plain names also work. A WoWAudit export may contain several encounters: choose one after pasting. WoWAudit invite lists have names but no group positions, so imported names fill slots in order.
- Under Export, **Export draft as NSRT list** makes a positional list from the open draft. **Export live group for WoWAudit** makes a `raidlist:` snapshot of the real group with available specs and classes, not the draft or its group layout. Select the output and press Ctrl+C to copy it; the addon cannot copy to the clipboard for you.

WoWUtils exports NSRT lists. Whether its website accepts them for import is unverified; the NSRT-format export is for tools that accept that format.

### Split the raid and assign PI

**Split raid...** opens **Split setup**. **Generate split** divides raiders into two sides, spreading tanks and healers before balancing DPS and HPS from the built-in meter. It uses roles when the meter has no data. Out of a raid, it can split players on the draft using what the meter knows about them. Choose **Evens/Odds** (groups 1/3/5/7 vs 2/4/6/8) or **Grouped** (for example, 1-2 vs 3-4). By default the result goes into a new roster; uncheck **As new roster** to replace the draft, then Save when you're happy with it.

Split setup also has these options:

- **Even melee/ranged** spreads melee and ranged healers and DPS across both sides. Unknown specs count as ranged.
- **Lust and brez** aims for Bloodlust/Heroism on both sides and up to two battle res per side.
- **Raid buffs** spreads class buffs across sides when the raid has two providers. It covers Battle Shout, Fortitude, Skyfury, Arcane Intellect, Mark of the Wild, Blessing of the Bronze, Chaos Brand (+3% magic damage taken), and Mystic Touch (+5% physical damage taken). **For most damage** also places a lone Demon Hunter or Monk where their debuff helps most while keeping the sides within 3% DPS of each other.
- **Balance on** uses the Overall meter session, the last fight, or roles only.
- **Groups 1-4 only** leaves raiders sitting out in groups 5-8, and offline raiders, out of the split, side totals, and PI. It starts on in a Mythic raid; your choice sticks after you change it. Left-out raiders stay on the roster in groups 5-8 where there is room. The split reports any it cannot keep.

For buffs, lust, and brez, the tool swaps players of the same role and position after balancing and reports anything it could not spread. Shift-right-click a player to pin them to side A, again for B, and again to unpin. Pins stay with the roster on Save; a split stops if more than 20 players are pinned to one side. The balance strip shows each side's roles and DPS/HPS as you edit.

**Power Infusion** (or `/nru pi`) ranks DPS by expected PI gain and pairs priests with targets. It moves priests into their targets' groups on the draft when it can; Save to keep the moves. **PI priority** controls whether the ranking trusts spec sims, player DPS, or both. **Group priests with PI targets** runs the pairing during Generate split, with PI markers on the slots. Out of a raid, PI uses players on the draft with whatever the meter knows about them. The spec gains come from [Ulria's PI sims](https://docs.google.com/spreadsheets/d/1exJeu5eVe4bTmyg3WFx5PTxIWvDLi0j-WW-XWpGoG88), [bloodmallet](https://bloodmallet.com/chart/power_infusion), and [whoshouldgetpi](https://www.whoshouldgetpi.com/); see `src/split/PIData.lua` for the date.

**Post to raid** sends the split sides and PI pairs to raid chat when you click it. Hover to preview the lines. In a preview raid it prints them instead of sending them.

## Slash commands

- `/nru`: open the Rosters tab
- `/nru split`: open Rosters and generate a split immediately with the current split settings
- `/nru sort [roster]`: sort the raid using the active (or named) **saved** roster; the **Sort groups** button uses the unsaved draft
- `/nru invite`: invite players on the active **saved** roster who are not in the group
- `/nru pi`: rank PI targets and move priests into their targets' groups on the draft when possible; Save to keep the moves
- `/nru preview [2-40|off]`: try the tab solo with a made-up raid (default 20 players). **Sort groups** and **Invite missing** are dry runs. Run `/nru preview` again or use `off` to leave
- `/nru debug`: toggle debug output (what each roster entry resolved to during a sort)
- `/nsx` still works as an alias for `/nru`

## Notes

- Moving players requires raid leader or assistant, and players in combat can't be moved.
- Split balancing reads the damage meter out of combat; reset the meter before a session if you want fresh numbers. If the meter has no session data, the split balances roles only; a meter read error is reported instead. Power Infusion also stops on a meter read error instead of using an older reading.
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
| `mise run pi-data` | Regenerate `src/split/PIData.lua` (Power Infusion gain per spec) from the PI sims sheet, bloodmallet and whoshouldgetpi; needs `python3` and network. Rerun when the sims update, then commit the new file |
| `mise run test` | Behavior tests under LuaJIT (`tests/`; the harness stubs the WoW API) |
| `mise run lint` | luacheck, plus a check for non-ASCII characters |
| `mise run typecheck` | lua-language-server, as the editor sees it |

**In-game tests:** install [WoWUnit](https://www.curseforge.com/wow/addons/wowunit). With it enabled,
`tests/ingame.lua` runs at every login and `/reload` and reports in WoWUnit's window. These tests check the real
client and the real Northern Sky Raid Tools: the NSRT functions this addon calls, the damage meter API, Blizzard UI
globals, and a preview raid round trip. If one fails after an NSRT update, NSRT changed something we depend on.
Release builds leave the file out (the `.toc` lists it in a `#@do-not-package@` block), and without WoWUnit it does
nothing.

In game, `/nru preview [2-40|off]` gives you a made-up raid (default 20 players) so you can try the tab solo.
Sort groups and Invite missing only report what they would do. Anything that really moves or invites players needs a real
group where you are leader or assistant. `/nru debug` prints what each roster entry resolved to during a sort.

### 5. Contributing

Read [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) before changing code: it lists the rules every change is
checked against. CI runs `mise run check` on every push and pull request, and a release tag only publishes when it
passes.
