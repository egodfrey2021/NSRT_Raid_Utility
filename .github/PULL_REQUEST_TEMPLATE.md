<!-- Please read .github/CONTRIBUTING.md first. The checklist mirrors what review checks. -->

## What changes for the player?

## How was it tested?

<!-- mise run check output, plus what you did in game (raid size, leader/assist, NSRT version). -->

## Screenshots

<!-- Before and after for anything visible. Delete this section if nothing is. -->

## Checklist

<!-- Tick what applies; write N/A next to anything that genuinely doesn't. -->

- [ ] Idle until used: nothing built, registered or run while the NSRT window is closed
- [ ] No surprises: no player moves, invites or saved-roster changes without an explicit click or command
- [ ] Event-driven: no polling timers or `OnUpdate` beyond a drag in progress
- [ ] Secret values checked with `RaidUtility.Readable`; external calls that can fail are wrapped in `pcall`
- [ ] NSRT internals only touched in `src/NSRT.lua` (or tab injection in `src/Core.lua`)
- [ ] New strings use `L[...]`, whole sentences, positional placeholders for 2+ arguments
- [ ] Test added or updated; `mise run check` passes
- [ ] Tried in game with `/nru preview`, and in a real group if it moves or invites players
