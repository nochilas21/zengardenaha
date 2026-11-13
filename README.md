# Desktop Zen Garden — Template, Phases 0–9

A working Godot 4.3 project covering `zen-garden-detailed-guide.md` through
Phase 9: project setup, the three resource types, the `Plot` scene with the
`NeedPopup` refactor (Phase 4), multiple empty-by-default plots in a
`GridWindow` (Phase 5), two real species with shared sprout art and a
permanent-unhealthy penalty (Phase 6), sunlight/insects/music need handling
(Phase 7), a working shop with unlock/place/plant gating (Phase 8), and
save/load (Phase 9).

## How to open it
1. Godot 4.3+, Compatibility (GL Compatibility) renderer.
2. Project Manager → Import → select this folder's `project.godot`.
3. Press F5 (or F6 to run `test_main.tscn` directly).

## What's on screen
Three empty plots in a row, each with its own "Place Pot" button. A shop
panel to the right lists Dirt Pot / Water Pot and Sunflower / Lotus, each
showing "Unlock" until you spend currency, then "Place"/"Plant". Debug
controls across the bottom: give yourself 1000 gold, select which plot the
shop acts on (Select Plot 1/2/3), apply a mini-sun charge to Plot 1 (Phase
7's sunlight mechanic), and Save/Load buttons that round-trip the full game
state through `user://savegame.json`.

### A full test loop
1. Give Gold.
2. Select Plot 1 → Unlock Dirt Pot → Place (on Plot 1).
3. Unlock Sunflower → Plant (on Plot 1).
4. Watch growth tick; water/fertilizer popups appear side-by-side and bounce
   independently when due (Phase 4's fix, still holding under real species
   data).
5. Save, then quit and relaunch — Plot 1's exact growth/need state should
   restore instead of rerolling.

### Testing Phase 7's insects/music/sunlight by hand
The default catalog only wires up Sunflower (water+fertilizer) and Lotus
(water). To see all five needs at once, swap `test_main.gd`'s
`all_plants` array to also `load("res://resources/plants/test_full_needs_debug.tres")`,
unlock and plant it like any other species, and:
- **Sunlight** resolves automatically the moment it's due, *if* you've
  already clicked "Apply Mini Sun" on that grid (it has 3 charges before
  running out — click it again once they're spent).
- **Insects** opens a small dimmed overlay with a clickable icon you must
  find and click — closing it satisfies the need.
- **Music** opens a wind-up meter (FNAF2-style): the meter drains on its own,
  clicking "Wind Up" adds a chunk back (not a full refill), and letting it
  hit zero resets your progress. Keep it above zero for a short continuous
  stretch (8 sec by default) to satisfy the need. It auto-launches from the
  popup click and auto-connects to the plant, same as insects — no manual
  wiring needed.

## Honest caveats (same as before, still true)
Every file here — scripts, resources, and `.tscn` scenes — was written as
plain text without ever opening this in an actual Godot editor myself; I
have no GUI and can't render or click through it. The GDScript logic is the
same pattern you already ran and debugged with me through Phase 4, extended
the same way for Phases 5–9, so I trust the logic. I can't vouch for
pixel-level layout (container sizes, anchor offsets) by eye — if something
looks slightly off on screen, select that node and reapply the Layout
preset the guide names for it; that recalculates offsets from the node's
real size and overwrites whatever I guessed.

One deliberate deviation from the guide's exact wording: Phase 8's
`shop.gd` originally shows `all_pots`/`all_plants` as `@export` arrays you'd
fill in via the Inspector. I made them plain variables set through a new
`set_catalog()` method instead, called from `test_main.gd`'s `_ready()`.
Hand-authoring an `@export Array[Resource]` with populated slots directly in
`.tscn` text is brittle without Godot's own UID assignment; setting it from
script is just as functional and easier to verify. Nothing else about the
shop's behavior changed.

## What's NOT in this template
Phase 10 onward (real multi-window `Window` nodes, transparency, dragging,
the fairy, grid skins/tags, the weekly economy, series packs/fusion,
Decoration Mode, polish) is still only in the guide as instructions. Those
phases depend on Windows-specific rendering and interaction behavior I have
no way to verify without a GUI — building them blind risks compounding
unverified guesses across many phases, which is worse than testing one
phase at a time together the way we've been doing. Once you've run this
through Phase 9 and confirmed it behaves as described above, Phase 10 is
the right place to go back to building together step by step.
