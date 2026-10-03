# Contributing to NSRT Raid Utility

NSRT Raid Utility is a small companion addon that lives inside the Northern Sky Raid Tools (NSRT) window. Pull
requests are welcome. The rules below are what every change is reviewed against, so following them up front saves a
round of review. For anything bigger than a fix, open an issue first and describe the approach.

## Acceptance criteria

1. **Idle until used.** With the NSRT window closed, the addon does nothing beyond cheap event checks: no frames
   built, no timers started, no work in handlers. Tabs are built the first time the window opens. Event handlers
   return early when the tab they would refresh isn't visible.

2. **No surprises.** Nothing moves players, sends invites, or changes a saved roster without an explicit click or
   slash command. Roster edits go to the draft and are kept only on **Save**. Split results become a *new* roster
   unless the user unchecks **As new roster**; even then they only replace the draft, never a saved roster. A change that alters behavior for existing users needs a reason in the PR.

3. **Cheap when used.** Event-driven, not polled. No `OnUpdate` except on frames that only exist for the duration
   of a gesture (the drag ghost). Timers may debounce, defer to the next frame, or put an upper bound on a wait;
   they may not stand in for an event ("check every 0.5s whether X happened"). Build the member list once per
   refresh and pass it down (`RaidUtility.GetGroupMembers()` caches name lookups per list).

4. **No Lua errors, no taint.**
   - Never write fields onto, or `SetScript` on, frames we don't own. Use `HookScript` (as we do on NSRT's window).
   - Names and numbers can be secret in combat: check with `RaidUtility.Readable` before comparing or using them.
   - Wrap calls that can fail for reasons outside our control (`C_DamageMeter`, NSRT internals) in `pcall` and
     report the failure in chat instead of erroring.
   - Moving players is protected in combat. Refuse up front; NSRT's sorter also stops and names who is in combat.

5. **Retail 12.x only.** One client, one code path. No branches for older or Classic clients, and no fallbacks for
   Blizzard APIs that always exist on 12.x. Feature checks are only for things that can genuinely be absent at
   runtime: NSRT internals and NSRT's load-on-demand UI addon.

6. **NSRT goes through `NSRT.lua`.** NSRT has no plugin API and its internals change between releases. Every use of
   `_G.NorthernSkyRaidTools` or `NSAPI` lives in `NSRT.lua` (tab injection in `Core.lua` is the one exception). Prefer
   the public `NSAPI` and NSRT's own functions over reimplementing what NSRT already does.

## Code style

- **Lua 5.1.** No `goto`, labels, or integer division; luacheck enforces it.
- **ASCII only** in code, comments, the .toc, and English strings. Curly quotes and dashes break in packaging and
  in some chat fonts. Translation files, when they exist, are the exception (UTF-8 without BOM).
- **Formatting is StyLua's job.** Run `mise run fmt` before committing (`stylua.toml`: 4-space indents, 120
  columns, double quotes); CI fails on unformatted files. Wrap hand-aligned tables in `-- stylua: ignore start` /
  `-- stylua: ignore end`. StyLua won't wrap a concatenation inside `L[...]`, so build long keys in a local first.
- **Match the surrounding code.** Find the nearest similar code in the same file and follow its shape: short local
  helpers, the same naming, the same patterns.
- **Look like NSRT.** Buttons and dropdowns come from NSRT's components (`Widgets.TopButton`, `C.CreateDropdown`).
  Panels use the flat `Widgets.WHITE` backdrop with NSRT's cyan accent. Confirmations use `StaticPopup` with an
  `NSRTRAIDUTILITY_` prefix, as NSRT does.
- **Comments say why, briefly.** No restating the line below, no change history.
- **Reuse before writing.** `ForEachEntry`, `ResolveGroupMember`, `Readable`, `Print`, `Debug` and the `NSRT.*`
  adapter exist so they aren't rewritten per feature.

## Text and translations

- Every user-facing string goes through `L["English text"]`. English is the key; there are no symbolic IDs.
- Keep sentences whole. Never build a sentence from translated fragments, because word order differs by language.
- One argument: `%s` / `%d`. Two or more: positional `%1$s`, `%2$d`, so translators can reorder them.
- Color codes go outside the key: `"|cFFFF9900" .. L["Unsaved changes"] .. "|r"`.

## Tests and checks

- Run `mise run check` (luacheck, ASCII check, lua-language-server type check, and the LuaJIT test suites). CI runs
  the same check and blocks releases when it fails. The type check uses the same WoW API annotations as the VS Code
  extension; `mise run luals-setup` fetches them so the editor and CI agree.
- Using something from NSRT, or a Blizzard UI global the annotations don't cover? Declare it in `types/globals.lua`.
- Add or update a test in the suite for the area you changed: `tests/roster.lua`, `split.lua`, `core.lua`,
  `rosterui.lua`, `preview.lua`, `pi.lua`. The harness in `tests/harness.lua` stubs the WoW API; timers only fire on `H.RunTimers()`.
- `tests/ingame.lua` holds WoWUnit tests that run in the real client at login and `/reload` (install WoWUnit to see
  them). Add one when a change relies on something the offline harness stubs: a Blizzard API or global, a frame
  template, or an NSRT function. Keep them read-only: no saved-data changes, nothing sent to the game, and leave a
  preview raid you opened yourself alone.
- The harness can't prove anything about real frames or real NSRT. In game, try the change solo with
  `/nru preview` first (the tab runs on a made-up raid; Arrange and Invite are dry runs), then in a real group
  for anything that moves players. Say in the PR what you tested.
- Code that asks who is in the group goes through `RaidUtility.GetGroupMembers()` / `InRaid()` / `InGroup()`, so
  the preview raid and the tests cover it.

## Pull requests

- One focused change per PR, with the smallest diff that does it.
- Before and after screenshots for anything visible.
- Fill in every checklist item in the PR template. "N/A" is a fine answer; leaving it blank isn't.

## Research and AI tools

- **Learn the game from Blizzard's UI source** ([wow-ui-source](https://github.com/Gethe/wow-ui-source)), game data
  on [wago.tools](https://wago.tools), and the API docs on [warcraft.wiki.gg](https://warcraft.wiki.gg).
- **Check NSRT before building around it.** Read the NSRT code we hook (tab system, group sorter, invite lists) when
  it updates, and prefer calling NSRT's function over keeping our own copy, so behavior can't drift.
- **Review what your assistant writes** against these rules before committing it.

## License

The project is MIT licensed. By opening a pull request you agree that your contribution is released under the same
license.
